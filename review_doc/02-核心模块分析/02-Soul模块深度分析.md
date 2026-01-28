# Soul 模块深度分析

> 生成时间：2026-01-21
> 分析文件：
> - `src/kimi_cli/soul/__init__.py`
> - `src/kimi_cli/soul/agent.py`
> - `src/kimi_cli/soul/kimisoul.py`
> - `src/kimi_cli/soul/context.py`
> - `src/kimi_cli/soul/approval.py`

## 1. Soul 模块架构概述

Soul 模块是 kimi-cli 的核心，负责 Agent 的运行时逻辑、工具调用、上下文管理和用户交互。

### 1.1 核心组件关系

```
┌─────────────────────────────────────────────────────────┐
│                        KimiSoul                          │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐              │
│  │  Agent   │  │ Context  │  │   Flow   │              │
│  │(规格+工具)│  │(历史记录)│  │ (流程)   │              │
│  └──────────┘  └──────────┘  └──────────┘              │
└─────────────────────────────────────────────────────────┘
              │
              ├─ Runtime (运行时环境)
              │    ├─ Config
              │    ├─ LLM
              │    ├─ Session
              │    ├─ Approval
              │    ├─ LaborMarket (子Agent市场)
              │    ├─ DenwaRenji (D-Mail时间旅行)
              │    └─ Environment
              │
              └─ Wire (消息总线)
                   ├─ soul_side (Soul发送)
                   └─ ui_side (UI接收)
```

## 2. Runtime：运行时环境

### 2.1 Runtime 结构

`Runtime` 是 Agent 的运行时环境容器，包含所有运行时依赖：

```python
@dataclass(slots=True, kw_only=True)
class Runtime:
    config: Config                        # 配置
    llm: LLM | None                       # 语言模型（可变）
    session: Session                      # 会话
    builtin_args: BuiltinSystemPromptArgs # 内置提示词参数
    denwa_renji: DenwaRenji              # D-Mail 时间旅行系统
    approval: Approval                    # 审批机制
    labor_market: LaborMarket             # 子 Agent 市场
    environment: Environment              # 环境检测
    skills: dict[str, Skill]             # 技能索引
```

### 2.2 BuiltinSystemPromptArgs

内置系统提示词参数，通过 `string.Template` 替换到系统提示词中：

```python
@dataclass(frozen=True, slots=True, kw_only=True)
class BuiltinSystemPromptArgs:
    KIMI_NOW: str                  # 当前时间（ISO 8601）
    KIMI_WORK_DIR: KaosPath        # 工作目录
    KIMI_WORK_DIR_LS: str          # 工作目录列表（ls输出）
    KIMI_AGENTS_MD: str            # AGENTS.md 内容
    KIMI_SKILLS: str               # 可用技能列表
```

**使用示例：**
```python
# 在 agent.yaml 的 system_prompt 中：
Working directory: ${KIMI_WORK_DIR}
Current time: ${KIMI_NOW}
```

### 2.3 Runtime 创建流程

```python
@staticmethod
async def create(
    config: Config,
    llm: LLM | None,
    session: Session,
    yolo: bool,
    skills_dir: KaosPath | None = None,
) -> Runtime:
    # 1. 并发获取环境信息
    ls_output, agents_md, environment = await asyncio.gather(
        list_directory(session.work_dir),      # 列出工作目录
        load_agents_md(session.work_dir),      # 加载 AGENTS.md
        Environment.detect(),                   # 检测环境
    )

    # 2. 发现和索引技能
    skills_roots = await resolve_skills_roots(session.work_dir, skills_dir)
    skills = await discover_skills_from_roots(skills_roots)
    skills_by_name = index_skills(skills)

    # 3. 构造 Runtime
    return Runtime(
        config=config,
        llm=llm,
        session=session,
        builtin_args=BuiltinSystemPromptArgs(...),
        denwa_renji=DenwaRenji(),
        approval=Approval(yolo=yolo),
        labor_market=LaborMarket(),
        environment=environment,
        skills=skills_by_name,
    )
```

### 2.4 Runtime 克隆机制

为不同类型的子 Agent 提供不同的 Runtime 副本：

**1) Fixed Subagent（固定子Agent）：**
```python
def copy_for_fixed_subagent(self) -> Runtime:
    return Runtime(
        ...,
        denwa_renji=DenwaRenji(),        # 独立的 DenwaRenji
        labor_market=LaborMarket(),      # 独立的 LaborMarket
        ...,
    )
```
- 在 Agent 规格中定义（`subagents` 字段）
- 拥有独立的 LaborMarket，不能创建动态子 Agent

**2) Dynamic Subagent（动态子Agent）：**
```python
def copy_for_dynamic_subagent(self) -> Runtime:
    return Runtime(
        ...,
        denwa_renji=DenwaRenji(),        # 独立的 DenwaRenji
        labor_market=self.labor_market,  # 共享 LaborMarket
        ...,
    )
```
- 通过 Task 工具动态创建
- 共享主 Agent 的 LaborMarket

## 3. Agent：Agent 规格

### 3.1 Agent 结构

```python
@dataclass(frozen=True, slots=True, kw_only=True)
class Agent:
    name: str            # Agent 名称
    system_prompt: str   # 系统提示词（已替换变量）
    toolset: Toolset     # 工具集
    runtime: Runtime     # 运行时环境（每个 Agent 独立）
```

### 3.2 load_agent 加载流程

```
┌──────────────────────────────────────────────────────┐
│ 1. 加载 Agent 规格（YAML）                            │
│    - load_agent_spec(agent_file)                    │
│    - 解析继承链、合并字段                             │
└──────────────────────────────────────────────────────┘
                    ↓
┌──────────────────────────────────────────────────────┐
│ 2. 加载系统提示词                                     │
│    - 读取 system_prompt_path 文件                    │
│    - 使用 string.Template 替换变量                   │
└──────────────────────────────────────────────────────┘
                    ↓
┌──────────────────────────────────────────────────────┐
│ 3. 递归加载子 Agent                                   │
│    - 遍历 agent_spec.subagents                       │
│    - 为每个子 Agent 调用 load_agent                   │
│    - 注册到 runtime.labor_market                     │
└──────────────────────────────────────────────────────┘
                    ↓
┌──────────────────────────────────────────────────────┐
│ 4. 创建工具集                                         │
│    - KimiToolset()                                   │
│    - 依赖注入：Runtime, Config, Session, ...        │
│    - toolset.load_tools(tools, tool_deps)           │
└──────────────────────────────────────────────────────┘
                    ↓
┌──────────────────────────────────────────────────────┐
│ 5. 加载 MCP 工具                                      │
│    - 验证 MCPConfig                                  │
│    - toolset.load_mcp_tools(mcp_configs, runtime)   │
└──────────────────────────────────────────────────────┘
                    ↓
┌──────────────────────────────────────────────────────┐
│ 6. 返回 Agent 实例                                    │
│    - Agent(name, system_prompt, toolset, runtime)   │
└──────────────────────────────────────────────────────┘
```

**关键点：**
- 子 Agent 在工具加载之前加载（因为 Task 工具依赖 LaborMarket）
- 工具通过依赖注入获取 Runtime 及其组件
- MCP 工具是外部工具服务器，通过 fastmcp 加载

### 3.3 LaborMarket：子 Agent 市场

```python
class LaborMarket:
    def __init__(self):
        self.fixed_subagents: dict[str, Agent] = {}
        self.fixed_subagent_descs: dict[str, str] = {}
        self.dynamic_subagents: dict[str, Agent] = {}

    @property
    def subagents(self) -> Mapping[str, Agent]:
        return {**self.fixed_subagents, **self.dynamic_subagents}
```

**用途：**
- 管理所有子 Agent
- 固定子 Agent：在 Agent 规格中定义，跟随主 Agent 加载
- 动态子 Agent：运行时通过 Task 工具创建

## 4. Context：上下文管理

### 4.1 Context 结构

```python
class Context:
    _file_backend: Path           # 上下文文件路径
    _history: list[Message]       # 消息历史
    _token_count: int             # Token 计数
    _next_checkpoint_id: int      # 下一个 checkpoint ID
```

### 4.2 文件格式

Context 使用 **JSONL** (JSON Lines) 格式持久化：

```jsonl
{"role": "user", "content": "hello"}
{"role": "assistant", "content": "hi"}
{"role": "_usage", "token_count": 150}
{"role": "_checkpoint", "id": 0}
{"role": "user", "content": "what is 2+2?"}
{"role": "assistant", "content": "4"}
{"role": "_usage", "token_count": 300}
```

**特殊角色：**
- `_usage`：记录累计 token 数
- `_checkpoint`：标记 checkpoint 位置

### 4.3 核心操作

#### restore()：恢复上下文

```python
async def restore(self) -> bool:
    # 逐行读取 JSONL 文件
    async for line in f:
        line_json = json.loads(line)
        if line_json["role"] == "_usage":
            self._token_count = line_json["token_count"]
        elif line_json["role"] == "_checkpoint":
            self._next_checkpoint_id = line_json["id"] + 1
        else:
            message = Message.model_validate(line_json)
            self._history.append(message)
    return True
```

#### checkpoint()：创建检查点

```python
async def checkpoint(self, add_user_message: bool):
    checkpoint_id = self._next_checkpoint_id
    self._next_checkpoint_id += 1

    # 1. 写入 checkpoint 标记
    await f.write(json.dumps({"role": "_checkpoint", "id": checkpoint_id}) + "\n")

    # 2. 可选：添加用户可见的 checkpoint 消息
    if add_user_message:
        await self.append_message(
            Message(role="user", content=[system(f"CHECKPOINT {checkpoint_id}")])
        )
```

**checkpoint 策略：**
- 每个 step 之前创建 checkpoint
- 首次运行时创建 checkpoint 0
- 用于 D-Mail 时间旅行回退

#### revert_to()：回退到 checkpoint

```python
async def revert_to(self, checkpoint_id: int):
    # 1. 旋转（重命名）当前上下文文件
    rotated_file_path = await next_available_rotation(self._file_backend)
    await aiofiles.os.replace(self._file_backend, rotated_file_path)
    # 例：context.jsonl -> context.jsonl.1

    # 2. 从旋转文件恢复到指定 checkpoint
    async with (
        aiofiles.open(rotated_file_path, encoding="utf-8") as old_file,
        aiofiles.open(self._file_backend, "w", encoding="utf-8") as new_file,
    ):
        async for line in old_file:
            line_json = json.loads(line)
            # 遇到目标 checkpoint 就停止
            if line_json["role"] == "_checkpoint" and line_json["id"] == checkpoint_id:
                break
            await new_file.write(line)
            # 更新内存状态
            ...
```

#### append_message()：追加消息

```python
async def append_message(self, message: Message | Sequence[Message]):
    messages = [message] if isinstance(message, Message) else message
    self._history.extend(messages)

    # 追加到文件
    async with aiofiles.open(self._file_backend, "a", encoding="utf-8") as f:
        for message in messages:
            await f.write(message.model_dump_json(exclude_none=True) + "\n")
```

### 4.4 Checkpoint 应用场景

1. **常规 checkpoint**：每步之前创建，用于跟踪进度
2. **D-Mail 时间旅行**：未来的 Agent 发送消息到过去的 checkpoint
3. **上下文压缩（compaction）**：清空后创建新的 checkpoint 0

## 5. Approval：审批机制

### 5.1 Approval 结构

```python
class Approval:
    _request_queue: Queue[Request]               # 审批请求队列
    _requests: dict[str, tuple[Request, Future]] # 待处理请求
    _yolo: bool                                  # YOLO 模式（自动批准）
    _auto_approve_actions: set[str]              # 自动批准的操作
```

### 5.2 审批流程

```
┌──────────┐                    ┌──────────┐
│   Tool   │                    │  Soul    │
└──────────┘                    └──────────┘
      │                               │
      │ 1. request()                  │
      ├──────────────────────────────>│
      │   (send Request to queue)     │
      │                               │
      │                               │ 2. fetch_request()
      │                               │    (Soul循环获取)
      │                               │
      │                               │ 3. wire_send(ApprovalRequest)
      │                               │    (发送到UI)
      │                               │
      │         [用户在UI中审批]        │
      │                               │
      │                               │ 4. resolve_request(response)
      │                               │    (设置 Future 结果)
      │                               │
      │ 5. await future               │
      │<──────────────────────────────┤
      │   (Tool 继续执行或抛出异常)     │
      │                               │
```

### 5.3 审批响应类型

```python
type Response = Literal["approve", "approve_for_session", "reject"]
```

- `approve`：批准一次
- `approve_for_session`：批准并记住，本会话不再询问
- `reject`：拒绝

### 5.4 YOLO 模式

```python
if self._yolo:
    return True  # 直接批准，不进队列
```

**触发条件：**
- CLI 参数 `--yolo/-y/--auto-approve`
- print 模式自动启用 YOLO

## 6. KimiSoul：核心引擎

### 6.1 KimiSoul 初始化

```python
class KimiSoul:
    def __init__(
        self,
        agent: Agent,
        *,
        context: Context,
        flow: PromptFlow | None = None,
    ):
        self._agent = agent
        self._runtime = agent.runtime
        self._context = context
        self._loop_control = agent.runtime.config.loop_control
        self._compaction = SimpleCompaction()
        self._reserved_tokens = 50_000  # 为新输入和输出预留

        # 构建 slash 命令索引
        self._slash_commands = self._build_slash_commands()
        self._slash_command_map = self._index_slash_commands(...)
```

### 6.2 run() 方法：入口

```python
async def run(self, user_input: str | list[ContentPart]):
    user_message = Message(role="user", content=user_input)
    text_input = user_message.extract_text(" ").strip()

    # 1. 检查是否为 slash 命令
    if command_call := parse_slash_command_call(text_input):
        wire_send(TurnBegin(user_input=user_input))
        command = self._find_slash_command(command_call.name)
        if command:
            ret = command.func(self, command_call.args)
            if isinstance(ret, Awaitable):
                await ret
        return

    # 2. 检查是否启用 Ralph 模式或 Flow 模式
    if self._loop_control.max_ralph_iterations != 0 and self._flow_runner is None:
        runner = FlowRunner.ralph_loop(user_message, ...)
        await runner.run(self, "")
        return

    # 3. 正常的单轮对话
    wire_send(TurnBegin(user_input=user_input))
    result = await self._turn(user_message)
```

### 6.3 _turn() 方法：单轮对话

```python
async def _turn(self, user_message: Message) -> TurnOutcome:
    # 1. LLM 检查
    if self._runtime.llm is None:
        raise LLMNotSet()

    # 2. 检查消息能力（如 vision）
    if missing_caps := check_message(user_message, self._runtime.llm.capabilities):
        raise LLMNotSupported(self._runtime.llm, list(missing_caps))

    # 3. Checkpoint 并追加用户消息
    await self._checkpoint()
    await self._context.append_message(user_message)

    # 4. 进入 Agent 主循环
    return await self._agent_loop()
```

### 6.4 _agent_loop() 方法：Agent 主循环

```python
async def _agent_loop(self) -> TurnOutcome:
    # 并发任务：将审批请求转发到 Wire
    async def _pipe_approval_to_wire():
        while True:
            request = await self._approval.fetch_request()
            wire_request = ApprovalRequest(...)
            wire_send(wire_request)
            resp = await wire_request.wait()  # 等待 UI 响应
            self._approval.resolve_request(request.id, resp)
            wire_send(ApprovalRequestResolved(...))

    step_no = 0
    while True:
        step_no += 1

        # 检查步数限制
        if step_no > self._loop_control.max_steps_per_turn:
            raise MaxStepsReached(...)

        wire_send(StepBegin(n=step_no))
        approval_task = asyncio.create_task(_pipe_approval_to_wire())

        try:
            # 检查是否需要压缩上下文
            if self._context.token_count + self._reserved_tokens >= llm.max_context_size:
                await self.compact_context()

            # Checkpoint
            await self._checkpoint()
            self._denwa_renji.set_n_checkpoints(self._context.n_checkpoints)

            # 执行一步
            step_outcome = await self._step()

        except BackToTheFuture as e:
            # D-Mail：回退到过去的 checkpoint
            await self._context.revert_to(e.checkpoint_id)
            await self._checkpoint()
            await self._context.append_message(e.messages)
            continue

        finally:
            approval_task.cancel()

        # 检查是否结束循环
        if step_outcome is not None:
            return TurnOutcome(
                stop_reason=step_outcome.stop_reason,
                final_message=step_outcome.assistant_message if ... else None,
                step_count=step_no,
            )
```

**循环逻辑：**
1. 每个 step 之前创建 checkpoint
2. 调用 `_step()` 执行 LLM 推理和工具调用
3. 如果没有工具调用 → 返回结果，循环结束
4. 如果有工具调用 → 继续下一个 step
5. 捕获 `BackToTheFuture` 异常 → 回退到指定 checkpoint

### 6.5 _step() 方法：单步执行

```python
async def _step(self) -> StepOutcome | None:
    # Kosong step with retry
    @tenacity.retry(
        retry=retry_if_exception(self._is_retryable_error),
        wait=wait_exponential_jitter(initial=0.3, max=5, jitter=0.5),
        stop=stop_after_attempt(self._loop_control.max_retries_per_step),
    )
    async def _kosong_step_with_retry() -> StepResult:
        return await kosong.step(
            chat_provider,
            self._agent.system_prompt,
            self._agent.toolset,
            self._context.history,
            on_message_part=wire_send,   # 流式输出
            on_tool_result=wire_send,     # 工具结果
        )

    # 1. 调用 LLM
    result = await _kosong_step_with_retry()

    # 2. 发送状态更新
    status_update = StatusUpdate(token_usage=result.usage, message_id=result.id)
    await self._context.update_token_count(result.usage.input)
    status_update.context_usage = self.status.context_usage
    wire_send(status_update)

    # 3. 等待所有工具执行完成
    results = await result.tool_results()

    # 4. 更新上下文（shield 避免中断）
    await asyncio.shield(self._grow_context(result, results))

    # 5. 检查是否有工具被拒绝
    if any(isinstance(r.return_value, ToolRejectedError) for r in results):
        _ = self._denwa_renji.fetch_pending_dmail()
        return StepOutcome(stop_reason="tool_rejected", ...)

    # 6. 处理 D-Mail
    if dmail := self._denwa_renji.fetch_pending_dmail():
        raise BackToTheFuture(dmail.checkpoint_id, [...])

    # 7. 判断是否继续循环
    if result.tool_calls:
        return None  # 继续循环
    return StepOutcome(stop_reason="no_tool_calls", ...)
```

**重试策略：**
- 可重试错误：连接错误、超时、429/500/502/503 状态码
- 指数退避：初始 0.3 秒，最大 5 秒，带 jitter
- 最大重试次数：`max_retries_per_step`

### 6.6 compact_context()：上下文压缩

```python
async def compact_context(self) -> None:
    @tenacity.retry(...)
    async def _compact_with_retry() -> Sequence[Message]:
        return await self._compaction.compact(self._context.history, self._runtime.llm)

    wire_send(CompactionBegin())
    compacted_messages = await _compact_with_retry()

    # 清空并重建上下文
    await self._context.clear()
    await self._checkpoint()
    await self._context.append_message(compacted_messages)

    wire_send(CompactionEnd())
```

**触发条件：**
```python
if (self._context.token_count + self._reserved_tokens >= llm.max_context_size):
    await self.compact_context()
```

## 7. run_soul()：Soul 与 UI 的桥梁

```python
async def run_soul(
    soul: Soul,
    user_input: str | list[ContentPart],
    ui_loop_fn: UILoopFn,
    cancel_event: asyncio.Event,
    wire_file: Path | None = None,
) -> None:
    # 1. 创建 Wire
    wire = Wire(file_backend=wire_file)
    wire_token = _current_wire.set(wire)  # 存储到 ContextVar

    # 2. 启动 UI 循环
    wire_future = asyncio.Future[WireUISide]()

    async def _ui_loop_fn_wrapper(wire: Wire) -> None:
        wire_future.set_result(wire.ui_side(merge=...))
        await stop_ui_loop.wait()

    ui_task = asyncio.create_task(_ui_loop_fn_wrapper(wire))

    # 3. 启动 Soul 任务
    soul_task = asyncio.create_task(soul.run(user_input))
    cancel_event_task = asyncio.create_task(cancel_event.wait())

    # 4. 等待 Soul 完成或取消
    await asyncio.wait([soul_task, cancel_event_task], return_when=asyncio.FIRST_COMPLETED)

    # 5. 处理取消或完成
    try:
        if cancel_event.is_set():
            soul_task.cancel()
            await soul_task  # 捕获 CancelledError
            raise RunCancelled
        else:
            cancel_event_task.cancel()
            soul_task.result()  # 如果有异常会抛出
    finally:
        # 6. 关闭 Wire 和 UI
        wire.shutdown()
        await asyncio.wait_for(ui_task, timeout=0.5)
        _current_wire.reset(wire_token)
```

**关键点：**
1. **ContextVar**：`_current_wire` 存储当前 Wire，供 `wire_send()` 使用
2. **并发任务**：Soul 和 UI 并发运行
3. **取消机制**：通过 `cancel_event` 优雅取消
4. **异常传播**：Soul 的异常会传播到调用者

## 8. Wire 消息系统

### 8.1 Wire 架构

```
┌─────────────┐          ┌─────────────┐
│   Soul      │          │     UI      │
│  (Agent)    │          │  (Shell)    │
└─────────────┘          └─────────────┘
      │                        │
      │  wire_send(msg)        │
      ├───────────────────────>│
      │                        │
      │       wire.soul_side   │  wire.ui_side
      │         (Queue)        │    (Queue)
      │                        │
      │<───────────────────────┤
      │  approval response     │
```

### 8.2 核心 Wire 消息类型

**Soul → UI：**
- `TurnBegin`：开始新的对话轮
- `StepBegin`：开始新的推理步
- `TextPart`：文本输出
- `ToolResult`：工具执行结果
- `StatusUpdate`：状态更新（token 使用、上下文占用）
- `ApprovalRequest`：审批请求
- `CompactionBegin`/`CompactionEnd`：压缩开始/结束
- `StepInterrupted`：步骤被中断

**UI → Soul：**
- `ApprovalResponse`：审批响应（通过 `ApprovalRequest.wait()`）

### 8.3 wire_send() 全局函数

```python
def wire_send(msg: WireMessage) -> None:
    wire = get_wire_or_none()
    assert wire is not None, "Wire is expected to be set when soul is running"
    wire.soul_side.send(msg)
```

**使用场景：**
- Soul 代码中任何地方发送消息
- Tool 代码中发送消息
- 通过 ContextVar 获取当前 Wire

## 9. 高级特性

### 9.1 D-Mail：时间旅行

**DenwaRenji**（「電話レンジ」，微波炉电话）：

```python
class DenwaRenji:
    def send_dmail(self, checkpoint_id: int, message: str):
        ...

    def fetch_pending_dmail(self) -> DMail | None:
        ...
```

**工作流程：**
1. 工具调用 `send_dmail(checkpoint_id, message)`
2. KimiSoul 在 `_step()` 结束时检查 pending D-Mail
3. 如果有 D-Mail，抛出 `BackToTheFuture` 异常
4. `_agent_loop()` 捕获异常，调用 `context.revert_to(checkpoint_id)`
5. 追加 D-Mail 消息作为系统消息
6. Agent 从过去的 checkpoint 继续执行

**应用场景：**
- 未来的 Agent 发现错误，通知过去的自己
- 实验性的时间循环任务

### 9.2 FlowRunner：流程控制

**两种模式：**

**1) Ralph 模式（自动循环）：**
```python
FlowRunner.ralph_loop(user_message, max_ralph_iterations)
```
- 自动构造一个 `BEGIN -> R1 -> R2 -> END` 的循环流程
- R2 是决策节点，选择 `CONTINUE` 或 `STOP`
- 用于重复执行相同任务直到完成

**2) Prompt Flow 模式：**
- 从 D2 或 Mermaid 文件加载流程图
- 支持 `begin`、`task`、`decision`、`end` 节点
- 决策节点根据 Agent 输出的 `<choice>` 标签选择分支

### 9.3 Slash 命令系统

**内置命令：**
- `/setup`、`/reload`、`/yolo`、`/clear` 等
- 定义在 `soul/slash.py` 中的 `registry`

**技能命令：**
- 格式：`/skill:name`
- 动态从 `skills_dir` 加载
- 将技能内容作为用户消息注入

**Flow 命令：**
- `/begin`：启动 prompt flow

## 10. 异常和错误处理

### 10.1 异常类型

```python
class LLMNotSet(Exception): ...
class LLMNotSupported(Exception): ...
class MaxStepsReached(Exception): ...
class RunCancelled(Exception): ...
class BackToTheFuture(Exception): ...  # 内部异常
```

### 10.2 重试策略

**可重试错误：**
```python
def _is_retryable_error(exception: BaseException) -> bool:
    if isinstance(exception, (APIConnectionError, APITimeoutError, APIEmptyResponseError)):
        return True
    return isinstance(exception, APIStatusError) and exception.status_code in (
        429, 500, 502, 503
    )
```

**重试配置：**
- 等待策略：指数退避 + jitter
- 最大重试：`max_retries_per_step`（配置）
- 应用范围：LLM step 和 compaction

## 11. 数据流总结

```
用户输入
  │
  ├─ KimiSoul.run()
  │
  ├─ 检查 slash 命令
  │    ├─ Yes → 执行命令 → 结束
  │    └─ No ↓
  │
  ├─ 检查 Flow/Ralph 模式
  │    ├─ Yes → FlowRunner.run() → 多轮循环
  │    └─ No ↓
  │
  ├─ _turn()
  │    ├─ checkpoint
  │    ├─ append user message
  │    └─ _agent_loop()
  │
  ├─ _agent_loop() [循环]
  │    │
  │    ├─ 启动 approval_task
  │    │
  │    ├─ _step()
  │    │    ├─ kosong.step (LLM 推理)
  │    │    ├─ 等待工具执行
  │    │    ├─ 更新上下文
  │    │    └─ 检查 D-Mail
  │    │
  │    ├─ 检查 step_outcome
  │    │    ├─ tool_rejected → 结束
  │    │    ├─ no_tool_calls → 结束
  │    │    └─ None → 继续循环
  │    │
  │    └─ 捕获 BackToTheFuture → revert_to
  │
  └─ 返回结果
```

## 12. 性能和优化

### 12.1 上下文管理

- **预留 Token**：`RESERVED_TOKENS = 50_000`
- **触发条件**：`token_count + reserved >= max_context_size`
- **压缩策略**：`SimpleCompaction`（TODO：可配置和组合）

### 12.2 异步优化

- **并发审批**：`_pipe_approval_to_wire()` 与主循环并发
- **异步 I/O**：使用 `aiofiles` 进行文件操作
- **并发环境检测**：`asyncio.gather()` 并发加载环境信息

### 12.3 Shield 机制

```python
await asyncio.shield(self._grow_context(result, results))
```
- 避免上下文操作在中断时损坏
- 确保 checkpoint 一致性

## 13. 文件位置参考

- Soul 核心：`src/kimi_cli/soul/kimisoul.py`
- Agent 加载：`src/kimi_cli/soul/agent.py`
- 上下文管理：`src/kimi_cli/soul/context.py`
- 审批机制：`src/kimi_cli/soul/approval.py`
- 消息工具：`src/kimi_cli/soul/message.py`
- Slash 命令：`src/kimi_cli/soul/slash.py`
- 压缩策略：`src/kimi_cli/soul/compaction.py`
- 工具集：`src/kimi_cli/soul/toolset.py`

## 14. 待深入研究的问题

1. **SimpleCompaction** 的具体实现策略
2. **DenwaRenji** 的完整实现和约束
3. **Toolset 的依赖注入机制**（下一节重点）
4. **MCP 工具的加载和生命周期**
5. **kosong 库的 step() 函数内部实现**
6. **Context 压缩后的消息选择算法**

---

**下一步**：深入分析 Toolset 和内置工具的实现。

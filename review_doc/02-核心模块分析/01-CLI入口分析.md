# CLI 入口与 App 模块分析

> 生成时间：2026-01-21
> 分析文件：`src/kimi_cli/cli/__init__.py`, `src/kimi_cli/app.py`

## 1. CLI 参数解析流程

### 1.1 Typer 框架组织

kimi-cli 使用 `typer` 作为CLI框架，主要结构如下：

```python
cli = typer.Typer(
    epilog="...",
    add_completion=False,
    context_settings={"help_option_names": ["-h", "--help"]},
    help="Kimi, your next CLI agent.",
)
```

**命令组织：**
- 主命令：`kimi()` - 通过 `@cli.callback(invoke_without_command=True)` 装饰
- 子命令组：
  - `info_cli` - 信息查询命令组
  - `mcp_cli` - MCP 管理命令组
  - `term` - Toad TUI 命令
  - `acp` - ACP 服务器命令

### 1.2 参数分类

参数按功能分为以下几类：

**元信息参数：**
- `--version/-V`: 显示版本
- `--verbose`: 详细信息输出
- `--debug`: 调试日志

**基础配置：**
- `--work-dir/-w`: 工作目录（默认当前目录）
- `--session/-S`: 指定会话 ID
- `--continue/-C`: 继续上次会话
- `--config`: 配置 TOML/JSON 字符串
- `--config-file`: 配置文件路径（默认 ~/.kimi/config.toml）
- `--model/-m`: 指定 LLM 模型
- `--thinking/--no-thinking`: 启用思考模式

**运行模式：**
- `--yolo/-y/--auto-approve`: 自动批准所有操作
- `--prompt/-p/-c`: 直接提供提示词
- `--prompt-flow`: D2/Mermaid 流程图文件

**UI 模式控制（互斥）：**
- `--print`: print 模式（非交互）
- `--acp`: ACP 服务器模式（已废弃，使用 `kimi acp`）
- `--wire`: Wire 服务器模式（实验性）
- 默认：shell 模式（交互式）

**Print 模式专属：**
- `--input-format`: 输入格式（text/stream-json）
- `--output-format`: 输出格式（text/stream-json）
- `--final-message-only`: 只输出最终消息
- `--quiet`: 快捷方式 = `--print --output-format text --final-message-only`

**定制化：**
- `--agent`: 内置 agent 规格（default/okabe）
- `--agent-file`: 自定义 agent 规格文件
- `--mcp-config-file`: MCP 配置文件（可多次指定）
- `--mcp-config`: MCP 配置 JSON（可多次指定）
- `--skills-dir`: 技能目录路径

**循环控制：**
- `--max-steps-per-turn`: 单轮最大步数
- `--max-retries-per-step`: 单步最大重试次数
- `--max-ralph-iterations`: Ralph 模式额外迭代次数

### 1.3 参数冲突检测

使用 `conflict_option_sets` 机制检测互斥参数：

```python
conflict_option_sets = [
    {"--print": print_mode, "--acp": acp_mode, "--wire": wire_mode},
    {"--agent": agent is not None, "--agent-file": agent_file is not None},
    {"--continue": continue_, "--session": session_id is not None},
    {"--config": config_string is not None, "--config-file": config_file is not None},
]
```

### 1.4 四种 UI 模式

**1) shell 模式（默认）：**
- 触发条件：没有指定其他模式
- 特点：交互式、支持命令历史、可切换 shell 命令模式（Ctrl-X）
- 实现：`KimiCLI.run_shell()`

**2) print 模式：**
- 触发条件：`--print` 或 `--quiet`
- 特点：非交互式、隐式启用 `--yolo`、支持管道输入
- 实现：`KimiCLI.run_print()`
- 应用场景：脚本集成、批处理

**3) acp 模式：**
- 触发条件：`--acp` 或 `kimi acp` 子命令
- 特点：实现 Agent Client Protocol，供 IDE 集成
- 实现：`KimiCLI.run_acp()`
- 支持的编辑器：Zed、JetBrains

**4) wire 模式（实验性）：**
- 触发条件：`--wire`
- 特点：基于 Wire 消息协议的服务器
- 实现：`KimiCLI.run_wire_stdio()`

### 1.5 配置优先级

配置来源的优先级（从高到低）：

1. **CLI 参数**：直接命令行指定的参数
2. **环境变量**：通过 `augment_provider_with_env_vars()` 处理
   - `KIMI_BASE_URL`
   - `KIMI_API_KEY`
   - `KIMI_MODEL_NAME`
3. **配置文件**：
   - `--config`: 直接提供的配置字符串
   - `--config-file`: 指定的配置文件
   - 默认：`~/.kimi/config.toml`
4. **默认值**：Config 类的默认值

代码体现：

```python
# 先从配置文件加载
if not model_name and config.default_model:
    model = config.models[config.default_model]
    provider = config.providers[model.provider]
if model_name and model_name in config.models:
    model = config.models[model_name]
    provider = config.providers[model.provider]

# 再用环境变量覆盖
env_overrides = augment_provider_with_env_vars(provider, model)
```

## 2. KimiCLI.create 工厂方法

### 2.1 完整创建流程

```
┌─────────────────────────────────────────────────────┐
│ 1. 配置加载与合并                                    │
│    - load_config(config)                            │
│    - 合并 loop_control 参数                          │
└─────────────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────────────┐
│ 2. LLM 模型选择                                      │
│    - 从配置文件选择模型和提供者                       │
│    - 环境变量覆盖（augment_provider_with_env_vars） │
│    - 确定 thinking 模式                              │
└─────────────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────────────┐
│ 3. 创建 LLM 实例                                     │
│    - create_llm(provider, model, thinking, session) │
└─────────────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────────────┐
│ 4. 创建 Runtime                                      │
│    - Runtime.create(config, llm, session, yolo,     │
│                     skills_dir)                      │
│    - 初始化工作目录、技能加载器、审批机制            │
└─────────────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────────────┐
│ 5. 加载 Agent 规格                                   │
│    - load_agent(agent_file, runtime, mcp_configs)   │
│    - 解析 YAML、加载工具、MCP 服务器                │
└─────────────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────────────┐
│ 6. 创建/恢复 Context                                 │
│    - Context(session.context_file)                   │
│    - await context.restore()                         │
└─────────────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────────────┐
│ 7. 创建 KimiSoul                                     │
│    - KimiSoul(agent, context=context, flow=flow)    │
└─────────────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────────────┐
│ 8. 返回 KimiCLI 实例                                 │
│    - KimiCLI(soul, runtime, env_overrides)          │
└─────────────────────────────────────────────────────┘
```

### 2.2 核心组件依赖关系

```
KimiCLI
  │
  ├─ KimiSoul (核心 Agent 引擎)
  │    │
  │    ├─ Agent (Agent 规格)
  │    │    ├─ Toolset (工具集)
  │    │    └─ MCP Servers (外部工具)
  │    │
  │    ├─ Context (上下文管理)
  │    └─ PromptFlow (流程控制)
  │
  └─ Runtime (运行时环境)
       ├─ Config (配置)
       ├─ LLM (语言模型)
       ├─ Session (会话)
       ├─ Approval (审批机制)
       └─ SkillLoader (技能加载)
```

### 2.3 关键初始化步骤

**配置加载：**
```python
config = config if isinstance(config, Config) else load_config(config)
```
- 支持 Config 对象或文件路径
- `load_config()` 会递归加载默认配置

**LLM 初始化：**
```python
# 1. 从配置选择模型
if model_name and model_name in config.models:
    model = config.models[model_name]
    provider = config.providers[model.provider]

# 2. 环境变量覆盖
env_overrides = augment_provider_with_env_vars(provider, model)

# 3. 创建 LLM
llm = create_llm(provider, model, thinking=thinking, session_id=session.id)
```

**Context 恢复：**
```python
context = Context(session.context_file)
await context.restore()  # 从磁盘恢复上下文
```

## 3. 运行时流程

### 3.1 _run() 异步函数执行流程

```python
async def _run(session_id: str | None) -> bool:
    # 1. Session 管理
    if session_id is not None:
        session = await Session.find(work_dir, session_id)
        if session is None:
            session = await Session.create(work_dir, session_id)
    elif continue_:
        session = await Session.continue_(work_dir)
    else:
        session = await Session.create(work_dir)

    # 2. 创建 KimiCLI 实例
    instance = await KimiCLI.create(...)

    # 3. 根据 UI 模式运行
    match ui:
        case "shell":
            succeeded = await instance.run_shell(prompt)
        case "print":
            succeeded = await instance.run_print(...)
        case "acp":
            await instance.run_acp()
            succeeded = True
        case "wire":
            await instance.run_wire_stdio()
            succeeded = True

    # 4. 持久化 Session 元数据
    if succeeded:
        metadata = load_metadata()
        work_dir_meta = metadata.get_work_dir_meta(session.work_dir)

        if session.is_empty():
            await session.delete()
        else:
            work_dir_meta.last_session_id = session.id

        save_metadata(metadata)

    return succeeded
```

**外层循环支持配置重载：**
```python
while True:
    try:
        succeeded = asyncio.run(_run(session_id))
        if not succeeded:
            raise typer.Exit(code=1)
        break
    except Reload as e:
        session_id = e.session_id  # 支持 /reload 命令
        continue
```

### 3.2 Session 管理机制

**三种 Session 创建方式：**

1. **新建 Session：**
   ```python
   session = await Session.create(work_dir)  # 生成新 UUID
   ```

2. **指定 Session ID：**
   ```python
   session = await Session.find(work_dir, session_id)
   if session is None:
       session = await Session.create(work_dir, session_id)
   ```

3. **继续上次 Session：**
   ```python
   session = await Session.continue_(work_dir)  # 从元数据读取
   ```

**Session 持久化：**
- Context 保存到 `session.context_file`
- 元数据保存到 `~/.kimi/metadata.json`（包含 `last_session_id`）
- 空 Session 自动删除

### 3.3 不同 UI 模式的 run 方法

**1) run_shell()：**
```python
async def run_shell(self, command: str | None = None) -> bool:
    welcome_info = [...]  # 欢迎信息（工作目录、会话ID、模型等）
    async with self._env():
        shell = Shell(self._soul, welcome_info=welcome_info)
        return await shell.run(command)
```

**2) run_print()：**
```python
async def run_print(
    self,
    input_format: InputFormat,
    output_format: OutputFormat,
    command: str | None = None,
    *,
    final_only: bool = False,
) -> bool:
    async with self._env():
        print_ = Print(self._soul, input_format, output_format,
                       self._runtime.session.context_file,
                       final_only=final_only)
        return await print_.run(command)
```

**3) run_acp()：**
```python
async def run_acp(self) -> None:
    async with self._env():
        acp = ACP(self._soul)
        await acp.run()  # 启动 ACP 服务器循环
```

**4) run_wire_stdio()：**
```python
async def run_wire_stdio(self) -> None:
    async with self._env():
        server = WireOverStdio(self._soul)
        await server.serve()  # 启动 Wire 服务器
```

## 4. 关键设计模式

### 4.1 Wire 消息系统

**定义：**
Wire 是 kimi-cli 内部的消息传递协议，用于解耦 Agent 逻辑（Soul）和 UI 层。

**架构：**
```
┌──────────┐        Wire         ┌──────────┐
│ KimiSoul │ ◄─────────────────► │ UI Layer │
└──────────┘                      └──────────┘
  (Agent逻辑)                      (Shell/Print/ACP/Wire)
```

**消息类型（WireMessage）：**
- 用户消息、助手消息、工具调用、审批请求等
- 定义在 `wire/types.py`

**使用场景：**
```python
async def run(
    self,
    user_input: str | list[ContentPart],
    cancel_event: asyncio.Event,
    merge_wire_messages: bool = False,
) -> AsyncGenerator[WireMessage]:
    # 启动 soul 任务
    soul_task = asyncio.create_task(
        run_soul(self.soul, user_input, _ui_loop_fn, cancel_event)
    )

    # 接收并 yield Wire 消息
    wire_ui = await wire_future
    while True:
        msg = await wire_ui.receive()
        yield msg
```

### 4.2 异步生成器模式

**在 `run()` 方法中使用：**
```python
async def run(...) -> AsyncGenerator[WireMessage]:
    async with self._env():
        # ... 设置 Wire
        while True:
            msg = await wire_ui.receive()
            yield msg  # 流式返回消息
```

**优势：**
- 实时流式返回 Agent 输出
- 支持长时间运行任务的中间结果
- 内存高效（不需要缓存所有消息）

### 4.3 环境上下文管理

**`_env()` 上下文管理器：**
```python
@contextlib.asynccontextmanager
async def _env(self) -> AsyncGenerator[None]:
    original_cwd = KaosPath.cwd()
    await kaos.chdir(self._runtime.session.work_dir)  # 切换到工作目录
    try:
        warnings.filterwarnings("ignore", category=DeprecationWarning)
        with contextlib.redirect_stderr(StreamToLogger()):  # 重定向 stderr
            yield
    finally:
        await kaos.chdir(original_cwd)  # 恢复原目录
```

**作用：**
1. **目录隔离**：确保 Agent 在正确的工作目录执行
2. **日志管理**：重定向 stderr 到日志系统
3. **警告过滤**：避免第三方库的警告干扰
4. **清理保证**：通过 finally 确保状态恢复

### 4.4 工厂方法模式

**KimiCLI.create() 是异步工厂方法：**
- 封装复杂的初始化逻辑
- 支持参数验证和默认值
- 返回完全初始化的实例

**优势：**
- 构造函数 `__init__` 保持简单
- 支持异步初始化（Session、Context、Agent 加载）
- 便于测试（可以 mock 各个组件）

## 5. 数据流向图

### 5.1 CLI 启动流程

```
用户命令
  │
  ├─ typer.Typer 解析参数
  │
  ├─ 参数验证与冲突检测
  │
  ├─ _run() 异步函数
  │    │
  │    ├─ Session.create/find/continue_
  │    │
  │    ├─ KimiCLI.create
  │    │    │
  │    │    ├─ load_config
  │    │    ├─ create_llm
  │    │    ├─ Runtime.create
  │    │    ├─ load_agent
  │    │    ├─ Context.restore
  │    │    └─ KimiSoul
  │    │
  │    └─ instance.run_*()
  │         │
  │         ├─ Shell/Print/ACP/Wire UI
  │         │
  │         └─ run_soul (通过 Wire)
  │              │
  │              └─ Agent 执行循环
  │
  └─ Session 持久化 & 元数据更新
```

### 5.2 消息流向

```
用户输入
  │
  ├─ UI Layer 封装
  │
  ├─ Wire.agent_side()
  │    │
  │    └─ KimiSoul.run()
  │         │
  │         ├─ LLM 调用
  │         │
  │         ├─ Tool 执行
  │         │
  │         └─ Wire 消息
  │
  ├─ Wire.ui_side()
  │
  └─ UI Layer 渲染
```

## 6. 关键文件位置

- CLI 入口：`src/kimi_cli/cli/__init__.py`
- App 主类：`src/kimi_cli/app.py`
- 配置管理：`src/kimi_cli/config.py`
- Session 管理：`src/kimi_cli/session.py`
- Soul 核心：`src/kimi_cli/soul/kimisoul.py`
- Wire 协议：`src/kimi_cli/wire/`

## 7. 待深入研究的问题

1. Runtime.create() 的详细实现和依赖注入机制
2. load_agent() 的 Agent 规格解析流程
3. Context 的压缩（compaction）策略
4. run_soul() 的事件循环和异常处理
5. MCP 工具的加载和调用机制

---

**下一步**：深入分析 Soul 模块的 Agent 运行时和主循环。

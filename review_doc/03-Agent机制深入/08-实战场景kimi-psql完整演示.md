# 08 - 实战场景：基于 Kimi CLI 项目的 Skill 和 MCP 完整演示

## 前言

本文档基于 **kimi-cli 项目的实际配置和代码**，通过真实场景演示 Skill 和 MCP 的使用。

**实战场景**: `kimi-psql` - AI 辅助的 PostgreSQL 交互终端

---

## 一、场景背景

### 1.1 kimi-psql 项目简介

`kimi-psql` 是 kimi-cli 的一个示例项目，它创建了一个 AI 辅助的 PostgreSQL 终端。

**功能**:
- 用自然语言查询数据库
- 自动生成 SQL 语句
- 只读模式（安全）
- 可切换 AI 模式和原生 psql 模式

**技术栈**:
- ✅ 使用 kimi-cli 的 `KimiSoul`
- ✅ 自定义工具: `ExecuteSql`
- ✅ 自定义 Agent 配置: `agent.yaml`
- ✅ 继承内置 Skill: `kimi-cli-help`

---

### 1.2 项目结构

```
examples/kimi-psql/
├── main.py          # 主程序
├── agent.yaml       # Agent 配置
└──README.md         # 文档
```

---

## 二、Skill 在 kimi-psql 中的使用

### 2.1 内置 Skill: kimi-cli-help

**位置**: `src/kimi_cli/skills/kimi-cli-help/SKILL.md`

**完整内容**:

```markdown
---
name: kimi-cli-help
description: Answer Kimi CLI usage, configuration, and troubleshooting questions. Use when user asks about Kimi CLI installation, setup, configuration, slash commands, keyboard shortcuts, MCP integration, providers, environment variables, how something works internally, or any questions about Kimi CLI itself.
---

# Kimi CLI Help

Help users with Kimi CLI questions by consulting documentation and source code.

## Strategy

1. **Prefer official documentation** for most questions
2. **Read local source** when in kimi-cli project itself
3. **Clone and explore source** for complex internals - ask user for confirmation first

## Documentation

Base URL: `https://moonshotai.github.io/kimi-cli/`

Fetch documentation index:
https://moonshotai.github.io/kimi-cli/llms.txt

### Topic Mapping

| Topic | Page |
|-------|------|
| Installation | `/en/guides/getting-started.md` |
| Config files | `/en/configuration/config-files.md` |
| MCP | `/en/customization/mcp.md` |
| Skills | `/en/customization/skills.md` |
...
```

---

### 2.2 Skill 的加载流程（kimi-psql 中）

**代码**: `examples/kimi-psql/main.py` (L262-L289)

```python
async def create_psql_soul(llm: LLM, conninfo: str) -> KimiSoul:
    """创建配置了 PostgreSQL 的 KimiSoul"""
    
    # 1. 创建 Runtime（自动发现 Skills）
    runtime = await Runtime.create(
        config=config,
        llm=llm,
        session=session,
        yolo=True,
    )
    
    # Runtime.create() 内部会调用:
    # skills = discover_skills_from_roots([
    #     get_builtin_skills_dir(),  # ← 包含 kimi-cli-help
    #     get_skills_dir()
    # ])
    
    # 2. 加载 Agent（注入 Skills 到系统提示词）
    agent_file = Path(__file__).parent / "agent.yaml"
    agent = await load_agent(agent_file, runtime, mcp_configs=[])
    
    # load_agent() 内部会:
    # system_prompt = _load_system_prompt(...)
    # → 替换 ${KIMI_SKILLS} 为格式化的 Skills 列表
    
    # ... 返回 KimiSoul
```

---

### 2.3 系统提示词中的 Skills

**生成的系统提示词**（部分）:

```markdown
You are Kimi, an AI assistant...

## Available skills

- kimi-cli-help
  - Path: /path/to/kimi_cli/skills/kimi-cli-help/SKILL.md
  - Description: Answer Kimi CLI usage, configuration, and troubleshooting questions...
- skill-creator
  - Path: /path/to/kimi_cli/skills/skill-creator/SKILL.md
  - Description: Guide for creating effective skills...

## How to use skills

Identify the skills that are likely to be useful...
read the `SKILL.md` file for detailed instructions.

## PostgreSQL Assistant (from agent.yaml)

You are now a PostgreSQL assistant with read-only access...
```

**Token 消耗估算**:
- `kimi-cli-help` 元数据: ~120 tokens
- `skill-creator` 元数据: ~100 tokens
- 总计: ~220 tokens（每次 LLM 调用）

---

### 2.4 实战场景 1: 用户询问 kimi-cli 使用方法

**用户输入**:
```
用户: "如何配置 MCP 服务器？"
```

**执行流程**:

```python
# Step 1: LLM 看到系统提示词中的 Skills
system_prompt = """
...
## Available skills

- kimi-cli-help
  - Description: Answer Kimi CLI usage questions...
...
"""

# Step 2: AI 决定读取 kimi-cli-help Skill
tool_call_1 = {
    "name": "read_file",
    "arguments": {
        "path": "/path/to/kimi_cli/skills/kimi-cli-help/SKILL.md"
    }
}

# Step 3: Kimi CLI 执行文件读取
skill_content = """
---
name: kimi-cli-help
description: ...
---

# Kimi CLI Help

## Documentation

Base URL: `https://moonshotai.github.io/kimi-cli/`

### Topic Mapping
| Topic | Page |
| MCP | `/en/customization/mcp.md` |
...
"""

# Step 4: 内容追加到对话历史
# Context 增加: ~1500 tokens

# Step 5: AI 根据 Skill 指导，读取文档
tool_call_2 = {
    "name": "web_get",
    "arguments": {
        "url": "https://moonshotai.github.io/kimi-cli/en/customization/mcp.md"
    }
}

# Step 6: AI 基于文档回答用户问题
```

**关键点**:
- ✅ Skill 告诉 AI **去哪里找答案**（文档 URL）
- ✅ Skill 提供**主题映射表**（快速定位）
- ✅ AI **自主决定**读取 Skill

---

## 三、自定义工具在 kimi-psql 中的使用

### 3.1 自定义工具: ExecuteSql

**代码**: `examples/kimi-psql/main.py` (L52-L131)

```python
class ExecuteSql(CallableTool2[ExecuteSqlParams]):
    """Execute read-only SQL query in PostgreSQL database."""
    
    name: str = "ExecuteSql"
    description: str = (
        "Execute a READ-ONLY SQL query in the connected PostgreSQL database. "
        "Use this tool for SELECT queries and database introspection queries. "
        "This tool CANNOT execute write operations (INSERT, UPDATE, DELETE, DROP). "
        "For write operations, return the SQL in a markdown code block. "
        "Note: psql meta-commands (\\d, \\dt, etc.) are NOT supported - use SQL queries instead."
    )
    params: type[ExecuteSqlParams] = ExecuteSqlParams
    
    def __init__(self, conninfo: str):
        super().__init__()
        self._conninfo = conninfo
    
    async def __call__(self, params: ExecuteSqlParams) -> ToolReturnValue:
        try:
            # Connect in read-only mode
            async with await psycopg.AsyncConnection.connect(
                self._conninfo, autocommit=False
            ) as conn:
                await conn.set_read_only(True)
                async with conn.cursor() as cur:
                    await cur.execute(params.sql)
                    
                    # Format results as table
                    if cur.description:
                        rows = await cur.fetchall()
                        # ... format table ...
                        return ToolOk(output=table_text)
                    else:
                        return ToolOk(output="Query executed successfully")
        
        except psycopg.errors.ReadOnlySqlTransaction as e:
            return ToolError(
                message=f"Cannot execute write operation: {e}",
                brief="Write operation not allowed"
            )
        except Exception as e:
            return ToolError(message=f"SQL error: {e}", brief="SQL error")
```

**关键设计**:
- ✅ 只读模式（安全）
- ✅ 自动格式化表格输出
- ✅ 明确的错误处理
- ✅ 清晰的工具描述（告诉 AI 能做什么、不能做什么）

---

### 3.2 注册自定义工具

**代码**: `examples/kimi-psql/main.py` (L282-L286)

```python
# 加载 Agent（包含内置工具）
agent = await load_agent(agent_file, runtime, mcp_configs=[])

# 添加自定义 ExecuteSql 工具
cast(KimiToolset, agent.toolset).add(ExecuteSql(conninfo))

# 最终 toolset._tool_dict 包含:
# {
#     "read_file": FileReadTool(...),      # 内置
#     "write_file": FileWriteTool(...),    # 内置
#     "shell": ShellTool(...),             # 内置
#     "web_get": WebGetTool(...),          # 内置
#     "ExecuteSql": ExecuteSql(...)        # 自定义！
# }
```

---

### 3.3 工具传递给 LLM

**kosong.step() 调用**:

```python
# main.py 中使用 run_soul()，内部调用 kosong.step()
result = await kosong.step(
    chat_provider,
    system_prompt,  # 包含 Skills 列表
    toolset,        # 包含所有工具
    history,
    ...
)

# kosong 内部提取工具定义
tools = [
    {
        "type": "function",
        "function": {
            "name": "ExecuteSql",
            "description": "Execute a READ-ONLY SQL query...",
            "parameters": {
                "type": "object",
                "properties": {
                    "sql": {
                        "type": "string",
                        "description": "The SQL query to execute..."
                    }
                },
                "required": ["sql"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "read_file",
            "description": "Read file content",
            "parameters": {...}
        }
    },
    // ... 其他工具
]

# 发送给 LLM API
response = await llm_api.call(
    messages=[...],
    tools=tools  # ← 所有工具定义（占用 Context）
)
```

**Token 消耗估算**:
- `ExecuteSql` 定义: ~200 tokens
- 所有内置工具: ~1500 tokens
- 总计: ~1700 tokens（每次 LLM 调用）

---

### 3.4 实战场景 2: 用户查询数据库

**用户输入**:
```
用户: "显示所有表"
```

**执行流程**:

```python
# Step 1: LLM 看到 agent.yaml 中的提示词
system_prompt = """
...
You are now a PostgreSQL assistant...

Examples:
- User: "show all tables"
  → Use ExecuteSql with: SELECT tablename FROM pg_tables WHERE schemaname = 'public';
...
"""

# Step 2: LLM 调用 ExecuteSql 工具
tool_call = {
    "name": "ExecuteSql",
    "arguments": {
        "sql": "SELECT tablename FROM pg_tables WHERE schemaname = 'public';"
    }
}

# Step 3: Kimi CLI 执行工具
tool = toolset._tool_dict["ExecuteSql"]  # ExecuteSql 实例
result = await tool.call({"sql": "SELECT tablename FROM ..."})

# Step 4: ExecuteSql 连接数据库并执行
# 返回:
ToolOk(output="""
tablename
---------
users
orders
products

(3 rows)
""")

# Step 5: 工具结果追加到对话历史
# Context 增加: ~150 tokens

# Step 6: AI 基于结果生成友好回复
response = "数据库中有 3 个表：users, orders, products"
```

**关键点**:
- ✅ `agent.yaml` 提供**示例**（教 AI 如何使用工具）
- ✅ 工具描述**清晰**（只读、不支持 psql 命令）
- ✅ 自动格式化输出（表格）

---

## 四、Agent 配置文件详解

### 4.1 agent.yaml 完整内容

**位置**: `examples/kimi-psql/agent.yaml`

```yaml
version: 1

agent:
  extend: default  # ← 继承默认 Agent
  name: kimi-psql
  system_prompt_args:
    ROLE_ADDITIONAL: |
      You are now a PostgreSQL assistant with read-only access.

      Database Tools:
      - ExecuteSql: Execute read-only SQL queries

      When the user asks about data or wants to run queries:
      1. Use the ExecuteSql tool to run the appropriate SQL query
      2. Use proper PostgreSQL SQL syntax (psql meta-commands NOT supported)
      3. For database introspection, use SQL queries from information_schema

      Examples:
      - User: "show all tables"
        → Use ExecuteSql with: SELECT tablename FROM pg_tables WHERE schemaname = 'public';
      - User: "describe users table"
        → Use ExecuteSql with: SELECT column_name, data_type FROM information_schema.columns WHERE table_name = 'users';
      - User: "count users"
        → Use ExecuteSql with: SELECT COUNT(*) FROM users;

      For write operations (INSERT, UPDATE, DELETE), return the SQL in a markdown code block.
```

**关键设计**:
1. **extend: default**: 继承所有默认配置（Skills、工具）
2. **ROLE_ADDITIONAL**: 在默认系统提示词基础上追加
3. **清晰示例**: 教 AI 如何处理常见请求

---

### 4.2 系统提示词的合成

**最终系统提示词** = 默认提示词 + ROLE_ADDITIONAL

```markdown
# 默认部分（来自 agents/default/system.md）
You are Kimi, an AI assistant...

## Available skills
- kimi-cli-help
  - Path: ...
  - Description: ...

## How to use skills
...

# 追加部分（来自 agent.yaml 的 ROLE_ADDITIONAL）
You are now a PostgreSQL assistant with read-only access.

Database Tools:
- ExecuteSql: Execute read-only SQL queries

Examples:
- User: "show all tables"
  → Use ExecuteSql with: SELECT tablename FROM pg_tables...
...
```

**Token 消耗估算**:
- 默认部分: ~2000 tokens
- ROLE_ADDITIONAL: ~500 tokens
- 总计: ~2500 tokens

---

## 五、完整交互流程追踪

### 场景: 用户询问并查询数据库

**用户**: "kimi-psql 如何配置？然后帮我查询用户表的前 10 条记录"

---

### 阶段 1: 启动时加载

```python
# 1. Runtime 创建
runtime = await Runtime.create(...)

# 内部自动执行:
skills = discover_skills_from_roots([
    "/path/to/kimi_cli/skills",  # 内置 Skills
    "~/.kimi/skills"              # 用户 Skills
])
# 结果: [Skill(name="kimi-cli-help", ...), Skill(name="skill-creator", ...)]

skills_formatted = """
- kimi-cli-help
  - Path: /path/to/kimi_cli/skills/kimi-cli-help/SKILL.md
  - Description: Answer Kimi CLI usage...
- skill-creator
  - Path: /path/to/kimi_cli/skills/skill-creator/SKILL.md
  - Description: Guide for creating skills...
"""

# 2. Agent 加载
agent = await load_agent("agent.yaml", runtime, mcp_configs=[])

# 内部执行:
system_prompt = load_system_prompt_template()
# 模板中有: ${KIMI_SKILLS}
system_prompt = system_prompt.replace("${KIMI_SKILLS}", skills_formatted)
# 追加: agent.yaml 中的 ROLE_ADDITIONAL

# 3. 添加自定义工具
agent.toolset.add(ExecuteSql(conninfo))

# 现在 agent 包含:
# - system_prompt: 完整的系统提示词（含 Skills）
# - toolset: 内置工具 + ExecuteSql
```

---

### 阶段 2: 第一次 LLM 调用（处理 kimi-psql 配置问题）

```python
# 用户输入
user_input = "kimi-psql 如何配置？然后帮我查询用户表的前 10 条记录"

# LLM API 请求
request = {
    "messages": [
        {
            "role": "system",
            "content": """
            You are Kimi...
            
            ## Available skills
            - kimi-cli-help
              - Description: Answer Kimi CLI usage...
            
            You are now a PostgreSQL assistant...
            """
        },
        {
            "role": "user",
            "content": "kimi-psql 如何配置？然后帮我查询用户表的前 10 条记录"
        }
    ],
    "tools": [
        {"type": "function", "function": {"name": "ExecuteSql", ...}},
        {"type": "function", "function": {"name": "read_file", ...}},
        {"type": "function", "function": {"name": "web_get", ...}},
        // ... 其他工具
    ]
}

# Token 消耗:
# - System prompt: 2500 tokens
# - User message: 30 tokens
# - Tools definitions: 1700 tokens
# 总计: 4230 tokens
```

**LLM 返回**:

```json
{
    "content": "让我先查看 kimi-psql 的文档...",
    "tool_calls": [
        {
            "id": "call_1",
            "function": {
                "name": "read_file",
                "arguments": "{\"path\": \"/path/to/kimi_cli/skills/kimi-cli-help/SKILL.md\"}"
            }
        }
    ]
}
```

---

### 阶段 3: 执行 Skill 读取

```python
# Kimi CLI 执行工具
tool_result = await toolset.handle(tool_call)

# 结果:
skill_content = """
---
name: kimi-cli-help
description: ...
---

# Kimi CLI Help

...

## Source Code
Repository: https://github.com/MoonshotAI/kimi-cli
"""

# 追加到对话历史
history.append({
    "role": "tool",
    "tool_call_id": "call_1",
    "content": skill_content
})

# Context 增加: ~1500 tokens
```

---

### 阶段 4: 第二次 LLM 调用（基于 Skill 内容）

```python
# LLM API 请求
request = {
    "messages": [
        {"role": "system", "content": "..."},
        {"role": "user", "content": "kimi-psql 如何配置？..."},
        {"role": "assistant", "content": "...", "tool_calls": [...]},
        {"role": "tool", "tool_call_id": "call_1", "content": skill_content},
    ],
    "tools": [...]
}

# Token 消耗:
# - System prompt: 2500 tokens
# - User message: 30 tokens
# - Skill content: 1500 tokens
# - Tools definitions: 1700 tokens
# 总计: 5730 tokens
```

**LLM 返回**:

```json
{
    "content": "根据文档，kimi-psql 的配置在源码的 examples/kimi-psql 目录...\n\n现在让我查询用户表：",
    "tool_calls": [
        {
            "id": "call_2",
            "function": {
                "name": "ExecuteSql",
                "arguments": "{\"sql\": \"SELECT * FROM users LIMIT 10;\"}"
            }
        }
    ]
}
```

---

### 阶段 5: 执行 SQL 查询

```python
# Kimi CLI 执行工具
tool = toolset._tool_dict["ExecuteSql"]
result = await tool.call({"sql": "SELECT * FROM users LIMIT 10;"})

# ExecuteSql 内部:
# 1. 连接数据库（只读模式）
# 2. 执行 SQL
# 3. 格式化结果为表格

# 结果:
tool_result = ToolOk(output="""
id   | name     | email
-----|----------|------------------
1    | Alice    | alice@example.com
2    | Bob      | bob@example.com
...
(10 rows)
""")

# 追加到对话历史
history.append({
    "role": "tool",
    "tool_call_id": "call_2",
    "content": tool_result.output
})

# Context 增加: ~300 tokens
```

---

### 阶段 6: 第三次 LLM 调用（生成最终回复）

```python
# LLM API 请求
request = {
    "messages": [
        {"role": "system", "content": "..."},
        {"role": "user", "content": "..."},
        {"role": "assistant", "tool_calls": [...]},
        {"role": "tool", "tool_call_id": "call_1", "content": skill_content},
        {"role": "assistant", "tool_calls": [...]},
        {"role": "tool", "tool_call_id": "call_2", "content": table_output},
    ],
    "tools": [...]
}

# Token 消耗:
# - System prompt: 2500 tokens
# - 对话历史: 2000 tokens
# - Tools definitions: 1700 tokens
# 总计: 6200 tokens
```

**LLM 返回**:

```json
{
    "content": "kimi-psql 的配置方法如下：...\n\n查询到用户表的前 10 条记录：\n[展示表格]\n\n是否需要进一步的查询？"
}
```

---

## 六、Token 消耗总结

### 完整交互的 Token 消耗

| 阶段 | Input Tokens | Output Tokens |
|------|--------------|---------------|
| 第 1 次调用 | 4230 | 50 |
| Skill 读取 | - | - |
| 第 2 次调用 | 5730 | 100 |
| SQL 执行 | - | - |
| 第 3 次调用 | 6200 | 150 |
| **总计** | **16160** | **300** |

**费用估算**（以 GPT-4 Turbo 为例）:
- Input: 16160 tokens × $0.01/1K = $0.16
- Output: 300 tokens × $0.03/1K = $0.01
- **总计**: $0.17

---

### 优化建议

1. **Skill 优化**:
   - ✅ 已经很精简（2 个内置 Skills）
   - 如需添加更多，考虑精简描述

2. **系统提示词优化**:
   - ✅ ROLE_ADDITIONAL 很简洁
   - 可考虑使用 Prompt Caching（节省 ~90% 重复费用）

3. **工具优化**:
   - ✅ 只加载了必要的工具
   - 如果有很多自定义工具，考虑动态选择

---

## 七、对比：如果使用 MCP

### 假设场景：将 ExecuteSql 改为 MCP 服务器

**MCP 方式**:

```python
# 1. 创建 MCP 服务器（单独进程）
# postgresql-mcp-server/main.py
from fastmcp import FastMCP

mcp = FastMCP("PostgreSQL MCP")

@mcp.tool()
async def execute_sql(sql: str) -> str:
    """Execute read-only SQL query"""
    # ... 数据库连接和查询 ...
    return result

# 2. 启动 MCP 服务器
# uv run postgresql-mcp-server

# 3. 配置 kimi-psql 连接 MCP
mcp_configs = [
    {
        "mcpServers": {
            "postgresql": {
                "command": "uv",
                "args": ["run", "postgresql-mcp-server"]
            }
        }
    }
]

agent = await load_agent(agent_file, runtime, mcp_configs=mcp_configs)
# 现在 ExecuteSql 变成了 MCP 工具
```

---

### 对比分析

| 维度 | 自定义工具（当前） | MCP 方式 |
|------|-------------------|----------|
| **复杂度** | 简单（单文件） | 复杂（需要额外进程） |
| **灵活性** | 高（直接访问代码） | 低（需要序列化通信） |
| **可复用性** | 低（仅限本项目） | 高（其他项目也能用） |
| **维护成本** | 低 | 高 |
| **Token 消耗** | 相同（都占用 Context） | 相同 |
| **适用场景** | 单一项目定制 | 跨项目共享 |

**结论**：对于 kimi-psql 这种**单一用途**的项目，**自定义工具更合适**。

---

## 八、关键要点总结

### Skill 的作用

在 kimi-psql 中，Skill（`kimi-cli-help`）：
1. ✅ 提供文档查询指导
2. ✅ 告诉 AI 去哪里找答案
3. ✅ 自动继承（extend: default）
4. ✅ Token 消耗低（~220 tokens 元数据）

### 自定义工具的作用

`ExecuteSql` 工具：
1. ✅ 提供实际执行能力（SQL 查询）
2. ✅ 清晰的功能边界（只读）
3. ✅ 自动格式化输出
4. ✅ 与 Skill 互补（知识 + 能力）

### Agent 配置的作用

`agent.yaml`:
1. ✅ 继承默认配置（减少重复）
2. ✅ 追加特定指导（ROLE_ADDITIONAL）
3. ✅ 提供使用示例（教 AI 如何用工具）

---

## 九、实战练习建议

### 练习 1: 修改 Skill

创建自定义 Skill：`~/.kimi/skills/postgres-best-practices/SKILL.md`

```markdown
---
name: postgres-best-practices
description: PostgreSQL 查询优化和最佳实践
---

## 查询优化建议

1. 避免 SELECT *，明确指定需要的列
2. 使用 LIMIT 限制返回行数
3. 为常用查询列添加索引
...
```

### 练习 2: 添加写操作工具

创建 `ExecuteWriteSql` 工具（需要用户审批）：

```python
class ExecuteWriteSql(CallableTool2[ExecuteSqlParams]):
    """Execute write SQL with approval"""
    
    async def __call__(self, params: ExecuteSqlParams) -> ToolReturnValue:
        # 请求用户审批
        if not await runtime.approval.request(
            self.name,
            f"执行写操作: {params.sql}",
            "该操作将修改数据库"
        ):
            return ToolRejectedError()
        
        # 执行 SQL
        ...
```

### 练习 3: 集成真实 MCP 服务器

使用官方的 PostgreSQL MCP 服务器（如果有）：

```toml
# ~/.kimi/mcp-config.toml
[mcpServers.postgresql]
command = "npx"
args = ["-y", "@modelcontextprotocol/server-postgres"]
env = { DATABASE_URL = "postgresql://..." }
```

---

**文档状态**: ✅ 完成  
**实战项目**: kimi-psql  
**下一步**: 动手运行并调试 kimi-psql！

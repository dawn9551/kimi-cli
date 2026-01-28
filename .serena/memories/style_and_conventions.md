# 代码风格与约定
- 语言与版本：Python >=3.12（工具配置针对 3.14）。
- 格式与长度：遵循 ruff 格式化，行宽 100。
- Lint/静态分析：ruff（规则集 E,F,UP,B,SIM,I），类型检查使用 pyright 与 ty。
- 测试：pytest + pytest-asyncio，测试文件命名 `tests/test_*.py`。
- 编码：统一使用 UTF-8，无 BOM；避免非 ASCII 字符，除非已有且必要。
- CLI 入口：`src/kimi_cli/cli.py`（命令 `kimi` / `kimi-cli`）。
- 架构：Typer CLI，asyncio 运行时，llm 框架 kosong，MCP 集成 fastmcp，日志 loguru。
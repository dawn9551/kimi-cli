# 常用命令
- 安装与准备：`make prepare`（同步依赖并安装 git hooks）
- 格式化：`make format`
- 静态检查：`make check`（ruff + pyright + ty 等）
- 单元测试：`make test`
- AI 测试：`make ai-test`
- 构建：`make build`；生成可执行二进制：`make build-bin`
- 直接使用工具：`uv run ...`（例如 `uv run kimi --help`）
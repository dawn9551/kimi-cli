# 完成任务前检查
- 代码格式：运行 `make format`。
- 静态检查：运行 `make check`（含 ruff、pyright、ty）。
- 测试：运行 `make test`（必要时 `make ai-test`）。
- 构建验证：需要发布时运行 `make build` / `make build-bin`。
- 版本与文档：如涉及发布，更新 `pyproject.toml` 版本与 `CHANGELOG.md`。
- 提交信息：使用 Conventional Commits（如 `feat(scope): subject`）。
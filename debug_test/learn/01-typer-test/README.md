# Typer 學習指南

這些腳本旨在幫助您理解 `kimi-cli` 底層使用的 CLI 框架 `typer`。

## 如何運行

確保您在項目虛擬環境中，或者已經安裝了 `typer`：
`pip install typer`

### 1. 基礎用法
```bash
python 01_basic.py --help
python 01_basic.py Kimi
python 01_basic.py Kimi --formal --count 3
```

### 2. 子命令嵌套
```bash
python 02_nesting.py --help
python 02_nesting.py status
python 02_nesting.py user --help
python 02_nesting.py user list
```

### 3. 全局回調與上下文
```bash
python 03_callback.py --version
python 03_callback.py --verbose sync
python 03_callback.py  # 觸發無命令回調
```

### 4. 高級類型與驗證
```bash
# 注意：你需要提供一個存在的文件路徑，例如 ../../pyproject.toml
python 04_advanced_types.py ../../pyproject.toml --retry 10  # 這會報錯，因為 retry 最大為 5
python 04_advanced_types.py ../../pyproject.toml --theme green
```

### 5. 交互式 Shell 模式
```bash
# 單次運行
python 05_interactive_shell.py --name Kimi

# 進入持續交互模式
python 05_interactive_shell.py --name Kimi --shell
```

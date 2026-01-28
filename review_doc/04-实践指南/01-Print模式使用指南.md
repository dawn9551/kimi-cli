# Print 模式实用指南

## 快速开始

### 基本用法

```bash
# 最简单的方式
kimi --print -p "你的问题"

# 使用 quiet 模式（推荐）
kimi --quiet -p "你的问题"
```

## 与 Shell 模式的区别

| 特性 | Shell 模式（默认） | Print 模式 |
|------|-------------------|-----------|
| 交互性 | 交互式，可以多轮对话 | 非交互式，单次执行 |
| 审批 | 需要手动确认工具调用 | 自动批准（YOLO） |
| 输出 | 富文本、进度条、高亮 | 纯文本或 JSON |
| 适用场景 | 开发调试、探索性任务 | 脚本集成、自动化 |
| 启动 | `kimi` | `kimi --print` 或 `kimi --quiet` |

## 参数详解

### 核心参数

```bash
--print                   # 启用 print 模式
--quiet                   # 快捷方式 = --print + text + final-message-only
-p, --prompt "提示词"      # 用户提示
--final-message-only      # 只输出最终消息（不显示中间步骤）
```

### 格式控制

```bash
--output-format text          # 文本输出（默认）
--output-format stream-json   # JSON 流式输出
--input-format text           # 文本输入（默认）
--input-format stream-json    # JSON 流式输入
```

### 其他有用参数

```bash
-w, --work-dir /path/to/dir   # 指定工作目录
-m, --model model-name        # 指定模型
--max-steps-per-turn 10       # 限制最大步数
```

## 实用场景

### 1. 代码审查

```bash
# 审查当前目录的 Python 文件
git diff | kimi --quiet -p "审查这些代码改动，指出潜在问题"
```

### 2. 自动生成文档

```bash
# 为函数生成文档
cat my_function.py | kimi --quiet -p "生成 Google 风格的 docstring"
```

### 3. 日志分析

```bash
# 分析错误日志
tail -100 /var/log/app.log | kimi --quiet -p "总结错误原因和建议修复方法"
```

### 4. CI/CD 集成

```bash
#!/bin/bash
# 在 CI 中检查代码质量

git diff origin/main..HEAD | kimi --quiet \
  -p "检查这次提交是否有代码质量问题，如果有严重问题返回 ERROR，否则返回 OK" \
  > review.txt

if grep -q "ERROR" review.txt; then
  echo "代码审查失败"
  cat review.txt
  exit 1
fi
```

### 5. 批量处理

```bash
# 批量翻译文件
for file in docs/*.md; do
  cat "$file" | kimi --quiet -p "将这段文档翻译成英文" > "docs/en/$(basename $file)"
done
```

### 6. JSON 输出用于程序解析

```bash
# 获取结构化输出
kimi --print --output-format stream-json \
  -p "列出 Python 的5个最佳实践，用JSON数组格式输出" \
  | jq '.[] | select(.type == "assistant_message") | .content'
```

### 7. 与其他工具链集成

```bash
# 结合 find 和 grep
find . -name "*.py" -exec grep -l "TODO" {} \; | \
  kimi --quiet -p "统计这些文件中有多少个 TODO，并建议优先处理哪些"

# 结合 Docker
docker logs my-container --tail 50 | \
  kimi --quiet -p "这个容器日志有什么异常？"

# 结合 curl
curl -s https://api.github.com/repos/anthropics/kimi-cli | \
  kimi --quiet -p "这个 GitHub 仓库的主要信息是什么？"
```

## 输出格式对比

### 1. 默认模式（--print）

```bash
$ kimi --print -p "什么是 Python?"

Python 是一种高级编程语言...
[显示所有中间步骤和工具调用]
```

### 2. Quiet 模式（--quiet）

```bash
$ kimi --quiet -p "什么是 Python?"

Python 是一种高级编程语言，以简洁易读的语法著称。
```

### 3. Final Message Only

```bash
$ kimi --print --final-message-only -p "什么是 Python?"

Python 是一种高级编程语言，以简洁易读的语法著称。
```

### 4. JSON 输出

```bash
$ kimi --print --output-format stream-json -p "列出3个编程语言"

{"type":"turn_begin","user_input":"列出3个编程语言"}
{"type":"step_begin","n":1}
{"type":"assistant_message","content":"1. Python\n2. JavaScript\n3. Java"}
...
```

## 实际示例脚本

已创建完整的示例脚本：`debug_test/print_mode_examples.sh`

运行方式：
```bash
cd /opt/script/kimi-cli/debug_test
./print_mode_examples.sh
```

该脚本包含 7 个实用示例：
1. 简单问答
2. 文件内容分析
3. 代码解释
4. 批处理文档生成
5. JSON 输出
6. 管道操作
7. 自动化批量处理

## 常见问题

### Q1: Print 模式和 Shell 模式可以共存吗？
A: 不可以，它们是互斥的。使用 `--print` 会强制进入 print 模式。

### Q2: Print 模式会保存会话吗？
A: 会！Print 模式同样会创建 session 并保存上下文，可以用 `-C` 继续之前的会话。

```bash
# 第一次调用
kimi --print -p "创建一个TODO列表"

# 继续上次的会话
kimi --print -C -p "在TODO列表中添加一项"
```

### Q3: 如何在 print 模式中使用工具？
A: Print 模式自动启用 YOLO，工具会自动执行无需确认。

```bash
# 会自动执行文件读取工具
kimi --quiet -w /path/to/project -p "读取 README.md 并总结"
```

### Q4: 如何限制输出长度？
A: 在提示词中明确说明：

```bash
kimi --quiet -p "用一句话总结 Python"
kimi --quiet -p "用不超过50个字总结..."
```

### Q5: Print 模式支持图片输入吗？
A: 支持！但需要使用 stream-json 格式或其他方式传递图片路径。

## 性能提示

1. **使用 --quiet**：最快的输出方式
2. **限制步数**：`--max-steps-per-turn 5` 避免过长执行
3. **指定工作目录**：`-w` 避免在错误目录操作
4. **选择合适的模型**：`-m` 对简单任务使用更快的模型

## 安全注意事项

⚠️ Print 模式会自动执行工具（YOLO 模式），请注意：

1. 不要在不信任的目录运行
2. 小心执行可能修改文件的操作
3. 在生产环境使用前先在测试环境验证
4. 审查 AI 生成的命令再执行

## 最佳实践

1. **脚本中使用 `--quiet`**：输出最简洁
2. **CI/CD 中检查退出码**：根据输出判断成功/失败
3. **使用 `--work-dir`**：明确指定工作目录
4. **结合 `jq` 处理 JSON**：解析 stream-json 输出
5. **添加超时控制**：避免长时间运行
6. **日志记录**：保存输出用于审计

---

**相关文档**：
- CLI 参数详解：`review_doc/debug/doc/01_cli_entry_analysis.md`
- 完整用法：`kimi --help`

#!/bin/bash
# kimi-cli Print 模式使用示例

set -e

echo "=========================================="
echo "kimi-cli Print 模式使用示例"
echo "=========================================="
echo ""

# 示例 1: 简单问答
echo "📝 示例 1: 简单问答"
echo "命令: kimi --print -p '什么是 Python?'"
echo "---"
kimi --print -p "用一句话解释什么是 Python"
echo ""
echo ""

# 示例 2: 从文件读取内容并分析
echo "📄 示例 2: 分析文件内容"
echo "命令: cat README.md | kimi --quiet -p '用3个要点总结这个项目'"
echo "---"
head -20 ../../../README.md | kimi --quiet -p "用3个要点总结这个项目的功能"
echo ""
echo ""

# 示例 3: 代码解释
echo "💻 示例 3: 解释代码"
echo "命令: kimi --print --final-message-only -p '解释这段代码'"
echo "---"
cat << 'EOF' | kimi --print --final-message-only -p "用一句话解释这段代码的作用"
def fibonacci(n):
    if n <= 1:
        return n
    return fibonacci(n-1) + fibonacci(n-2)
EOF
echo ""
echo ""

# 示例 4: 批处理模式（不需要交互）
echo "🔄 示例 4: 批处理 - 生成文档"
echo "命令: kimi --quiet -p '为这个函数生成docstring'"
echo "---"
cat << 'EOF' | kimi --quiet -p "为这个Python函数生成Google风格的docstring"
def calculate_total(items, tax_rate=0.1):
    subtotal = sum(item['price'] * item['quantity'] for item in items)
    tax = subtotal * tax_rate
    return subtotal + tax
EOF
echo ""
echo ""

# 示例 5: JSON 输出（适合程序解析）
echo "📊 示例 5: JSON 输出格式"
echo "命令: kimi --print --output-format stream-json -p '列出3种编程语言'"
echo "---"
kimi --print --output-format stream-json -p "列出3种流行的编程语言，每个只用一个词" 2>/dev/null | head -20
echo ""
echo "..."
echo ""

# 示例 6: 结合其他工具的管道操作
echo "🔧 示例 6: 管道操作"
echo "命令: find . -name '*.py' | head -5 | kimi --quiet -p '这些是什么类型的文件?'"
echo "---"
find ../../../src -name "*.py" -type f | head -5 | kimi --quiet -p "这个列表中有多少个文件？"
echo ""
echo ""

# 示例 7: 多次调用（脚本自动化）
echo "🤖 示例 7: 自动化脚本"
echo "多次调用 kimi --quiet 进行批量处理"
echo "---"
for lang in Python JavaScript Go; do
    echo -n "Q: $lang 的主要用途? A: "
    echo "$lang" | kimi --quiet -p "用一句话说明 $lang 编程语言的主要用途"
done
echo ""

echo "=========================================="
echo "✅ 示例演示完成！"
echo "=========================================="
echo ""
echo "📚 Print 模式的关键参数："
echo "  --print              : 启用 print 模式（非交互）"
echo "  --quiet              : 快捷方式（等同于 --print + text输出 + 只显示最终消息）"
echo "  --final-message-only : 只输出最终的助手消息"
echo "  --output-format      : 输出格式（text 或 stream-json）"
echo "  --input-format       : 输入格式（text 或 stream-json）"
echo ""
echo "💡 提示："
echo "  - print 模式会自动启用 --yolo（不需要手动确认）"
echo "  - 适合脚本集成、CI/CD 管道、自动化任务"
echo "  - 使用 --quiet 可以获得最简洁的输出"
echo ""

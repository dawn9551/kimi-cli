#!/bin/bash
# kimi-cli Print 模式快速测试脚本

echo "🚀 kimi-cli Print 模式快速测试"
echo "================================"
echo ""

# 检查 kimi 命令
KIMI_CMD=""
if command -v kimi &> /dev/null; then
    KIMI_CMD="kimi"
    echo "✅ 使用系统安装的 kimi 命令"
elif command -v uv &> /dev/null; then
    KIMI_CMD="uv run kimi"
    echo "✅ 使用 uv run kimi 方式运行"
else
    echo "❌ 错误: 未找到 kimi 或 uv 命令"
    echo "请先安装 kimi-cli 或 uv"
    exit 1
fi

echo ""

# 测试 1: 最简单的问答
echo "📝 测试 1: 简单问答"
echo "命令: $KIMI_CMD --quiet -p '用一句话解释什么是 AI'"
echo "---"
$KIMI_CMD --quiet -p "用一句话解释什么是 AI"
echo ""
echo ""

# 测试 2: 代码解释
echo "💻 测试 2: 代码解释"
echo "---"
cat << 'EOF' | $KIMI_CMD --quiet -p "这段代码做什么？用一句话回答"
def hello():
    print("Hello, World!")
EOF
echo ""
echo ""

# 测试 3: 数学计算
echo "🔢 测试 3: 数学计算"
echo "---"
$KIMI_CMD --quiet -p "2的10次方是多少？只回答数字"
echo ""
echo ""

echo "================================"
echo "✅ 测试完成！"
echo ""
echo "💡 提示："
echo "  - 使用 '$KIMI_CMD --print -p \"问题\"' 启动 print 模式"
echo "  - 使用 '$KIMI_CMD --quiet -p \"问题\"' 获得最简洁输出"
echo "  - 查看完整示例: ./print_mode_examples.sh"
echo "  - 查看详细文档: ../review_doc/debug/doc/03_print_mode_guide.md"
echo ""

#!/bin/bash
# kimi-cli Print 模式 Mock 测试（不需要真实 API）

echo "🧪 kimi-cli Print 模式 Mock 测试"
echo "================================"
echo "说明: 这个测试使用模拟数据，不需要真实的 API Key"
echo ""

# 创建临时 mock 脚本
MOCK_KIMI="/tmp/mock_kimi_$$.sh"
cat > "$MOCK_KIMI" << 'MOCK_EOF'
#!/bin/bash
# Mock kimi command for testing

# 解析参数
PROMPT=""
IS_QUIET=false
IS_PRINT=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --quiet)
            IS_QUIET=true
            IS_PRINT=true
            shift
            ;;
        --print)
            IS_PRINT=true
            shift
            ;;
        -p|--prompt)
            PROMPT="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

# 从标准输入读取（如果有）
if [ -z "$PROMPT" ] && [ ! -t 0 ]; then
    INPUT=$(cat)
    PROMPT="输入内容：$INPUT"
fi

# 模拟响应
if [ "$IS_PRINT" = true ]; then
    # 根据提示词生成不同的模拟响应
    case "$PROMPT" in
        *"AI"*)
            echo "AI（人工智能）是一种使计算机系统能够执行通常需要人类智能的任务的技术。"
            ;;
        *"hello"*|*"Hello"*)
            echo "这段代码定义了一个名为 hello 的函数，用于打印 'Hello, World!' 到控制台。"
            ;;
        *"2的10次方"*|*"2^10"*)
            echo "1024"
            ;;
        *"代码"*)
            echo "这段代码创建了一个简单的函数。"
            ;;
        *)
            echo "这是对您问题的模拟响应：$PROMPT"
            ;;
    esac
else
    echo "请使用 --print 或 --quiet 模式"
    exit 1
fi
MOCK_EOF

chmod +x "$MOCK_KIMI"

# 运行测试
KIMI_CMD="$MOCK_KIMI"

echo "📝 测试 1: 简单问答"
echo "命令: $KIMI_CMD --quiet -p '用一句话解释什么是 AI'"
echo "---"
$KIMI_CMD --quiet -p "用一句话解释什么是 AI"
echo ""
echo ""

echo "💻 测试 2: 代码解释"
echo "---"
cat << 'EOF' | $KIMI_CMD --quiet -p "这段代码做什么？用一句话回答"
def hello():
    print("Hello, World!")
EOF
echo ""
echo ""

echo "🔢 测试 3: 数学计算"
echo "---"
$KIMI_CMD --quiet -p "2的10次方是多少？只回答数字"
echo ""
echo ""

# 清理
rm -f "$MOCK_KIMI"

echo "================================"
echo "✅ Mock 测试完成！"
echo ""
echo "ℹ️  这是模拟测试，展示了 print 模式的工作流程"
echo ""
echo "💡 要使用真实的 kimi-cli："
echo "  1. 配置 API Key（查看 ../review_doc/debug/doc/04_configuration_setup.md）"
echo "  2. 运行: ./test_print_mode.sh"
echo ""
echo "📚 相关文档："
echo "  - 配置指南: ../review_doc/debug/doc/04_configuration_setup.md"
echo "  - Print 模式详解: ../review_doc/debug/doc/03_print_mode_guide.md"
echo ""

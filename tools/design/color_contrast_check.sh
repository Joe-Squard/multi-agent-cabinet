#!/bin/bash
# color_contrast_check.sh - カラーコントラスト比チェック (WCAG)
# 使い方: ./tools/design/color_contrast_check.sh "#FFFFFF" "#333333"

FG="${1:-#FFFFFF}"
BG="${2:-#000000}"

echo "🎨 カラーコントラストチェック"
echo "================================"
echo "  前景色: $FG"
echo "  背景色: $BG"
echo ""
echo "WCAG 基準:"
echo "  AA (通常テキスト): 4.5:1 以上"
echo "  AA (大きいテキスト): 3:1 以上"
echo "  AAA (通常テキスト): 7:1 以上"
echo ""
echo "※ 正確な計算には Web ツール (https://webaim.org/resources/contrastchecker/) を使用してください"

#!/bin/bash
# test_scenario_gen.sh - テストシナリオ雛形生成
# 使い方: ./tools/uat/test_scenario_gen.sh "機能名"

FEATURE_NAME="${1:-機能名}"
OUTPUT_FILE="queue/reports/uat_scenario_$(date +%Y%m%d_%H%M%S).md"

cat > "$OUTPUT_FILE" <<EOF
# UAT テストシナリオ: ${FEATURE_NAME}

作成日: $(date -Iseconds)

## 前提条件

- [ ] テスト環境が利用可能
- [ ] テストデータが準備済み
- [ ] テストアカウントが利用可能

## テストシナリオ

### シナリオ 1: 正常系 - 基本操作
| 項目 | 内容 |
|------|------|
| 目的 | |
| 前提条件 | |
| 手順 | 1. <br>2. <br>3. |
| 期待結果 | |
| 実際結果 | |
| 判定 | PASS / FAIL |

### シナリオ 2: 正常系 - 代替フロー
| 項目 | 内容 |
|------|------|
| 目的 | |
| 前提条件 | |
| 手順 | 1. <br>2. <br>3. |
| 期待結果 | |
| 実際結果 | |
| 判定 | PASS / FAIL |

### シナリオ 3: 異常系 - エラーケース
| 項目 | 内容 |
|------|------|
| 目的 | |
| 前提条件 | |
| 手順 | 1. <br>2. <br>3. |
| 期待結果 | |
| 実際結果 | |
| 判定 | PASS / FAIL |

## 総合判定

- [ ] 全シナリオ PASS
- [ ] 重大バグなし
- [ ] 受入条件充足

**判定**: ACCEPT / REJECT
EOF

echo "📋 テストシナリオを生成しました: $OUTPUT_FILE"

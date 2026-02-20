# /phase-transition — フェーズ遷移

プロジェクトのフェーズを遷移します。

## 使い方

```
/phase-transition <project> <target_phase>
/phase-transition <project> status
/phase-transition list
```

## フェーズ

| フェーズ | 強制レベル | 説明 |
|---|---|---|
| genesis | L2 | 提案のみ — 最大の開発速度。main 直接コミット可 |
| growth | L4 | 警告 — feature ブランチ必須、TDD 強制、QA 非同期レビュー |
| maintenance | L5 | ブロック — main 直接コミット禁止、セルフレビュー必須、クロスレビュー |

## 実行手順

1. ユーザーから引数を受け取る（project名、target_phase）
2. 引数がない場合は `list` を実行して全プロジェクトの状態を表示
3. `status` の場合は対象プロジェクトの状態を表示
4. 遷移の場合は以下を実行:

```bash
cd /home/joe/joe-scratchpad/multi-agent-cabinet
# --force で確認プロンプトをスキップ（スキルから実行するため）
echo "y" | bash scripts/phase_transition.sh <project> <target_phase>
```

5. 遷移結果をユーザーに報告

## 例

```
/phase-transition my-app growth
/phase-transition my-app status
/phase-transition list
```

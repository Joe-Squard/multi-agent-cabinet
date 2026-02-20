# /ship-to-develop — develop へのマージ

feature ブランチを develop にマージします（PR 作成 → QA 承認待ち → squash merge）。

## 使い方

```
/ship-to-develop [branch_name]
```

## 実行手順

### Step 1: ブランチ確認
```bash
cd <worktree_path>
git branch --show-current  # feature/* であることを確認
git status                 # 未コミットの変更がないことを確認
```

### Step 2: プッシュ
```bash
git push -u origin <branch_name>
```

### Step 3: PR 作成
```bash
gh pr create \
  --base develop \
  --head <branch_name> \
  --title "<conventional commit prefix>: <description>" \
  --body "$(cat <<'EOF'
## Summary
<リリーススペックからの要約>

## Changes
<変更ファイル一覧>

## Test Plan
- [ ] 全テスト通過
- [ ] セルフレビュー完了

## Release Spec
<リリーススペックへのリンク>
EOF
)"
```

### Step 4: QA 大臣にレビュー依頼
```bash
bash scripts/inbox_write.sh m_qa task "PR #<number> のレビューをお願いします: <PR URL>"
```

### Step 5: マージ（QA 承認後）
```bash
# QA の承認を確認
gh pr checks <number>
gh pr reviews <number>

# squash merge
gh pr merge <number> --squash --delete-branch
```

## 注意事項
- main への直接マージは gh-guard がブロック
- QA の承認がない場合はマージしない
- PM のみがこのスキルを実行する想定

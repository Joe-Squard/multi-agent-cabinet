# /git-worktrees — Git Worktree 管理

プロジェクトの worktree を管理します（大臣×プロジェクト単位）。

## 使い方

```
/git-worktrees create <project> <minister_type> [branch_name]
/git-worktrees switch <project> <minister_type> <branch_name>
/git-worktrees list [project]
/git-worktrees cleanup <project> [minister_type]
/git-worktrees status <project> <minister_type>
```

## 実行手順

1. ユーザーから引数を受け取る
2. 引数がない場合は `list` を実行

```bash
cd /home/joe/joe-scratchpad/multi-agent-cabinet
bash scripts/worktree_manager.sh <command> [args...]
```

3. 結果をユーザーに報告

## Worktree 戦略

- **1大臣 × 1プロジェクト = 1 worktree**（使い回し）
- deps install は初回のみ
- ブランチ切り替えで同じ worktree を再利用
- パス: `.worktrees/<project>/<minister_type>/`

---
name: skill-creator
description: 作業中に発見したパターンを再利用可能なスキルとして作成する
---

# Skill Creator

作業中に発見した再利用可能なパターンをスキルとして永続化します。

## 判定基準（4条件すべて満たすこと）

1. **再利用性**: 他のプロジェクトや別の場面でも使えるパターン
2. **複雑性**: 単純すぎず、手順や専門知識が必要
3. **安定性**: 頻繁に変わらない手順やルール
4. **価値**: スキル化することで明確なメリットがある（時間短縮、品質向上）

## 作成手順

1. **最新仕様を確認**: WebSearch で対象技術の最新情報を確認（必須）
2. **SKILL.md を作成**: 下記テンプレートに従い YAML frontmatter + Markdown で作成
3. **保存**: `~/.claude/skills/cabinet-{skill-name}/SKILL.md` に保存
4. **記録**: dashboard.md に作成記録を追記

## テンプレート

```markdown
---
name: {skill-name}
description: {1行の説明}
---

# {スキル名}

{スキルの概要: 何をするスキルか、いつ使うか}

## 前提条件

- {必要なツール、環境、知識}

## 手順

1. {ステップ1}
2. {ステップ2}
3. {ステップ3}

## 例

{具体的な使用例}

## 注意事項

- {知っておくべきこと、よくある落とし穴}
```

## スキル名の規則

- `cabinet-` プレフィックスを付ける（Cabinet System 由来であることを示す）
- ケバブケース（例: `cabinet-react-migration`, `cabinet-api-design`）
- 短く明確な名前

## 保存先

- グローバルスキル: `~/.claude/skills/cabinet-{name}/SKILL.md`
- ローカルスキル: `skills/{name}/SKILL.md`（このリポジトリ内）

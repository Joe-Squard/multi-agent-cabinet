# /security-balance — 4軸セキュリティトレードオフ評価

セキュリティ判断を4つの軸で定量評価し、バランスの取れた判断を支援します。

## 使い方

```
/security-balance <セキュリティに関する判断事項>
```

## 4軸評価

| 軸 | 説明 | スコア |
|---|---|---|
| **Security** | 攻撃面の減少、脆弱性リスク | 1-5 |
| **Velocity** | 開発速度への影響 | 1-5 |
| **Operations** | 運用・管理コスト | 1-5 |
| **User Experience** | ユーザー体験への影響 | 1-5 |

## 実行手順

1. ユーザーの判断事項を分析
2. 各選択肢について4軸のスコアを算出
3. レーダーチャート風に可視化:

```
        Security
           5
           |
Velocity --+-- Operations
           |
         UX
```

4. 各選択肢のトレードオフを説明
5. 推奨案とその理由を提示
6. DECISIONS.md への記録を提案

## 例

```
/security-balance JWT vs Session-based 認証のどちらを採用すべきか

=== 評価結果 ===

案A: JWT
  Security:   3 (トークン漏洩リスク、失効が困難)
  Velocity:   5 (ステートレス、実装が容易)
  Operations: 4 (サーバー負荷低)
  UX:         4 (シームレスな認証)

案B: Session-based
  Security:   4 (サーバー側で即座に失効可能)
  Velocity:   3 (セッションストア必要)
  Operations: 3 (セッション管理必要)
  UX:         3 (セッション切れ時の再認証)
```

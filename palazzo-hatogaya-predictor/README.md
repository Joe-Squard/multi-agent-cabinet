# 🎰 パラッツォ鳩ヶ谷 予想システム（AT機専用 / 立ち回りナビ付き）

**当日の「おすすめ台・設定が入っていそうな台・激アツ台」を予想し、さらに「朝一に座るならこの台」「今から動くならこの台」という立ち回りまでリアルタイムに提示する自動更新システム。**

対象は **AT機（スマスロ含む）専用**。ジャグラー等のAタイプは対象外です。
初当たり確率の設定差からベイズ設定判別を行い、天井・現在ハマりG数・イベント傾向を
組み合わせて、狙い目と移動判断を自動でランク付けします。

---

## ⚠️ はじめに（重要）

- 本システムは **統計的推定** ツールです。設定は非公開・出玉には乱数（分散）が伴うため、
  **「完璧な的中（100%）は原理的に不可能」** です。勝利を保証するものではありません。
- **20歳未満の遊技は法律で禁止** されています。ギャンブル等依存症にご注意ください。
  遊技は必ず **余裕資金の範囲** で、自己責任でお楽しみください。
- 外部データサイト取得（`web`）を使う場合は **利用規約・robots.txt を必ず確認** し、
  アクセス間隔などのマナー・法令を守ってください（順守は利用者責任）。
- 同梱の機種スペック値（初当たり・天井・機械割）や傾向は **参考値／経験則の仮説** です。
  実運用前に最新の公式・信頼できる情報へ更新してください（すべて YAML で編集可）。

---

## 何ができるか

| 機能 | 説明 |
|---|---|
| 🔥 激アツ台 | データが揃い、超高設定(5〜6)である確率が高い台 |
| ⭐ 設定示唆台 | 高設定(4以上)である確率が基準を超えた台 |
| 👍 おすすめ台 | 総合期待度が高い台 |
| 🌅 **朝一プラン** | 開店前の狙い目。優遇されやすい機種・座るべき台番号を提示 |
| 🏃 **移動プラン** | **リアルタイム**の移動判断。当たりが軽く・浅い（はまってない）・天井接近の台へ |
| 📈 期待値表示 | 期待機械割・残り期待差枚をリアルタイム算出 |
| 🔄 自動更新 | 営業時間中に一定間隔で再計算（cron / 常駐 / GitHub Actions） |
| 🧠 傾向学習 | 過去の予想スナップショットからホールの癖を学習し補正 |
| 📊 3形式出力 | ターミナル / JSON（連携用） / HTMLダッシュボード |

---

## 立ち回り（Tachimawari）

### 🌅 朝一プラン（データが出る前）

イベント・末尾・ゾロ目・角台・看板機種・学習傾向から「本日の優遇されやすい機種」と
「座るならこの台番号」を提示します。開店前〜朝イチの台選びに。

### 🏃 移動プラン（リアルタイム）

今どの台に移動して座るのが得か、を実データからスコア化します。
ご要望の「当たりが軽い・一定はまってない・まだ大当たりいけそうな台へ動く」を次で評価:

```
move_score = 0.5·当たりの軽さ + 0.3·状態 + 0.2·残り期待値
```

- **当たりの軽さ** = 高設定期待度 P(設定4以上)。実測の初当たりが軽いほど高い。
- **状態** = 現在ハマりG数と天井距離。
  - 浅い（天井比が低い）＝「はまってない・軽く引ける」→ 高評価
  - 天井接近（天井比が高い）＝「当選が近い」→ 高評価（別枠で天井狙い表示）
- **残り期待値** = 閉店までの期待差枚。

アクション表示:

| 表示 | 意味 |
|---|---|
| 🎯 移動推奨 | 軽くて浅い（伸びしろあり）本命。今から動くならここ |
| ⏰ 天井狙い | 天井接近で当選が近い |
| 🚪 撤退/回避 | 低設定濃厚かつ期待値マイナス（座らない／離れる） |

自動更新のたびに再計算されるため、**時間経過（データ増加・ハマり進行）に応じて
おすすめの移動先がリアルタイムに変わります。**

---

## 仕組み（方法論）

### 1. ベイズ設定判別（AT機 / 初当たり）

AT機は「初当たり確率(hatsuatari)」の設定差を主軸に判別します。初当たりを
「1ゲームあたり確率 p の事象」とみなし、G ゲーム中の発生回数 k を **ポアソン分布** で評価。
設定ごとの尤度を掛け合わせ、事前分布と組み合わせて **設定1〜6の事後確率** を求めます。

```
P(設定 s | データ) ∝ prior(s) × Poisson(初当たり回数 | G · p_s)
```

> AT機は初当たり回数のサンプルが少ないため、1日のデータだけでは判別が“ぼやける”のが
> 普通です（分散が大きい）。だからこそ、天井・状態・期待値・優遇を束ねる**立ち回り**の
> 価値が高くなります。

### 2. ホール傾向・イベント分析（経験則）

台番号パターンと当日イベントから **事前注目度スコア** を算出し、設定の
**事前分布(prior)** に変換して 1. のベイズ推論へ渡します（末尾・ゾロ目・角台・看板機種・
イベント日・**過去データからの学習傾向**）。

### 3. 統合スコアリング

```
総合スコア = 信頼度 × データ判別 + (1 − 信頼度) × 事前パターン
```

- **開店直後**（データ薄い）→ 事前パターンが主役（＝朝イチの狙い目）
- **夕方**（データ潤沢）→ 実測の設定判別が主役（＝激アツの確定寄り）

---

## クイックスタート

```bash
cd palazzo-hatogaya-predictor
pip install -r requirements.txt          # コアは PyYAML のみ

python -m palazzo_predictor predict       # 当日の予想＋立ち回り（デモデータ）
python -m palazzo_predictor strategy      # 立ち回り（朝一＋移動）だけ表示
python -m palazzo_predictor predict --format all   # HTMLダッシュボードも生成
```

`pip install -e .` で `palazzo-predict` コマンドが使えます。

---

## CLI の使い方

```bash
# 予想＋立ち回りを1回実行
python -m palazzo_predictor predict [--date YYYY-MM-DD] [--source demo|file|web]
                                    [--mode auto|preday] [--format text|json|html|all]
                                    [--top N] [--no-learn] [--no-save] [--quiet]

# 立ち回り集中ビュー（朝一プラン＋移動プラン）
python -m palazzo_predictor strategy [--date ...] [--source ...]
python -m palazzo_predictor move            # strategy のエイリアス

# 自動更新（営業時間中、一定間隔でループ）
python -m palazzo_predictor watch --interval 30 [--source ...] [--no-hours]
python -m palazzo_predictor watch --once

# デモCSVを data/raw に書き出し（フォーマット確認）
python -m palazzo_predictor demo-data --date 2026-07-27

# 設定サマリ（登録機種・天井・島構成）
python -m palazzo_predictor info
```

- `--mode preday` … データが出る前の **事前予想（朝一プラン中心）**

---

## 自動更新のセットアップ

### A) 常駐プロセス
```bash
./scripts/watch.sh 30            # 30分間隔で更新し続ける（Ctrl+Cで停止）
```
### B) cron（推奨）
```bash
./scripts/install_cron.sh 30           # 営業時間9-22時台に30分毎
./scripts/install_cron.sh --remove     # 解除
```
### C) GitHub Actions（サーバー不要）
`.github/workflows/daily-update.yml` が JST 9/12/15/18/21 時に予想を生成し `output/` を
アーティファクト保存。GitHub Pages 有効化で `latest.html` を自動公開。

---

## データの用意（実運用）

### file ソース（CSV）

`config/hall.yaml` の `data_source.kind` を `file` にし、`data/raw/<日付>.csv` を置きます。

```csv
machine_no,model_key,total_games,hatsuatari,current_games,diff_coins
201,smash_hokuto,6282,15,820,47
202,monkey_turn_5,8050,32,1,88
```

| 列 | 意味 | 必須 |
|---|---|---|
| `machine_no` | 台番号 | ✅ |
| `model_key` | 機種キー（`config/machines.yaml` のキー） | ✅ |
| `total_games` | 総回転数(G) | ✅ |
| `hatsuatari` | 初当たり回数（設定判別の主軸） | ✅ |
| `current_games` | 現在ハマりG数（最後の当たりからの回転数。移動プランに使用） | 任意 |
| `diff_coins` | 差枚 | 任意 |

- 見本: [`data/demo/sample_2026-07-27.csv`](data/demo/sample_2026-07-27.csv)
- `current_games` が無くても設定判別・激アツ判定は動作します（移動プランの状態評価のみ簡略化）。

### web ソース（スクレイパー雛形）

`config/hall.yaml` の `data_source.web` を設定し、`WebDataSource._parse()` を対象サイトの
HTML構造に合わせて実装します。**利用規約・robots.txt の順守は利用者責任** です。

---

## 設定ファイル（すべて YAML）

| ファイル | 内容 |
|---|---|
| `config/machines.yaml` | AT機スペック（初当たり設定差・機械割・**天井**・ゾーン） |
| `config/hall.yaml` | ホール情報・しきい値・**立ち回りパラメータ**・傾向・島構成・データソース |
| `config/events.yaml` | イベント/傾向カレンダー |

### 機種を追加する（AT機）

```yaml
new_at_machine:
  name: "機種名"
  type: AT
  bet_per_game: 3
  setting_count: 6
  ceiling_games: 900          # 天井（立ち回り用）
  zones: [[0, 40], [100, 140]] # 当たりゾーン（任意）
  indicators:
    hatsuatari: {1: 399.0, 2: 380.0, 3: 360.0, 4: 340.0, 5: 320.0, 6: 300.0}
  payout: {1: 97.8, 2: 98.9, 3: 100.3, 4: 104.8, 5: 108.9, 6: 112.6}
```

島（`config/hall.yaml` の `tendencies.islands`）に台番号レンジと機種を割り当てます。

### 立ち回りの調整

`config/hall.yaml` の `strategy` でスコア重み・天井接近しきい値・撤退基準などを調整できます
（`weight_setting`, `weight_state`, `weight_ev`, `shallow_ratio`, `ceiling_near_ratio` など）。

---

## 収録機種（初期・すべて参考値）

スマスロ北斗の拳 / Lモンキーターン5 / L沖ドキ！GOLD / L押忍!番長ZERO /
L転生したらスライムだった件 / Lゴジラ対エヴァンゲリオン

`config/machines.yaml` で自由に追加・削除・数値更新できます。

---

## テスト

```bash
python -m unittest discover -s tests -p "test_*.py" -v
```

標準ライブラリの `unittest` のみ（pytest でも可）。判別・イベント・推薦・**立ち回り**・
エンドツーエンドを 35 ケースで検証します。

---

## ディレクトリ構成

```
palazzo-hatogaya-predictor/
├── config/
│   ├── machines.yaml      # AT機スペック（初当たり設定差・天井・ゾーン）
│   ├── hall.yaml          # ホール設定・しきい値・立ち回りパラメータ・島構成
│   └── events.yaml        # イベントカレンダー
├── src/palazzo_predictor/
│   ├── setting_estimator.py  # ★ベイズ設定判別（初当たり）
│   ├── hall_analyzer.py   # ★ホール傾向・イベント・学習
│   ├── strategy.py        # ★立ち回り（朝一プラン＋リアルタイム移動プラン）
│   ├── recommender.py     # 推薦スコアリング（激アツ/設定示唆/おすすめ）
│   ├── data_source.py     # demo / file / web データ供給
│   ├── report.py          # text / json / html 出力
│   ├── updater.py         # オーケストレーション + 自動更新ループ
│   ├── config.py / models.py / cli.py
├── data/{demo,raw,processed}/
├── output/                # 生成レポート
├── scripts/{run_daily,watch,install_cron}.sh
├── tests/
└── .github/workflows/daily-update.yml
```

---

## よくある質問

**Q. 「完璧」に当たりますか？**
いいえ。設定は非公開・出玉は乱数を含むため 100% はあり得ません。特にAT機は初当たり
サンプルが少なく単日判別はぶれます。本ツールは「観測データ・天井・優遇・期待値」から
統計的に最も確からしい判断と立ち回りを示すものです。無理な投資は避けてください。

**Q. スペック値が実機と違う気がします。**
`config/machines.yaml` は参考値です。最新の公表値・信頼できる解析値に置き換えてください。

**Q. 現在ハマりG数はどうやって入れるの？**
データロボット/データサイトに表示される「現在のゲーム数（最後の当たりからの回転数）」を
CSV の `current_games` に入れます。無い場合は移動プランの状態評価が簡略化されるだけで、
設定判別・激アツ判定は動作します。

---

## ライセンス

MIT License

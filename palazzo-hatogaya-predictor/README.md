# 🎰 パラッツォ鳩ヶ谷 予想システム

**当日の「おすすめ台・設定が入っていそうな台・激アツ台」を、ベイズ設定判別とホール傾向分析で予想する自動更新システム。**

パチスロのホールデータ（総回転数・BIG・REG・ブドウ）から各台の設定を統計推定し、
イベント日や台番号パターン（末尾・ゾロ目・角台）と組み合わせて、狙い目を自動でランク付けします。
朝の「事前予想」から、データが揃うほど鋭くなる「リアルタイム判別」まで一気通貫。

---

## ⚠️ はじめに（重要）

- 本システムは **統計的推定** を行うツールです。パチスロの設定は非公開であり、出玉には
  必ず乱数（分散）が伴います。したがって **「完璧な的中（100%）は原理的に不可能」** です。
  本ツールは「根拠のある確率」を提示するもので、勝利を保証するものではありません。
- **20歳未満の遊技は法律で禁止** されています。ギャンブル等依存症にご注意ください。
  遊技は必ず **余裕資金の範囲** で、自己責任でお楽しみください。
- 外部データサイトの取得（`web` ソース）を使う場合、対象サイトの **利用規約・robots.txt を必ず確認** し、
  アクセス間隔などのマナー・法令を守ってください。順守は利用者の責任です。
- 同梱の機種スペック値・イベント傾向は **参考値／経験則の仮説** です。実運用前に
  信頼できる最新情報で更新してください（すべて YAML で編集できます）。

---

## 何ができるか

| 機能 | 説明 |
|---|---|
| 🔥 激アツ台 | データが揃い、超高設定(5〜6)である確率が高い台 |
| ⭐ 設定示唆台 | 高設定(4以上)である確率が基準を超えた台 |
| 👍 おすすめ台 | 総合期待度が高い台（朝の事前パターン or 中程度のデータ根拠） |
| 📈 期待値表示 | 期待機械割・残り期待差枚をリアルタイム算出 |
| 🗓 事前予想 | 開店前でも、イベント・末尾・ゾロ目・角台から狙い目を提示 |
| 🔄 自動更新 | 営業時間中に一定間隔で再計算（cron / 常駐 / GitHub Actions） |
| 🧠 傾向学習 | 過去の予想スナップショットからホールの癖を学習し精度を補正 |
| 📊 3形式出力 | ターミナル / JSON（連携用） / HTMLダッシュボード |

---

## 仕組み（方法論）

### 1. ベイズ設定判別（実データ）

各指標（BIG・REG・ブドウ）を「1ゲームあたり確率 p の事象」とみなし、G ゲーム中の
発生回数 k を **ポアソン分布** で評価します。設定 s ごとの尤度を掛け合わせ、事前分布と
組み合わせて **設定1〜6の事後確率** を求めます。

```
P(設定 s | データ) ∝ prior(s) × Π_指標 Poisson(k | G·p_{s,指標})
```

- REG 確率は多くのジャグラー系で最も設定差が大きく、判別の主役になります。
- サンプル（G数）が増えるほど事後分布が尖り、**信頼度(confidence)** が上がります。
- 事後分布から **期待設定・期待機械割・残り期待差枚** を算出します。

### 2. ホール傾向・イベント分析（経験則）

台番号パターンと当日イベントから **事前注目度スコア** を算出し、これを設定の
**事前分布(prior)** に変換して 1. のベイズ推論に渡します。

- 末尾狙い（イベント優遇末尾）、ゾロ目台、角台、看板機種
- イベント日（0のつく日 / 7のつく日 / ゾロ目の日 / 週末 / 特定日）
- **過去データから学習した** 末尾別・機種別の高設定傾向

### 3. 統合スコアリング

```
総合スコア = 信頼度 × データ判別 + (1 − 信頼度) × 事前パターン
```

- **開店直後**（データ薄い）→ 事前パターンが主役（＝朝イチの狙い目）
- **夕方**（データ潤沢）→ 実測の設定判別が主役（＝激アツの確定寄り）
- その中間は自動でブレンドされ、時間帯に応じて自然に判断が移行します。

---

## クイックスタート

```bash
cd palazzo-hatogaya-predictor

# 依存インストール（コアは PyYAML のみ）
pip install -r requirements.txt

# そのまま動く（内蔵デモデータで当日の予想を表示）
python -m palazzo_predictor predict

# イベント日を指定して上位だけ表示
python -m palazzo_predictor predict --date 2026-07-27 --top 5

# HTMLダッシュボードも生成（output/latest.html をブラウザで開く）
python -m palazzo_predictor predict --format all
```

`pip install -e .` すると `palazzo-predict` コマンドが使えます。

```bash
pip install -e .
palazzo-predict predict --top 5
```

---

## CLI の使い方

```bash
# 予想を1回実行
python -m palazzo_predictor predict [--date YYYY-MM-DD] [--source demo|file|web]
                                    [--mode auto|preday] [--format text|json|html|all]
                                    [--top N] [--no-learn] [--no-save] [--quiet]

# 自動更新（営業時間中、一定間隔でループ）
python -m palazzo_predictor watch --interval 30 [--source ...] [--no-hours]
python -m palazzo_predictor watch --once          # 1回だけ更新

# デモCSVを data/raw に書き出し（フォーマット確認・file ソースの練習）
python -m palazzo_predictor demo-data --date 2026-07-27

# 設定サマリ（登録機種・島構成）
python -m palazzo_predictor info
```

**モード:**
- `--mode auto`（既定）… データを判別に使う通常モード
- `--mode preday` … データが出る前の **事前予想**。パターン注目度だけで狙い目を提示。

---

## 自動更新のセットアップ

### A) 常駐プロセス（手元PC・サーバー）

```bash
./scripts/watch.sh 30            # 30分間隔で更新し続ける（Ctrl+Cで停止）
```

### B) cron（推奨・軽量）

```bash
./scripts/install_cron.sh 30           # 営業時間9-22時台に30分毎
./scripts/install_cron.sh --remove     # 解除
```

### C) GitHub Actions（サーバー不要）

`.github/workflows/daily-update.yml` が JST 9/12/15/18/21 時に予想を生成し、
`output/` をアーティファクト保存します。GitHub Pages を有効化すると
`latest.html` が自動公開されます（手動実行 `workflow_dispatch` も可）。

> このリポジトリはモノレポ配下（`palazzo-hatogaya-predictor/`）にあるため、ワークフローは
> `working-directory` を合わせてあります。単独リポジトリに切り出す場合はパスを調整してください。

---

## データの用意（実運用）

デモ以外で使うには、当日のホールデータを供給します。

### file ソース（CSV）

`config/hall.yaml` の `data_source.kind` を `file` にし、`data/raw/<日付>.csv` を置きます。

```csv
machine_no,model_key,total_games,big,reg,grape,diff_coins
101,my_juggler_v,5200,18,15,860,1200
102,im_juggler_ex,4870,17,11,,305
```

- `grape` / `diff_coins` は空欄可（分かる範囲でOK。BIG・REG だけでも判別します）。
- 見本: [`data/demo/sample_2026-07-27.csv`](data/demo/sample_2026-07-27.csv)
- 台データ（データロボット/データサイトの数値）を上記形式に整形して置くだけです。

### web ソース（スクレイパー雛形）

`config/hall.yaml` の `data_source.web` を設定し、`src/palazzo_predictor/data_source.py`
の `WebDataSource._parse()` を対象サイトのHTML構造に合わせて実装します。
**利用規約・robots.txt の順守は利用者責任** です。

---

## 設定ファイル（すべて YAML）

| ファイル | 内容 |
|---|---|
| `config/machines.yaml` | 機種スペック（設定差のある確率・機械割）。機種追加もここに書くだけ。 |
| `config/hall.yaml` | ホール情報・判定しきい値・傾向重み・島構成・データソース |
| `config/events.yaml` | イベント/傾向カレンダー（日付条件→優遇パターン） |

### 機種を追加する

`config/machines.yaml` に 1 ブロック足すだけ（コード変更不要）:

```yaml
new_machine_key:
  name: "機種名"
  type: A
  bet_per_game: 3
  setting_count: 6
  indicators:
    big:  {1: 273.1, 2: 270.8, 3: 266.4, 4: 259.0, 5: 255.0, 6: 252.1}
    reg:  {1: 439.8, 2: 399.6, 3: 354.5, 4: 331.0, 5: 303.4, 6: 273.1}
  payout: {1: 97.0, 2: 98.0, 3: 99.9, 4: 101.5, 5: 103.3, 6: 105.3}
```

島（`config/hall.yaml` の `tendencies.islands`）に台番号レンジと機種を割り当てます。

### しきい値の調整

`config/hall.yaml` の `thresholds` で「激アツ／設定示唆」の基準を変えられます
（例: `super_hot_p`, `likely_high_p`, `reliable_games` など）。

---

## テスト

```bash
python -m unittest discover -s tests -p "test_*.py" -v
```

依存は標準ライブラリの `unittest` のみ（pytest でも実行可）。26 ケースで
ベイズ判別・イベント判定・推薦分類・エンドツーエンドを検証します。

---

## ディレクトリ構成

```
palazzo-hatogaya-predictor/
├── README.md
├── requirements.txt / pyproject.toml
├── config/
│   ├── machines.yaml      # 機種スペック（設定差）
│   ├── hall.yaml          # ホール設定・しきい値・島構成・データソース
│   └── events.yaml        # イベントカレンダー
├── src/palazzo_predictor/
│   ├── models.py          # データモデル
│   ├── config.py          # 設定ローダー
│   ├── setting_estimator.py  # ★ベイズ設定判別
│   ├── hall_analyzer.py   # ★ホール傾向・イベント・学習
│   ├── recommender.py     # ★推薦スコアリング
│   ├── data_source.py     # demo / file / web データ供給
│   ├── report.py          # text / json / html 出力
│   ├── updater.py         # オーケストレーション + 自動更新ループ
│   └── cli.py             # コマンドライン
├── data/
│   ├── demo/              # サンプルCSV（コミット対象）
│   ├── raw/               # 実データ置き場（.gitignore）
│   └── processed/         # 日次スナップショット（学習用, .gitignore）
├── output/                # 生成レポート（.gitignore）
├── scripts/
│   ├── run_daily.sh       # 1回実行（cron用）
│   ├── watch.sh           # 自動更新ループ
│   └── install_cron.sh    # cron登録/解除
├── tests/                 # unittest 一式
└── .github/workflows/daily-update.yml   # 自動更新（GitHub Actions）
```

---

## よくある質問

**Q. 本当に「完璧」に当たりますか？**
いいえ。設定は非公開・出玉は乱数を含むため、原理的に 100% はあり得ません。本ツールは
「観測データと経験則から、統計的に最も確からしい設定と期待値」を示すものです。データが
増えるほど推定は鋭くなりますが、確率である事実は変わりません。過度な期待や無理な投資は
避けてください。

**Q. スペック値が実機と違う気がします。**
`config/machines.yaml` は参考値です。最新の公表値・信頼できる解析値に置き換えてください。
値を直すだけで判別精度が上がります。

**Q. 他のホールにも使えますか？**
はい。`config/hall.yaml` のホール情報・島構成・傾向と、`config/events.yaml` を
対象ホールに合わせれば流用できます。

---

## ライセンス

MIT License

"""
パラッツォ鳩ヶ谷 予想システム (Palazzo Hatogaya Predictor)

パチスロの「当日のおすすめ台・設定入っていそうな台・激アツ台」を、
ベイズ設定判別 + ホール傾向分析で予想する自動更新システム。

主要モジュール:
    config            設定ファイル(YAML)の読み込み
    models            データモデル(機種スペック/観測データ/推定結果)
    setting_estimator ベイズ設定判別エンジン
    hall_analyzer     ホール傾向・イベント分析（事前予想 & 学習）
    recommender       おすすめ/設定示唆/激アツ の統合スコアリング
    data_source       データ取得（demo / file / web）
    report            レポート生成（text / json / html）
    updater           1サイクルのオーケストレーション + 自動更新ループ
    cli               コマンドラインインターフェース
"""

__version__ = "1.0.0"
__all__ = ["__version__"]

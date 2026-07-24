"""
データモデル定義。

外部依存なし（標準ライブラリの dataclasses のみ）。
JSON へのシリアライズを容易にするため、各モデルに `to_dict()` を用意。
"""
from __future__ import annotations

from dataclasses import dataclass, field, asdict
from typing import Dict, List, Optional


# -----------------------------------------------------------------------------
# 機種スペック
# -----------------------------------------------------------------------------
@dataclass
class MachineSpec:
    """1機種のスペック。設定差のある指標(確率分母)と機械割を持つ。"""

    key: str
    name: str
    type: str  # "A" | "AT"
    setting_count: int
    bet_per_game: int
    # indicator名 -> {設定: 確率の分母}  例: {"hatsuatari": {1: 399.0, ..., 6: 300.0}}
    indicators: Dict[str, Dict[int, float]]
    # {設定: 機械割(%)}
    payout: Dict[int, float]
    # 立ち回り用: 天井G数（AT機）。当選が確定/濃厚になるハマりG数の上限。
    ceiling_games: Optional[int] = None
    # 立ち回り用: 当たりが集中しやすいゾーン [[開始G, 終了G], ...]（任意）
    zones: Optional[List[List[int]]] = None

    @property
    def settings(self) -> List[int]:
        return list(range(1, self.setting_count + 1))

    def in_zone(self, current_games: Optional[int]) -> bool:
        """現在ハマりG数が当たりゾーン内かどうか。"""
        if current_games is None or not self.zones:
            return False
        return any(lo <= current_games <= hi for lo, hi in self.zones)

    def prob(self, indicator: str, setting: int) -> Optional[float]:
        """指標の1ゲームあたり発生確率（0〜1）。未定義なら None。"""
        table = self.indicators.get(indicator)
        if not table:
            return None
        denom = table.get(setting)
        if not denom:
            return None
        return 1.0 / float(denom)

    def to_dict(self) -> dict:
        return asdict(self)


# -----------------------------------------------------------------------------
# 観測データ（1台・1日分）
# -----------------------------------------------------------------------------
@dataclass
class MachineData:
    """ホールデータ1台分の観測値。"""

    machine_no: int
    model_key: str
    total_games: int
    # indicator名 -> 観測回数  例: {"hatsuatari": 18}（AT機は初当たり回数が主軸）
    observed: Dict[str, int] = field(default_factory=dict)
    diff_coins: Optional[int] = None    # 差枚（分かれば）
    # 立ち回り用: 現在のハマりG数（最後の当たりからの回転数）。
    current_games: Optional[int] = None
    date: Optional[str] = None

    def to_dict(self) -> dict:
        return asdict(self)


# -----------------------------------------------------------------------------
# 設定推定結果
# -----------------------------------------------------------------------------
@dataclass
class SettingEstimate:
    """ベイズ設定判別の結果。"""

    machine_no: int
    model_key: str
    model_name: str
    total_games: int
    posterior: Dict[int, float]          # {設定: 事後確率}
    expected_setting: float              # 期待設定（加重平均）
    p_high: float                        # P(設定>=4)
    p_super: float                       # P(設定>=5)
    p_max: float                         # P(設定==最高設定)
    estimated_payout: float              # 期待機械割(%)（事後加重）
    expected_value_coins: float          # 閉店までの期待差枚（枚）
    confidence: float                    # 0〜1（主にサンプル数由来）

    def most_likely_setting(self) -> int:
        return max(self.posterior, key=self.posterior.get)

    def to_dict(self) -> dict:
        d = asdict(self)
        d["most_likely_setting"] = self.most_likely_setting()
        return d


# -----------------------------------------------------------------------------
# ホールパターン・シグナル（事前予想）
# -----------------------------------------------------------------------------
@dataclass
class HallSignal:
    """データが出る前の、台番号パターン/イベント/学習傾向からの注目度。"""

    machine_no: int
    model_key: str
    score: float                         # 0〜1
    reasons: List[str] = field(default_factory=list)

    def to_dict(self) -> dict:
        return asdict(self)


# -----------------------------------------------------------------------------
# 最終推薦
# -----------------------------------------------------------------------------
@dataclass
class Recommendation:
    """データ判別 + ホールパターンを統合した最終推薦。"""

    machine_no: int
    model_key: str
    model_name: str
    category: str                        # "激アツ" | "設定示唆" | "おすすめ" | "様子見"
    combined_score: float                # 0〜1
    data_score: float                    # 判別由来スコア 0〜1
    pattern_score: float                 # ホールパターン由来スコア 0〜1
    reasons: List[str] = field(default_factory=list)
    estimate: Optional[SettingEstimate] = None
    signal: Optional[HallSignal] = None

    def to_dict(self) -> dict:
        return {
            "machine_no": self.machine_no,
            "model_key": self.model_key,
            "model_name": self.model_name,
            "category": self.category,
            "combined_score": self.combined_score,
            "data_score": self.data_score,
            "pattern_score": self.pattern_score,
            "reasons": self.reasons,
            "estimate": self.estimate.to_dict() if self.estimate else None,
            "signal": self.signal.to_dict() if self.signal else None,
        }


# -----------------------------------------------------------------------------
# 立ち回り: 朝一プラン
# -----------------------------------------------------------------------------
@dataclass
class MorningPick:
    """開店前の狙い目（優遇パターンから座るべき台）。"""

    machine_no: int
    model_key: str
    model_name: str
    score: float                         # 事前注目度 0〜1
    reasons: List[str] = field(default_factory=list)

    def to_dict(self) -> dict:
        return asdict(self)


# -----------------------------------------------------------------------------
# 立ち回り: リアルタイム移動候補
# -----------------------------------------------------------------------------
@dataclass
class MoveCandidate:
    """今から移動して座る価値のある台（リアルタイム）。"""

    machine_no: int
    model_key: str
    model_name: str
    action: str                          # 移動推奨 / 天井狙い / 撤退候補 / 様子見
    move_score: float                    # 0〜1
    setting_score: float                 # 高設定期待度（＝当たりの軽さ）
    state_score: float                   # 状態（ハマり具合・天井距離）
    ev_score: float                      # 残り期待値スコア
    expected_setting: Optional[float] = None
    p_high: Optional[float] = None
    hit_rate_denom: Optional[float] = None   # 実測初当たり分母（1/N の N。小さいほど軽い）
    current_games: Optional[int] = None
    ceiling_games: Optional[int] = None
    ceiling_distance: Optional[int] = None
    in_zone: bool = False
    expected_value_coins: Optional[float] = None
    reasons: List[str] = field(default_factory=list)

    def to_dict(self) -> dict:
        return asdict(self)

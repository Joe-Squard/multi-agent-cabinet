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
    # indicator名 -> {設定: 確率の分母}  例: {"reg": {1: 439.8, ..., 6: 273.1}}
    indicators: Dict[str, Dict[int, float]]
    # {設定: 機械割(%)}
    payout: Dict[int, float]

    @property
    def settings(self) -> List[int]:
        return list(range(1, self.setting_count + 1))

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
    # indicator名 -> 観測回数  例: {"big": 18, "reg": 15, "grape": 860}
    observed: Dict[str, int] = field(default_factory=dict)
    diff_coins: Optional[int] = None  # 差枚（分かれば）
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

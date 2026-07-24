"""
ベイズ設定判別エンジン (Bayesian Setting Estimator)
====================================================

観測データ（総回転数 G、BIG回数、REG回数、ブドウ回数 …）から、
設定1〜6の事後確率分布を推定します。

理論
----
各指標は「1ゲームあたり確率 p で発生する事象」とみなし、G ゲーム中の
発生回数 k をポアソン分布 Poisson(k | λ=G·p) で近似します。
（BIG と REG は独立事象として扱う ─ 設定判別で一般的な近似）

設定 s の尤度:
    L(s) = Π_indicator Poisson(k_i | G · p_{s,i})

事後確率（ベイズ）:
    P(s | data) ∝ prior(s) · L(s)

アンダーフローを避けるため対数空間で計算し、最後に正規化します。

prior は一様分布がデフォルトですが、ホール傾向（イベント日・末尾など）から
得た事前分布を渡すことで「データ + 経験則」を1つの枠組みに統合できます。
"""
from __future__ import annotations

import math
from typing import Dict, Optional

from .models import MachineData, MachineSpec, SettingEstimate


def _poisson_logpmf(k: int, lam: float) -> float:
    """ポアソン対数確率 log P(k | lam)。"""
    if lam <= 0:
        # λ=0 なら k=0 のみ確率1、それ以外は不可能（-inf 相当の大きな負値）
        return 0.0 if k == 0 else -1e18
    return k * math.log(lam) - lam - math.lgamma(k + 1)


class SettingEstimator:
    """1台の観測データから設定事後分布を推定する。"""

    def __init__(self, reliable_games: float = 5000.0,
                 typical_full_day_games: int = 8000):
        self.reliable_games = float(reliable_games)
        self.typical_full_day_games = int(typical_full_day_games)

    # ------------------------------------------------------------------ #
    def estimate(
        self,
        data: MachineData,
        spec: MachineSpec,
        prior: Optional[Dict[int, float]] = None,
    ) -> SettingEstimate:
        settings = spec.settings
        prior = self._normalize_prior(prior, settings)

        # --- 対数尤度を計算 ---------------------------------------------
        log_post: Dict[int, float] = {}
        used_indicators = [
            name for name in spec.indicators.keys()
            if name in data.observed
        ]
        for s in settings:
            log_lik = 0.0
            for name in used_indicators:
                p = spec.prob(name, s)
                if p is None:
                    continue
                lam = data.total_games * p
                log_lik += _poisson_logpmf(int(data.observed[name]), lam)
            log_post[s] = math.log(prior[s]) + log_lik

        posterior = self._softmax_normalize(log_post)

        # --- 各種要約統計 ------------------------------------------------
        expected_setting = sum(s * posterior[s] for s in settings)
        max_setting = max(settings)
        p_high = sum(posterior[s] for s in settings if s >= 4)
        p_super = sum(posterior[s] for s in settings if s >= 5)
        p_max = posterior[max_setting]

        est_payout = sum(posterior[s] * spec.payout.get(s, 100.0) for s in settings)
        remaining = max(0, self.typical_full_day_games - data.total_games)
        # 期待差枚(枚) = 残り試行 × 1G投入枚数 × (機械割/100 - 1)
        ev_coins = remaining * spec.bet_per_game * (est_payout / 100.0 - 1.0)

        confidence = self._confidence(data, used_indicators)

        return SettingEstimate(
            machine_no=data.machine_no,
            model_key=spec.key,
            model_name=spec.name,
            total_games=data.total_games,
            posterior={s: round(posterior[s], 6) for s in settings},
            expected_setting=round(expected_setting, 3),
            p_high=round(p_high, 4),
            p_super=round(p_super, 4),
            p_max=round(p_max, 4),
            estimated_payout=round(est_payout, 2),
            expected_value_coins=round(ev_coins, 1),
            confidence=round(confidence, 3),
        )

    # ------------------------------------------------------------------ #
    @staticmethod
    def _normalize_prior(prior: Optional[Dict[int, float]],
                         settings) -> Dict[int, float]:
        if not prior:
            u = 1.0 / len(settings)
            return {s: u for s in settings}
        # 負値やゼロを避けつつ正規化
        clean = {s: max(1e-9, float(prior.get(s, 0.0))) for s in settings}
        total = sum(clean.values())
        return {s: clean[s] / total for s in settings}

    @staticmethod
    def _softmax_normalize(log_post: Dict[int, float]) -> Dict[int, float]:
        m = max(log_post.values())
        exps = {s: math.exp(v - m) for s, v in log_post.items()}
        total = sum(exps.values())
        if total <= 0:
            n = len(log_post)
            return {s: 1.0 / n for s in log_post}
        return {s: exps[s] / total for s in log_post}

    def _confidence(self, data: MachineData, used_indicators) -> float:
        """サンプル量に基づく信頼度（0〜1）。指標が多いほど僅かに加点。"""
        if data.total_games <= 0 or not used_indicators:
            return 0.0
        sample_conf = min(1.0, data.total_games / self.reliable_games)
        # ブドウ（大量サンプル）まで揃うと判別力が上がるため軽く加点
        indicator_bonus = 0.1 if "grape" in used_indicators else 0.0
        return min(1.0, sample_conf + indicator_bonus)

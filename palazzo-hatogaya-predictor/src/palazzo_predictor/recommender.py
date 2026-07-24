"""
推薦エンジン (Recommender)
==========================

設定判別（データ由来）とホールパターン（事前予想由来）を統合し、
各台を次のカテゴリに分類する:

    激アツ    … データがそろい、超高設定(5〜6)の確率が高い
    設定示唆  … 高設定(4以上)の確率が高い
    おすすめ  … 総合スコアが高い（事前パターン or 中程度のデータ根拠）
    様子見    … 現時点で根拠が弱い

統合スコア (combined_score) の考え方
-----------------------------------
    combined = confidence · data_signal + (1 − confidence) · pattern_signal

    ・データが薄い開店直後  → confidence≈0 → 事前パターンが主役
    ・データがそろった夕方  → confidence≈1 → 実測の判別が主役
    ・その中間は自然にブレンドされる
"""
from __future__ import annotations

from typing import List, Optional

from .config import Config
from .models import HallSignal, MachineSpec, Recommendation, SettingEstimate

CATEGORY_ORDER = ["激アツ", "設定示唆", "おすすめ", "様子見"]


class Recommender:
    def __init__(self, config: Config):
        self.cfg = config
        self.likely_high_p = config.threshold("likely_high_p", 0.55)
        self.super_hot_p = config.threshold("super_hot_p", 0.45)
        self.super_hot_max6_p = config.threshold("super_hot_max6_p", 0.30)
        self.watch_pattern_score = config.threshold("watch_pattern_score", 0.5)

    # ------------------------------------------------------------------ #
    @staticmethod
    def _data_signal(est: Optional[SettingEstimate]) -> float:
        """データ由来の生シグナル（信頼度で割り引く前の 0〜1）。"""
        if est is None:
            return 0.0
        return max(0.0, min(1.0, 0.6 * est.p_high + 0.4 * est.p_super))

    def classify(
        self,
        machine_no: int,
        spec: MachineSpec,
        estimate: Optional[SettingEstimate],
        signal: HallSignal,
    ) -> Recommendation:
        confidence = estimate.confidence if estimate else 0.0
        data_sig = self._data_signal(estimate)
        pattern_sig = signal.score

        combined = confidence * data_sig + (1.0 - confidence) * pattern_sig
        combined = round(max(0.0, min(1.0, combined)), 4)

        category, reasons = self._categorize(estimate, signal, combined)

        return Recommendation(
            machine_no=machine_no,
            model_key=spec.key,
            model_name=spec.name,
            category=category,
            combined_score=combined,
            data_score=round(data_sig, 4),
            pattern_score=round(pattern_sig, 4),
            reasons=reasons,
            estimate=estimate,
            signal=signal,
        )

    # ------------------------------------------------------------------ #
    def _categorize(self, est: Optional[SettingEstimate], signal: HallSignal,
                    combined: float):
        reasons: List[str] = []

        has_data = est is not None and est.total_games > 0
        conf = est.confidence if est else 0.0

        # --- 激アツ: データ十分 かつ 超高設定確率が高い -----------------
        if has_data and conf >= 0.4 and (
            est.p_super >= self.super_hot_p or est.p_max >= self.super_hot_max6_p
        ):
            reasons.append(
                f"超高設定(5↑)確率 {est.p_super*100:.0f}% / "
                f"設定{max(est.posterior)}確率 {est.p_max*100:.0f}%"
            )
            reasons.append(
                f"期待機械割 {est.estimated_payout:.1f}% / "
                f"残り期待差枚 {est.expected_value_coins:+.0f}枚"
            )
            reasons += self._top_signal_reasons(signal)
            return "激アツ", reasons

        # --- 設定示唆: 高設定確率が基準以上 -----------------------------
        if has_data and conf >= 0.3 and est.p_high >= self.likely_high_p:
            reasons.append(f"高設定(4↑)確率 {est.p_high*100:.0f}%")
            reasons.append(
                f"期待設定 {est.expected_setting:.1f} / "
                f"期待機械割 {est.estimated_payout:.1f}%"
            )
            reasons += self._top_signal_reasons(signal)
            return "設定示唆", reasons

        # --- おすすめ: 総合スコアが基準以上 -----------------------------
        if combined >= self.watch_pattern_score:
            if has_data:
                reasons.append(
                    f"総合期待度 {combined*100:.0f}%"
                    f"（判別{est.p_high*100:.0f}% × 信頼度{conf*100:.0f}%）"
                )
            else:
                reasons.append(f"事前注目度 {signal.score*100:.0f}%（データ待ち）")
            reasons += self._top_signal_reasons(signal)
            # プラス期待値なら明示
            if has_data and est.expected_value_coins > 0:
                reasons.append(f"残り期待差枚 {est.expected_value_coins:+.0f}枚")
            return "おすすめ", reasons

        # --- 様子見 ------------------------------------------------------
        if has_data:
            reasons.append(
                f"期待設定 {est.expected_setting:.1f} / 高設定確率 "
                f"{est.p_high*100:.0f}%（現状では根拠不足）"
            )
        else:
            reasons.append("事前注目度・データともに弱い")
        return "様子見", reasons

    @staticmethod
    def _top_signal_reasons(signal: HallSignal, limit: int = 3) -> List[str]:
        return list(signal.reasons[:limit])

    # ------------------------------------------------------------------ #
    def rank(self, recs: List[Recommendation]) -> List[Recommendation]:
        """カテゴリ優先度 → 総合スコアで降順ソート。"""
        cat_rank = {c: i for i, c in enumerate(CATEGORY_ORDER)}
        return sorted(
            recs,
            key=lambda r: (cat_rank.get(r.category, 99), -r.combined_score),
        )

    def filter_category(self, recs: List[Recommendation],
                        category: str) -> List[Recommendation]:
        return [r for r in recs if r.category == category]

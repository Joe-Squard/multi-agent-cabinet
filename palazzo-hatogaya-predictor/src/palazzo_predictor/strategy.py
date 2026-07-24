"""
立ち回りエンジン (Strategy / Tachimawari Advisor)
================================================

2つのプランを提示する:

1. 朝一プラン (morning_plan)
   開店前〜朝イチに「どの機種・どの台に座るか」を、ホールの優遇傾向
   （イベント・末尾・ゾロ目・角台・看板機種・学習傾向）から提案する。
   → データが出る前の意思決定を支援。

2. 移動プラン (move_plan) ※リアルタイム
   今どの台に移動して座るのが得か、を実データからスコア化する。
   ユーザ要望「当たりが軽い・一定はまってない・まだ大当たりいけそうな台へ動く」を
   次の3要素で評価:
       ・当たりの軽さ  = 高設定期待度 P(設定4以上)（実測初当たりが軽いほど高い）
       ・状態          = 現在ハマりG数と天井距離（浅い=軽く引ける / 天井接近=狙い目）
       ・残り期待値    = 閉店までの期待差枚

   move_score = w_set·軽さ + w_state·状態 + w_ev·期待値

   アクション:
       🎯 移動推奨   … 軽くて浅い（伸びしろあり）本命
       ⏰ 天井狙い   … 天井接近で当選が近い
       🚪 撤退/回避  … 低設定濃厚かつ期待値マイナス（座らない/離れる）
       様子見        … 明確な妙味なし

自動更新のたびに再計算されるため、時間経過（データ増加・ハマり進行）に応じて
おすすめの移動先がリアルタイムに変化する。
"""
from __future__ import annotations

from typing import Dict, List, Optional

from .config import Config
from .models import (HallSignal, MachineData, MachineSpec, MorningPick,
                     MoveCandidate, SettingEstimate)


class StrategyAdvisor:
    def __init__(self, config: Config):
        self.cfg = config
        s = config.strategy
        self.w_set = float(s.get("weight_setting", 0.5))
        self.w_state = float(s.get("weight_state", 0.3))
        self.w_ev = float(s.get("weight_ev", 0.2))
        self.shallow_ratio = float(s.get("shallow_ratio", 0.35))
        self.ceiling_near_ratio = float(s.get("ceiling_near_ratio", 0.70))
        self.ev_scale = float(s.get("ev_scale", 1500))
        self.move_recommend_score = float(s.get("move_recommend_score", 0.58))
        self.bail_high_p = float(s.get("bail_high_p", 0.22))
        self.morning_top_n = int(s.get("morning_top_n", 8))

    # ====================================================================== #
    # 朝一プラン
    # ====================================================================== #
    def morning_plan(self, signals_by_no: Dict[int, HallSignal],
                     specs: Dict[int, MachineSpec]) -> dict:
        """
        signals_by_no: machine_no -> HallSignal（事前パターン注目度）
        specs:         machine_no -> MachineSpec
        return: {"picks": [MorningPick...], "favored_models": [{...}]}
        """
        picks: List[MorningPick] = []
        model_scores: Dict[str, List[float]] = {}
        model_name: Dict[str, str] = {}

        for no, sig in signals_by_no.items():
            spec = specs.get(no)
            if not spec:
                continue
            picks.append(MorningPick(
                machine_no=no,
                model_key=sig.model_key,
                model_name=spec.name,
                score=sig.score,
                reasons=list(sig.reasons),
            ))
            model_scores.setdefault(sig.model_key, []).append(sig.score)
            model_name[sig.model_key] = spec.name

        picks.sort(key=lambda p: -p.score)
        top = [p for p in picks if p.score > 0][: self.morning_top_n]

        favored = []
        for mk, scores in model_scores.items():
            avg = sum(scores) / len(scores)
            favored.append({
                "model_key": mk,
                "model_name": model_name.get(mk, mk),
                "avg_score": round(avg, 4),
                "best_score": round(max(scores), 4),
            })
        favored.sort(key=lambda m: -m["avg_score"])

        return {
            "picks": [p.to_dict() for p in top],
            "favored_models": favored,
        }

    # ====================================================================== #
    # 移動プラン（リアルタイム）
    # ====================================================================== #
    def move_plan(self, contexts: List[dict]) -> List[MoveCandidate]:
        """
        contexts: [{"machine_no", "spec": MachineSpec,
                    "estimate": SettingEstimate|None, "data": MachineData|None}, ...]
        データのある台のみ評価し、move_score 降順で返す。
        """
        cands: List[MoveCandidate] = []
        for c in contexts:
            spec: MachineSpec = c["spec"]
            est: Optional[SettingEstimate] = c.get("estimate")
            data: Optional[MachineData] = c.get("data")
            if est is None or data is None or data.total_games <= 0:
                continue
            cands.append(self._score_move(spec, est, data))
        cands.sort(key=lambda x: -x.move_score)
        return cands

    # ---------------------------------------------------------------------- #
    def _score_move(self, spec: MachineSpec, est: SettingEstimate,
                    data: MachineData) -> MoveCandidate:
        reasons: List[str] = []

        # --- 当たりの軽さ = 高設定期待度 ---
        setting_score = est.p_high
        hits = data.observed.get("hatsuatari", 0)
        hit_denom = (data.total_games / hits) if hits > 0 else None
        if hit_denom:
            if setting_score >= 0.5:
                reasons.append(
                    f"初当たり1/{hit_denom:.0f}と軽い（設定{est.most_likely_setting()}"
                    f"濃厚・P(4↑)={setting_score*100:.0f}%）")
            elif setting_score <= self.bail_high_p:
                reasons.append(
                    f"初当たり1/{hit_denom:.0f}と重い（低設定寄り）")

        # --- 状態（ハマり・天井） ---
        state_score, ceiling_dist, ceiling_soon, in_zone = self._state(spec, data)
        cg = data.current_games
        if cg is not None and spec.ceiling_games:
            ratio = cg / spec.ceiling_games
            if ceiling_soon:
                reasons.append(
                    f"天井まであと{ceiling_dist}G（現在{cg}G・当選近い）")
            elif ratio <= self.shallow_ratio:
                reasons.append(
                    f"現在{cg}G（天井の{ratio*100:.0f}%）とまだ浅い→軽く引ける")
            else:
                reasons.append(f"現在{cg}G（天井{spec.ceiling_games}G）")
        if in_zone:
            reasons.append("当たりゾーン内")

        # --- 残り期待値 ---
        ev = est.expected_value_coins
        ev_score = max(0.0, min(1.0, ev / self.ev_scale)) if ev is not None else 0.0
        if ev is not None and ev > 0:
            reasons.append(f"残り期待差枚 {ev:+.0f}枚")

        move = (self.w_set * setting_score
                + self.w_state * state_score
                + self.w_ev * ev_score)
        move = round(max(0.0, min(1.0, move)), 4)

        action = self._action(setting_score, state_score, move, ceiling_soon, ev)

        return MoveCandidate(
            machine_no=data.machine_no,
            model_key=spec.key,
            model_name=spec.name,
            action=action,
            move_score=move,
            setting_score=round(setting_score, 4),
            state_score=round(state_score, 4),
            ev_score=round(ev_score, 4),
            expected_setting=est.expected_setting,
            p_high=est.p_high,
            hit_rate_denom=round(hit_denom, 1) if hit_denom else None,
            current_games=cg,
            ceiling_games=spec.ceiling_games,
            ceiling_distance=ceiling_dist,
            in_zone=in_zone,
            expected_value_coins=ev,
            reasons=reasons,
        )

    def _state(self, spec: MachineSpec, data: MachineData):
        """状態スコア(0〜1)・天井距離・天井接近フラグ・ゾーン内フラグ。"""
        cg = data.current_games
        ceiling = spec.ceiling_games
        in_zone = spec.in_zone(cg)
        if cg is None or not ceiling:
            # 情報がなければ中立（少し高め＝判断保留）。ゾーンだけ反映。
            base = 0.55 if in_zone else 0.5
            return base, None, False, in_zone

        ratio = cg / ceiling
        ceiling_dist = ceiling - cg
        ceiling_soon = ratio >= self.ceiling_near_ratio

        if ceiling_soon:
            # 天井接近: 近いほど高い（0.70→1.0）
            span = max(1e-6, 1.0 - self.ceiling_near_ratio)
            state = 0.70 + 0.30 * min(1.0, (ratio - self.ceiling_near_ratio) / span)
        elif ratio <= self.shallow_ratio:
            # 浅い（はまってない）: 良状態。浅いほどやや高め（0.55→0.75）
            state = 0.75 - 0.20 * (ratio / max(1e-6, self.shallow_ratio))
            if in_zone:
                state = min(1.0, state + 0.15)
        else:
            # 中間のハマり: 特に妙味なし
            state = 0.40
            if in_zone:
                state = min(1.0, state + 0.15)
        return round(state, 4), ceiling_dist, ceiling_soon, in_zone

    def _action(self, setting_score: float, state_score: float,
                move: float, ceiling_soon: bool, ev: Optional[float]) -> str:
        if (setting_score >= 0.45 and state_score >= 0.50
                and move >= self.move_recommend_score):
            return "🎯 移動推奨"
        if ceiling_soon:
            return "⏰ 天井狙い"
        if setting_score < self.bail_high_p and (ev is not None and ev < 0):
            return "🚪 撤退/回避"
        return "様子見"

    # 便利: アクション別フィルタ
    @staticmethod
    def filter_action(cands: List[MoveCandidate], *actions) -> List[MoveCandidate]:
        return [c for c in cands if c.action in actions]

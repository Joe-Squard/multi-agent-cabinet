"""
ホール傾向・イベント分析 (Hall Analyzer)
========================================

2つの役割:

1. 事前予想（データが出る前）
   台番号パターン（末尾・ゾロ目・角台）、当日のイベント、機種の格、
   そして過去データから学習した傾向を統合し、各台の「注目度スコア」を出す。

2. 事前分布（prior）の生成
   注目度スコアを設定1〜6の prior 分布に変換し、SettingEstimator に渡す。
   → 「経験則（事前）」と「実データ（尤度）」を1つのベイズ枠組みに統合。

イベント日と設定投入の相関は経験則の仮説にすぎず、確実性はありません。
過去データが蓄積されると learn() が実際の傾向を学習し、初期仮説を補正します。
"""
from __future__ import annotations

from datetime import date, datetime
from typing import Dict, List, Optional

from .config import Config
from .models import HallSignal, MachineSpec


def _parse_date(date_str: str) -> date:
    return datetime.strptime(date_str, "%Y-%m-%d").date()


def _is_repdigit(n: int) -> bool:
    """全桁が同じ数字（2桁以上）。例: 11, 77, 111, 222, 999。"""
    s = str(n)
    return len(s) >= 2 and len(set(s)) == 1


class HallAnalyzer:
    def __init__(self, config: Config, learned: Optional[dict] = None):
        self.cfg = config
        self.t = config.tendencies
        # learned = {"last_digit": {d: weight}, "model": {key: weight}}
        self.learned = learned or {"last_digit": {}, "model": {}}

    # ================================================================== #
    # イベント判定
    # ================================================================== #
    def active_events(self, date_str: str) -> List[dict]:
        """当日にマッチするイベントルールのリストを返す。"""
        d = _parse_date(date_str)
        matched: List[dict] = []
        for ev in self.cfg.events.get("events", []):
            if self._match(ev.get("match", {}), d):
                matched.append(ev)
        return matched

    @staticmethod
    def _match(cond: dict, d: date) -> bool:
        dom = d.day
        if "date" in cond and d.strftime("%Y-%m-%d") in cond["date"]:
            return True
        if "day_of_month" in cond and dom in cond["day_of_month"]:
            return True
        if "last_digit_of_day" in cond and (dom % 10) in cond["last_digit_of_day"]:
            return True
        if cond.get("repdigit_day") and _is_repdigit(dom):
            return True
        if "weekday" in cond and d.weekday() in cond["weekday"]:
            return True
        return False

    def effective_effects(self, date_str: str) -> dict:
        """当日の全マッチイベントを統合した実効効果。"""
        events = self.active_events(date_str)
        eff = {
            "strength": self.cfg.events.get("default", {}).get("strength", 0.2),
            "favored_last_digits": set(),
            "favored_models": set(),
            "favor_corner": False,
            "favor_repdigit": False,
            "event_names": [],
        }
        for ev in events:
            e = ev.get("effects", {})
            eff["strength"] = max(eff["strength"], float(e.get("strength", 0.0)))
            eff["favored_last_digits"] |= set(e.get("favored_last_digits", []))
            eff["favored_models"] |= set(e.get("favored_models", []))
            eff["favor_corner"] = eff["favor_corner"] or bool(e.get("favor_corner"))
            eff["favor_repdigit"] = eff["favor_repdigit"] or bool(e.get("favor_repdigit"))
            eff["event_names"].append(ev.get("name", "event"))
        return eff

    # ================================================================== #
    # 事前予想スコア（台ごと）
    # ================================================================== #
    def is_corner(self, machine_no: int) -> bool:
        isl = self.cfg.island_of(machine_no)
        if not isl:
            return False
        rng = isl.get("range", [])
        return len(rng) == 2 and machine_no in (rng[0], rng[1])

    def pattern_signal(self, machine_no: int, model_key: str,
                       date_str: str) -> HallSignal:
        """台番号パターン・イベント・学習傾向から注目度スコアを算出。"""
        eff = self.effective_effects(date_str)
        reasons: List[str] = []
        score = 0.0

        last_digit = machine_no % 10
        flagship = set(self.t.get("flagship_models", []))

        # --- イベント: 優遇末尾 ---
        if last_digit in eff["favored_last_digits"]:
            w = float(self.t.get("last_digit_bias_weight", 0.6))
            score += w
            reasons.append(f"イベント優遇末尾{last_digit}")

        # --- ゾロ目台 ---
        if _is_repdigit(machine_no):
            w = float(self.t.get("repdigit_bias_weight", 0.7))
            # イベントでゾロ目優遇なら満額、そうでなければ半分
            w = w if eff["favor_repdigit"] else w * 0.5
            score += w
            reasons.append(f"ゾロ目台({machine_no})")

        # --- 角台 ---
        if self.is_corner(machine_no):
            w = float(self.t.get("corner_bias_weight", 0.5))
            w = w if eff["favor_corner"] else w * 0.6
            score += w
            reasons.append("角台")

        # --- 看板/イベント優遇機種 ---
        if model_key in eff["favored_models"]:
            score += float(self.t.get("flagship_model_weight", 0.6))
            reasons.append("イベント優遇機種")
        elif model_key in flagship:
            score += float(self.t.get("flagship_model_weight", 0.6)) * 0.5
            reasons.append("看板機種")

        # --- 学習傾向（過去データから） ---
        ld_learn = self.learned.get("last_digit", {}).get(last_digit)
        if ld_learn and ld_learn > 0.5:
            bonus = (ld_learn - 0.5) * 0.8  # 0〜0.4
            score += bonus
            reasons.append(f"学習傾向: 末尾{last_digit}が高設定寄り")
        md_learn = self.learned.get("model", {}).get(model_key)
        if md_learn and md_learn > 0.5:
            bonus = (md_learn - 0.5) * 0.8
            score += bonus
            reasons.append("学習傾向: この機種が高設定寄り")

        # イベント強度で全体を変調（強いイベント日ほどパターンが効く）
        score *= (0.5 + 0.5 * eff["strength"])

        # 0〜1にクランプ
        score = max(0.0, min(1.0, score))
        if eff["event_names"]:
            reasons.insert(0, "本日: " + " / ".join(eff["event_names"]))

        return HallSignal(
            machine_no=machine_no,
            model_key=model_key,
            score=round(score, 4),
            reasons=reasons,
        )

    # ================================================================== #
    # prior 生成: 注目度スコア → 設定分布
    # ================================================================== #
    def prior_from_signal(self, signal: HallSignal, spec: MachineSpec,
                          tilt: float = 0.35) -> Dict[int, float]:
        """
        注目度スコア(0〜1)を、高設定に緩やかに傾いた prior に変換。
        score=0 なら一様分布、score=1 なら高設定寄り。
        データが十分ある台では尤度が支配的になるよう傾きは控えめ。
        """
        settings = spec.settings
        mid = (settings[0] + settings[-1]) / 2.0
        span = max(1.0, settings[-1] - settings[0])
        raw = {}
        for s in settings:
            # 中心からの偏差に応じて線形に増減（正値を保つよう tilt を抑制）
            raw[s] = 1.0 + signal.score * tilt * ((s - mid) / (span / 2.0))
            raw[s] = max(0.05, raw[s])
        total = sum(raw.values())
        return {s: raw[s] / total for s in settings}

    # ================================================================== #
    # 学習: 過去の推定結果からホール傾向を抽出
    # ================================================================== #
    def learn(self, history: List[dict]) -> dict:
        """
        history: 過去の推定結果のリスト。各要素は
            {"machine_no": int, "model_key": str, "p_high": float}
        を含む dict（SettingEstimate.to_dict() 互換）。

        末尾ごと・機種ごとに「高設定だった度合い」を集計し、
        0〜1 に正規化した傾向重みを learned に格納して返す。
        """
        ld_sum: Dict[int, float] = {}
        ld_cnt: Dict[int, int] = {}
        md_sum: Dict[str, float] = {}
        md_cnt: Dict[str, int] = {}

        for rec in history:
            p_high = float(rec.get("p_high", 0.0))
            ld = int(rec.get("machine_no", 0)) % 10
            mk = rec.get("model_key", "")
            ld_sum[ld] = ld_sum.get(ld, 0.0) + p_high
            ld_cnt[ld] = ld_cnt.get(ld, 0) + 1
            if mk:
                md_sum[mk] = md_sum.get(mk, 0.0) + p_high
                md_cnt[mk] = md_cnt.get(mk, 0) + 1

        ld_avg = {d: ld_sum[d] / ld_cnt[d] for d in ld_sum if ld_cnt[d] > 0}
        md_avg = {m: md_sum[m] / md_cnt[m] for m in md_sum if md_cnt[m] > 0}

        self.learned = {
            "last_digit": self._normalize_map(ld_avg),
            "model": self._normalize_map(md_avg),
        }
        return self.learned

    @staticmethod
    def _normalize_map(m: Dict) -> Dict:
        """値を 0〜1 にスケール（相対傾向）。全て同値なら 0.5 に寄せる。"""
        if not m:
            return {}
        lo, hi = min(m.values()), max(m.values())
        if hi - lo < 1e-9:
            return {k: 0.5 for k in m}
        return {k: (v - lo) / (hi - lo) for k, v in m.items()}

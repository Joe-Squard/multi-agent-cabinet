"""
オーケストレーション & 自動更新 (Updater)
=========================================

1回の予想サイクル run_prediction():
    1. 台ロスター構築（島定義 ∪ 取得データ）
    2. 過去スナップショットからホール傾向を学習（任意）
    3. 各台:
         ホールパターン signal → prior 生成
         データがあれば prior を事前分布にベイズ設定判別
         推薦カテゴリに分類
    4. 総合スコアでランク付け
    5. 結果 dict を返す（JSON化可能）

自動更新 Updater.run_loop():
    営業時間中、一定間隔で run_prediction を回し、レポートを更新し続ける。
    データが増えるほど判別が鋭くなり、事前パターン主導 → 実測主導へ自然移行。
"""
from __future__ import annotations

import glob
import json
import os
import time
from datetime import datetime
from typing import List, Optional

from .config import Config, load_config
from .data_source import get_data_source
from .hall_analyzer import HallAnalyzer
from .models import MachineData
from .recommender import CATEGORY_ORDER, Recommender
from .report import render_html, render_json, render_text
from .setting_estimator import SettingEstimator
from .strategy import StrategyAdvisor


def _now_str() -> str:
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")


def today_str() -> str:
    return datetime.now().strftime("%Y-%m-%d")


# ============================================================================ #
# 1サイクル
# ============================================================================ #
def run_prediction(
    config: Config,
    date_str: str,
    source_kind: Optional[str] = None,
    mode: str = "auto",
    learn_days: int = 30,
) -> dict:
    """1回の予想を実行して結果 dict を返す。"""
    analyzer = HallAnalyzer(config)

    # --- 過去データから傾向を学習（あれば） ---
    if learn_days > 0:
        history = load_history(config, before=date_str, days=learn_days)
        if history:
            analyzer.learn(history)

    # --- データ取得 ---
    data_by_no = {}
    used_kind = source_kind or config.data_source.get("kind", "demo")
    if mode != "preday":
        src = get_data_source(config, source_kind)
        for d in src.fetch(date_str):
            data_by_no[d.machine_no] = d
    else:
        used_kind = "preday(パターンのみ)"

    # --- 台ロスター（島定義 ∪ 取得データ） ---
    roster = _build_roster(config, data_by_no)

    estimator = SettingEstimator(
        reliable_games=config.threshold("reliable_games", 5000),
        typical_full_day_games=int(
            config.hall_info.get("typical_full_day_games", 8000)),
    )
    recommender = Recommender(config)
    advisor = StrategyAdvisor(config)

    recommendations = []
    signals_by_no = {}
    specs_by_no = {}
    contexts = []
    for machine_no, model_key in roster:
        spec = config.spec(model_key)
        if not spec:
            continue
        signal = analyzer.pattern_signal(machine_no, model_key, date_str)
        data = data_by_no.get(machine_no)
        estimate = None
        if data and data.total_games > 0 and data.observed:
            prior = analyzer.prior_from_signal(signal, spec)
            estimate = estimator.estimate(data, spec, prior)
        rec = recommender.classify(machine_no, spec, estimate, signal)
        recommendations.append(rec)
        signals_by_no[machine_no] = signal
        specs_by_no[machine_no] = spec
        contexts.append({"machine_no": machine_no, "spec": spec,
                         "estimate": estimate, "data": data})

    ranked = recommender.rank(recommendations)

    counts = {c: 0 for c in CATEGORY_ORDER}
    for r in ranked:
        counts[r.category] = counts.get(r.category, 0) + 1

    # --- 立ち回り（朝一プラン + リアルタイム移動プラン） ---
    morning = advisor.morning_plan(signals_by_no, specs_by_no)
    moves = advisor.move_plan(contexts)
    strategy = {
        "morning": morning,
        "move": [m.to_dict() for m in moves],
    }

    eff = analyzer.effective_effects(date_str)
    return {
        "hall_name": config.hall_name,
        "hall_id": config.hall_info.get("id", ""),
        "date": date_str,
        "generated_at": _now_str(),
        "data_source": used_kind,
        "mode": mode,
        "events": eff.get("event_names", []),
        "machine_count": len(ranked),
        "counts": counts,
        "learned": bool(analyzer.learned.get("last_digit")),
        "recommendations": [r.to_dict() for r in ranked],
        "strategy": strategy,
    }


def _build_roster(config: Config, data_by_no: dict) -> List[tuple]:
    """(machine_no, model_key) のロスターを島定義と取得データから構築。"""
    roster = {}
    for isl in config.islands:
        rng = isl.get("range", [])
        models = isl.get("models", [])
        if len(rng) != 2 or not models:
            continue
        lo, hi = rng
        for idx, no in enumerate(range(lo, hi + 1)):
            roster[no] = models[idx % len(models)]
    # データにしか存在しない台も取り込む（島定義の抜けを補完）
    for no, d in data_by_no.items():
        if no not in roster and d.model_key:
            roster[no] = d.model_key
    return sorted(roster.items())


# ============================================================================ #
# 履歴（学習用）
# ============================================================================ #
def load_history(config: Config, before: str, days: int) -> List[dict]:
    """
    data/processed/*.json のスナップショットから、before より前の日付を
    最大 days 件読み、各推薦の推定サマリ(list[dict])を返す。
    """
    proc_dir = config.resolve_path("data/processed")
    if not os.path.isdir(proc_dir):
        return []
    files = sorted(glob.glob(os.path.join(proc_dir, "*.json")))
    history: List[dict] = []
    picked = 0
    for path in reversed(files):
        name = os.path.splitext(os.path.basename(path))[0]
        if name >= before:  # 当日以降は学習に使わない
            continue
        try:
            with open(path, "r", encoding="utf-8") as f:
                snap = json.load(f)
        except (json.JSONDecodeError, OSError):
            continue
        for r in snap.get("recommendations", []):
            est = r.get("estimate")
            if est:
                history.append({
                    "machine_no": r.get("machine_no"),
                    "model_key": r.get("model_key"),
                    "p_high": est.get("p_high", 0.0),
                })
        picked += 1
        if picked >= days:
            break
    return history


# ============================================================================ #
# 出力保存
# ============================================================================ #
def save_outputs(config: Config, result: dict,
                 formats=("text", "json", "html")) -> dict:
    """レポートを output/ に保存し、data/processed に日次スナップショットを残す。"""
    out_dir = config.resolve_path("output")
    proc_dir = config.resolve_path("data/processed")
    os.makedirs(out_dir, exist_ok=True)
    os.makedirs(proc_dir, exist_ok=True)
    date_str = result["date"]
    written = {}

    if "text" in formats:
        p = os.path.join(out_dir, f"{date_str}.txt")
        _write(p, render_text(result))
        _write(os.path.join(out_dir, "latest.txt"), render_text(result))
        written["text"] = p
    if "json" in formats:
        p = os.path.join(out_dir, f"{date_str}.json")
        _write(p, render_json(result))
        _write(os.path.join(out_dir, "latest.json"), render_json(result))
        written["json"] = p
    if "html" in formats:
        p = os.path.join(out_dir, f"{date_str}.html")
        _write(p, render_html(result))
        _write(os.path.join(out_dir, "latest.html"), render_html(result))
        written["html"] = p

    # 学習用スナップショット（常に保存）
    snap = os.path.join(proc_dir, f"{date_str}.json")
    _write(snap, render_json(result))
    written["snapshot"] = snap
    return written


def _write(path: str, content: str) -> None:
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)


# ============================================================================ #
# 自動更新ループ
# ============================================================================ #
class Updater:
    """営業時間中に一定間隔で予想を更新し続ける自動更新オーケストレータ。"""

    def __init__(self, config: Optional[Config] = None):
        self.cfg = config or load_config()

    def run_once(self, date_str: Optional[str] = None,
                 source_kind: Optional[str] = None,
                 mode: str = "auto",
                 formats=("text", "json", "html"),
                 learn_days: int = 30) -> dict:
        date_str = date_str or today_str()
        result = run_prediction(self.cfg, date_str, source_kind=source_kind,
                                mode=mode, learn_days=learn_days)
        save_outputs(self.cfg, result, formats=formats)
        return result

    def _within_hours(self) -> bool:
        info = self.cfg.hall_info
        open_h = float(info.get("open_hour", 9))
        close_h = float(info.get("close_hour", 22.75))
        now = datetime.now()
        cur = now.hour + now.minute / 60.0
        return open_h <= cur <= close_h

    def run_loop(self, interval_min: int = 30,
                 source_kind: Optional[str] = None,
                 respect_hours: bool = True,
                 max_iterations: int = 0,
                 formats=("text", "json", "html"),
                 on_update=None) -> None:
        """
        interval_min 間隔で run_once を繰り返す（Ctrl+C で停止）。
        respect_hours=True のとき営業時間外はスキップ。
        max_iterations>0 でその回数だけ実行して終了（テスト用）。
        """
        interval = max(60, int(interval_min * 60))
        iterations = 0
        print(f"[auto-update] 開始: {self.cfg.hall_name} / "
              f"間隔{interval_min}分 / ソース={source_kind or self.cfg.data_source.get('kind')}")
        try:
            while True:
                if (not respect_hours) or self._within_hours():
                    result = self.run_once(source_kind=source_kind, formats=formats)
                    top = _top_line(result)
                    print(f"[{_now_str()}] 更新完了 — {top}")
                    if on_update:
                        on_update(result)
                else:
                    print(f"[{_now_str()}] 営業時間外のためスキップ")
                iterations += 1
                if max_iterations and iterations >= max_iterations:
                    print("[auto-update] 指定回数に達したため終了")
                    break
                time.sleep(interval)
        except KeyboardInterrupt:
            print("\n[auto-update] 停止しました")


def _top_line(result: dict) -> str:
    c = result.get("counts", {})
    return (f"🔥{c.get('激アツ',0)} ⭐{c.get('設定示唆',0)} "
            f"👍{c.get('おすすめ',0)} / 全{result.get('machine_count',0)}台")

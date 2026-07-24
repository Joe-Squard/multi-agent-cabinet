"""
コマンドラインインターフェース (CLI)
====================================

使い方:
    python -m palazzo_predictor predict            # 当日の予想（デモデータ）
    python -m palazzo_predictor predict --date 2026-07-24 --top 5
    python -m palazzo_predictor predict --source file       # data/raw のCSVを使用
    python -m palazzo_predictor predict --mode preday        # データ前・パターン予想
    python -m palazzo_predictor watch --interval 30          # 30分毎に自動更新
    python -m palazzo_predictor watch --once                 # 1回だけ更新
    python -m palazzo_predictor demo-data --date 2026-07-24  # デモCSVを書き出し
    python -m palazzo_predictor info                          # 設定サマリ表示
"""
from __future__ import annotations

import argparse
import csv
import os
import sys

from .config import load_config
from .data_source import DemoDataSource
from .report import render_html, render_json, render_text
from .updater import Updater, run_prediction, save_outputs, today_str


def _add_common(p):
    p.add_argument("--config-root", default=None,
                   help="プロジェクトルート（config/ の親）を明示指定")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="palazzo_predictor",
        description="パラッツォ鳩ヶ谷 おすすめ台・設定・激アツ予想システム",
    )
    sub = parser.add_subparsers(dest="command")

    # predict
    pp = sub.add_parser("predict", help="1回の予想を実行")
    _add_common(pp)
    pp.add_argument("--date", default=None, help="対象日 YYYY-MM-DD（既定: 当日）")
    pp.add_argument("--source", default=None, choices=["demo", "file", "web"],
                    help="データソース（既定: config の設定）")
    pp.add_argument("--mode", default="auto", choices=["auto", "preday"],
                    help="auto=データ判別 / preday=データ前パターン予想")
    pp.add_argument("--format", default="text",
                    choices=["text", "json", "html", "all"], help="出力形式")
    pp.add_argument("--top", type=int, default=0, help="各カテゴリの表示上限（0=全件）")
    pp.add_argument("--no-learn", action="store_true", help="過去データ学習を無効化")
    pp.add_argument("--no-save", action="store_true", help="output/ への保存をしない")
    pp.add_argument("--quiet", action="store_true", help="標準出力を抑制")

    # watch
    pw = sub.add_parser("watch", help="自動更新ループ")
    _add_common(pw)
    pw.add_argument("--interval", type=int, default=30, help="更新間隔（分）")
    pw.add_argument("--source", default=None, choices=["demo", "file", "web"])
    pw.add_argument("--once", action="store_true", help="1回だけ実行して終了")
    pw.add_argument("--iterations", type=int, default=0, help="実行回数上限（0=無限）")
    pw.add_argument("--no-hours", action="store_true", help="営業時間チェックを無視")

    # demo-data
    pd = sub.add_parser("demo-data", help="デモCSVを data/raw に書き出し")
    _add_common(pd)
    pd.add_argument("--date", default=None, help="対象日 YYYY-MM-DD（既定: 当日）")

    # info
    pi = sub.add_parser("info", help="設定サマリを表示")
    _add_common(pi)

    return parser


# ---------------------------------------------------------------------------- #
def cmd_predict(args) -> int:
    cfg = load_config(args.config_root)
    date_str = args.date or today_str()
    result = run_prediction(
        cfg, date_str,
        source_kind=args.source,
        mode=args.mode,
        learn_days=0 if args.no_learn else 30,
    )
    if not args.no_save:
        fmts = ("text", "json", "html") if args.format == "all" else (args.format,)
        written = save_outputs(cfg, result, formats=fmts)
        if not args.quiet:
            for k, v in written.items():
                print(f"  saved [{k}]: {v}", file=sys.stderr)

    if not args.quiet:
        if args.format == "json":
            print(render_json(result))
        elif args.format == "html":
            print(render_html(result))
        else:
            print(render_text(result, top=args.top))
    return 0


def cmd_watch(args) -> int:
    cfg = load_config(args.config_root)
    updater = Updater(cfg)
    if args.once:
        result = updater.run_once(source_kind=args.source)
        print(render_text(result))
        return 0
    updater.run_loop(
        interval_min=args.interval,
        source_kind=args.source,
        respect_hours=not args.no_hours,
        max_iterations=args.iterations,
    )
    return 0


def cmd_demo_data(args) -> int:
    cfg = load_config(args.config_root)
    date_str = args.date or today_str()
    rows = DemoDataSource(cfg).fetch(date_str)
    out_dir = cfg.resolve_path("data/raw")
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, f"{date_str}.csv")
    with open(path, "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(["machine_no", "model_key", "total_games",
                    "big", "reg", "grape", "diff_coins"])
        for d in rows:
            w.writerow([d.machine_no, d.model_key, d.total_games,
                        d.observed.get("big", ""), d.observed.get("reg", ""),
                        d.observed.get("grape", ""), d.diff_coins])
    print(f"デモデータを書き出しました: {path}（{len(rows)}台）")
    print("→ config/hall.yaml の data_source.kind を file にすると読み込めます。")
    return 0


def cmd_info(args) -> int:
    cfg = load_config(args.config_root)
    print(f"ホール: {cfg.hall_name}  ({cfg.hall_info.get('area','')})")
    print(f"営業: {cfg.hall_info.get('open_hour')}時〜{cfg.hall_info.get('close_hour')}時")
    print(f"データソース: {cfg.data_source.get('kind')}")
    print(f"\n登録機種 ({len(cfg.machines)}):")
    for key, spec in cfg.machines.items():
        print(f"  - {spec.name} [{key}] type={spec.type} "
              f"設定{spec.setting_count} 指標={list(spec.indicators)}")
    print(f"\n島構成 ({len(cfg.islands)}):")
    total = 0
    for isl in cfg.islands:
        rng = isl.get("range", [])
        n = (rng[1] - rng[0] + 1) if len(rng) == 2 else 0
        total += n
        print(f"  - {isl.get('name')}: {rng} ({n}台) 機種={isl.get('models')}")
    print(f"\n合計 {total} 台")
    return 0


def main(argv=None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if not args.command:
        # デフォルトは predict（引数なしでも動く）
        args = parser.parse_args(["predict"])
    handlers = {
        "predict": cmd_predict,
        "watch": cmd_watch,
        "demo-data": cmd_demo_data,
        "info": cmd_info,
    }
    return handlers[args.command](args)


if __name__ == "__main__":
    raise SystemExit(main())

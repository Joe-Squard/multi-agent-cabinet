"""
レポート生成 (Report)
=====================

updater が作る予想結果(dict)を、3形式で出力する:
    render_text … ターミナル向けの読みやすいテキスト
    render_json … JSON 文字列（API / 連携用）
    render_html … 自己完結HTMLダッシュボード（ブラウザで閲覧）
"""
from __future__ import annotations

import html
import json
from typing import List

CATEGORY_EMOJI = {
    "激アツ": "🔥",
    "設定示唆": "⭐",
    "おすすめ": "👍",
    "様子見": "・",
}
CATEGORY_COLOR = {
    "激アツ": "#e8412e",
    "設定示唆": "#e8992e",
    "おすすめ": "#2e9be8",
    "様子見": "#8a8f98",
}
ACTION_COLOR = {
    "🎯 移動推奨": "#2ea043",
    "⏰ 天井狙い": "#a371f7",
    "🚪 撤退/回避": "#8a8f98",
    "様子見": "#8a8f98",
}
MORNING_COLOR = "#e8992e"
MOVE_COLOR = "#2ea043"


# ============================================================================ #
# JSON
# ============================================================================ #
def render_json(result: dict) -> str:
    return json.dumps(result, ensure_ascii=False, indent=2)


# ============================================================================ #
# テキスト（CLI）
# ============================================================================ #
def render_text(result: dict, top: int = 0) -> str:
    lines: List[str] = []
    push = lines.append

    push("=" * 64)
    push(f"  🎰 {result['hall_name']} 予想レポート")
    push(f"  📅 {result['date']}  （生成: {result.get('generated_at', '-')}）")
    src = result.get("data_source", "-")
    push(f"  📊 データソース: {src}   対象台数: {result.get('machine_count', 0)}")
    if result.get("events"):
        push(f"  🗓  本日のイベント: {' / '.join(result['events'])}")
    push("=" * 64)

    counts = result.get("counts", {})
    push("  内訳: " + "  ".join(
        f"{CATEGORY_EMOJI.get(c,'')}{c} {counts.get(c,0)}"
        for c in ["激アツ", "設定示唆", "おすすめ", "様子見"]
    ))
    push("")

    recs = result.get("recommendations", [])
    for cat in ["激アツ", "設定示唆", "おすすめ"]:
        group = [r for r in recs if r["category"] == cat]
        if not group:
            continue
        emoji = CATEGORY_EMOJI.get(cat, "")
        push(f"{emoji} 【{cat}】 {len(group)}台")
        push("-" * 64)
        shown = group if top <= 0 else group[:top]
        for r in shown:
            _push_machine(push, r)
        push("")

    if not any(r["category"] in ("激アツ", "設定示唆", "おすすめ") for r in recs):
        push("  本日は明確な狙い目が検出されませんでした（様子見）。")
        push("")

    _push_strategy(push, result)

    push("-" * 64)
    push("  ※ 本予想は統計的推定です。設定は非公開・出玉には乱数が伴うため、")
    push("     100%の的中は原理的に不可能です。余裕資金の範囲でお楽しみください。")
    push("=" * 64)
    return "\n".join(lines)


def render_strategy_text(result: dict) -> str:
    """立ち回り（朝一プラン + 移動プラン）だけを表示する集中ビュー。"""
    lines: List[str] = []
    push = lines.append
    push("=" * 64)
    push(f"  🎰 {result['hall_name']} 立ち回りナビ")
    push(f"  📅 {result['date']}  （生成: {result.get('generated_at','-')}）")
    if result.get("events"):
        push(f"  🗓  本日のイベント: {' / '.join(result['events'])}")
    push("=" * 64)
    _push_strategy(push, result)
    push("-" * 64)
    push("  ※ 統計推定です。設定は非公開・出玉に乱数を伴い100%的中は不可能。")
    push("     天井・現在G数はデータ提供元の値に依存します。余裕資金で自己責任にて。")
    push("=" * 64)
    return "\n".join(lines)


def _push_machine(push, r: dict) -> None:
    est = r.get("estimate")
    head = f"  [{r['machine_no']:>4}番] {r['model_name']}  " \
           f"総合{r['combined_score']*100:.0f}%"
    if est:
        head += (f"  期待設定{est['expected_setting']:.1f}"
                 f"  設定{est['most_likely_setting']}濃厚"
                 f"  機械割{est['estimated_payout']:.1f}%")
    push(head)
    if est:
        bar = _posterior_bar(est["posterior"])
        push(f"        設定分布 {bar}")
        push(f"        G{est['total_games']}  "
             f"P(4↑)={est['p_high']*100:.0f}%  "
             f"P(5↑)={est['p_super']*100:.0f}%  "
             f"期待差枚{est['expected_value_coins']:+.0f}枚  "
             f"信頼度{est['confidence']*100:.0f}%")
    for reason in r.get("reasons", [])[:3]:
        push(f"        ・{reason}")


def _push_strategy(push, result: dict) -> None:
    strat = result.get("strategy") or {}
    morning = strat.get("morning") or {}
    moves = strat.get("move") or []

    # ---- 朝一プラン ----
    push("🌅 【朝一プラン】本日の優遇狙い（データ前の狙い目）")
    push("-" * 64)
    fav = [f for f in (morning.get("favored_models") or []) if f["avg_score"] > 0]
    if fav:
        push("  優遇されやすい機種: " + " / ".join(
            f'{f["model_name"]}({f["avg_score"]*100:.0f}%)' for f in fav[:4]))
    else:
        push("  機種優遇の傾向は弱め。データ判別を重視。")
    picks = morning.get("picks") or []
    if picks:
        push("  座るならこの台:")
        for p in picks[:8]:
            rs = " / ".join(p["reasons"][:2])
            push(f"    [{p['machine_no']:>4}番] {p['model_name']}  "
                 f"注目度{p['score']*100:.0f}%  {rs}")
    else:
        push("  明確な朝一狙い目は検出されず。")
    push("")

    # ---- 移動プラン（リアルタイム） ----
    push("🏃 【移動プラン】リアルタイム狙い目（今から動くなら）")
    push("-" * 64)
    recommend = [m for m in moves
                 if m["action"] in ("🎯 移動推奨", "⏰ 天井狙い")][:8]
    if recommend:
        for m in recommend:
            push(f"  {m['action']} [{m['machine_no']:>4}番] {m['model_name']}  "
                 f"移動度{m['move_score']*100:.0f}%  "
                 f"（軽さ{m['setting_score']*100:.0f}% 状態{m['state_score']*100:.0f}%）")
            for r in m["reasons"][:3]:
                push(f"        ・{r}")
    else:
        push("  今すぐ動くべき台は検出されていません（様子見）。")
    bail = [m for m in moves if m["action"] == "🚪 撤退/回避"][:6]
    if bail:
        push("  🚪 回避（低設定濃厚・期待値マイナス）: "
             + ", ".join(f"{m['machine_no']}番" for m in bail))
    push("")


def _posterior_bar(posterior: dict) -> str:
    """設定1〜6の事後確率を簡易バーで表現。"""
    blocks = " ▁▂▃▄▅▆▇█"
    parts = []
    for s in sorted(posterior, key=lambda x: int(x)):
        p = posterior[s]
        idx = min(len(blocks) - 1, int(p * (len(blocks) - 1) * 1.4))
        parts.append(f"{s}:{blocks[idx]}")
    return " ".join(parts)


# ============================================================================ #
# HTML ダッシュボード（自己完結）
# ============================================================================ #
def render_html(result: dict) -> str:
    recs = result.get("recommendations", [])
    counts = result.get("counts", {})

    def esc(x) -> str:
        return html.escape(str(x))

    cards = [_html_strategy(result, esc)]
    for cat in ["激アツ", "設定示唆", "おすすめ", "様子見"]:
        group = [r for r in recs if r["category"] == cat]
        if not group:
            continue
        cards.append(f'<h2 class="cat" style="border-color:{CATEGORY_COLOR[cat]}">'
                     f'{CATEGORY_EMOJI.get(cat,"")} {esc(cat)} '
                     f'<span class="cnt">{len(group)}台</span></h2>')
        cards.append('<div class="grid">')
        for r in group:
            cards.append(_html_card(r, esc))
        cards.append("</div>")

    events = " / ".join(result.get("events", [])) or "平常営業"
    summary = "".join(
        f'<span class="pill" style="background:{CATEGORY_COLOR[c]}">'
        f'{CATEGORY_EMOJI.get(c,"")} {c} {counts.get(c,0)}</span>'
        for c in ["激アツ", "設定示唆", "おすすめ", "様子見"]
    )

    return _HTML_TEMPLATE.format(
        title=esc(f"{result['hall_name']} 予想 {result['date']}"),
        hall=esc(result["hall_name"]),
        date=esc(result["date"]),
        generated=esc(result.get("generated_at", "-")),
        source=esc(result.get("data_source", "-")),
        machine_count=esc(result.get("machine_count", 0)),
        events=esc(events),
        summary=summary,
        body="\n".join(cards),
    )


def _html_strategy(result: dict, esc) -> str:
    strat = result.get("strategy") or {}
    morning = strat.get("morning") or {}
    moves = strat.get("move") or []
    out: List[str] = []

    # ---- 朝一プラン ----
    out.append(f'<h2 class="cat" style="border-color:{MORNING_COLOR}">'
               f'🌅 朝一プラン <span class="cnt">本日の優遇狙い（データ前）</span></h2>')
    fav = [f for f in (morning.get("favored_models") or []) if f["avg_score"] > 0][:5]
    if fav:
        pills = "".join(
            f'<span class="pill" style="background:{MORNING_COLOR}">'
            f'{esc(f["model_name"])} {f["avg_score"]*100:.0f}%</span>' for f in fav)
        out.append(f'<div class="pills">{pills}</div>')
    picks = (morning.get("picks") or [])[:8]
    if picks:
        out.append('<div class="grid">')
        for p in picks:
            reasons = "".join(f"<li>{esc(x)}</li>" for x in p["reasons"][:3])
            out.append(
                f'<div class="card" style="border-top:4px solid {MORNING_COLOR}">'
                f'<div class="card-head"><span class="no">{esc(p["machine_no"])}番</span>'
                f'<span class="model">{esc(p["model_name"])}</span>'
                f'<span class="score">{p["score"]*100:.0f}%</span></div>'
                f'<ul class="reasons">{reasons}</ul></div>')
        out.append('</div>')
    else:
        out.append('<p class="empty">明確な朝一狙い目は検出されず。</p>')

    # ---- 移動プラン（リアルタイム） ----
    out.append(f'<h2 class="cat" style="border-color:{MOVE_COLOR}">'
               f'🏃 移動プラン <span class="cnt">リアルタイム狙い目（今から動くなら）</span></h2>')
    recommend = [m for m in moves
                 if m["action"] in ("🎯 移動推奨", "⏰ 天井狙い")][:9]
    if recommend:
        out.append('<div class="grid">')
        for m in recommend:
            color = ACTION_COLOR.get(m["action"], MOVE_COLOR)
            reasons = "".join(f"<li>{esc(x)}</li>" for x in m["reasons"][:3])
            denom = (f'<div class="stat"><b>初当たり</b>1/{m["hit_rate_denom"]:.0f}</div>'
                     if m.get("hit_rate_denom") else "")
            state = ""
            if m.get("current_games") is not None and m.get("ceiling_games"):
                state = (f'<div class="stat"><b>現在/天井</b>'
                         f'{m["current_games"]}/{m["ceiling_games"]}G</div>')
            ev = (f'<div class="stat"><b>期待差枚</b>{m["expected_value_coins"]:+.0f}</div>'
                  if m.get("expected_value_coins") is not None else "")
            out.append(
                f'<div class="card" style="border-top:4px solid {color}">'
                f'<div class="card-head"><span class="no">{esc(m["machine_no"])}番</span>'
                f'<span class="model">{esc(m["model_name"])}</span>'
                f'<span class="score">{m["move_score"]*100:.0f}%</span></div>'
                f'<div class="badge" style="background:{color}">{esc(m["action"])}</div>'
                f'<div class="stats">{denom}{state}{ev}'
                f'<div class="stat"><b>軽さ</b>{m["setting_score"]*100:.0f}%</div>'
                f'<div class="stat"><b>状態</b>{m["state_score"]*100:.0f}%</div></div>'
                f'<ul class="reasons">{reasons}</ul></div>')
        out.append('</div>')
    else:
        out.append('<p class="empty">今すぐ動くべき台は検出されていません。</p>')

    bail = [m for m in moves if m["action"] == "🚪 撤退/回避"][:8]
    if bail:
        chips = ", ".join(f'{esc(m["machine_no"])}番' for m in bail)
        out.append(f'<p class="empty">🚪 回避（低設定濃厚・期待値マイナス）: {chips}</p>')

    return "\n".join(out)


def _html_card(r: dict, esc) -> str:
    est = r.get("estimate")
    color = CATEGORY_COLOR.get(r["category"], "#888")
    rows = ""
    dist = ""
    if est:
        rows = (
            f'<div class="stat"><b>期待設定</b>{est["expected_setting"]:.1f}</div>'
            f'<div class="stat"><b>濃厚</b>設定{est["most_likely_setting"]}</div>'
            f'<div class="stat"><b>機械割</b>{est["estimated_payout"]:.1f}%</div>'
            f'<div class="stat"><b>P(4↑)</b>{est["p_high"]*100:.0f}%</div>'
            f'<div class="stat"><b>P(5↑)</b>{est["p_super"]*100:.0f}%</div>'
            f'<div class="stat"><b>期待差枚</b>{est["expected_value_coins"]:+.0f}</div>'
            f'<div class="stat"><b>G数</b>{est["total_games"]}</div>'
            f'<div class="stat"><b>信頼度</b>{est["confidence"]*100:.0f}%</div>'
        )
        dist = _html_dist(est["posterior"])
    reasons = "".join(f"<li>{esc(x)}</li>" for x in r.get("reasons", [])[:4])
    return (
        f'<div class="card" style="border-top:4px solid {color}">'
        f'<div class="card-head"><span class="no">{esc(r["machine_no"])}番</span>'
        f'<span class="model">{esc(r["model_name"])}</span>'
        f'<span class="score">{r["combined_score"]*100:.0f}%</span></div>'
        f'<div class="dist">{dist}</div>'
        f'<div class="stats">{rows}</div>'
        f'<ul class="reasons">{reasons}</ul>'
        f'</div>'
    )


def _html_dist(posterior: dict) -> str:
    bars = ""
    for s in sorted(posterior, key=lambda x: int(x)):
        p = posterior[s]
        h = max(3, int(p * 100))
        hot = "hot" if int(s) >= 5 else ("mid" if int(s) >= 4 else "cold")
        bars += (f'<div class="dbar"><div class="dfill {hot}" '
                 f'style="height:{h}%"></div><span>{s}</span>'
                 f'<em>{p*100:.0f}</em></div>')
    return f'<div class="distbars">{bars}</div>'


_HTML_TEMPLATE = """<!doctype html>
<html lang="ja"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<style>
:root{{--bg:#f5f6f8;--card:#fff;--fg:#1b1d21;--sub:#6b7280;--line:#e3e6ea;}}
@media(prefers-color-scheme:dark){{:root{{--bg:#15171c;--card:#1e2128;--fg:#e8eaed;--sub:#9aa0aa;--line:#2c313a;}}}}
*{{box-sizing:border-box}}
body{{margin:0;background:var(--bg);color:var(--fg);
  font-family:-apple-system,"Hiragino Kaku Gothic ProN","Noto Sans JP",sans-serif;line-height:1.6}}
.wrap{{max-width:1100px;margin:0 auto;padding:20px}}
header{{background:linear-gradient(135deg,#e8412e,#e8992e);color:#fff;border-radius:14px;padding:22px 24px;margin-bottom:18px}}
header h1{{margin:0 0 6px;font-size:22px}}
header .meta{{font-size:13px;opacity:.95}}
.pills{{margin:14px 0 4px;display:flex;flex-wrap:wrap;gap:8px}}
.pill{{color:#fff;padding:5px 12px;border-radius:999px;font-size:13px;font-weight:600}}
h2.cat{{font-size:17px;border-left:5px solid;padding-left:10px;margin:24px 0 12px}}
h2.cat .cnt{{font-size:13px;color:var(--sub);font-weight:400;margin-left:6px}}
.grid{{display:grid;grid-template-columns:repeat(auto-fill,minmax(280px,1fr));gap:14px}}
.card{{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:14px;box-shadow:0 1px 3px rgba(0,0,0,.05)}}
.card-head{{display:flex;align-items:baseline;gap:8px;margin-bottom:10px}}
.card-head .no{{font-weight:700;font-size:18px}}
.card-head .model{{flex:1;color:var(--sub);font-size:13px}}
.card-head .score{{font-weight:700;font-size:18px}}
.distbars{{display:flex;gap:6px;align-items:flex-end;height:70px;margin:6px 0 10px;padding:4px;background:var(--bg);border-radius:8px}}
.dbar{{flex:1;display:flex;flex-direction:column;align-items:center;justify-content:flex-end;height:100%;position:relative}}
.dfill{{width:70%;border-radius:3px 3px 0 0;min-height:3px}}
.dfill.hot{{background:#e8412e}}.dfill.mid{{background:#e8992e}}.dfill.cold{{background:#7d8590}}
.dbar span{{font-size:10px;color:var(--sub);margin-top:2px}}
.dbar em{{position:absolute;top:-2px;font-size:9px;color:var(--sub);font-style:normal}}
.stats{{display:grid;grid-template-columns:repeat(4,1fr);gap:6px;font-size:11px;margin-bottom:8px}}
.stat{{background:var(--bg);border-radius:6px;padding:5px 4px;text-align:center}}
.stat b{{display:block;color:var(--sub);font-weight:500;font-size:10px}}
.reasons{{margin:0;padding-left:16px;font-size:12px;color:var(--sub)}}
.reasons li{{margin:2px 0}}
.badge{{display:inline-block;color:#fff;font-size:11px;font-weight:700;padding:3px 9px;border-radius:6px;margin-bottom:8px}}
.empty{{color:var(--sub);font-size:13px;margin:6px 0 4px}}
footer{{margin-top:26px;font-size:12px;color:var(--sub);text-align:center;line-height:1.8}}
</style></head><body><div class="wrap">
<header>
  <h1>🎰 {hall} 予想レポート</h1>
  <div class="meta">📅 {date} ／ 生成 {generated} ／ データ: {source} ／ 対象 {machine_count}台<br>
  🗓 本日: {events}</div>
  <div class="pills">{summary}</div>
</header>
{body}
<footer>
  ※ 本予想は統計的推定です。設定は非公開で出玉には乱数が伴うため、100%の的中は原理的に不可能です。<br>
  20歳未満の遊技は禁止です。ギャンブル等依存症にご注意いただき、余裕資金の範囲でお楽しみください。
</footer>
</div></body></html>"""

"""
データソース (Data Sources)
===========================

当日のホールデータ（1台ごとの G数・BIG・REG・ブドウ・差枚）を供給する。

3種類:
    DemoDataSource … 内蔵シミュレータ。隠し設定を割り当てて結果をサンプリング。
                     依存物なしで即動作確認できる（設定判別の検証にも使える）。
    FileDataSource … data/raw/{date}.csv (または .json) を読む。実運用の基本形。
    WebDataSource  … 外部データサイトを取得する雛形。対象サイトのHTML構造に
                     合わせて parse を実装する必要がある。robots.txt / 利用規約を
                     必ず確認し、リクエスト間隔を守ること（利用は自己責任）。

CSV フォーマット:
    machine_no,model_key,total_games,big,reg,grape,diff_coins
    101,my_juggler_v,5200,18,15,860,1200
    grape / diff_coins は空欄可。
"""
from __future__ import annotations

import csv
import json
import math
import os
import random
from typing import List, Optional

from .config import Config
from .models import MachineData


# ============================================================================ #
# 抽象基底
# ============================================================================ #
class DataSource:
    def fetch(self, date_str: str) -> List[MachineData]:
        raise NotImplementedError


# ============================================================================ #
# ファイル
# ============================================================================ #
class FileDataSource(DataSource):
    def __init__(self, config: Config):
        self.cfg = config

    def _path(self, date_str: str) -> str:
        tmpl = self.cfg.data_source.get("file", {}).get(
            "path", "data/raw/{date}.csv")
        return self.cfg.resolve_path(tmpl.format(date=date_str))

    def fetch(self, date_str: str) -> List[MachineData]:
        path = self._path(date_str)
        if not os.path.exists(path):
            # .json も試す
            alt = os.path.splitext(path)[0] + ".json"
            if os.path.exists(alt):
                return self._load_json(alt, date_str)
            raise FileNotFoundError(
                f"データファイルが見つかりません: {path}\n"
                f"（data/raw/{date_str}.csv を用意するか、config/hall.yaml の "
                f"data_source.kind を demo にしてください）"
            )
        return self._load_csv(path, date_str)

    @staticmethod
    def _to_int(v, default=None):
        if v is None or str(v).strip() == "":
            return default
        return int(float(v))

    def _load_csv(self, path: str, date_str: str) -> List[MachineData]:
        out: List[MachineData] = []
        with open(path, "r", encoding="utf-8-sig", newline="") as f:
            reader = csv.DictReader(f)
            for row in reader:
                observed = {}
                # AT機の主指標は hatsuatari。旧A機の big/reg/grape も後方互換で許容。
                for key in ("hatsuatari", "cz", "big", "reg", "grape"):
                    v = self._to_int(row.get(key))
                    if v is not None:
                        observed[key] = v
                out.append(MachineData(
                    machine_no=self._to_int(row.get("machine_no")),
                    model_key=(row.get("model_key") or "").strip(),
                    total_games=self._to_int(row.get("total_games"), 0) or 0,
                    observed=observed,
                    diff_coins=self._to_int(row.get("diff_coins")),
                    current_games=self._to_int(row.get("current_games")),
                    date=date_str,
                ))
        return out

    def _load_json(self, path: str, date_str: str) -> List[MachineData]:
        with open(path, "r", encoding="utf-8") as f:
            rows = json.load(f)
        out = []
        for row in rows:
            out.append(MachineData(
                machine_no=int(row["machine_no"]),
                model_key=row["model_key"],
                total_games=int(row.get("total_games", 0)),
                observed={k: int(v) for k, v in (row.get("observed") or {}).items()},
                diff_coins=row.get("diff_coins"),
                current_games=row.get("current_games"),
                date=date_str,
            ))
        return out


# ============================================================================ #
# Web スクレイパー（雛形）
# ============================================================================ #
class WebDataSource(DataSource):
    """
    外部データサイトから取得する雛形。

    ⚠️ 対象サイトの robots.txt / 利用規約を必ず確認してください。
       多くのデータサイトはスクレイピングを禁止しています。個人利用の範囲・
       リクエスト間隔の順守など、法令とマナーの遵守は利用者の責任です。

    実際のHTMLはサイトごとに異なるため、_parse() を対象に合わせて実装します。
    """

    def __init__(self, config: Config):
        self.cfg = config
        self.web = config.data_source.get("web", {})

    def fetch(self, date_str: str) -> List[MachineData]:
        if not self.web.get("enabled"):
            raise RuntimeError(
                "web データソースは未設定です。config/hall.yaml の "
                "data_source.web.enabled=true と url を設定し、"
                "対象サイトに合わせて WebDataSource._parse() を実装してください。"
            )
        try:
            import requests  # 遅延 import（未使用環境でも他機能は動く）
        except ImportError as e:
            raise RuntimeError("requests が必要です: pip install requests") from e

        url = self.web.get("url", "").format(date=date_str)
        headers = {"User-Agent": self.web.get("user_agent", "predictor/1.0")}
        resp = requests.get(url, headers=headers,
                            timeout=self.web.get("timeout_sec", 20))
        resp.raise_for_status()
        return self._parse(resp.text, date_str)

    def _parse(self, html: str, date_str: str) -> List[MachineData]:
        """
        対象サイトのHTMLをパースして MachineData のリストを返す。
        （サイト構造に強く依存するため、ここは各自で実装してください）

        実装例のヒント:
            from bs4 import BeautifulSoup
            soup = BeautifulSoup(html, "html.parser")
            for tr in soup.select("table.data tr"):
                ... 各セルから machine_no / total_games / big / reg を抽出 ...
        """
        raise NotImplementedError(
            "WebDataSource._parse() は対象データサイトに合わせて実装してください。"
        )


# ============================================================================ #
# デモ（内蔵シミュレータ）
# ============================================================================ #
class DemoDataSource(DataSource):
    """
    隠し設定を割り当て、その設定の確率に従って結果をサンプリングする擬似データ。
    高設定は「イベント優遇末尾・ゾロ目・角台・看板機種」に集中させ、実ホールの
    “設定投入の癖”を模擬する。→ 事前パターン予想と設定判別の両方を検証できる。

    date をシードにするので、同じ日付なら毎回同じ擬似データになる（再現性）。
    """

    def __init__(self, config: Config):
        self.cfg = config

    def fetch(self, date_str: str) -> List[MachineData]:
        # 遅延 import で循環参照を回避
        from .hall_analyzer import HallAnalyzer, _is_repdigit

        rng = random.Random(self._seed(date_str))
        analyzer = HallAnalyzer(self.cfg)
        eff = analyzer.effective_effects(date_str)
        flagship = set(self.cfg.tendencies.get("flagship_models", []))

        out: List[MachineData] = []
        for isl in self.cfg.islands:
            rng_range = isl.get("range", [])
            models = isl.get("models", [])
            if len(rng_range) != 2 or not models:
                continue
            lo, hi = rng_range
            for idx, no in enumerate(range(lo, hi + 1)):
                model_key = models[idx % len(models)]
                spec = self.cfg.spec(model_key)
                if not spec:
                    continue

                # --- 高設定投入の傾向（隠し真値の決定） ---
                propensity = 0.08  # 平常の高設定率ベース
                last_digit = no % 10
                if last_digit in eff["favored_last_digits"]:
                    propensity += 0.30
                if _is_repdigit(no) and eff["favor_repdigit"]:
                    propensity += 0.30
                if analyzer.is_corner(no) and eff["favor_corner"]:
                    propensity += 0.20
                if model_key in eff["favored_models"]:
                    propensity += 0.20
                elif model_key in flagship:
                    propensity += 0.10
                propensity *= (0.6 + 0.8 * eff["strength"])
                propensity = min(0.85, propensity)

                true_setting = self._sample_setting(rng, spec, propensity)
                total_games = rng.randint(2500, 9000)
                observed = self._simulate(rng, spec, true_setting, total_games)
                diff = self._simulate_diff(rng, spec, true_setting, total_games)
                current_games = self._simulate_current_games(rng, spec, true_setting)

                out.append(MachineData(
                    machine_no=no,
                    model_key=model_key,
                    total_games=total_games,
                    observed=observed,
                    diff_coins=diff,
                    current_games=current_games,
                    date=date_str,
                ))
        return out

    # ---- helpers ------------------------------------------------------- #
    @staticmethod
    def _seed(date_str: str) -> int:
        return int.from_bytes(date_str.encode("utf-8"), "little") % (2**31)

    @staticmethod
    def _sample_setting(rng: random.Random, spec, propensity: float) -> int:
        settings = spec.settings
        if rng.random() < propensity:
            # 高設定帯（4〜6）。6ほどやや出にくく。
            high = [s for s in settings if s >= 4] or settings
            weights = [1.0 if s < settings[-1] else 0.7 for s in high]
            return rng.choices(high, weights=weights)[0]
        # 低設定帯（1〜3）。1〜2 に厚め。
        low = [s for s in settings if s <= 3] or settings
        weights = {1: 3.0, 2: 2.5, 3: 1.5}
        w = [weights.get(s, 1.0) for s in low]
        return rng.choices(low, weights=w)[0]

    def _simulate(self, rng, spec, setting: int, games: int) -> dict:
        observed = {}
        for name in spec.indicators.keys():
            p = spec.prob(name, setting)
            if p is None:
                continue
            observed[name] = self._poisson(rng, games * p)
        return observed

    @staticmethod
    def _simulate_diff(rng, spec, setting: int, games: int) -> int:
        payout = spec.payout.get(setting, 100.0)
        expected = games * spec.bet_per_game * (payout / 100.0 - 1.0)
        noise = rng.gauss(0, 350)
        return int(round(expected + noise))

    @staticmethod
    def _simulate_current_games(rng, spec, setting: int) -> int:
        """現在ハマりG数を天井比で疑似生成（高設定ほど平均は浅め）。"""
        p = spec.prob("hatsuatari", setting)
        mean_interval = (1.0 / p) if p else 300.0
        ceiling = spec.ceiling_games or int(mean_interval * 3)
        # 0〜天井を低めに歪めて分布（多くは浅い、たまに天井近く）
        base = rng.random() ** 1.6
        setting_factor = 1.0 - 0.05 * (setting - 1)  # 設定6で約0.75
        current = int(base * ceiling * setting_factor)
        return max(0, min(ceiling, current))

    @staticmethod
    def _poisson(rng: random.Random, lam: float) -> int:
        """ポアソン乱数。小さいλは Knuth、大きいλは正規近似。"""
        if lam <= 0:
            return 0
        if lam < 30:
            L = math.exp(-lam)
            k, p = 0, 1.0
            while True:
                k += 1
                p *= rng.random()
                if p <= L:
                    return k - 1
        return max(0, int(round(rng.gauss(lam, math.sqrt(lam)))))


# ============================================================================ #
# ファクトリ
# ============================================================================ #
def get_data_source(config: Config, override_kind: Optional[str] = None) -> DataSource:
    kind = (override_kind or config.data_source.get("kind", "demo")).lower()
    if kind == "demo":
        return DemoDataSource(config)
    if kind == "file":
        return FileDataSource(config)
    if kind == "web":
        return WebDataSource(config)
    raise ValueError(f"未知のデータソース種別: {kind}")

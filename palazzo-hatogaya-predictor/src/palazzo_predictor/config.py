"""
設定ファイル（YAML）の読み込みとアクセス。

config/
    machines.yaml … 機種スペック
    hall.yaml     … ホール設定・しきい値・傾向・データソース
    events.yaml   … イベントカレンダー
"""
from __future__ import annotations

import os
from dataclasses import dataclass
from typing import Dict, List, Optional

import yaml

from .models import MachineSpec


def _project_root() -> str:
    """このパッケージから見たプロジェクトルート（config/ の親）。"""
    here = os.path.dirname(os.path.abspath(__file__))
    # src/palazzo_predictor/config.py -> project root は3つ上
    return os.path.abspath(os.path.join(here, "..", ".."))


@dataclass
class Config:
    """全設定を保持するコンテナ。"""

    root: str
    machines: Dict[str, MachineSpec]
    hall: dict
    events: dict

    # --- ホール便利アクセサ -------------------------------------------------
    @property
    def hall_info(self) -> dict:
        return self.hall.get("hall", {})

    @property
    def hall_name(self) -> str:
        return self.hall_info.get("name", "不明ホール")

    @property
    def thresholds(self) -> dict:
        return self.hall.get("thresholds", {})

    @property
    def tendencies(self) -> dict:
        return self.hall.get("tendencies", {})

    @property
    def islands(self) -> List[dict]:
        return self.tendencies.get("islands", [])

    @property
    def data_source(self) -> dict:
        return self.hall.get("data_source", {})

    def threshold(self, key: str, default: float) -> float:
        val = self.thresholds.get(key)
        return float(val) if val is not None else float(default)

    def spec(self, model_key: str) -> Optional[MachineSpec]:
        return self.machines.get(model_key)

    def island_of(self, machine_no: int) -> Optional[dict]:
        """台番号が属する島定義を返す。"""
        for isl in self.islands:
            rng = isl.get("range", [])
            if len(rng) == 2 and rng[0] <= machine_no <= rng[1]:
                return isl
        return None

    def resolve_path(self, rel_or_abs: str) -> str:
        if os.path.isabs(rel_or_abs):
            return rel_or_abs
        return os.path.join(self.root, rel_or_abs)


def _load_yaml(path: str) -> dict:
    if not os.path.exists(path):
        raise FileNotFoundError(f"設定ファイルが見つかりません: {path}")
    with open(path, "r", encoding="utf-8") as f:
        data = yaml.safe_load(f)
    return data or {}


def _parse_machines(raw: dict) -> Dict[str, MachineSpec]:
    specs: Dict[str, MachineSpec] = {}
    for key, m in raw.items():
        # 設定キーは YAML では int になるが、念のため int() で正規化
        indicators = {
            name: {int(s): float(v) for s, v in table.items()}
            for name, table in (m.get("indicators") or {}).items()
        }
        payout = {int(s): float(v) for s, v in (m.get("payout") or {}).items()}
        specs[key] = MachineSpec(
            key=key,
            name=m.get("name", key),
            type=m.get("type", "A"),
            setting_count=int(m.get("setting_count", 6)),
            bet_per_game=int(m.get("bet_per_game", 3)),
            indicators=indicators,
            payout=payout,
        )
    return specs


def load_config(root: Optional[str] = None) -> Config:
    """config/ 配下を読み込んで Config を返す。"""
    root = root or _project_root()
    cfg_dir = os.path.join(root, "config")
    machines_raw = _load_yaml(os.path.join(cfg_dir, "machines.yaml"))
    hall = _load_yaml(os.path.join(cfg_dir, "hall.yaml"))
    events = _load_yaml(os.path.join(cfg_dir, "events.yaml"))
    return Config(
        root=root,
        machines=_parse_machines(machines_raw),
        hall=hall,
        events=events,
    )

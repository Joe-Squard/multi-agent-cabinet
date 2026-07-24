"""立ち回りエンジン（朝一プラン・移動プラン）のテスト。"""
import unittest

import _bootstrap  # noqa: F401
from palazzo_predictor.config import load_config
from palazzo_predictor.models import HallSignal, MachineData
from palazzo_predictor.setting_estimator import SettingEstimator
from palazzo_predictor.strategy import StrategyAdvisor


class TestStrategy(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cfg = load_config(_bootstrap.PROJECT_ROOT)
        cls.spec = cls.cfg.spec("monkey_turn_5")   # 天井700
        cls.est = SettingEstimator(6000, 8000)
        cls.adv = StrategyAdvisor(cls.cfg)

    def _ctx(self, machine_no, games, hatsuatari, current_games):
        d = MachineData(machine_no, "monkey_turn_5", games,
                        {"hatsuatari": hatsuatari}, current_games=current_games)
        est = self.est.estimate(d, self.spec)
        return {"machine_no": machine_no, "spec": self.spec,
                "estimate": est, "data": d}

    # ---- 状態スコア ---------------------------------------------------- #
    def test_state_shallow_high(self):
        d = MachineData(1, "monkey_turn_5", 4000, {"hatsuatari": 20},
                        current_games=100)
        state, dist, soon, zone = self.adv._state(self.spec, d)
        self.assertFalse(soon)
        self.assertGreater(state, 0.5)   # 浅い＝良状態

    def test_state_ceiling_near_flag(self):
        d = MachineData(2, "monkey_turn_5", 4000, {"hatsuatari": 20},
                        current_games=650)   # 650/700=93%
        state, dist, soon, zone = self.adv._state(self.spec, d)
        self.assertTrue(soon)
        self.assertEqual(dist, 50)
        self.assertGreater(state, 0.7)

    def test_state_middle_low(self):
        shallow = self.adv._state(
            self.spec, MachineData(1, "monkey_turn_5", 4000,
                                   {"hatsuatari": 20}, current_games=100))[0]
        middle = self.adv._state(
            self.spec, MachineData(1, "monkey_turn_5", 4000,
                                   {"hatsuatari": 20}, current_games=350))[0]
        self.assertGreater(shallow, middle)

    # ---- 移動プラン ---------------------------------------------------- #
    def test_light_shallow_is_recommended(self):
        # 軽い（1/190）＋浅い（100G）＋残りEVあり → 移動推奨
        ctx = self._ctx(211, 4000, 21, 100)
        cands = self.adv.move_plan([ctx])
        self.assertEqual(len(cands), 1)
        self.assertEqual(cands[0].action, "🎯 移動推奨")
        self.assertTrue(any("軽い" in r for r in cands[0].reasons))
        self.assertTrue(any("浅い" in r for r in cands[0].reasons))

    def test_ceiling_target_flagged(self):
        # 重め＋天井接近（660G）→ 天井狙い、理由に天井
        ctx = self._ctx(212, 5000, 15, 660)
        cand = self.adv.move_plan([ctx])[0]
        self.assertIn(cand.action, ("⏰ 天井狙い", "🎯 移動推奨"))
        self.assertTrue(any("天井" in r for r in cand.reasons))

    def test_heavy_machine_bail(self):
        # 重い（1/500）＋残りEVマイナス → 撤退/回避
        ctx = self._ctx(213, 5000, 10, 300)
        cand = self.adv.move_plan([ctx])[0]
        self.assertEqual(cand.action, "🚪 撤退/回避")

    def test_move_plan_sorted_desc(self):
        ctxs = [self._ctx(211, 4000, 21, 100),   # 良台
                self._ctx(213, 6000, 18, 300)]   # 悪台
        cands = self.adv.move_plan(ctxs)
        scores = [c.move_score for c in cands]
        self.assertEqual(scores, sorted(scores, reverse=True))

    def test_move_plan_skips_no_data(self):
        ctx = {"machine_no": 999, "spec": self.spec,
               "estimate": None, "data": None}
        self.assertEqual(self.adv.move_plan([ctx]), [])

    # ---- 朝一プラン ---------------------------------------------------- #
    def test_morning_plan(self):
        signals = {
            207: HallSignal(207, "smash_hokuto", 0.7, ["末尾7"]),
            217: HallSignal(217, "smash_hokuto", 0.6, ["末尾7"]),
            222: HallSignal(222, "okidoki_gold", 0.5, ["ゾロ目台"]),
            210: HallSignal(210, "smash_hokuto", 0.0, []),
        }
        specs = {207: self.cfg.spec("smash_hokuto"),
                 217: self.cfg.spec("smash_hokuto"),
                 222: self.cfg.spec("okidoki_gold"),
                 210: self.cfg.spec("smash_hokuto")}
        plan = self.adv.morning_plan(signals, specs)
        # score>0 の台のみ、スコア降順
        picks = plan["picks"]
        self.assertTrue(len(picks) >= 3)
        self.assertEqual(picks[0]["machine_no"], 207)   # 最高スコア
        self.assertGreaterEqual(picks[0]["score"], picks[1]["score"])
        self.assertTrue(all(p["score"] > 0 for p in picks))  # 0スコア台は除外
        self.assertNotIn(210, [p["machine_no"] for p in picks])
        # favored_models: 最も強い台を持つ機種は smash_hokuto（best=0.7）
        fav = plan["favored_models"]
        best_model = max(fav, key=lambda m: m["best_score"])
        self.assertEqual(best_model["model_key"], "smash_hokuto")


if __name__ == "__main__":
    unittest.main()

"""推薦エンジンとエンドツーエンドのパイプラインのテスト（AT機）。"""
import json
import unittest

import _bootstrap  # noqa: F401
from palazzo_predictor.config import load_config
from palazzo_predictor.models import HallSignal, MachineData
from palazzo_predictor.recommender import CATEGORY_ORDER, Recommender
from palazzo_predictor.setting_estimator import SettingEstimator
from palazzo_predictor.updater import run_prediction


class TestRecommender(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cfg = load_config(_bootstrap.PROJECT_ROOT)
        cls.spec = cls.cfg.spec("monkey_turn_5")
        cls.rec = Recommender(cls.cfg)
        cls.est = SettingEstimator(6000, 8000)

    def _estimate(self, games, hatsuatari, prior=None):
        d = MachineData(211, "monkey_turn_5", games, {"hatsuatari": hatsuatari})
        return self.est.estimate(d, self.spec, prior=prior)

    def test_super_hot_category(self):
        est = self._estimate(9000, 45)  # 1/200・超高設定濃厚
        sig = HallSignal(211, "monkey_turn_5", 0.5, [])
        r = self.rec.classify(211, self.spec, est, sig)
        self.assertEqual(r.category, "激アツ")

    def test_watch_category_for_weak(self):
        est = self._estimate(8000, 24)  # 重い＝低設定
        sig = HallSignal(212, "monkey_turn_5", 0.0, [])
        r = self.rec.classify(212, self.spec, est, sig)
        self.assertEqual(r.category, "様子見")

    def test_no_data_uses_pattern(self):
        sig = HallSignal(211, "monkey_turn_5", 0.8, ["ゾロ目台"])
        r = self.rec.classify(211, self.spec, None, sig)
        self.assertEqual(r.data_score, 0.0)
        self.assertAlmostEqual(r.combined_score, 0.8, places=4)
        self.assertEqual(r.category, "おすすめ")

    def test_confidence_blends_scores(self):
        thin = self._estimate(500, 2)
        thick = self._estimate(9000, 45)
        sig = HallSignal(211, "monkey_turn_5", 0.9, [])
        r_thin = self.rec.classify(211, self.spec, thin, sig)
        r_thick = self.rec.classify(211, self.spec, thick, sig)
        self.assertGreater(r_thin.combined_score, 0.5)   # pattern寄り
        self.assertGreater(r_thick.data_score, 0.5)      # data寄り

    def test_rank_orders_by_category(self):
        recs = [
            self.rec.classify(1, self.spec, self._estimate(8000, 24),
                              HallSignal(1, "monkey_turn_5", 0.0, [])),
            self.rec.classify(2, self.spec, self._estimate(9000, 45),
                              HallSignal(2, "monkey_turn_5", 0.5, [])),
        ]
        ranked = self.rec.rank(recs)
        cat_rank = {c: i for i, c in enumerate(CATEGORY_ORDER)}
        self.assertLessEqual(
            cat_rank[ranked[0].category], cat_rank[ranked[1].category])


class TestPipeline(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cfg = load_config(_bootstrap.PROJECT_ROOT)

    def test_only_at_machines(self):
        # ジャグラー系(Aタイプ)が完全に排除され、全機種 AT であること
        types = {s.type for s in self.cfg.machines.values()}
        self.assertEqual(types, {"AT"})
        self.assertNotIn("my_juggler_v", self.cfg.machines)

    def test_end_to_end_demo(self):
        result = run_prediction(self.cfg, "2026-07-27",
                                source_kind="demo", learn_days=0)
        self.assertEqual(result["hall_name"], "パラッツォ鳩ヶ谷")
        self.assertGreater(result["machine_count"], 0)
        self.assertEqual(
            sum(result["counts"].values()), result["machine_count"])
        self.assertIn("strategy", result)
        self.assertIn("morning", result["strategy"])
        self.assertIn("move", result["strategy"])
        json.dumps(result, ensure_ascii=False)  # シリアライズ可能

    def test_preday_mode_no_estimates(self):
        result = run_prediction(self.cfg, "2026-07-27", mode="preday", learn_days=0)
        self.assertTrue(all(r["estimate"] is None
                            for r in result["recommendations"]))
        self.assertEqual(result["counts"]["激アツ"], 0)
        # 朝一プランはデータ前でも生成される
        self.assertGreater(len(result["strategy"]["morning"]["picks"]), 0)

    def test_deterministic_demo(self):
        a = run_prediction(self.cfg, "2026-07-27", source_kind="demo", learn_days=0)
        b = run_prediction(self.cfg, "2026-07-27", source_kind="demo", learn_days=0)
        self.assertEqual(a["counts"], b["counts"])


if __name__ == "__main__":
    unittest.main()

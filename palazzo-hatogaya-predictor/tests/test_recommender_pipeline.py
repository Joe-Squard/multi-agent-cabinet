"""推薦エンジンとエンドツーエンドのパイプラインのテスト。"""
import json
import unittest

import _bootstrap  # noqa: F401
from palazzo_predictor.config import load_config
from palazzo_predictor.hall_analyzer import HallAnalyzer
from palazzo_predictor.models import HallSignal, MachineData
from palazzo_predictor.recommender import CATEGORY_ORDER, Recommender
from palazzo_predictor.setting_estimator import SettingEstimator
from palazzo_predictor.updater import run_prediction


class TestRecommender(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cfg = load_config(_bootstrap.PROJECT_ROOT)
        cls.spec = cls.cfg.spec("my_juggler_v")
        cls.rec = Recommender(cls.cfg)
        cls.est = SettingEstimator(5000, 8000)

    def _estimate(self, games, big, reg, prior=None):
        d = MachineData(111, "my_juggler_v", games, {"big": big, "reg": reg})
        return self.est.estimate(d, self.spec, prior=prior)

    def test_super_hot_category(self):
        est = self._estimate(7000, 28, 26)  # 高設定濃厚
        sig = HallSignal(111, "my_juggler_v", 0.5, [])
        r = self.rec.classify(111, self.spec, est, sig)
        self.assertEqual(r.category, "激アツ")

    def test_watch_category_for_weak(self):
        est = self._estimate(6000, 20, 11)  # 低設定
        sig = HallSignal(112, "my_juggler_v", 0.0, [])
        r = self.rec.classify(112, self.spec, est, sig)
        self.assertEqual(r.category, "様子見")

    def test_no_data_uses_pattern(self):
        # データなし・高パターン → combined は pattern_score に一致
        sig = HallSignal(111, "my_juggler_v", 0.8, ["ゾロ目台"])
        r = self.rec.classify(111, self.spec, None, sig)
        self.assertEqual(r.data_score, 0.0)
        self.assertAlmostEqual(r.combined_score, 0.8, places=4)
        self.assertEqual(r.category, "おすすめ")

    def test_confidence_blends_scores(self):
        # 薄いデータ(低信頼度)は pattern 寄り、厚いデータは data 寄り
        thin = self._estimate(500, 2, 2)
        thick = self._estimate(8000, 33, 29)
        sig = HallSignal(111, "my_juggler_v", 0.9, [])
        r_thin = self.rec.classify(111, self.spec, thin, sig)
        r_thick = self.rec.classify(111, self.spec, thick, sig)
        # 薄いほう: pattern(0.9) の影響が強く combined が高い
        self.assertGreater(r_thin.combined_score, 0.5)
        # 厚いほう: data_signal が支配
        self.assertGreater(r_thick.data_score, 0.5)

    def test_rank_orders_by_category(self):
        recs = [
            self.rec.classify(1, self.spec, self._estimate(6000, 20, 11),
                              HallSignal(1, "my_juggler_v", 0.0, [])),
            self.rec.classify(2, self.spec, self._estimate(7000, 28, 26),
                              HallSignal(2, "my_juggler_v", 0.5, [])),
        ]
        ranked = self.rec.rank(recs)
        cat_rank = {c: i for i, c in enumerate(CATEGORY_ORDER)}
        self.assertLessEqual(
            cat_rank[ranked[0].category], cat_rank[ranked[1].category])


class TestPipeline(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cfg = load_config(_bootstrap.PROJECT_ROOT)

    def test_end_to_end_demo(self):
        result = run_prediction(self.cfg, "2026-07-27",
                                source_kind="demo", learn_days=0)
        self.assertEqual(result["hall_name"], "パラッツォ鳩ヶ谷")
        self.assertGreater(result["machine_count"], 0)
        self.assertEqual(
            sum(result["counts"].values()), result["machine_count"])
        # JSON シリアライズ可能
        json.dumps(result, ensure_ascii=False)

    def test_event_day_has_more_high(self):
        # イベント日は高設定投入が増えるよう demo が模擬 → 平常日より激アツが多い傾向
        ev = run_prediction(self.cfg, "2026-07-27", source_kind="demo", learn_days=0)
        plain = run_prediction(self.cfg, "2026-07-25", source_kind="demo", learn_days=0)
        ev_hot = ev["counts"]["激アツ"] + ev["counts"]["設定示唆"]
        plain_hot = plain["counts"]["激アツ"] + plain["counts"]["設定示唆"]
        self.assertGreaterEqual(ev_hot, plain_hot)

    def test_preday_mode_no_estimates(self):
        result = run_prediction(self.cfg, "2026-07-27", mode="preday", learn_days=0)
        # preday はデータ判別しない → estimate は全て None
        self.assertTrue(all(r["estimate"] is None
                            for r in result["recommendations"]))
        self.assertEqual(result["counts"]["激アツ"], 0)

    def test_deterministic_demo(self):
        # 同一日付の demo は再現性がある
        a = run_prediction(self.cfg, "2026-07-27", source_kind="demo", learn_days=0)
        b = run_prediction(self.cfg, "2026-07-27", source_kind="demo", learn_days=0)
        self.assertEqual(a["counts"], b["counts"])


if __name__ == "__main__":
    unittest.main()

"""ベイズ設定判別エンジンのテスト（AT機 / 初当たり判別）。"""
import unittest

import _bootstrap  # noqa: F401  (sys.path 設定)
from palazzo_predictor.config import load_config
from palazzo_predictor.models import MachineData
from palazzo_predictor.setting_estimator import SettingEstimator, _poisson_logpmf


class TestSettingEstimator(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cfg = load_config(_bootstrap.PROJECT_ROOT)
        # 設定差の大きい Lモンキーターン5 で判別を検証（初当たり 1/288〜1/207）
        cls.spec = cls.cfg.spec("monkey_turn_5")
        cls.est = SettingEstimator(reliable_games=6000, typical_full_day_games=8000)

    def test_posterior_normalized(self):
        d = MachineData(201, "monkey_turn_5", 6000, {"hatsuatari": 25})
        r = self.est.estimate(d, self.spec)
        self.assertAlmostEqual(sum(r.posterior.values()), 1.0, places=5)
        for p in r.posterior.values():
            self.assertGreaterEqual(p, 0.0)

    def test_light_hits_favor_high_setting(self):
        # 初当たりが軽い（1/190相当）→ 高設定寄り
        d = MachineData(211, "monkey_turn_5", 8000, {"hatsuatari": 42})
        r = self.est.estimate(d, self.spec)
        self.assertGreater(r.p_high, 0.5)
        self.assertGreater(r.expected_setting, 4.0)
        self.assertGreater(r.estimated_payout, 100.0)

    def test_heavy_hits_favor_low_setting(self):
        # 初当たりが重い（1/500相当）→ 低設定寄り
        d = MachineData(212, "monkey_turn_5", 8000, {"hatsuatari": 16})
        r = self.est.estimate(d, self.spec)
        self.assertLess(r.p_high, 0.3)
        self.assertLess(r.expected_setting, 3.0)
        self.assertLess(r.estimated_payout, 100.0)

    def test_thin_data_low_confidence(self):
        d = MachineData(213, "monkey_turn_5", 600, {"hatsuatari": 2})
        r = self.est.estimate(d, self.spec)
        self.assertLess(r.confidence, 0.2)
        self.assertGreater(r.expected_setting, 2.5)
        self.assertLess(r.expected_setting, 4.5)

    def test_prior_influences_result(self):
        d = MachineData(214, "monkey_turn_5", 900, {"hatsuatari": 4})
        high_prior = {1: 0.02, 2: 0.03, 3: 0.05, 4: 0.2, 5: 0.3, 6: 0.4}
        r_flat = self.est.estimate(d, self.spec)
        r_high = self.est.estimate(d, self.spec, prior=high_prior)
        self.assertGreater(r_high.expected_setting, r_flat.expected_setting)

    def test_more_games_more_confidence(self):
        d_small = MachineData(1, "monkey_turn_5", 1500, {"hatsuatari": 6})
        d_big = MachineData(2, "monkey_turn_5", 9000, {"hatsuatari": 36})
        self.assertLess(
            self.est.estimate(d_small, self.spec).confidence,
            self.est.estimate(d_big, self.spec).confidence,
        )

    def test_poisson_logpmf_edge(self):
        self.assertEqual(_poisson_logpmf(0, 0.0), 0.0)
        self.assertLess(_poisson_logpmf(3, 0.0), -1e6)

    def test_ev_scales_with_remaining_games(self):
        d_early = MachineData(1, "monkey_turn_5", 2000, {"hatsuatari": 10})
        d_late = MachineData(2, "monkey_turn_5", 7800, {"hatsuatari": 39})
        e = self.est.estimate(d_early, self.spec)
        l = self.est.estimate(d_late, self.spec)
        self.assertGreaterEqual(e.expected_value_coins, l.expected_value_coins)


if __name__ == "__main__":
    unittest.main()

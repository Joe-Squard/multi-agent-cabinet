"""ベイズ設定判別エンジンのテスト。"""
import unittest

import _bootstrap  # noqa: F401  (sys.path 設定)
from palazzo_predictor.config import load_config
from palazzo_predictor.models import MachineData
from palazzo_predictor.setting_estimator import SettingEstimator, _poisson_logpmf


class TestSettingEstimator(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cfg = load_config(_bootstrap.PROJECT_ROOT)
        cls.spec = cls.cfg.spec("my_juggler_v")
        cls.est = SettingEstimator(reliable_games=5000, typical_full_day_games=8000)

    def test_posterior_normalized(self):
        d = MachineData(101, "my_juggler_v", 5000, {"big": 18, "reg": 15})
        r = self.est.estimate(d, self.spec)
        self.assertAlmostEqual(sum(r.posterior.values()), 1.0, places=5)
        for p in r.posterior.values():
            self.assertGreaterEqual(p, 0.0)

    def test_high_setting_data_favors_high(self):
        # REG が軽い（高設定寄り）データ
        d = MachineData(111, "my_juggler_v", 6000, {"big": 24, "reg": 22})
        r = self.est.estimate(d, self.spec)
        self.assertGreater(r.p_high, 0.5)
        self.assertGreater(r.expected_setting, 4.0)
        self.assertGreater(r.estimated_payout, 100.0)

    def test_low_setting_data_favors_low(self):
        # REG が重い（低設定寄り）データ
        d = MachineData(112, "my_juggler_v", 6000, {"big": 20, "reg": 11})
        r = self.est.estimate(d, self.spec)
        self.assertLess(r.p_high, 0.3)
        self.assertLess(r.expected_setting, 3.0)
        self.assertLess(r.estimated_payout, 100.0)

    def test_thin_data_low_confidence(self):
        d = MachineData(113, "my_juggler_v", 400, {"big": 2, "reg": 2})
        r = self.est.estimate(d, self.spec)
        self.assertLess(r.confidence, 0.2)
        # サンプルが薄いと事後は一様に近い（期待設定が中央付近）
        self.assertGreater(r.expected_setting, 2.5)
        self.assertLess(r.expected_setting, 4.5)

    def test_prior_influences_result(self):
        d = MachineData(114, "my_juggler_v", 800, {"big": 3, "reg": 3})
        high_prior = {1: 0.02, 2: 0.03, 3: 0.05, 4: 0.2, 5: 0.3, 6: 0.4}
        r_flat = self.est.estimate(d, self.spec)
        r_high = self.est.estimate(d, self.spec, prior=high_prior)
        # 同じ薄いデータなら prior が高いほうが期待設定が高くなる
        self.assertGreater(r_high.expected_setting, r_flat.expected_setting)

    def test_more_games_more_confidence(self):
        d_small = MachineData(1, "my_juggler_v", 1000, {"big": 4, "reg": 3})
        d_big = MachineData(2, "my_juggler_v", 9000, {"big": 36, "reg": 30})
        self.assertLess(
            self.est.estimate(d_small, self.spec).confidence,
            self.est.estimate(d_big, self.spec).confidence,
        )

    def test_poisson_logpmf_edge(self):
        # λ=0 のとき k=0 は log P=0、k>0 は不可能（大きな負値）
        self.assertEqual(_poisson_logpmf(0, 0.0), 0.0)
        self.assertLess(_poisson_logpmf(3, 0.0), -1e6)

    def test_ev_scales_with_remaining_games(self):
        # G が少ない（残り試行が多い）ほど、高設定の期待差枚は大きい
        d_early = MachineData(1, "my_juggler_v", 2000, {"big": 8, "reg": 7})
        d_late = MachineData(2, "my_juggler_v", 7800, {"big": 31, "reg": 27})
        e = self.est.estimate(d_early, self.spec)
        l = self.est.estimate(d_late, self.spec)
        self.assertGreaterEqual(e.expected_value_coins, l.expected_value_coins)


if __name__ == "__main__":
    unittest.main()

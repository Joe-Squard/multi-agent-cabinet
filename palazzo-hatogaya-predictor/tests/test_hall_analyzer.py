"""ホール傾向・イベント分析のテスト。"""
import unittest

import _bootstrap  # noqa: F401
from palazzo_predictor.config import load_config
from palazzo_predictor.hall_analyzer import HallAnalyzer, _is_repdigit


class TestHallAnalyzer(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cfg = load_config(_bootstrap.PROJECT_ROOT)
        cls.an = HallAnalyzer(cls.cfg)

    def test_is_repdigit(self):
        for n in (11, 22, 77, 111, 222, 999):
            self.assertTrue(_is_repdigit(n), n)
        for n in (5, 12, 101, 123, 110):
            self.assertFalse(_is_repdigit(n), n)

    def test_event_seven_day(self):
        eff = self.an.effective_effects("2026-07-27")  # 7のつく日
        self.assertIn("7のつく日", eff["event_names"])
        self.assertIn(7, eff["favored_last_digits"])

    def test_event_repdigit_day(self):
        eff = self.an.effective_effects("2026-07-22")  # 22日=ゾロ目の日
        self.assertIn("ゾロ目の日", eff["event_names"])
        self.assertTrue(eff["favor_repdigit"])

    def test_plain_day_low_strength(self):
        eff = self.an.effective_effects("2026-07-25")  # 平日想定
        # 週末強化(土日)以外は強度が低め
        self.assertLessEqual(eff["strength"], 0.7)

    def test_corner_detection(self):
        # 島A range [201,216] → 201 と 216 が角
        self.assertTrue(self.an.is_corner(201))
        self.assertTrue(self.an.is_corner(216))
        self.assertFalse(self.an.is_corner(210))

    def test_pattern_signal_favored_digit(self):
        # 末尾7・7のつく日 → スコアが立つ
        sig = self.an.pattern_signal(207, "smash_hokuto", "2026-07-27")
        self.assertGreater(sig.score, 0.0)
        self.assertTrue(any("末尾7" in r for r in sig.reasons))

    def test_pattern_signal_range(self):
        for no in (201, 207, 211, 216, 233, 256):
            sig = self.an.pattern_signal(no, "smash_hokuto", "2026-07-27")
            self.assertGreaterEqual(sig.score, 0.0)
            self.assertLessEqual(sig.score, 1.0)

    def test_prior_from_signal_leans_high(self):
        sig = self.an.pattern_signal(211, "smash_hokuto", "2026-07-27")
        spec = self.cfg.spec("smash_hokuto")
        prior = self.an.prior_from_signal(sig, spec)
        self.assertAlmostEqual(sum(prior.values()), 1.0, places=6)
        if sig.score > 0.2:
            # 高注目なら設定6の prior > 設定1の prior
            self.assertGreater(prior[6], prior[1])

    def test_learning(self):
        history = [
            {"machine_no": 207, "model_key": "smash_hokuto", "p_high": 0.9},
            {"machine_no": 217, "model_key": "smash_hokuto", "p_high": 0.8},
            {"machine_no": 202, "model_key": "tensura", "p_high": 0.1},
            {"machine_no": 203, "model_key": "tensura", "p_high": 0.2},
        ]
        learned = self.an.learn(history)
        # 末尾7 が高 p_high、末尾2/3 が低 → 末尾7の学習重みが最大
        self.assertIn(7, learned["last_digit"])
        self.assertGreaterEqual(learned["last_digit"][7], max(
            learned["last_digit"].get(2, 0), learned["last_digit"].get(3, 0)))


if __name__ == "__main__":
    unittest.main()

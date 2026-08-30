import math
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest


REPO_ROOT = Path(__file__).resolve().parents[1]
RATE_LIMIT = REPO_ROOT / "plugins/semantic-scholar/bin/_rate_limit.sh"


def run_limiter(state_path, interval="0", timeout=3):
    env = os.environ.copy()
    env.pop("S2_API_KEY", None)
    env["S2_MIN_INTERVAL"] = str(interval)
    env["TMPDIR"] = str(Path(state_path).parent)
    command = f'source "{RATE_LIMIT}"; ss_rate_wait'
    return subprocess.run(
        ["bash", "-c", command],
        env=env,
        text=True,
        capture_output=True,
        timeout=timeout,
        check=False,
    )


class RateLimitTest(unittest.TestCase):
    def assert_rewritten_as_seconds(self, state_path):
        value = float(Path(state_path).read_text().strip())
        self.assertTrue(math.isfinite(value))
        self.assertLess(abs(value - time.time()), 2)

    def test_accepts_current_seconds(self):
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / ".s2_rate_limit"
            state.write_text(f"{time.time() - 1}\n")
            result = run_limiter(state)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assert_rewritten_as_seconds(state)

    def test_migrates_legacy_nanoseconds(self):
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / ".s2_rate_limit"
            state.write_text(f"{time.time_ns()}\n")
            result = run_limiter(state)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assert_rewritten_as_seconds(state)

    def test_migrates_milliseconds_and_microseconds(self):
        for scale in (1e3, 1e6):
            with self.subTest(scale=scale), tempfile.TemporaryDirectory() as directory:
                state = Path(directory) / ".s2_rate_limit"
                state.write_text(f"{time.time() * scale:.0f}\n")
                result = run_limiter(state)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assert_rewritten_as_seconds(state)

    def test_ignores_corrupt_and_nonfinite_state(self):
        for raw in ("", "not-a-number", "nan", "inf", "-1"):
            with self.subTest(raw=raw), tempfile.TemporaryDirectory() as directory:
                state = Path(directory) / ".s2_rate_limit"
                state.write_text(raw)
                result = run_limiter(state)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assert_rewritten_as_seconds(state)

    def test_future_state_wait_is_bounded_by_interval(self):
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / ".s2_rate_limit"
            state.write_text(f"{time.time() + 1e6}\n")
            started = time.monotonic()
            result = run_limiter(state, interval="0.05")
            elapsed = time.monotonic() - started
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertLess(elapsed, 0.5)
            self.assertGreaterEqual(elapsed, 0.04)

    def test_creates_missing_state_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / "nested" / ".s2_rate_limit"
            result = run_limiter(state)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assert_rewritten_as_seconds(state)

    def test_rejects_invalid_interval(self):
        for interval in ("not-a-number", "nan", "inf", "-0.1"):
            with self.subTest(interval=interval), tempfile.TemporaryDirectory() as directory:
                state = Path(directory) / ".s2_rate_limit"
                result = run_limiter(state, interval=interval)
                self.assertEqual(result.returncode, 2)
                self.assertIn("finite non-negative", result.stderr)

    def test_concurrent_calls_are_serialized(self):
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / ".s2_rate_limit"
            env = os.environ.copy()
            env.pop("S2_API_KEY", None)
            env["S2_MIN_INTERVAL"] = "0.08"
            env["TMPDIR"] = directory
            command = f'source "{RATE_LIMIT}"; ss_rate_wait'
            started = time.monotonic()
            processes = [
                subprocess.Popen(
                    ["bash", "-c", command],
                    env=env,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                )
                for _ in range(2)
            ]
            results = [process.communicate(timeout=3) for process in processes]
            elapsed = time.monotonic() - started
            self.assertTrue(all(process.returncode == 0 for process in processes), results)
            self.assertGreaterEqual(elapsed, 0.07)
            self.assertLess(elapsed, 0.6)


if __name__ == "__main__":
    unittest.main()

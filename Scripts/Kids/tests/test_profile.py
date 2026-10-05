"""Regression checks for evidence attribution and honest timing summaries."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("kids_profile", Path(__file__).parents[1] / "profile.py")
profile = importlib.util.module_from_spec(spec)
spec.loader.exec_module(profile)


def event(trace, operation, phase, ms, parent=None, outcome=None, endpoint=None, values=None):
    return dict(runID="run", traceID=trace, parentID=parent, operation=operation,
                variant="ordered" if operation == "playback" else "grid", phase=phase,
                elapsedMS=ms, uptimeMS=1000 + ms, unixMS=2000 + ms,
                outcome=outcome, endpoint=endpoint, values=values or {})


class EvidenceTests(unittest.TestCase):
    def analyze(self, events, trailing=""):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "run.jsonl").write_text("".join(json.dumps(e) + "\n" for e in events) + trailing)
            return profile.analyze(root)

    def test_nested_http_attribution_excludes_other_playback(self):
        result = self.analyze([
            event("start", "playback", "begin", 0),
            event("episodes", "episodes", "begin", 1, parent="start"),
            event("request", "http", "begin", 2, parent="episodes", endpoint="ancestors"),
            event("request", "http", "end", 22, parent="episodes", endpoint="ancestors", outcome="success"),
            event("other", "http", "end", 20, endpoint="ancestors", outcome="success"),
            event("start", "playback", "itemSelected", 40),
            event("start", "playback", "vlcOpen", 60),
            event("start", "playback", "firstVideoOutput", 100),
            event("start", "playback", "firstClock", 100),
            event("start", "playback", "playerSurfacePresented", 120),
            event("start", "playback", "end", 100, outcome="success"),
        ])
        row = result["playback_starts"][0]
        self.assertEqual(row["instrumented_http_count"], 1)
        self.assertEqual(row["ancestor_http_count"], 1)
        self.assertEqual(row["openToVideoOutput_ms"], 40)

    def test_cancellation_missing_artwork_and_partial_line_are_distinct(self):
        result = self.analyze([
            event("cancel", "artwork", "begin", 0),
            event("cancel", "artwork", "end", 1, outcome="cancelled"),
            event("missing", "artwork", "end", 1, outcome="failure"),
            event("ok", "artwork", "response", 10, values={"status": 200}),
            event("ok", "artwork", "end", 10, outcome="success"),
        ], trailing='{"traceID":')
        self.assertEqual(result["cancellations"], {"artwork": 1})
        self.assertEqual(result["failures"], {"artwork": 1})
        self.assertEqual(result["response_status"], {"artwork": {"200": 1}})
        self.assertEqual(result["malformed_lines"], 1)

    def test_first_observed_output_can_trail_surface_without_negative_latency(self):
        result = self.analyze([
            event("start", "playback", "begin", 0),
            event("start", "playback", "playerSurfacePresented", 90),
            event("start", "playback", "firstVideoOutput", 100),
            event("start", "playback", "firstClock", 100),
            event("start", "playback", "end", 100, outcome="success"),
        ])
        distribution = result["metrics"]["playback.component.outputToSurface.ordered"]
        self.assertEqual(distribution, {"n": 0, "excluded_negative": 1})
        self.assertEqual(result["playback_starts"][0]["outputToSurface_ms"], -10)

    def test_player_surface_without_decoded_video_is_not_a_success_sample(self):
        result = self.analyze([
            event("start", "playback", "begin", 0),
            event("start", "playback", "vlcPlaying", 100),
            event("start", "playback", "playerSurfacePresented", 120),
        ])
        self.assertFalse(result["playback_starts"][0]["validated_timing_sample"])
        self.assertNotIn("playback.playerSurfacePresented.ordered", result["metrics"])

    def test_artwork_cache_hit_is_distinct_from_network_and_unclassified_shared_load(self):
        result = self.analyze([
            event("art", "artwork", "begin", 0),
            event("cache", "artworkCache", "end", 1, parent="art", outcome="success", values={"cache_hit": 1}),
            event("art", "artwork", "end", 1, outcome="success"),
            event("art", "artwork", "artworkPresented", 16),
            event("networkArt", "artwork", "begin", 0),
            event("network", "http", "end", 80, parent="networkArt", endpoint="artwork", outcome="success"),
            event("networkArt", "artwork", "end", 85, outcome="success"),
            event("networkArt", "artwork", "artworkPresented", 100),
            event("shared", "artwork", "end", 80, outcome="success"),
            event("shared", "artwork", "artworkPresented", 90),
            event("canceled", "artwork", "end", 1, outcome="cancelled"),
        ])
        self.assertEqual(result["artwork_sources"], {"memoryHit": 1, "network": 1, "sharedOrUnclassified": 1})
        self.assertEqual(result["metrics"]["artwork.presented.memoryHit.grid"]["median_ms"], 16)
        self.assertEqual(result["metrics"]["artwork.presented.network.grid"]["median_ms"], 100)

    def test_report_latency_is_separate_from_playback_preparation_requests(self):
        result = self.analyze([
            event("reportStart", "playbackReport", "begin", 0, endpoint="playbackStart"),
            event("reportStart", "playbackReport", "end", 65, endpoint="playbackStart", outcome="success"),
            event("reportStop", "playbackReport", "begin", 0, endpoint="playbackStop"),
            event("reportStop", "playbackReport", "end", 45, endpoint="playbackStop", outcome="success"),
        ])
        self.assertEqual(result["metrics"]["report.duration.playbackStart"]["median_ms"], 65)
        self.assertEqual(result["metrics"]["report.duration.playbackStop"]["median_ms"], 45)
        self.assertEqual(result["http"], {})
        self.assertEqual(result["playback_starts"], [])

    def test_failed_reports_remain_failures_and_never_enter_success_latency(self):
        result = self.analyze([
            event("report", "playbackReport", "begin", 0, endpoint="playbackProgress"),
            event("report", "playbackReport", "end", 50, endpoint="playbackProgress", outcome="failure"),
        ])
        self.assertEqual(result["failures"], {"playbackReport": 1})
        self.assertNotIn("report.duration.playbackProgress", result["metrics"])

    def test_nearest_rank_p95_is_observed_not_extrapolated(self):
        result = profile.stats([10, 20, 30, float("nan")])
        self.assertEqual(result["n"], 3)
        self.assertEqual(result["median_ms"], 20)
        self.assertEqual(result["p95_ms"], 30)


if __name__ == "__main__":
    unittest.main()

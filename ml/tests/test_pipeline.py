"""Tests for the Model 2 pipeline. Run from the workspace root:
    python -m unittest discover -s ml/tests -v
Tests that need the generated dataset (ml/data/*.csv) are skipped when it is absent.
"""
from __future__ import annotations

import json
import re
import sys
import tempfile
import unittest
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "ml"))
import common  # noqa: E402
import evaluate  # noqa: E402
import train  # noqa: E402

MODEL = ROOT / "simulator/models/track_classifier_v1.json"
METRICS = ROOT / "simulator/models/track_classifier_v1.metrics.json"
PARITY = ROOT / "simulator/tests/fixtures/ml_parity_v1.json"
FEATURES_GD = ROOT / "simulator/scripts/ai/features.gd"
DATA = ROOT / "ml/data"
HAVE_DATA = all((DATA / f"{s}.csv").exists() for s in common.SPLITS)


def simulator_feature_names() -> list:
    """Parses the NAMES constant from the simulator's features.gd source."""
    text = FEATURES_GD.read_text(encoding="utf-8")
    block = re.search(r"const NAMES := \[(.*?)\]", text, re.S).group(1)
    return re.findall(r'"([a-z0-9_]+)"', block)


class ModelArtefactTests(unittest.TestCase):
    def setUp(self):
        self.model = common.load_model(MODEL)

    def test_schema_and_feature_contract(self):
        self.assertEqual(self.model["format"], "droneacharya-ml-model")
        self.assertEqual(self.model["features_version"], "features-1")
        self.assertEqual(self.model["feature_names"], simulator_feature_names(),
                         "model inputs must equal the simulator's features-1 list, in order")
        self.assertTrue(set(self.model["classes"]) <= {"bird", "balloon", "authorised_uav", "unidentified_uav", "swarm"})
        self.assertIn(self.model["model_type"], {"random_forest", "decision_tree", "logistic_regression"})
        self.assertLess(MODEL.stat().st_size, train.MAX_ARTIFACT_BYTES)

    def test_no_ground_truth_inputs(self):
        forbidden = {"label", "profile", "truth_category", "significant", "actor_id", "group_id", "scenario_seed", "split"}
        self.assertFalse(forbidden & set(self.model["feature_names"]))

    def test_exported_inference_matches_parity_fixture(self):
        fixture = json.loads(PARITY.read_text(encoding="utf-8"))
        ours = common.predict_proba(self.model, np.asarray(fixture["features"]))
        self.assertLess(float(np.max(np.abs(ours - np.asarray(fixture["probabilities"])))), 1e-9)

    def test_training_metadata_recorded(self):
        training = self.model["training"]
        self.assertEqual(set(training["dataset_sha256"]), set(common.SPLITS))
        self.assertLess(training["export_parity_max_abs_diff"], 1e-6)
        self.assertIn("synthetic", training["label_note"])


class MetricTests(unittest.TestCase):
    def test_metrics_on_known_predictions(self):
        classes = ["a", "b"]
        perfect = evaluate.metrics(np.array(["a", "b", "a"]), np.array(["a", "b", "a"]), classes)
        self.assertEqual((perfect["accuracy"], perfect["macro_f1"]), (1.0, 1.0))
        half = evaluate.metrics(np.array(["a", "a", "b", "b"]), np.array(["a", "b", "b", "a"]), classes)
        self.assertEqual(half["accuracy"], 0.5)
        self.assertEqual(half["confusion_matrix"]["rows_true_cols_predicted"], [[1, 1], [1, 1]])

    def test_rule_metrics_report_coverage(self):
        result = evaluate.rule_metrics(np.array(["a", "b", "a", "b"]), np.array(["a", "unknown", "b", "b"]), ["a", "b"])
        self.assertEqual(result["coverage"], 0.75)
        self.assertAlmostEqual(result["accuracy_when_answering"], 2 / 3, places=4)
        self.assertEqual(result["accuracy"], 0.5)

    def test_calibration_error_of_a_perfectly_calibrated_case_is_zero(self):
        probabilities = np.array([[1.0, 0.0], [0.0, 1.0]])
        self.assertEqual(evaluate.expected_calibration_error(probabilities, np.array(["a", "b"]), ["a", "b"]), 0.0)

    def test_leakage_check_rejects_shared_seeds(self):
        splits = {"train": {"meta": {"scenario_seed": ["1", "2"]}}, "test": {"meta": {"scenario_seed": ["2", "3"]}}}
        with self.assertRaises(SystemExit):
            train.check_no_leakage(splits)


@unittest.skipUnless(HAVE_DATA, "generated dataset not present (run the generator first)")
class DatasetTests(unittest.TestCase):
    def test_splits_are_disjoint_by_scenario_and_columns_match(self):
        splits = {s: common.load_split(DATA, s) for s in common.SPLITS}
        counts = train.check_no_leakage(splits)
        self.assertEqual(counts, {"train": 600, "val": 150, "test": 200, "degraded": 100})
        for s in splits.values():
            self.assertEqual(s["feature_names"], simulator_feature_names())

    def test_shipped_metrics_come_from_the_full_held_out_test_split(self):
        test = common.load_split(DATA, "test")
        shipped = json.loads(METRICS.read_text(encoding="utf-8"))
        self.assertEqual(shipped["test"]["samples"], test["X"].shape[0])
        self.assertEqual(shipped["model_sha256"], common.file_sha256(MODEL))
        model = common.load_model(MODEL)
        predicted = np.asarray(model["classes"])[common.predict_proba(model, test["X"]).argmax(axis=1)]
        self.assertAlmostEqual(float((predicted == test["y"]).mean()), shipped["test"]["accuracy"], places=4)


class ArtefactFailureTests(unittest.TestCase):
    def test_load_model_rejects_wrong_format(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "m.json"
            path.write_text(json.dumps({"format": "other"}), encoding="utf-8")
            with self.assertRaises(ValueError):
                common.load_model(path)


if __name__ == "__main__":
    unittest.main()

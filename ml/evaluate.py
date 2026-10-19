"""Evaluate the exported Model 2 artefact on held-out data and compare with Model 1.

Usage (from the workspace root):
    python ml/evaluate.py --data ml/data --model simulator/models/track_classifier_v1.json --reports ml/reports

All ML metrics are computed from the exported JSON artefact (the model the simulator
runs), on the test split (200 unseen scenario seeds) and the separate degraded split
(100 unseen seeds with night/fog, difficulty 4-5 and long sensor degradation).
The rule-based baseline is scored on exactly the same rows from the rule category the
simulator recorded for each sample.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np
from sklearn.metrics import accuracy_score, confusion_matrix, f1_score, precision_recall_fscore_support

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common  # noqa: E402


def metrics(y_true: np.ndarray, y_pred: np.ndarray, classes: list) -> dict:
    precision, recall, f1, support = precision_recall_fscore_support(y_true, y_pred, labels=classes, zero_division=0)
    return {
        "samples": int(len(y_true)),
        "accuracy": round(float(accuracy_score(y_true, y_pred)), 4),
        "macro_f1": round(float(f1_score(y_true, y_pred, labels=classes, average="macro", zero_division=0)), 4),
        "per_class": {c: {"precision": round(float(p), 4), "recall": round(float(r), 4), "f1": round(float(f), 4), "support": int(s)}
                      for c, p, r, f, s in zip(classes, precision, recall, f1, support)},
        "confusion_matrix": {"labels": classes, "rows_true_cols_predicted":
                             confusion_matrix(y_true, y_pred, labels=classes).tolist()},
    }


def rule_metrics(y_true: np.ndarray, rule: np.ndarray, classes: list) -> dict:
    covered = rule != "unknown"
    result = metrics(y_true, rule, classes + ["unknown"])
    result["macro_f1"] = round(float(f1_score(y_true, rule, labels=classes, average="macro", zero_division=0)), 4)
    result["coverage"] = round(float(covered.mean()), 4)
    result["accuracy_when_answering"] = round(float((rule[covered] == y_true[covered]).mean()), 4) if covered.any() else None
    return result


def expected_calibration_error(probabilities: np.ndarray, y_true: np.ndarray, classes: list, bins: int = 10) -> float:
    confidence = probabilities.max(axis=1)
    correct = np.asarray(classes)[probabilities.argmax(axis=1)] == y_true
    edges = np.linspace(0.0, 1.0, bins + 1)
    ece = 0.0
    for low, high in zip(edges[:-1], edges[1:]):
        mask = (confidence > low) & (confidence <= high)
        if mask.any():
            ece += mask.mean() * abs(correct[mask].mean() - confidence[mask].mean())
    return round(float(ece), 4)


def evaluate_split(model: dict, data: dict) -> dict:
    classes = model["classes"]
    probabilities = common.predict_proba(model, data["X"])
    predicted = np.asarray(classes)[probabilities.argmax(axis=1)]
    y = data["y"]
    meta = {k: np.asarray(v) for k, v in data["meta"].items()}
    degraded_fraction = data["X"][:, data["feature_names"].index("degraded_fraction")]
    subsets = {
        "rule_evidence_insufficient": meta["rule_evidence"] == "insufficient",
        "rule_evidence_fair": meta["rule_evidence"] == "fair",
        "rule_evidence_good": meta["rule_evidence"] == "good",
        "night": meta["time_of_day"] == "night",
        "fog": meta["visibility"] == "fog",
        "haze": meta["visibility"] == "haze",
        "degraded_observations_over_30pct": degraded_fraction > 0.3,
        "difficulty_4_5": np.isin(meta["difficulty"], ["4", "5"]),
    }
    breakdown = {}
    for name, mask in subsets.items():
        if mask.sum() >= 50:
            breakdown[name] = {"samples": int(mask.sum()),
                               "ml_accuracy": round(float((predicted[mask] == y[mask]).mean()), 4),
                               "ml_macro_f1": round(float(f1_score(y[mask], predicted[mask], labels=classes, average="macro", zero_division=0)), 4),
                               "rules_accuracy": round(float((meta["rule_category"][mask] == y[mask]).mean()), 4)}
    answered = meta["rule_evidence"] != "insufficient"
    purity = meta["label_purity"].astype(float)
    return {
        "ml": metrics(y, predicted, classes),
        "rules": rule_metrics(y, meta["rule_category"], classes),
        "ml_on_rows_with_sufficient_evidence": metrics(y[answered], predicted[answered], classes),
        "ml_expected_calibration_error": expected_calibration_error(probabilities, y, classes),
        "breakdown": breakdown,
        "label_purity": {"mean": round(float(purity.mean()), 4), "share_below_0_9": round(float((purity < 0.9).mean()), 4)},
        "scenarios": int(len(set(data["meta"]["scenario_seed"]))),
    }


def matrix_table(cm: dict) -> str:
    labels = cm["labels"]
    lines = ["| true \\ predicted | " + " | ".join(labels) + " |", "|---" * (len(labels) + 1) + "|"]
    for label, row in zip(labels, cm["rows_true_cols_predicted"]):
        lines.append(f"| {label} | " + " | ".join(str(v) for v in row) + " |")
    return "\n".join(lines)


def report_markdown(model: dict, results: dict) -> str:
    out = [f"# Model 2 evaluation — {model['version']} ({model['model_type']})", "",
           "Generated by `python ml/evaluate.py`. Synthetic data from the DroneAcharya simulator only; "
           "these numbers describe performance on the simulator's own fictional behaviour profiles and do "
           "**not** indicate real-world threat-recognition accuracy.", ""]
    for split, r in results.items():
        out += [f"## Split: {split} ({r['scenarios']} unseen scenarios, {r['ml']['samples']} samples)", "",
                "| Metric | ML classifier | Rule-based baseline |", "|---|---|---|",
                f"| Accuracy | {r['ml']['accuracy']} | {r['rules']['accuracy']} (answers {r['rules']['coverage']:.0%} of samples; "
                f"{r['rules']['accuracy_when_answering']} when answering) |",
                f"| Macro-F1 | {r['ml']['macro_f1']} | {r['rules']['macro_f1']} |",
                f"| ML on samples where the rules have enough evidence | accuracy {r['ml_on_rows_with_sufficient_evidence']['accuracy']}, macro-F1 {r['ml_on_rows_with_sufficient_evidence']['macro_f1']} | — |",
                f"| ML expected calibration error (10 bins) | {r['ml_expected_calibration_error']} | n/a |", "",
                "Per-class (ML):", "", "| Class | Precision | Recall | F1 | Support |", "|---|---|---|---|---|"]
        for c, m in r["ml"]["per_class"].items():
            out.append(f"| {c} | {m['precision']} | {m['recall']} | {m['f1']} | {m['support']} |")
        out += ["", "Confusion matrix (ML):", "", matrix_table(r["ml"]["confusion_matrix"]), "",
                "Breakdown:", "", "| Subset | Samples | ML accuracy | ML macro-F1 | Rules accuracy |", "|---|---|---|---|---|"]
        for name, b in r["breakdown"].items():
            out.append(f"| {name} | {b['samples']} | {b['ml_accuracy']} | {b['ml_macro_f1']} | {b['rules_accuracy']} |")
        out += ["", f"Label purity (share of a track's observations from its majority source): mean {r['label_purity']['mean']}, "
                    f"{r['label_purity']['share_below_0_9']:.1%} of samples below 0.9.", ""]
    return "\n".join(out)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--data", default="ml/data")
    parser.add_argument("--model", default="simulator/models/track_classifier_v1.json")
    parser.add_argument("--reports", default="ml/reports")
    args = parser.parse_args()
    model = common.load_model(Path(args.model))
    results = {}
    for split in ["test", "degraded"]:
        data = common.load_split(Path(args.data), split)
        if data["feature_names"] != model["feature_names"]:
            raise SystemExit(f"{split}: feature columns do not match the model")
        results[split] = evaluate_split(model, data)
        print(f"{split}: ML accuracy {results[split]['ml']['accuracy']} macro-F1 {results[split]['ml']['macro_f1']} | "
              f"rules accuracy {results[split]['rules']['accuracy']} macro-F1 {results[split]['rules']['macro_f1']} "
              f"coverage {results[split]['rules']['coverage']} | ECE {results[split]['ml_expected_calibration_error']}")
    reports = Path(args.reports)
    reports.mkdir(parents=True, exist_ok=True)
    summary = {"model_version": model["version"], "model_type": model["model_type"], "model_sha256": common.file_sha256(Path(args.model)),
               "dataset_sha256": model["training"]["dataset_sha256"], "results": results}
    (reports / "metrics_v1.json").write_text(json.dumps(summary, indent=1), encoding="utf-8")
    (reports / "EVALUATION_v1.md").write_text(report_markdown(model, results), encoding="utf-8")
    # Compact copy shipped with the model for the in-game model information screen.
    shipped = {"model_version": model["version"], "model_type": model["model_type"], "model_sha256": summary["model_sha256"],
               "test": {k: results["test"]["ml"][k] for k in ["samples", "accuracy", "macro_f1"]} | {"ece": results["test"]["ml_expected_calibration_error"],
                        "rules_accuracy": results["test"]["rules"]["accuracy"], "rules_macro_f1": results["test"]["rules"]["macro_f1"]},
               "degraded": {k: results["degraded"]["ml"][k] for k in ["samples", "accuracy", "macro_f1"]} | {"ece": results["degraded"]["ml_expected_calibration_error"],
                            "rules_accuracy": results["degraded"]["rules"]["accuracy"], "rules_macro_f1": results["degraded"]["rules"]["macro_f1"]},
               "per_class_test": results["test"]["ml"]["per_class"]}
    Path(args.model).with_suffix(".metrics.json").write_text(json.dumps(shipped, indent=1), encoding="utf-8")
    print(f"wrote {reports / 'metrics_v1.json'}, {reports / 'EVALUATION_v1.md'} and {Path(args.model).with_suffix('.metrics.json')}")


if __name__ == "__main__":
    main()

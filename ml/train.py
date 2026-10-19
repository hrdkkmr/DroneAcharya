"""Train, select and export Model 2 (synthetic track-behaviour classifier).

Usage (from the workspace root):
    python ml/train.py --data ml/data --out simulator/models/track_classifier_v1.json

Selection uses the validation split only; the test and degraded splits are never
read here. The exported JSON contains the exact preprocessing and parameters that
the simulator evaluates in GDScript (scripts/ai/ml_classifier.gd).
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import sys
from pathlib import Path

import numpy as np
import sklearn
from sklearn.ensemble import RandomForestClassifier
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import f1_score
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.tree import DecisionTreeClassifier

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common  # noqa: E402

MAX_ARTIFACT_BYTES = 4_000_000
RANDOM_STATE = 26247


def check_no_leakage(splits: dict) -> dict:
    """Scenario seeds must not overlap between splits (each scenario is in one split)."""
    seeds = {name: set(data["meta"]["scenario_seed"]) for name, data in splits.items()}
    names = list(seeds)
    for i, a in enumerate(names):
        for b in names[i + 1:]:
            overlap = seeds[a] & seeds[b]
            if overlap:
                raise SystemExit(f"LEAKAGE: splits {a} and {b} share scenario seeds {sorted(overlap)[:5]}")
    return {name: len(s) for name, s in seeds.items()}


def candidates() -> dict:
    return {
        "logistic_regression": make_pipeline(StandardScaler(), LogisticRegression(max_iter=3000, C=1.0)),
        "decision_tree": DecisionTreeClassifier(max_depth=12, min_samples_leaf=20, class_weight="balanced", random_state=RANDOM_STATE),
        "random_forest": RandomForestClassifier(n_estimators=40, max_depth=12, min_samples_leaf=20, class_weight="balanced_subsample",
                                                random_state=RANDOM_STATE, n_jobs=-1),
    }


def export(name: str, estimator, feature_names: list) -> dict:
    model = {
        "format": common.MODEL_FORMAT, "format_version": common.MODEL_FORMAT_VERSION,
        "model_type": name, "classes": [str(c) for c in (estimator.classes_ if name != "logistic_regression" else estimator[-1].classes_)],
        "features_version": common.FEATURES_VERSION, "feature_names": feature_names,
        "preprocessing": {}, "params": {},
    }
    if name == "logistic_regression":
        scaler, clf = estimator[0], estimator[-1]
        model["preprocessing"] = {"scaler": {"mean": scaler.mean_.tolist(), "scale": scaler.scale_.tolist()}}
        model["params"] = {"coef": clf.coef_.tolist(), "intercept": clf.intercept_.tolist()}
    else:
        trees = estimator.estimators_ if name == "random_forest" else [estimator]
        model["params"] = {"trees": [export_tree(t) for t in trees]}
    return model


def export_tree(tree) -> dict:
    t = tree.tree_
    leaves = [i for i in range(t.node_count) if t.children_left[i] == -1]
    values = t.value[leaves, 0, :]
    values = values / values.sum(axis=1, keepdims=True)
    return {
        "left": t.children_left.tolist(), "right": t.children_right.tolist(),
        "feature": [int(f) if f >= 0 else -1 for f in t.feature],
        "threshold": [float(x) for x in t.threshold],  # full precision: rounding can flip a split
        "leaf_nodes": leaves, "leaf_values": np.round(values, 9).tolist(),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--data", default="ml/data")
    parser.add_argument("--out", default="simulator/models/track_classifier_v1.json")
    parser.add_argument("--parity", default="simulator/tests/fixtures/ml_parity_v1.json")
    args = parser.parse_args()
    data_dir = Path(args.data)
    train = common.load_split(data_dir, "train")
    val = common.load_split(data_dir, "val")
    seed_counts = check_no_leakage({"train": train, "val": val,
                                    "test": common.load_split(data_dir, "test"),
                                    "degraded": common.load_split(data_dir, "degraded")})
    if train["feature_names"] != val["feature_names"]:
        raise SystemExit("feature columns differ between splits")
    feature_names = train["feature_names"]
    print(f"train {train['X'].shape}, val {val['X'].shape}, scenarios per split {seed_counts}")

    results = {}
    for name, estimator in candidates().items():
        estimator.fit(train["X"], train["y"])
        predicted = estimator.predict(val["X"])
        macro_f1 = f1_score(val["y"], predicted, average="macro")
        exported = export(name, estimator, feature_names)
        size = len(json.dumps(exported, separators=(",", ":")))
        results[name] = {"estimator": estimator, "val_macro_f1": float(macro_f1), "bytes": size, "model": exported}
        print(f"  {name:20s} val macro-F1 {macro_f1:.4f}  artefact {size / 1e6:.2f} MB")

    eligible = {n: r for n, r in results.items() if r["bytes"] <= MAX_ARTIFACT_BYTES}
    chosen = max(eligible, key=lambda n: (round(eligible[n]["val_macro_f1"], 3), -eligible[n]["bytes"]))
    model = results[chosen]["model"]
    # Exported-artefact parity with scikit-learn on the validation split.
    ours = common.predict_proba(model, val["X"])
    theirs = results[chosen]["estimator"].predict_proba(val["X"])
    parity = float(np.max(np.abs(ours - theirs)))
    if parity > 1e-6:
        raise SystemExit(f"exported model differs from scikit-learn by {parity}")
    model["training"] = {
        "created_at": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
        "sklearn_version": sklearn.__version__, "numpy_version": np.__version__,
        "selected_by": "validation macro-F1 (ties: smaller artefact)",
        "candidates": {n: {"val_macro_f1": round(r["val_macro_f1"], 4), "bytes": r["bytes"]} for n, r in results.items()},
        "train_samples": int(train["X"].shape[0]), "val_samples": int(val["X"].shape[0]),
        "scenarios_per_split": seed_counts,
        "dataset_sha256": {s: common.file_sha256(data_dir / f"{s}.csv") for s in common.SPLITS},
        "export_parity_max_abs_diff": parity,
        "label_note": "Labels are the simulator's predefined synthetic behaviour profiles, not real-world classes.",
    }
    model["version"] = "track-classifier-v1"
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(model, separators=(",", ":")), encoding="utf-8")
    print(f"selected {chosen}; wrote {out} ({out.stat().st_size / 1e6:.2f} MB); parity {parity:.2e}")

    # Parity fixture for the GDScript test: first 300 validation rows + expected probabilities.
    sample = val["X"][:300]
    fixture = {"model": out.name, "classes": model["classes"], "feature_names": feature_names,
               "features": sample.tolist(), "probabilities": common.predict_proba(model, sample).tolist()}
    parity_path = Path(args.parity)
    parity_path.parent.mkdir(parents=True, exist_ok=True)
    parity_path.write_text(json.dumps(fixture), encoding="utf-8")
    print(f"wrote parity fixture {parity_path}")


if __name__ == "__main__":
    main()

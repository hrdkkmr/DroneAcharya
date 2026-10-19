"""Shared helpers for the DroneAcharya track-classifier pipeline.

The dataset CSVs are produced by simulator/tools/generate_dataset.gd. Columns are
META_COLUMNS followed by the features-1 values in the simulator's documented order.
"""
from __future__ import annotations

import csv
import hashlib
import json
from pathlib import Path

import numpy as np

META_COLUMNS = ["split", "scenario_seed", "difficulty", "environment", "time_of_day", "visibility",
                "t", "track_id", "label", "label_purity", "rule_category", "rule_evidence"]
CLASSES = ["authorised_uav", "balloon", "bird", "swarm", "unidentified_uav"]
MODEL_FORMAT = "droneacharya-ml-model"
MODEL_FORMAT_VERSION = 1
FEATURES_VERSION = "features-1"
SPLITS = ["train", "val", "test", "degraded"]


def load_split(data_dir: Path, split: str) -> dict:
    """Returns {"meta": {column: list}, "X": float array, "y": str array, "feature_names": list}."""
    path = Path(data_dir) / f"{split}.csv"
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.reader(handle)
        header = next(reader)
        if header[: len(META_COLUMNS)] != META_COLUMNS:
            raise ValueError(f"{path}: unexpected metadata columns {header[:len(META_COLUMNS)]}")
        feature_names = header[len(META_COLUMNS):]
        meta = {name: [] for name in META_COLUMNS}
        rows = []
        for row in reader:
            for i, name in enumerate(META_COLUMNS):
                meta[name].append(row[i])
            rows.append([float(v) for v in row[len(META_COLUMNS):]])
    X = np.asarray(rows, dtype=np.float64)
    if not np.all(np.isfinite(X)):
        raise ValueError(f"{path}: non-finite feature values")
    return {"meta": meta, "X": X, "y": np.asarray(meta["label"]), "feature_names": feature_names}


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_model(path: Path) -> dict:
    model = json.loads(Path(path).read_text(encoding="utf-8"))
    if model.get("format") != MODEL_FORMAT or model.get("format_version") != MODEL_FORMAT_VERSION:
        raise ValueError("not a droneacharya-ml-model v1 file")
    return model


def predict_proba(model: dict, X: np.ndarray) -> np.ndarray:
    """Inference from the exported JSON artefact (the same maths the simulator runs)."""
    X = np.asarray(X, dtype=np.float64)
    if model["model_type"] == "logistic_regression":
        scaler = model["preprocessing"]["scaler"]
        Z = (X - np.asarray(scaler["mean"])) / np.asarray(scaler["scale"])
        logits = Z @ np.asarray(model["params"]["coef"]).T + np.asarray(model["params"]["intercept"])
        logits -= logits.max(axis=1, keepdims=True)
        exp = np.exp(logits)
        return exp / exp.sum(axis=1, keepdims=True)
    # scikit-learn trees compare float32-rounded inputs with their thresholds.
    X = X.astype(np.float32).astype(np.float64)
    trees = model["params"]["trees"]
    total = np.zeros((X.shape[0], len(model["classes"])))
    rows = np.arange(X.shape[0])
    for tree in trees:
        left = np.asarray(tree["left"])
        right = np.asarray(tree["right"])
        feature = np.asarray(tree["feature"])
        threshold = np.asarray(tree["threshold"])
        leaf_slot = np.full(left.shape[0], -1)
        leaf_slot[np.asarray(tree["leaf_nodes"])] = np.arange(len(tree["leaf_nodes"]))
        leaf_values = np.asarray(tree["leaf_values"])
        node = np.zeros(X.shape[0], dtype=np.int64)
        while True:
            internal = left[node] != -1
            if not internal.any():
                break
            go_left = X[rows, np.maximum(feature[node], 0)] <= threshold[node]
            node = np.where(internal, np.where(go_left, left[node], right[node]), node)
        total += leaf_values[leaf_slot[node]]
    return total / len(trees)

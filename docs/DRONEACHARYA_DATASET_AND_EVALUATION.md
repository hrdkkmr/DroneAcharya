# DroneAcharya — Model 2: Dataset and Evaluation

Component class: **trained ML inference** (Model 2). Rule-based Models 1 and 3 and the assessment rubric are described in `DRONEACHARYA_DECISION_MODELS.md`.

> **Scope and limitation (read first).** Model 2 classifies **synthetic track behaviour produced by this simulator** into the simulator's own five fictional behaviour profiles. Its training labels are those predefined profiles, and its inputs come from a synthetic sensor model. The results below measure how well it separates *these simulated profiles*. They **do not** establish real-world threat-recognition accuracy, are **not** validated for any operational use, and the model's scores are **not calibrated probabilities**.

---

## 1. Intended use

The model is a training aid. Once per second, for each confirmed track, it proposes one of `authorised_uav`, `balloon`, `bird`, `swarm` or `unidentified_uav`. The decision-support panel shows this beside the rule-based baseline, and the response policy (Model 3) uses it when it is loaded.

The trainee always makes their own classification and response. The model's recommendation at response time is recorded so the after-action review can compare the two.

## 2. Inputs and labels

- **Inputs:** the 27 `features-1` values (`scripts/ai/features.gd`), computed from tracker output and public context only. They are listed in `DRONEACHARYA_DECISION_MODELS.md` §1.
  - The model file stores the feature names and order. The simulator refuses to load a model whose features differ.
  - A Python test parses the feature list from `features.gd` and checks it against the model.
- **Labels:** the profile of the actor that produced the majority of a track's observations, taken from the sensor's separate truth-link map. This happens **only in the dataset generator**, never at inference.
  - **Label purity** (the share of a track's observations from its majority source) averages 0.886 on test and 0.821 on the degraded set. Association errors make some tracks mixtures, so labels carry some noise.
  - **No clutter class:** no false (clutter) track survived the 2 s minimum track age needed to be sampled, so clutter is not a class. False tracks are handled by the tracker's confirmation rule and by the rubric's false-alarm penalty.

## 3. Dataset generation (reproducible)

`simulator/tools/generate_dataset.gd` runs the real simulation headless: procedural scenario → world → sensors → tracker → `features-1`. This is the exact code used at inference time. Every 5 simulated seconds, each confirmed track at least 2 s old contributes one sample.

| Split | Scenario seeds | Scenarios | Samples | authorised_uav | balloon | bird | swarm | unidentified_uav |
|---|---|---|---|---|---|---|---|---|
| train | 100000–100599 | 600 | 100,961 | 12,844 | 13,051 | 32,541 | 23,861 | 18,664 |
| val | 200000–200149 | 150 | 25,760 | 3,274 | 3,095 | 8,520 | 6,192 | 4,679 |
| test | 300000–300199 | 200 | 33,976 | 4,321 | 4,664 | 10,933 | 7,362 | 6,696 |
| degraded | 400000–400099 | 100 | 13,199 | 1,393 | 1,651 | 4,152 | 2,454 | 3,549 |
| **total** | | **1,050** | **173,896** | | | | | |

- **Scenario options:** difficulty is drawn from 1–5 per seed, and swarms appear in about half the scenarios. The *degraded* split forces difficulty 4–5, night **or** fog, and a sensor degradation window (severity 0.6) covering all but the first and last 20 s.
- **Leakage control:** splits are by **scenario seed**, so a scenario contributes to exactly one split and correlated samples from the same track never cross splits. `train.py` aborts if any seed appears in two splits, and a Python test repeats the check. Model selection uses only `val`; `test` and `degraded` are read only by `evaluate.py`.
- **Not committed:** the datasets (about 51 MB in `ml/data/`, git-ignored). Their SHA-256 hashes are stored in the model file.
- **Generation time:** about 6 minutes on this laptop, with the four splits in parallel.

## 4. Model and preprocessing

| Item | Value |
|---|---|
| Candidates (validation macro-F1) | logistic regression with standardisation **0.8928**; decision tree (depth 12) 0.8622; **random forest 0.8979** |
| Selected | random forest: 40 trees, max depth 12, min 20 samples per leaf, `class_weight="balanced_subsample"`, `random_state=26247` |
| Selection rule | highest validation macro-F1 (rounded to 3 decimals), ties to the smaller artefact; artefact limit 4 MB. The margin over logistic regression is small (0.005) |
| Preprocessing | none for trees. Inputs are rounded to float32 before threshold comparison, exactly as scikit-learn does |
| Artefact | `simulator/models/track_classifier_v1.json` (`droneacharya-ml-model` v1, 1.34 MB): classes, feature names, version, all tree arrays at full precision, training metadata |
| Export check | exported-artefact probabilities match scikit-learn to **1.8 × 10⁻¹⁰** on the validation split |
| Libraries | Python 3.13.7, scikit-learn 1.8.0, NumPy 2.3.5 (`ml/requirements.txt`); used only for training and evaluation |

### Inference in the simulator (`scripts/ai/ml_classifier.gd`)

The simulator evaluates the JSON artefact natively in GDScript, so there is **no Python, service or network at run time**.

- **Validation on load:** format, version, model type, classes, exact feature list, and array lengths and indices. Any failure leaves the model unloaded with an error message. Decision support then uses the rule-based baseline, and the UI labels this as a fallback.
- **Parity:** GDScript output matches scikit-learn to within 10⁻⁶ on all 300 rows of `tests/fixtures/ml_parity_v1.json`, with identical predicted classes (`test_ml_classifier.gd`).
- **Latency:** **about 0.11–0.12 ms per track** (mean of 200–300 predictions; measured by the test suite and on the Settings screen) on an Intel Core Ultra 5 125H laptop with integrated Intel Arc graphics. Inference runs once per second per confirmed track.

## 5. Held-out results (from the deployed artefact)

All numbers come from `python ml/evaluate.py`, computed on scenarios never used in training or selection. The full report is in `ml/reports/EVALUATION_v1.md` and the machine-readable version in `ml/reports/metrics_v1.json`.

The rule-based baseline (`rules-da-2`) is scored on **the same rows**. It may answer "unknown" (when evidence is insufficient or no rule matches), which counts as wrong for accuracy; its coverage is reported.

| Split | ML accuracy | ML macro-F1 | Rules accuracy | Rules macro-F1 | Rules coverage | ML calibration error (ECE, 10 bins) |
|---|---|---|---|---|---|---|
| test (33,976) | **0.889** | **0.898** | 0.565 | 0.635 | 84 % (0.669 when answering) | 0.128 |
| degraded (13,199) | **0.757** | **0.783** | 0.302 | 0.341 | 64 % (0.473 when answering) | 0.104 |

On rows where the rules had enough evidence to answer, ML accuracy is 0.903 (test) and 0.782 (degraded).

### Per-class (test)

| Class | Precision | Recall | F1 | Support |
|---|---|---|---|---|
| authorised_uav | 0.988 | 0.991 | 0.990 | 4,321 |
| balloon | 0.924 | 0.906 | 0.915 | 4,664 |
| bird | 0.862 | 0.907 | 0.884 | 10,933 |
| swarm | 0.906 | 0.889 | 0.897 | 7,362 |
| unidentified_uav | 0.829 | 0.784 | 0.806 | 6,696 |

### Confusion matrix (test, rows = true, columns = predicted)

| true \ predicted | authorised_uav | balloon | bird | swarm | unidentified_uav |
|---|---|---|---|---|---|
| authorised_uav | 4283 | 4 | 17 | 6 | 11 |
| balloon | 4 | 4227 | 309 | 26 | 98 |
| bird | 40 | 127 | 9917 | 231 | 618 |
| swarm | 6 | 49 | 411 | 6541 | 355 |
| unidentified_uav | 3 | 169 | 857 | 418 | 5249 |

### Degraded conditions

Accuracy falls from 0.889 to 0.757. The most serious weakness:

- **Unidentified UAVs are recalled only 47 % of the time under degradation.** 1,461 of 3,549 are predicted as *bird*.
- In a trainer this matters most, because it under-calls a threat. This is one reason the trainee, not the model, makes the final decision, and the policy asks for more identification when evidence is weak.

Subset results (test):

| Subset | ML accuracy | Rules accuracy |
|---|---|---|
| night | 0.894 | 0.624 |
| fog | 0.864 | 0.595 |
| haze | 0.914 | 0.594 |
| > 30 % of observations degraded | 0.887 | 0.520 |
| difficulty 4–5 | 0.878 | 0.525 |
| insufficient evidence (rules abstain) | 0.783 | 0.000 |

### Rule-baseline history

`rules-da-1` used a-priori thresholds and scored accuracy 0.448 / macro-F1 0.484 on test. Its R2, R3 and R5 thresholds were then revised using per-class percentiles of the **training split only**, giving `rules-da-2` (0.565 / 0.635). The rules remain a deliberately simple, explainable baseline. Single features overlap heavily between birds, unidentified UAVs and swarms, which is where the multivariate model gains most.

## 6. Reproduce

From `E:\Hardik\Programming\DroneAcharya` in PowerShell (the four generator commands may run in parallel):

```powershell
$G = ".\Godot_v4.7.2-stable_win64_console.exe"
& $G --headless --path simulator --script res://tools/generate_dataset.gd -- --split=train    --out=E:/Hardik/Programming/DroneAcharya/ml/data/train.csv
& $G --headless --path simulator --script res://tools/generate_dataset.gd -- --split=val      --out=E:/Hardik/Programming/DroneAcharya/ml/data/val.csv
& $G --headless --path simulator --script res://tools/generate_dataset.gd -- --split=test     --out=E:/Hardik/Programming/DroneAcharya/ml/data/test.csv
& $G --headless --path simulator --script res://tools/generate_dataset.gd -- --split=degraded --out=E:/Hardik/Programming/DroneAcharya/ml/data/degraded.csv
python ml/train.py                       # selects on val; writes the model JSON and parity fixture
python ml/evaluate.py                    # test + degraded metrics; writes ml/reports/* and the shipped metrics
python -m unittest discover -s ml/tests -v
```

Python requirements: `python -m pip install -r ml/requirements.txt`. These were already installed on the development machine.

The dataset hashes in the model file let you confirm that a regenerated dataset is byte-identical. Generation is deterministic for a given simulator version.

## 7. Known limitations

- **Synthetic only:** behaviour profiles, sensor physics and noise are fictional, and the model has never seen real data.
- **Not calibrated:** ECE is about 0.10–0.13, and scores must not be read as probabilities. The policy uses fixed thresholds.
- **Labels:** labels inherit tracker association errors (the purity figures in §2).
- **Correlated samples:** samples from the same track are correlated. Splitting by scenario prevents leakage, but the effective sample size is smaller than the row count.
- **Degraded performance and threat under-calling:** see §5.
- **No continuous retraining:** a new simulator version that changes `features-1` requires regenerating, retraining and bumping the feature version. The loader enforces this.

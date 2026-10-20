# DroneAcharya — Decision Models and Training Assessment

Component classes:

- **Rule-based decisions:** Model 1 (rule engine) and Model 3 (policy).
- **Trained ML inference:** Model 2 (§3).
- **Training assessment:** `da-rubric-1` (§5).

All of them read **only** trainee-visible data: tracker output and public scenario context. Ground truth is used only by the assessment, by dataset labelling and by replay.

Everything here is a **synthetic training aid**:

- Categories describe the simulator's own fictional behaviour profiles; they do not establish real-world threat-recognition ability.
- Responses are procedural communication steps. There is no targeting, interception, engagement or electronic-attack function anywhere in the project.

---

## 1. Inputs: `features-1` (`scripts/ai/features.gd`)

These are computed once per second for every confirmed track, from the tracker's record of delivered observations plus public context: the wind report, the protected-zone geometry and other tracks.

| Feature | Meaning |
|---|---|
| `duration_s`, `hits`, `radar_hits`, `eo_hits`, `eo_id_hits` | Observation volume; `eo_id_hits` = camera looks at identification quality |
| `speed_mean`, `speed_std`, `speed_max` | Horizontal speed of the filtered track (m/s) |
| `turn_rate_mean_dps`, `turn_rate_std_dps` | Heading change between history samples, only when both samples exceed 2 m/s |
| `climb_abs_mean`, `altitude_mean`, `altitude_std` | Vertical behaviour |
| `straightness` | Net displacement ÷ path length (0–1) |
| `air_speed_mean`, `wind_alignment` | \|v − wind\| and the cosine between the track heading and the reported wind |
| `quality_mean`, `id_reply_fraction` | Mean signal quality; share of radar returns carrying the fictional cooperative ID reply |
| `size_mean`, `has_size`, `flap_fraction` | Camera apparent size and wing-beat share (identification quality only) |
| `neighbor_count`, `in_swarm_group` | Other confirmed tracks within 80 m with similar velocity; tracker swarm-group flag |
| `zone_distance_min`, `zone_distance_last`, `range_last` | Distance to the zone centre in zone radii; range from the observer (m) |
| `degraded_fraction` | Share of the track's observations made during degradation |

**Truth isolation is verified, not just claimed.** `test_decision_models.gd::test_decisions_never_read_ground_truth_labels` overwrites every actor's profile, truth category, significance and group in a running session. Every feature, assessment and recommendation stays identical to an unmodified run.

## 2. Model 1 — rule-based baseline (`rules-da-2`, `scripts/ai/rule_engine.gd`)

This is a **rule-based model, not machine learning.**

**Evidence quality:**

- *insufficient* — under 6 s of track or fewer than 5 observations; the result is always "unknown";
- *good* — at least 5 identification-quality camera looks, **or** at least 15 radar hits over 15 s or more;
- *fair* — anything else.

Rules are checked in this order, and the first match wins:

| Code | Category | Base score | Condition |
|---|---|---|---|
| R1_ID_REPLY | authorised_uav | 0.85 | ≥ 3 radar hits and ID reply on ≥ 50 % |
| R2_SWARM | swarm | 0.80 | ≥ 1 neighbouring track, or a tracker swarm group |
| R3_WIND_DRIFT | balloon | 0.80 | air speed < 4 m/s and wind alignment > 0.5 |
| R4_WING_BEAT | bird | 0.85 | ≥ 3 identification looks and wing beat on ≥ 50 % |
| R5_ERRATIC | bird | 0.60 | mean turn rate > 18°/s **or** straightness < 0.4, speed 4–16 m/s, apparent size absent or < 0.9 m |
| R6_LARGE_SLOW | balloon | 0.70 | apparent size ≥ 1.4 m and speed < 4 m/s |
| R7_UAV_KINEMATICS | unidentified_uav | 0.65 | ≥ 5 radar hits, ID reply < 20 %, speed ≤ 16 m/s |
| R8_NO_MATCH | unknown | 0.35 | none of the above |

With *fair* evidence the score is multiplied by 0.85. The score is a **rule-assigned value, not a calibrated probability**, and the UI says so.

## 3. Model 2 — trained machine-learning classifier (`track-classifier-v1`)

This is **trained ML inference**: a scikit-learn random forest (40 trees, depth ≤ 12). It was trained on 100,961 samples from 600 seeded scenarios, selected on 150 validation scenarios and evaluated on 200 + 100 unseen scenarios.

- **Artefact:** exported to `simulator/models/track_classifier_v1.json` and evaluated **in GDScript**, locally and offline (`scripts/ai/ml_classifier.gd`; about 0.12 ms per track).
- **Inputs:** `features-1` only. The loader refuses a model whose feature list differs.
- **Output:** `{ok, model, method, category, confidence, probabilities, evidence, latency_us}`. `evidence` is Model 1's evidence-quality rating for the same features.
- **Fallback:** if the file is missing, corrupt, of the wrong version or has mismatched features, the classifier stays unloaded with an error message. Decision support and the policy then use Model 1, and the UI shows "ML classifier unavailable … using the rule-based baseline". The "Use the trained ML classifier" setting can also switch it off.
- **Held-out test:** accuracy **0.889**, macro-F1 **0.898** (rules-da-2: 0.565 / 0.635).
- **Degraded set:** 0.757 / 0.783 (rules-da-2: 0.302 / 0.341).
- **Not calibrated:** ECE 0.13. Scores are not probabilities.

Full dataset, method, metrics, confusion matrices and limitations: `DRONEACHARYA_DATASET_AND_EVALUATION.md`.

### Rule-baseline version note

The table in §2 shows the current `rules-da-2`. Compared with `rules-da-1`, the R2, R3 and R5 thresholds were set from **training-split** per-class percentiles, and R7 lost its turn-rate cap. `rules-da-1` used a-priori values: R2 ≥ 2 neighbours; R3 air speed < 2 m/s and alignment > 0.7; R5 turn rate > 25°/s; R7 turn rate ≤ 25°/s.

## 4. Model 3 — response policy (`policy-da-1`, `scripts/ai/decision_policy.gd`)

The policy is **separate from classification.** It consumes an assessment (category, score, evidence quality) from Model 2 when a valid ML model is loaded, otherwise from Model 1. It also uses `features-1` for the motion and zone geometry. It never sees truth.

| Reason code | Condition (checked in order) | Recommended response |
|---|---|---|
| P_INSUFFICIENT_UAV_LIKE | evidence insufficient; speed > 3 m/s, ID reply < 20 %, no wing beat | Request additional identification |
| P_INSUFFICIENT | evidence insufficient otherwise | Continue observing |
| P_UNKNOWN | category unknown | Request additional identification |
| P_LOW_CONFIDENCE | score < 0.6 | Request additional identification |
| P_BACKGROUND | bird or balloon | Log the observation |
| P_COOPERATIVE | authorised UAV | Log the observation |
| P_UNIDENTIFIED_IN_ZONE | unidentified UAV with last position inside the zone | Issue a training-area alert |
| P_UNIDENTIFIED | unidentified UAV outside the zone | Notify the supervisor |
| P_SWARM | swarm | Issue a training-area alert |

Every recommendation includes `response`, `reason_code` (machine-readable), `explanation` (human-readable) and `based_on` (which model produced the assessment).

`decision_support.gd` runs features → Model 1 (→ Model 2) → Model 3 once per second. It logs a `model_output` event whenever a track's category, evidence, ML category, response or reason changes. When the trainee responds, the current recommendation is stored with the action, so the review can compare model and trainee.

## 5. Training assessment — `da-rubric-1` (`scripts/training/rubric.gd`)

This is a pure function of a session record. It adapts **VIGIL `rubric-1`**: window credit, unknown-is-legitimate credit, the evidence-based decision table, explicit penalties and event-anchored findings. It also adds 3D-specific rules. It **does not** copy VIGIL's 4-second observation schedule.

### Entities and opportunity

- **Entities:** one per actor; a truth swarm group counts as one entity when `group_swarms` is true (the default).
- **False tracks:** tracks whose observations are mostly clutter become separate false-track entities.
- **Track-to-entity mapping:** a majority vote over each track's observation truth links.
- **Available time (T_avail):** the first time any of the entity's tracks was **confirmed**, which is when the sensors presented it to the trainee.
- **Not scored:** an entity never confirmed is not scored (rule N0). That's the sensors' miss, not the trainee's.
- **Evidence seconds:** the number of 1-second samples between T_avail and the decision in which the object was **genuinely available at identification quality**, per a truth-side geometric check (`SensorModel.identification_available`):
  - within the camera's identification range and field of view, with clear line of sight;
  - or a cooperative object within radar coverage.

  This measures real availability, **not** time spent looking at the screen. *Strong* evidence = 3 s or more.

### Components (each 0–1 per entity, averaged over eligible entities)

| Component (default weight) | Credit |
|---|---|
| Detection (20) | `windowCredit(T_ack − T_avail, 5 s, 30 s)`; 0 if never acknowledged |
| Classification (20) | correct = 1; wrong = 0; unknown = 0.75 (weak evidence) / 0.5 (strong); none = 0 |
| Evidence (15) | unknown: 1 (weak) / 0.75 (strong); specific with weak evidence = 0.25; specific with strong evidence: 1 if correct, 0 if wrong |
| Response (20) | table below, weak / strong evidence at response time |
| Response time (15) | `0.4 + 0.6 × windowCredit(T_resp − T_avail, 15 s, 60 s)`; 0 if no response |
| Degraded conditions (10) | mean of detection, classification and response credit for entities first available within 30 s before or during a degradation window |

`windowCredit(l, g, d) = clamp((d − l) / (d − g), 0, 1)`, the same function as VIGIL's.

If no entity qualifies for the degraded component (or any other component has no data), its weight is **redistributed proportionally**, so the effective weights still total 100. Finding W1 records this.

### Response credit (strong / weak evidence)

| Object (truth) | Log | Continue observing | Request ID | Notify supervisor | Training-area alert |
|---|---|---|---|---|---|
| Bird, balloon, authorised UAV | 1 / 1 | 0.75 / 1 | 0.75 / 1 | 0 (+ P2) | 0 (+ P2) |
| Unidentified UAV | 0 | 0.5 / 0.75 | 0.5 / 0.75 | 1 | 0.75 (1 if it entered the zone) |
| Swarm | 0 | 0.5 / 0.75 | 0.5 / 0.75 | 0.75 | 1 |

### Penalties

| Rule | Points | Condition |
|---|---|---|
| P1 | −4 | specific category with confidence > 70 % and fewer than 3 s of identification-quality evidence |
| P2 | −8 each | notify or alert for a non-threat or a false (clutter) track — **false alarm** |
| P3 | −5 each | a threat (unidentified UAV or swarm) was confirmed but never received a response — **missed threat** |
| P4 | −1 per action over 3, max −5 | **action spam**: repeated acknowledgements, more than 3 classifications of one track, responses after a final response, actions on non-existent tracks |

### Result and edge cases

- **Score** = clamp(Σ component mean × effective weight − penalties, 0, 100), displayed to 0.1. Unrounded values are used internally.
- **Component scores** are always within 0–100.
- **Comparable** = the session completed **and** at least one entity was eligible. Aborted sessions and E0 sessions (nothing ever confirmed) are not comparable.
- **Explanations:** every component shortfall and penalty is a finding with a rule code, entity, points, a plain-language reason and the `event_seqs` of the actions it refers to.

### Trainee workflow (`ThreatSession`)

acknowledge (F) → classify (category + confidence 0–100) → respond (one final response).

- Classifying or responding to a track in an observed swarm group applies to the whole group when `group_swarms` is on.
- Order errors (for example, classifying before acknowledging) are rejected with a message but are **not** spam.
- Every action, accepted or rejected, is logged with its tick.

## 6. Adaptive difficulty — `adapt-da-1` (`scripts/training/adaptive.gd`)

This is **rule-based, not machine learning.** It is modelled on VIGIL's `rules-1`, is deterministic (the same history always gives the same recommendation) and runs on the history screen. "Start recommended exercise" opens the briefing for the recommended config.

**Which sessions count:** only **completed, comparable** sessions; aborted and no-evidence sessions are excluded, and the number excluded is reported. The window is the last 5 such sessions; "recent" means the last 3. The baseline level is that of the latest counted session.

| Rule | Condition | Result |
|---|---|---|
| foundation | no counted session | level 1, single threat, day, clear |
| sparse | fewer than 3 counted sessions | hold the level |
| inconsistent | recent scores differ by more than 20 points | hold the level |
| increase / ceiling | all recent scores ≥ 80 and no missed-threat (P3) or false-alarm (P2) findings | +1 level (never above 5) |
| decrease / floor | all recent scores < 55 | −1 level (never below 1) |
| consolidate | otherwise | hold the level |

**Focus.** The component with the lowest mean over the window steers the next exercise's conditions:

| Weakest component | Next exercise |
|---|---|
| classification or evidence | day, clear visibility |
| detection or response time | no swarm |
| degraded conditions | fog |
| response | same conditions |

**Seed and config.** The next seed is the latest seed + 7919, skipping any seed already used in saved history. The config comes from the procedural generator for that seed, options and level, so the difficulty level in turn sets target count, sensor detection probability, noise, delay, clutter and degradation (`DRONEACHARYA_SIMULATION_MODELS.md` §2).

**Output:** `{policy, method: "rule-based", rule, baseline_difficulty, difficulty, difficulty_change, focus, reasons[], evidence_session_ids, excluded_sessions, config}`. Every reason is shown on screen.

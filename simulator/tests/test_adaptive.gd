extends "res://tests/test_case.gd"
## adapt-da-1: every rule, bounds, focus selection, fresh seeds and reproducibility.

const Adaptive := preload("res://scripts/training/adaptive.gd")
const ScenarioConfig := preload("res://scripts/sim/scenario_config.gd")
const Rubric := preload("res://scripts/training/rubric.gd")


## A minimal session record with a given score, difficulty and component scores.
func _session(n: int, score: float, difficulty := 2, components := {}, status := "completed", findings := []) -> Dictionary:
	var comps := {}
	for key in Rubric.COMPONENTS:
		comps[key] = {"score": float(components.get(key, score)), "n": 0 if key == "degraded" and not components.has("degraded") else 1}
	var config: Dictionary = ScenarioConfig.generate(5000 + n, {"difficulty": difficulty})["config"]
	return {"session_id": "s%02d" % n, "created_at": "2026-10-20T10:%02d:00Z" % n, "status": status,
		"scenario": config, "evaluation": {"score": score, "comparable": status == "completed", "components": comps, "findings": findings}}


func test_foundation_when_there_is_no_history() -> void:
	var r := Adaptive.recommend([])
	assert_eq([r["rule"], r["difficulty"], r["method"]], ["foundation", 1, "rule-based"], "foundation, labelled rule-based")
	assert_eq(r["config"]["groups"].size(), 1, "single threat")
	assert_true(ScenarioConfig.validate(r["config"])["ok"], "valid config")


func test_sparse_and_inconsistent_history_hold_the_level() -> void:
	var sparse := Adaptive.recommend([_session(1, 95, 2), _session(2, 95, 2)])
	assert_eq([sparse["rule"], sparse["difficulty"]], ["sparse", 2], "two sessions are not enough")
	var noisy := Adaptive.recommend([_session(1, 95, 2), _session(2, 60, 2), _session(3, 90, 2)])
	assert_eq([noisy["rule"], noisy["difficulty"]], ["inconsistent", 2], "35-point spread holds")


func test_strong_results_increase_by_one_up_to_the_ceiling() -> void:
	var up := Adaptive.recommend([_session(1, 85, 2), _session(2, 88, 2), _session(3, 90, 2)])
	assert_eq([up["rule"], up["difficulty"], up["difficulty_change"]], ["increase", 3, "increase"], "+1 level")
	assert_eq(up["config"]["difficulty"], 3, "recommended config uses the new level")
	var top := Adaptive.recommend([_session(1, 90, 5), _session(2, 92, 5), _session(3, 95, 5)])
	assert_eq([top["rule"], top["difficulty"]], ["ceiling", 5], "never above level 5")
	var penalised := Adaptive.recommend([_session(1, 85, 2), _session(2, 88, 2, {}, "completed", [{"rule": "P3"}]), _session(3, 90, 2)])
	assert_eq(penalised["difficulty"], 2, "a missed threat blocks the increase")


func test_weak_results_decrease_by_one_down_to_the_floor() -> void:
	var down := Adaptive.recommend([_session(1, 40, 3), _session(2, 45, 3), _session(3, 50, 3)])
	assert_eq([down["rule"], down["difficulty"]], ["decrease", 2, ], "-1 level")
	var bottom := Adaptive.recommend([_session(1, 30, 1), _session(2, 35, 1), _session(3, 40, 1)])
	assert_eq([bottom["rule"], bottom["difficulty"]], ["floor", 1], "never below level 1")


func test_only_completed_comparable_sessions_count() -> void:
	var r := Adaptive.recommend([_session(1, 90, 2), _session(2, 90, 2), _session(3, 10, 2, {}, "aborted"), _session(4, 90, 2)])
	assert_eq(r["rule"], "increase", "the aborted session is ignored")
	assert_eq(r["excluded_sessions"], 1, "exclusion reported")


func test_focus_follows_the_weakest_component_and_seed_is_fresh() -> void:
	var history := [_session(1, 70, 3, {"classification": 30}), _session(2, 72, 3, {"classification": 40}), _session(3, 71, 3, {"classification": 35})]
	var r := Adaptive.recommend(history)
	assert_eq([r["rule"], r["focus"]], ["consolidate", "classification"], "hold and focus on classification")
	assert_eq([r["config"]["time_of_day"], r["config"]["visibility"]], ["day", "clear"], "easier identification conditions")
	var used := history.map(func(s): return s["scenario"]["seed"])
	assert_true(not r["config"]["seed"] in used, "fresh seed")
	assert_true(r["reasons"].size() >= 3, "explained")
	assert_eq(Adaptive.recommend(history), r, "same history, same recommendation")
	var degraded := [_session(1, 70, 3, {"degraded": 20}), _session(2, 72, 3, {"degraded": 25}), _session(3, 71, 3, {"degraded": 30})]
	assert_eq(Adaptive.recommend(degraded)["config"]["visibility"], "fog", "degraded focus practises in fog")

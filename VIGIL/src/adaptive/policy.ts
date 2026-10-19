import { cloneConfig, PRESETS, SKILLS, SKILL_LABELS, validateConfig } from '../domain/config';
import type { AdaptiveRecommendation, AdaptiveRule, CompetencyEstimate, Difficulty, ScenarioConfig, SessionRecord, Skill } from '../domain/types';
import { canonicalJson } from '../engine/random';

export const POLICY_VERSION = 'rules-1' as const;
export const POLICY = Object.freeze({ window: 5, minimum: 3, maximumSpread: 20, strongScore: 80, strongSkill: 75, weakScore: 55, weakSkill: 60, seedStride: 7919 });

/** Context excludes only seed/cosmetic preset and objective order. No score normalization. */
export function trainingContext(config: ScenarioConfig): string {
  const context: Partial<ScenarioConfig> = cloneConfig(config);
  delete context.seed; delete context.presetId;
  context.objectives = [...config.objectives].sort();
  return canonicalJson(context);
}
const chronological = (a: SessionRecord, b: SessionRecord) => Date.parse(a.endedAt) - Date.parse(b.endedAt) || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0);
const spread = (values: readonly number[]) => values.length ? Math.max(...values) - Math.min(...values) : null;
const focusType: Record<Skill, ScenarioConfig['exerciseType']> = { detection: 'observation', classification: 'assessment', uncertainty: 'assessment', reporting: 'reporting', decision: 'reporting' };

/** Pure history-derived teaching policy: no engine, evaluator, clock, network or mutation. */
export function recommendNext(records: readonly SessionRecord[], savedIds: ReadonlySet<string>, profileId: string): AdaptiveRecommendation {
  const own = [...new Map(records.filter(r => r.profileId === profileId).map(r => [r.id, r])).values()].sort(chronological);
  const saved = own.filter(r => savedIds.has(r.id));
  const eligible = saved.filter(r => r.status === 'completed' && r.evaluation.comparable);
  const last = eligible.at(-1);
  const baseline = validateConfig(cloneConfig(last?.scenario.config ?? PRESETS[0].config));
  const context = trainingContext(baseline);
  const matching = eligible.filter(r => trainingContext(r.scenario.config) === context);
  // An exact repeated definition is not an independent exposure. Keep its latest actual attempt.
  const distinct = [...new Map(matching.map(r => [r.scenario.seed, r])).values()].sort(chronological);
  const sample = distinct.slice(-POLICY.window);
  const evidenceSessionIds = sample.map(r => r.id);
  const competencies: CompetencyEstimate[] = SKILLS.map(skill => {
    const recentScores = sample.map(r => {
      const metric = r.evaluation.metrics.find(m => m.key === skill);
      if (!metric || !Number.isFinite(metric.score) || metric.score < 0 || metric.score > 100 || metric.denominator <= 0) throw new Error('Adaptive planning requires validated finite eligible component evidence.');
      return metric.score;
    });
    const range = spread(recentScores);
    return { skill, estimate: recentScores.length ? recentScores.reduce((a,b) => a+b,0) / recentScores.length : null, sampleSize: sample.length, recentScores, evidenceSessionIds: [...evidenceSessionIds], spread: range,
      confidence: sample.length >= 5 && range! <= POLICY.maximumSpread ? 'established' : sample.length >= 3 && range! <= POLICY.maximumSpread ? 'developing' : 'provisional' };
  });
  const target = [...competencies].sort((a,b) => (a.estimate ?? 101) - (b.estimate ?? 101) || SKILLS.indexOf(a.skill) - SKILLS.indexOf(b.skill))[0].skill;
  const weakest = competencies.find(c => c.skill === target)!;
  const recent = eligible.slice(-POLICY.minimum);
  const reasons: string[] = [];
  let difficulty = baseline.difficulty;
  let rule: AdaptiveRule = 'consolidate';
  if (!last) {
    rule = 'foundation'; reasons.push('No saved, completed, comparable attempt exists for this profile. Start a Level 1 foundation; no weakness or competency score has been invented.');
  } else {
    reasons.push(`${SKILL_LABELS[target]} is the lowest heuristic component estimate: ${weakest.estimate!.toFixed(1)}% across ${sample.length} distinct-seed completion${sample.length === 1 ? '' : 's'} in the latest matching context. Ties use the declared skill order; this is not a mastery probability.`);
    if (recent.length < POLICY.minimum) {
      rule = 'sparse'; reasons.push(`Hold Level ${difficulty}: ${recent.length} eligible completion${recent.length === 1 ? '' : 's'}; at least 3 recent consistent, distinct scenarios are required for a level change.`);
    } else if (recent.some(r => trainingContext(r.scenario.config) !== context)) {
      rule = 'mixed-context'; reasons.push(`Hold Level ${difficulty}: the latest 3 eligible attempts differ in conditions, objectives, weights or difficulty. Results are not normalized across contexts.`);
    } else if (new Set(recent.map(r => r.scenario.seed)).size < POLICY.minimum) {
      rule = 'repeated'; reasons.push(`Hold Level ${difficulty}: the latest 3 attempts repeat a scenario definition. Rehearsing the same evidence does not justify a level change.`);
    } else if (spread(recent.map(r => r.evaluation.score))! > POLICY.maximumSpread || SKILLS.some(skill => spread(recent.map(r => r.evaluation.metrics.find(m => m.key === skill)!.score))! > POLICY.maximumSpread)) {
      rule = 'inconsistent'; reasons.push(`Hold Level ${difficulty}: recent total or component scores vary by more than 20 points. One noisy result cannot increase difficulty.`);
    } else if (recent.every(r => r.evaluation.score >= POLICY.strongScore && r.evaluation.penaltyPoints === 0 && SKILLS.every(skill => r.evaluation.metrics.find(m => m.key === skill)!.score >= POLICY.strongSkill))) {
      if (difficulty < 5) { difficulty = (difficulty + 1) as Difficulty; rule = 'increase'; reasons.push(`Increase one level only: each of the latest 3 distinct matching-context scores is at least 80, every skill at least 75, spread at most 20 and no explicit penalties.`); }
      else { rule = 'ceiling'; reasons.push('Hold Level 5: repeated strong evidence meets the rule, but the supported maximum is Level 5.'); }
    } else if (recent.every(r => r.evaluation.score < POLICY.weakScore) && weakest.estimate! < POLICY.weakSkill) {
      if (difficulty > 1) { difficulty = (difficulty - 1) as Difficulty; rule = 'decrease'; reasons.push('Reduce one level for supported practice: the latest 3 consistent distinct matching-context scores are below 55 and the lowest estimate is below 60.'); }
      else { rule = 'floor'; reasons.push('Hold Level 1: repeated low results call for focused practice, not a level below the supported foundation.'); }
    } else reasons.push(`Hold Level ${difficulty}: evidence does not meet all strong-increase or repeated-low decrease rules. Consolidate with a fresh seed and focused objective.`);
  }
  const usedSeeds = new Set(saved.map(r => r.scenario.seed));
  let seed = last ? (baseline.seed + POLICY.seedStride) >>> 0 : baseline.seed;
  for (let i = 0; usedSeeds.has(seed); i++) {
    if (i > usedSeeds.size) throw new Error('A fresh seed could not be selected. No repeated configuration was substituted.');
    seed = (seed + POLICY.seedStride) >>> 0;
  }
  const config = validateConfig(last ? { ...cloneConfig(baseline), presetId: 'custom', seed, difficulty, exerciseType: focusType[target], objectives: [target] } : { ...cloneConfig(baseline), seed });
  const excluded = { unsaved: own.length - saved.length, aborted: saved.filter(r => r.status === 'aborted').length, noEvidence: saved.filter(r => r.status === 'completed' && !r.evaluation.comparable).length, differentContext: eligible.length - matching.length, repeated: matching.length - distinct.length };
  reasons.push(`Use fresh seed ${seed}, not used by any saved attempt for this profile. Conditions, count, duration and declared weights are preserved${last ? '; the selected objective is targeted explicitly' : ''}. Review before starting; manual configuration remains available.`);
  reasons.push(`Performance excludes ${excluded.unsaved} unsaved, ${excluded.aborted} aborted and ${excluded.noEvidence} no-evidence reports. Estimates also exclude ${excluded.differentContext} other-context and ${excluded.repeated} repeated-definition samples; at most 5 distinct matching-context completions are used.`);
  return { policyVersion: POLICY_VERSION, method: 'rule-based', target, config, reasons, rule, evidenceSessionIds, decisionSessionIds: recent.map(r => r.id), sampleSize: sample.length, eligibleCount: eligible.length, baselineDifficulty: baseline.difficulty, difficultyChange: difficulty > baseline.difficulty ? 'increase' : difficulty < baseline.difficulty ? 'decrease' : 'hold', excluded, competencies };
}

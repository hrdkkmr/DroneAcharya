import { METRIC_LABELS, SKILLS, validateConfig } from '../domain/config';
import { CATEGORY_LABELS, DECISION_LABELS, METRIC_RULES } from '../domain/training';
import { TrainingError } from '../domain/actions';
import type { EvaluationFinding, EvaluationResult, EvaluationRuleId, MetricResult, ReportDecision, ScenarioDefinition, SimulationEvent, Skill, TrackEvaluation, TrackMetricAudit } from '../domain/types';
import { clearObservations } from '../engine/evidence';
import { validateSessionLog } from '../engine/log';
import { clamp, round1 } from '../engine/random';
import { validateRubric } from './rubric';

type ObservationEvent = Extract<SimulationEvent, { type: 'observation' }>;
type ActionEvent = Extract<SimulationEvent, { type: 'action' }>;
const unique = (ids: (string | undefined)[]) => [...new Set(ids.filter((id): id is string => Boolean(id)))];
function windowCredit(latency: number, grace: number, deadline: number) { return clamp((deadline - latency) / (deadline - grace)); }

/** The single pure evaluator. No playback state, wall clock, UI estimate or random score. */
export function evaluateSession(scenario: ScenarioDefinition, input: readonly SimulationEvent[]): EvaluationResult {
  const config = validateConfig(scenario.config);
  const r = validateRubric(scenario.rubric, config);
  const events = validateSessionLog(scenario, input);
  const finish = events.at(-1)!;
  if (finish.type !== 'finished') throw new TrainingError('UNFINISHED', 'The exercise has not ended.');
  const observations = events.filter((e): e is ObservationEvent => e.type === 'observation');
  const actions = events.filter((e): e is ActionEvent => e.type === 'action');
  const eligible = scenario.tracks.filter(track => observations.some(e => e.data.observation.trackId === track.id));
  const n = eligible.length;
  const credits: Record<Skill, number[]> = { detection: [], classification: [], uncertainty: [], reporting: [], decision: [] };
  const evidence: Record<Skill, string[]> = { detection: [], classification: [], uncertainty: [], reporting: [], decision: [] };
  const findings: EvaluationFinding[] = []; const trackResults: TrackEvaluation[] = [];

  for (const hidden of scenario.tracks) {
    const obs = observations.filter(e => e.data.observation.trackId === hidden.id);
    const acts = actions.filter(e => e.data.action.trackId === hidden.id);
    const tracked = acts.find(e => e.data.action.kind === 'track');
    const assessed = acts.filter(e => e.data.action.kind === 'classify').at(-1);
    const reported = acts.find(e => e.data.action.kind === 'report');
    const classification = assessed?.data.action.kind === 'classify' ? assessed.data.action : null;
    const report = reported?.data.action.kind === 'report' ? reported.data.action : null;
    const atAssessment = obs.filter(e => e.order < (assessed?.order ?? finish.order));
    const atReport = obs.filter(e => e.order < (reported?.order ?? finish.order));
    const clearAtAssessment = classification ? clearObservations(atAssessment.map(e => e.data.observation), r).length : 0;
    const clearAtReport = clearObservations(atReport.map(e => e.data.observation), r).length;
    const strong = clearAtAssessment >= r.minimumClearObservations;
    const perTrack: EvaluationFinding[] = []; const audits: TrackMetricAudit[] = [];
    const latency = tracked && obs[0] ? tracked.time - obs[0].time : null;
    const assessmentRefs = unique([...atAssessment.map(e => e.id), assessed?.id, !assessed ? finish.id : undefined]);
    const reportRefs = unique([...atReport.map(e => e.id), assessed?.id, reported?.id, !reported ? finish.id : undefined]);
    const detectionRefs = unique([obs[0]?.id, tracked?.id, !tracked ? finish.id : undefined]);
    const add = (ruleId: EvaluationRuleId, points: number, reason: string, anchorEventId: string, eventIds: string[], appliedPenalty = false) => {
      // Store precision; formatting is a display concern. Never round before aggregating penalties.
      const finding = { ruleId, trackId: hidden.id, points, appliedPenalty, reason, anchorEventId, eventIds: unique(eventIds) };
      perTrack.push(finding); findings.push(finding);
    };
    let expected: ReportDecision | null = null;
    if (obs.length) {
      const detection = latency === null ? 0 : windowCredit(latency, r.detectionGraceSeconds, r.detectionWindowSeconds);
      const classificationCredit = !classification ? 0 : classification.category === 'unknown' ? (strong ? 0.5 : 0.75) : classification.category === hidden.category ? 1 : 0;
      const uncertainty = !classification ? 0 : classification.category === 'unknown' ? (strong ? 0.75 : 1) : !strong ? 0.25 : classification.category === hidden.category ? 1 : 0;
      const reportLatency = reported ? reported.time - obs[0].time : null;
      const reporting = reportLatency === null ? 0 : 0.6 * windowCredit(reportLatency, r.reportingGraceSeconds, r.reportingWindowSeconds) + 0.4;
      // Without a report this explains the termination-time opportunity, not an invented action.
      expected = !classification || classification.category === 'unknown' || clearAtReport < r.minimumClearObservations ? 'observe' : hidden.category === 'review' ? 'escalate' : 'log';
      const decision = !report ? 0 : report.decision === expected ? 1 : report.decision === 'observe' ? 0.5 : 0;
      const values: Record<Skill, number> = { detection, classification: classificationCredit, uncertainty, reporting, decision };
      const reasons: Record<Skill, string> = {
        detection: latency === null ? 'No tracking mark was recorded after the first delivered observation.' : `Tracking was recorded ${latency}s after the first delivery (${r.detectionGraceSeconds}s grace; ${r.detectionWindowSeconds}s window).`,
        classification: !classification ? 'No category was recorded.' : classification.category === 'unknown' ? `Unknown earned ${classificationCredit * 100}% category credit with ${clearAtAssessment} clear deliveries at assessment.` : `${CATEGORY_LABELS[classification.category]} ${classification.category === hidden.category ? 'matched' : 'did not match'} the synthetic evaluator category ${CATEGORY_LABELS[hidden.category]}.`,
        uncertainty: !classification ? 'No uncertainty-handling assessment was recorded.' : `Assessment used ${clearAtAssessment} clear deliveries; ${strong ? 'sufficient' : 'insufficient'} evidence under the ${r.minimumClearObservations}-delivery rule (signal ≥${r.clearConfidenceThreshold}%, resolved cues).`,
        reporting: !reported ? 'No final report was recorded.' : `A complete report was submitted ${reportLatency}s after the first delivery (${r.reportingGraceSeconds}s grace; ${r.reportingWindowSeconds}s window).`,
        decision: !report ? `No final training disposition; the termination-time evidence-supported branch was ${DECISION_LABELS[expected]}.` : `${DECISION_LABELS[report.decision]} was recorded; the declared tree supported ${DECISION_LABELS[expected]}.`,
      };
      for (const skill of SKILLS) {
        const refs = skill === 'detection' ? detectionRefs : skill === 'classification' || skill === 'uncertainty' ? assessmentRefs : reportRefs;
        const anchorEventId = (skill === 'detection' ? tracked?.id : skill === 'classification' || skill === 'uncertainty' ? assessed?.id : reported?.id) ?? finish.id;
        const available = r.weights[skill] / n;
        credits[skill].push(values[skill]); evidence[skill].push(...refs);
        audits.push({ key: skill, ruleId: METRIC_RULES[skill], credit: values[skill], available, earned: available * values[skill], explanation: reasons[skill], eventIds: refs, anchorEventId });
        if (values[skill] < 1 && available > 0) add(METRIC_RULES[skill], available * (1 - values[skill]), reasons[skill], anchorEventId, refs);
      }
      if (classification && classification.category !== 'unknown' && classification.confidence > r.certaintyThreshold && !strong) add('P1', r.unsupportedCertaintyPenalty, `Specific assessment at ${classification.confidence}% confidence exceeded ${r.certaintyThreshold}% without ${r.minimumClearObservations} clear deliveries.`, assessed!.id, assessmentRefs, true);
      if (report?.decision === 'escalate' && expected !== 'escalate') add('P2', r.unjustifiedEscalationPenalty, 'Training escalation was not supported by the declared evidence-based decision tree.', reported!.id, reportRefs, true);
      if (hidden.significant && !reported) add('P3', r.missedSignificantPenalty, 'A significant synthetic track had delivered evidence but no final report at termination.', finish.id, [obs[0].id, finish.id], true);
    }
    trackResults.push({
      trackId: hidden.id, truthCategory: hidden.category, significant: hidden.significant, firstObservedAt: obs[0]?.time ?? null,
      detectedAt: tracked?.time ?? null, detectionLatencySeconds: latency,
      category: classification?.category ?? null, confidence: classification?.confidence ?? null,
      expectedDecision: expected, actualDecision: report?.decision ?? null,
      clearEvidenceCount: clearAtAssessment, missed: obs.length > 0 && !reported, findings: perTrack, metrics: audits,
    });
  }
  const averages = Object.fromEntries(SKILLS.map(skill => [skill, n ? credits[skill].reduce((a, b) => a + b, 0) / n : 0])) as Record<Skill, number>;
  const achieved = config.objectives.filter(skill => n > 0 && averages[skill] >= 0.7);
  const objectiveCredit = achieved.length / config.objectives.length;
  if (n) for (const skill of config.objectives.filter(s => !achieved.includes(s))) findings.push({ ruleId: 'O1', trackId: null, points: r.weights.objectives / config.objectives.length, appliedPenalty: false, reason: `${METRIC_LABELS[skill]} did not reach the 70% objective threshold.`, eventIds: unique([...evidence[skill], finish.id]), anchorEventId: finish.id });
  if (!n) findings.push({ ruleId: 'E0', trackId: null, points: 100, appliedPenalty: false, reason: 'No delivered evidence was available. Zero denominators earn no credit and this result is not comparable.', eventIds: [finish.id], anchorEventId: finish.id });
  const metrics: MetricResult[] = SKILLS.map(key => {
    const audits = trackResults.flatMap(t => t.metrics).filter(a => a.key === key).sort((a,b) => a.credit - b.credit);
    return {
      key, ruleId: METRIC_RULES[key], anchorEventId: audits[0]?.anchorEventId ?? finish.id,
      label: METRIC_LABELS[key], score: round1(averages[key] * 100), weight: r.weights[key], earned: round1(r.weights[key] * averages[key]), denominator: n,
      unit: key === 'detection' || key === 'reporting' ? 'simulation seconds / eligible tracks' : 'credit / eligible tracks',
      explanation: `${n} track${n === 1 ? '' : 's'} with delivered evidence; missing actions earn zero. ${n === 0 ? 'No eligible evidence.' : ''}`.trim(), evidenceIds: unique([...evidence[key], !n ? finish.id : undefined]),
    };
  });
  metrics.push({ key: 'objectives', ruleId: 'O1', anchorEventId: finish.id, label: METRIC_LABELS.objectives, score: round1(objectiveCredit * 100), weight: r.weights.objectives, earned: round1(objectiveCredit * r.weights.objectives), denominator: config.objectives.length, unit: 'achieved / selected objectives', explanation: `${achieved.length} of ${config.objectives.length} selected skills reached 70%.`, evidenceIds: unique([...config.objectives.flatMap(skill => evidence[skill]), finish.id]) });
  const weighted = SKILLS.reduce((sum, key) => sum + averages[key] * r.weights[key], 0) + objectiveCredit * r.weights.objectives;
  const penalties = findings.filter(f => f.appliedPenalty).reduce((sum, f) => sum + f.points, 0);
  return {
    rubricVersion: 'rubric-1', score: round1(clamp(weighted - penalties, 0, 100)), weightedScore: round1(weighted), penaltyPoints: round1(penalties),
    metrics, tracks: trackResults, findings,
    strengths: metrics.filter(m => m.denominator > 0 && m.score >= 80).map(m => `${m.label}: ${m.score}% of available component credit.`),
    improvements: metrics.filter(m => m.score < 70).map(m => `${m.label}: review the recorded evidence and ${m.key === 'objectives' ? 'selected objectives' : 'decision sequence'}.`),
    objectivesCompleted: achieved, comparable: finish.data.outcome === 'completed' && n > 0,
  };
}

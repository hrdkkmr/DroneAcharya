import type { Category, EvaluationRuleId, MetricKey, ReportDecision, SimulationEvent } from './types';

/** Public teaching cues and thresholds, not scenario answers or private evaluation weights. */
export const TRAINING_RULES = {
  minimumClearObservations: 2, clearConfidenceThreshold: 60, certaintyThreshold: 70,
  detectionGraceSeconds: 5, detectionWindowSeconds: 30,
  reportingGraceSeconds: 15, reportingWindowSeconds: 60,
  observationIntervalSeconds: 4, requestCooldownSeconds: 8, staleAfterSeconds: 10,
} as const;
export const CATEGORY_LABELS: Record<Category, string> = {
  routine: 'Routine activity', review: 'Requires review', background: 'Background return', unknown: 'Unknown / insufficient evidence',
};
export const DECISION_LABELS: Record<ReportDecision, string> = { log: 'Routine log', observe: 'Continue observation', escalate: 'Training escalation' };
export function formatTime(seconds: number): string {
  const safe = Math.max(0, Math.floor(seconds));
  return `${Math.floor(safe / 60).toString().padStart(2, '0')}:${(safe % 60).toString().padStart(2, '0')}`;
}
export function describeEvent(event: SimulationEvent): string {
  switch (event.type) {
    case 'started': return 'Exercise started. Synthetic observation feed enabled.';
    case 'observation': { const o = event.data.observation; return `${o.trackId} ${o.source} observation delivered · ${o.confidence}% signal confidence · ${o.deliveredAt - o.capturedAt}s delay`; }
    case 'sensor_change': return event.data.reason;
    case 'paused': return 'Exercise paused. Clock and observation capture stopped.';
    case 'resumed': return 'Exercise resumed. Simulation clock continued.';
    case 'finished': return event.data.outcome === 'completed' ? 'Exercise duration reached. Evaluation unlocked.' : 'Exercise ended early. Partial result only.';
    case 'action': {
      const a = event.data.action;
      switch (a.kind) {
        case 'select': return `${a.trackId} selected`;
        case 'track': return `${a.trackId} marked as tracked`;
        case 'request_observation': return `${a.trackId} additional observation requested`;
        case 'classify': return `${a.trackId} assessed: ${CATEGORY_LABELS[a.category]} · ${a.confidence}% confidence`;
        case 'report': return `${a.trackId} report: ${DECISION_LABELS[a.decision]} · ${a.summary}`;
      }
    }
  }
}

export const METRIC_RULES: Record<MetricKey, EvaluationRuleId> = { detection: 'D1', classification: 'C1', uncertainty: 'U1', reporting: 'R1', decision: 'Q1', objectives: 'O1' };
export const RULE_TITLES: Record<EvaluationRuleId, string> = { D1: 'Detection timeliness', C1: 'Classification', U1: 'Uncertainty handling', R1: 'Reporting', Q1: 'Training disposition', O1: 'Selected objectives', P1: 'Unsupported certainty', P2: 'Unjustified training escalation', P3: 'Missed significant observation', E0: 'No delivered evidence' };

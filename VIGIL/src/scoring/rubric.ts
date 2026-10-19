import { z } from 'zod';
import type { EvaluationRubric, MetricKey, ScenarioConfig } from '../domain/types';
import { evaluationWeightsSchema } from '../domain/config';
import { TrainingError } from '../domain/actions';
import { TRAINING_RULES } from '../domain/training';

const seconds = z.number().finite().min(0).max(3600);
const percent = z.number().finite().min(0).max(100);
const rubricSchema = z.object({
  version: z.literal('rubric-1'), weights: evaluationWeightsSchema,
  detectionGraceSeconds: seconds, detectionWindowSeconds: seconds,
  reportingGraceSeconds: seconds, reportingWindowSeconds: seconds,
  minimumClearObservations: z.number().finite().int().min(1).max(1000),
  clearConfidenceThreshold: percent, certaintyThreshold: percent,
  unjustifiedEscalationPenalty: percent, unsupportedCertaintyPenalty: percent, missedSignificantPenalty: percent,
}).strict().refine(r => r.detectionWindowSeconds > r.detectionGraceSeconds && r.reportingWindowSeconds > r.reportingGraceSeconds, 'Time windows must exceed their grace period.');

/** Reject incomplete/nonfinite rubric objects rather than producing plausible NaN scores. */
export function validateRubric(raw: unknown, config: ScenarioConfig): EvaluationRubric {
  const result = rubricSchema.safeParse(raw);
  if (!result.success) throw new TrainingError('INVALID_RUBRIC', `Evaluation thresholds and weights must be complete, finite and bounded: ${result.error.issues.map(i => `${i.path.join('.')}: ${i.message}`).join('; ')}`);
  if (!Object.entries(config.weights).every(([key, value]) => result.data.weights[key as MetricKey] === value)) throw new TrainingError('RUBRIC_WEIGHTS_MISMATCH', 'The stored rubric weights must match the declared scenario configuration.');
  return result.data;
}

export function createRubric(config: ScenarioConfig): EvaluationRubric {
  return {
    version: 'rubric-1', weights: { ...config.weights },
    detectionGraceSeconds: TRAINING_RULES.detectionGraceSeconds, detectionWindowSeconds: TRAINING_RULES.detectionWindowSeconds,
    reportingGraceSeconds: TRAINING_RULES.reportingGraceSeconds, reportingWindowSeconds: TRAINING_RULES.reportingWindowSeconds,
    minimumClearObservations: TRAINING_RULES.minimumClearObservations, clearConfidenceThreshold: TRAINING_RULES.clearConfidenceThreshold,
    certaintyThreshold: TRAINING_RULES.certaintyThreshold,
    unjustifiedEscalationPenalty: 8, unsupportedCertaintyPenalty: 4, missedSignificantPenalty: 5,
  };
}

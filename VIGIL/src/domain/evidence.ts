import type { Observation, SimulationEvent } from './types';
import { TRAINING_RULES } from './training';

/** Public evidence facts only; never infer missing/hidden tracks or detection accuracy. */
export const observationAge = (o: Observation, now: number) => Math.max(0, now - o.capturedAt);
export const isStaleObservation = (o: Observation, now: number) => observationAge(o, now) > TRAINING_RULES.staleAfterSeconds;
export const isClearObservation = (o: Observation, threshold: number = TRAINING_RULES.clearConfidenceThreshold) => o.confidence >= threshold && o.motion !== 'unresolved' && o.signature !== 'unresolved';
export function deliveryFacts(events: readonly SimulationEvent[]) {
  const observations = events.filter(e => e.type === 'observation').map(e => e.data.observation);
  return {
    observations,
    count: observations.length,
    requested: observations.filter(o => o.source === 'requested').length,
    unresolved: observations.filter(o => !isClearObservation(o)).length,
    meanDelay: observations.length ? observations.reduce((sum, o) => sum + o.deliveredAt - o.capturedAt, 0) / observations.length : null,
  };
}

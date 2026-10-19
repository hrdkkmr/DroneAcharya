import { isClearObservation } from '../domain/evidence';
import type { SimulationEvent, TrackEvidence, Observation, EvaluationRubric } from '../domain/types';

/** Pure event projection, shared by live state and evaluator. No hidden truth is required. */
export function applyEvidenceEvent(tracks: Map<string, TrackEvidence>, event: SimulationEvent): void {
  if (event.type === 'observation') {
    const o = event.data.observation;
    const existing = tracks.get(o.trackId);
    if (existing) {
      // Delivery can be out of capture order. Keep every actual arrival, never rewind the map.
      if (o.capturedAt > existing.latest.capturedAt || (o.capturedAt === existing.latest.capturedAt && o.deliveredAt > existing.latest.deliveredAt)) existing.latest = o;
      existing.observations.push(o);
    }
    else tracks.set(o.trackId, { id: o.trackId, latest: o, observations: [o], trackedAt: null, classification: null, report: null, lastRequestedAt: null });
  }
  if (event.type !== 'action') return;
  const a = event.data.action; const track = tracks.get(a.trackId);
  if (!track) return;
  switch (a.kind) {
    case 'select': break;
    case 'track': track.trackedAt = event.time; break;
    case 'request_observation': track.lastRequestedAt = event.time; break;
    case 'classify': track.classification = { category: a.category, confidence: a.confidence, eventId: event.id }; break;
    case 'report': track.report = { decision: a.decision, summary: a.summary, eventId: event.id }; break;
  }
}
export function projectEvidence(events: readonly SimulationEvent[]): Map<string, TrackEvidence> {
  const tracks = new Map<string, TrackEvidence>();
  for (const event of events) applyEvidenceEvent(tracks, event);
  return tracks;
}
export function clearObservations(observations: readonly Observation[], rubric: EvaluationRubric): Observation[] {
  return observations.filter(o => isClearObservation(o, rubric.clearConfidenceThreshold));
}

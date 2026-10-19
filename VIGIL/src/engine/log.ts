import { TrainingError, validateAction } from '../domain/actions';
import { simulationEventSchema } from '../domain/events';
import { MAX_DELIVERY_DELAY_SECONDS } from '../domain/conditions';
import { TRAINING_RULES } from '../domain/training';
import type { ScenarioDefinition, SessionStatus, SimulationEvent, TrackEvidence } from '../domain/types';
import { applyEvidenceEvent } from './evidence';

/** Reject impossible scoring inputs instead of turning malformed logs into plausible scores. */
export function validateSessionLog(scenario: ScenarioDefinition, raw: readonly SimulationEvent[]): SimulationEvent[] {
  if (!Array.isArray(raw) || raw.length < 2) throw new TrainingError('INVALID_LOG', 'A review requires a start and a termination event.');
  const events = raw.map(e => simulationEventSchema.parse(e));
  const tracks = new Map<string, TrackEvidence>();
  const ids = new Set<string>(); const observationIds = new Set<string>(); const captureKeys = new Set<string>();
  let status: SessionStatus = 'briefing'; let lastTime = 0; let pausedAt: number | null = null;
  const sessionId = events[0].sessionId;
  events.forEach((event, index) => {
    if (event.order !== index + 1 || event.sessionId !== sessionId || ids.has(event.id) || event.time < lastTime || event.time > scenario.config.durationSeconds) throw new TrainingError('INVALID_ORDER', 'Event IDs, session, order and simulation timestamps must form one ordered exercise.');
    ids.add(event.id); lastTime = event.time;
    if (status === 'completed' || status === 'aborted') throw new TrainingError('AFTER_FINISH', 'No events are allowed after termination.');
    if (status === 'paused' && event.time !== pausedAt) throw new TrainingError('PAUSED_CLOCK', 'Simulation time cannot advance while paused.');
    switch (event.type) {
      case 'started':
        if (index !== 0 || event.time !== 0 || event.data.scenarioId !== scenario.id) throw new TrainingError('INVALID_START', 'The first event must start the matching scenario at time zero.');
        status = 'running'; break;
      case 'observation': {
        const o = event.data.observation; const hidden = scenario.tracks.find(t => t.id === o.trackId);
        if (status !== 'running' || !hidden || observationIds.has(o.id) || captureKeys.has(`${o.trackId}:${o.capturedAt}`) || o.deliveredAt - o.capturedAt > MAX_DELIVERY_DELAY_SECONDS || o.deliveredAt !== event.time || o.capturedAt > o.deliveredAt || o.capturedAt < hidden.spawnAt || o.capturedAt > hidden.endAt) throw new TrainingError('INVALID_OBSERVATION', 'Observation must be unique, delivered while running and captured within the synthetic track lifetime.');
        const requested = events.slice(0, index).some(e => e.type === 'action' && e.data.action.kind === 'request_observation' && e.data.action.trackId === o.trackId && e.time + 2 === o.capturedAt);
        if ((o.source === 'requested' && !requested) || (o.source === 'scheduled' && (requested || (o.capturedAt - hidden.spawnAt) % TRAINING_RULES.observationIntervalSeconds !== 0))) throw new TrainingError('INVALID_PROVENANCE', 'Delivered source must match a real earlier request or the regular capture schedule.');
        observationIds.add(o.id); captureKeys.add(`${o.trackId}:${o.capturedAt}`); break;
      }
      case 'action': validateAction(event.data.action, status, tracks.get(event.data.action.trackId), event.time); break;
      case 'paused':
        if (status !== 'running') throw new TrainingError('INVALID_PAUSE', 'Only a running exercise can pause.');
        status = 'paused'; pausedAt = event.time; break;
      case 'resumed':
        if (status !== 'paused') throw new TrainingError('INVALID_RESUME', 'Only a paused exercise can resume.');
        status = 'running'; pausedAt = null; break;
      case 'sensor_change':
        if (status !== 'running') throw new TrainingError('INVALID_SENSOR_EVENT', 'Sensor changes require a running exercise.'); break;
      case 'finished':
        if (status === 'briefing' || index !== events.length - 1 || (event.data.outcome === 'completed' && event.time !== scenario.config.durationSeconds)) throw new TrainingError('INVALID_FINISH', 'Completion must be the final event at the configured duration. Early exits are aborted.');
        status = event.data.outcome; break;
    }
    applyEvidenceEvent(tracks, event);
  });
  if (events.at(-1)?.type !== 'finished') throw new TrainingError('UNFINISHED', 'Evaluation is available only after exercise termination.');
  return events;
}

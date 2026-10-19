import { SCHEMA_VERSION } from '../domain/types';
import type { ReplayCursor, ReplayFrame, ReplayTimeline, SessionRecord, SessionStatus, SimulationEvent } from '../domain/types';
import { publicScenario } from '../domain/publicScenario';
import { TrainingError } from '../domain/actions';
import { projectEvidence } from '../engine/evidence';
import { validateSessionLog } from '../engine/log';

function freeze<T>(value: T): T {
  if (value && typeof value === 'object' && !Object.isFrozen(value)) {
    Object.freeze(value); for (const child of Object.values(value)) freeze(child);
  }
  return value;
}

/** Validate and detach one real record. No engine/generator/sensor/evaluator is invoked. */
export function createReplayTimeline(record: SessionRecord): ReplayTimeline {
  if (record.schemaVersion !== SCHEMA_VERSION || record.scenario.schemaVersion !== SCHEMA_VERSION || record.scenario.generatorVersion !== 'generator-2' || record.scenario.sensorVersion !== 'sensor-2') throw new TrainingError('REPLAY_VERSION', 'This replay requires the current recorded schema and declared model versions; legacy import/migration is not connected.');
  validateSessionLog(record.scenario, record.events);
  const finish = record.events.at(-1)!;
  if (finish.type !== 'finished' || record.id !== finish.sessionId || record.status !== finish.data.outcome || record.elapsedSeconds !== finish.time) throw new TrainingError('REPLAY_RECORD_MISMATCH', 'Recorded identity, outcome and elapsed duration must match the actual final event.');
  const ids = new Map(record.events.map(e => [e.id, e]));
  const check = (anchor: string, refs: readonly string[], actionTimeOnly: boolean) => {
    const event = ids.get(anchor);
    if (!event || !refs.length || !refs.includes(anchor) || refs.some(id => !ids.has(id) || (actionTimeOnly && ids.get(id)!.order > event.order))) throw new TrainingError('REPLAY_REFERENCE', 'An audit anchor must reference actual events available at that recorded decision.');
  };
  for (const metric of record.evaluation.metrics) check(metric.anchorEventId, metric.evidenceIds, false);
  for (const finding of record.evaluation.findings) check(finding.anchorEventId, finding.eventIds, true);
  for (const track of record.evaluation.tracks) for (const metric of track.metrics) check(metric.anchorEventId, metric.eventIds, true);
  return freeze({
    version: 'replay-1', schemaVersion: SCHEMA_VERSION,
    sessionId: record.id, profileId: record.profileId, scenario: publicScenario(record.scenario),
    durationSeconds: record.elapsedSeconds, events: structuredClone(record.events),
  });
}

export const beginReplay = (): ReplayCursor => ({ time: 0, eventCount: 0 });
export const endReplay = (timeline: ReplayTimeline): ReplayCursor => ({ time: timeline.durationSeconds, eventCount: timeline.events.length });
export const isReplayEnd = (timeline: ReplayTimeline, cursor: ReplayCursor): boolean => cursor.time === timeline.durationSeconds && cursor.eventCount === timeline.events.length;

function validateCursor(timeline: ReplayTimeline, cursor: ReplayCursor) {
  const { time, eventCount } = cursor;
  if (!Number.isInteger(time) || time < 0 || time > timeline.durationSeconds || !Number.isInteger(eventCount) || eventCount < 0 || eventCount > timeline.events.length
    || (eventCount > 0 && timeline.events[eventCount - 1].time > time) || (eventCount < timeline.events.length && timeline.events[eventCount].time < time)) throw new TrainingError('REPLAY_CURSOR', 'Replay position must be a valid recorded prefix at a bounded simulation second.');
}

/** Scrubbing includes all events through this second; exact jumps preserve same-second order. */
export function seekReplayTime(timeline: ReplayTimeline, seconds: number): ReplayCursor {
  if (!Number.isFinite(seconds)) throw new TrainingError('REPLAY_TIME', 'Choose a finite replay time.');
  const time = Math.min(timeline.durationSeconds, Math.max(0, Math.floor(seconds)));
  let low = 0; let high = timeline.events.length;
  while (low < high) { const mid = Math.floor((low + high) / 2); if (timeline.events[mid].time <= time) low = mid + 1; else high = mid; }
  return { time, eventCount: low };
}
export function seekReplayEvent(timeline: ReplayTimeline, eventId: string): ReplayCursor {
  const index = timeline.events.findIndex(e => e.id === eventId);
  if (index < 0) throw new TrainingError('REPLAY_EVENT', 'That evidence reference is not in this recorded exercise.');
  return { time: timeline.events[index].time, eventCount: index + 1 };
}
export function stepReplayEvent(timeline: ReplayTimeline, cursor: ReplayCursor, direction: -1 | 1): ReplayCursor {
  validateCursor(timeline, cursor);
  if (direction === 1) return cursor.eventCount < timeline.events.length ? seekReplayEvent(timeline, timeline.events[cursor.eventCount].id) : endReplay(timeline);
  if (!cursor.eventCount) return beginReplay();
  const inGap = cursor.time > timeline.events[cursor.eventCount - 1].time;
  const index = cursor.eventCount - (inGap ? 1 : 2);
  return index >= 0 ? seekReplayEvent(timeline, timeline.events[index].id) : beginReplay();
}
export function advanceReplay(timeline: ReplayTimeline, cursor: ReplayCursor, seconds: number): ReplayCursor {
  validateCursor(timeline, cursor);
  if (!Number.isInteger(seconds) || seconds < 0) throw new TrainingError('REPLAY_ADVANCE', 'Advance by nonnegative simulation seconds.');
  return seconds === 0 ? { ...cursor } : seekReplayTime(timeline, cursor.time + seconds);
}

/** Exact public prefix projection. Frame mutation cannot modify the record or later frames. */
export function replayFrame(timeline: ReplayTimeline, cursor: ReplayCursor): ReplayFrame {
  validateCursor(timeline, cursor);
  const events = structuredClone(timeline.events.slice(0, cursor.eventCount));
  let status: SessionStatus = 'briefing'; let sensorHealth: 'nominal' | 'degraded' = 'nominal'; let recordedSelectionId: string | null = null;
  for (const event of events) {
    if (event.type === 'started' || event.type === 'resumed') status = 'running';
    else if (event.type === 'paused') status = 'paused';
    else if (event.type === 'finished') status = event.data.outcome;
    else if (event.type === 'sensor_change') sensorHealth = event.data.health;
    else if (event.type === 'action' && event.data.action.kind === 'select') recordedSelectionId = event.data.action.trackId;
  }
  return {
    cursor: { ...cursor }, recordedSelectionId, lastEvent: events.at(-1) ?? null,
    view: {
      schemaVersion: timeline.schemaVersion, sessionId: timeline.sessionId, profileId: timeline.profileId,
      scenario: structuredClone(timeline.scenario), status, elapsedSeconds: cursor.time, speed: 1,
      sensorHealth, tracks: [...projectEvidence(events).values()], events,
    },
  };
}

export const eventTrackId = (event: SimulationEvent | null): string | null => event?.type === 'observation' ? event.data.observation.trackId : event?.type === 'action' ? event.data.action.trackId : null;

import { SCHEMA_VERSION } from '../domain/types';
import { TrainingError, validateAction } from '../domain/actions';
import { TRAINING_RULES } from '../domain/training';
import type { ActiveSessionView, EventData, EventType, Observation, ScenarioDefinition, SessionRecord, SessionStatus, SimulationEvent, TrackEvidence } from '../domain/types';
import { evaluateSession } from '../scoring/evaluate';
import { applyEvidenceEvent } from './evidence';
import { generateScenario, publicScenario } from './scenario';
import { captureObservation } from './sensor';

export interface SessionIdentity { sessionId: string; profileId: string; startedAt: string }
/** Single authoritative state. Nothing in presentation advances tracks or computes a score. */
export class SimulationEngine {
  private readonly scenario: ScenarioDefinition;
  private readonly identity: SessionIdentity;
  private status: SessionStatus = 'briefing';
  private elapsed = 0;
  private speed: 1 | 2 | 4 = 1;
  private health: 'nominal' | 'degraded' = 'nominal';
  private readonly events: SimulationEvent[] = [];
  private readonly visible = new Map<string, TrackEvidence>();
  private pending: Observation[] = [];
  private requests: { trackId: string; at: number }[] = [];
  private readonly attempted = new Set<string>();
  private result: SessionRecord | null = null;
  constructor(config: unknown, identity: SessionIdentity, private readonly nowIso: () => string = () => new Date().toISOString()) {
    if (!identity.sessionId || identity.sessionId.length > 100 || !identity.profileId || identity.profileId.length > 100 || !Number.isFinite(Date.parse(identity.startedAt))) throw new TrainingError('BAD_IDENTITY', 'A valid session identifier, anonymous profile and ISO start date are required.');
    this.identity = { ...identity }; this.scenario = generateScenario(config);
  }
  private append<K extends EventType>(type: K, data: EventData[K]) {
    const order = this.events.length + 1;
    const event = { id: `${this.identity.sessionId}:e${String(order).padStart(5, '0')}`, sessionId: this.identity.sessionId, order, time: this.elapsed, type, data } as SimulationEvent;
    this.events.push(event); applyEvidenceEvent(this.visible, event);
  }
  clockState(): Pick<ActiveSessionView, 'status' | 'elapsedSeconds' | 'speed'> { return { status: this.status, elapsedSeconds: this.elapsed, speed: this.speed }; }
  getView(): ActiveSessionView {
    return structuredClone({ schemaVersion: SCHEMA_VERSION, sessionId: this.identity.sessionId, profileId: this.identity.profileId, scenario: publicScenario(this.scenario), status: this.status, elapsedSeconds: this.elapsed, speed: this.speed, sensorHealth: this.health, tracks: [...this.visible.values()], events: this.events });
  }
  start() {
    if (this.status !== 'briefing') throw new TrainingError('INVALID_START', 'This exercise has already started. Reset to begin a fresh attempt.');
    this.status = 'running'; this.append('started', { scenarioId: this.scenario.id });
  }
  pause() {
    if (this.status !== 'running') throw new TrainingError('INVALID_PAUSE', 'Only a running exercise can be paused.');
    this.status = 'paused'; this.append('paused', { source: 'trainee' });
  }
  resume() {
    if (this.status !== 'paused') throw new TrainingError('INVALID_RESUME', 'Only a paused exercise can be resumed.');
    this.status = 'running'; this.append('resumed', { source: 'trainee' });
  }
  setSpeed(value: number) {
    if (![1, 2, 4].includes(value)) throw new TrainingError('BAD_SPEED', 'Use 1×, 2× or 4× simulation speed.');
    if (this.status === 'completed' || this.status === 'aborted') throw new TrainingError('FINISHED', 'This exercise has ended.');
    this.speed = value as 1 | 2 | 4;
  }
  action(raw: unknown) {
    const id = raw && typeof raw === 'object' && 'trackId' in raw ? String(raw.trackId) : '';
    const action = validateAction(raw, this.status, this.visible.get(id), this.elapsed);
    this.append('action', { action });
    if (action.kind === 'request_observation') this.requests.push({ trackId: action.trackId, at: this.elapsed + 2 });
  }
  advance(seconds: number) {
    if (!Number.isInteger(seconds) || seconds < 0 || seconds > 3600) throw new TrainingError('BAD_STEP', 'Advance by a nonnegative integer number of seconds, at most 3600.');
    if (this.status !== 'running') return;
    for (let i = 0; i < seconds && this.status === 'running'; i++) {
      this.elapsed++;
      const disruption = this.scenario.degradation;
      if (disruption && this.elapsed === disruption.startsAt) { this.health = 'degraded'; this.append('sensor_change', { health: 'degraded', reason: 'Synthetic link disruption: intermittent returns, lower confidence and extra delivery delay.' }); }
      if (disruption && this.elapsed === disruption.endsAt) { this.health = 'nominal'; this.append('sensor_change', { health: 'nominal', reason: 'Synthetic link recovered. Nominal configured observation quality restored.' }); }
      for (const track of this.scenario.tracks) {
        if (this.elapsed < track.spawnAt || this.elapsed > track.endAt) continue;
        const requested = this.requests.some(request => request.trackId === track.id && request.at === this.elapsed);
        const scheduled = (this.elapsed - track.spawnAt) % TRAINING_RULES.observationIntervalSeconds === 0;
        const key = `${track.id}:${this.elapsed}`;
        if ((!requested && !scheduled) || this.attempted.has(key)) continue;
        this.attempted.add(key);
        const observation = captureObservation(this.scenario, track, this.elapsed, this.health, requested);
        if (observation) this.pending.push(observation);
      }
      this.requests = this.requests.filter(r => r.at > this.elapsed);
      const due = this.pending.filter(o => o.deliveredAt <= this.elapsed).sort((a, b) => a.deliveredAt - b.deliveredAt || a.trackId.localeCompare(b.trackId) || a.capturedAt - b.capturedAt);
      for (const observation of due) this.append('observation', { observation });
      this.pending = this.pending.filter(o => o.deliveredAt > this.elapsed);
      if (this.elapsed === this.scenario.config.durationSeconds) this.terminate('completed');
    }
  }
  finish() {
    if (this.status !== 'running' && this.status !== 'paused') throw new TrainingError('INVALID_FINISH', 'Start an exercise before ending it. A terminated exercise cannot be ended again.');
    this.terminate('aborted');
  }
  private terminate(outcome: 'completed' | 'aborted') {
    this.append('finished', { outcome }); this.status = outcome;
    const evaluation = evaluateSession(this.scenario, this.events);
    this.result = { schemaVersion: SCHEMA_VERSION, id: this.identity.sessionId, profileId: this.identity.profileId, startedAt: this.identity.startedAt, endedAt: this.nowIso(), status: outcome, elapsedSeconds: this.elapsed, scenario: structuredClone(this.scenario), events: structuredClone(this.events), evaluation };
  }
  completedRecord(): SessionRecord {
    if (!this.result) throw new TrainingError('REVIEW_LOCKED', 'Evaluator data is available only after exercise termination.');
    return structuredClone(this.result);
  }
}

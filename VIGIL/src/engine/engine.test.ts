import { describe, expect, it } from 'vitest';
import { SimulationEngine } from './SimulationEngine';
import { testConfig, testEngine } from '../test/fixtures';
import { FixedStepClock } from './clock';
import { generateScenario } from './scenario';
import { captureObservation } from './sensor';
import { mulberry32 } from './random';

describe('seeded scenario and synthetic observations', () => {
  it('reproduces byte-identical validated definitions, independent of config key ordering', () => {
    const config = testConfig(); const reversed = Object.fromEntries(Object.entries(config).reverse());
    expect(JSON.stringify(generateScenario(config))).toBe(JSON.stringify(generateScenario(reversed)));
    expect(generateScenario(config)).toEqual(generateScenario(config));
  });
  it('varies categories, positions, paths and timing across distinct seeds', () => {
    const scenarios = Array.from({ length: 20 }, (_, seed) => generateScenario(testConfig({ seed, trackCount: 4 })));
    expect(new Set(scenarios.map(s => s.id)).size).toBe(20);
    expect(new Set(scenarios.map(s => JSON.stringify(s.tracks))).size).toBe(20);
    expect(new Set(scenarios.map(s => s.tracks[0].category)).size).toBe(3);
    expect(new Set(scenarios.map(s => s.degradation?.startsAt)).size).toBeGreaterThan(1);
    for (const s of scenarios) for (const t of s.tracks) { expect(t.spawnAt).toBeGreaterThan(0); expect(t.spawnAt).toBeLessThan(s.config.durationSeconds); expect(t.endAt).toBeLessThanOrEqual(s.config.durationSeconds); }
  });
  it('rejects invalid generation configuration instead of silently fixing it', () => {
    expect(() => generateScenario(testConfig({ trackCount: 0 }))).toThrow();
    expect(() => generateScenario({ ...testConfig(), seed: NaN })).toThrow();
  });
  it('uses documented reproducible bounded Mulberry32 outputs', () => {
    const a = mulberry32(123); const b = mulberry32(123);
    const values = Array.from({ length: 100 }, () => a());
    expect(values).toEqual(Array.from({ length: 100 }, () => b()));
    expect(values.every(v => v >= 0 && v < 1)).toBe(true);
    expect(values[0]).toBeCloseTo(0.7872516233474016, 12);
  });
  it('uses per-capture seeds, bounded coordinates and separate capture/delivery times', () => {
    const s = generateScenario(testConfig({ delaySeconds: 3, noise: 0.1 }));
    const o = captureObservation(s, s.tracks[0], 1, 'nominal');
    expect(o).not.toBeNull(); expect(o).toEqual(captureObservation(s, s.tracks[0], 1, 'nominal'));
    expect(o!.deliveredAt - o!.capturedAt).toBe(3);
    for (let time = 1; time < 300; time++) { const sample = captureObservation(s, s.tracks[0], time, 'nominal'); if (sample) { expect(sample.x).toBeGreaterThanOrEqual(0); expect(sample.x).toBeLessThanOrEqual(100); expect(sample.y).toBeGreaterThanOrEqual(0); expect(sample.y).toBeLessThanOrEqual(100); } }
  });
  it('degradation changes actual return frequency, confidence and delivery delay', () => {
    const s = generateScenario(testConfig({ noise: 0.08 }));
    const nominal = []; const degraded = [];
    for (let t = 1; t <= 100; t++) { const a = captureObservation(s, s.tracks[0], t, 'nominal'); const b = captureObservation(s, s.tracks[0], t, 'degraded'); if (a) nominal.push(a); if (b) degraded.push(b); }
    expect(degraded.length).toBeLessThan(nominal.length);
    expect(degraded.length).toBeGreaterThan(0);
    expect(degraded.reduce((s,o) => s + o.confidence,0) / degraded.length).toBeLessThan(nominal.reduce((s,o) => s + o.confidence,0) / nominal.length);
    expect(degraded.every(o => o.deliveredAt - o.capturedAt === 2)).toBe(true);
  });
});

describe('authoritative exercise state machine', () => {
  it('starts in briefing with no observations or answer key, and locks review', () => {
    const engine = testEngine(); const view = engine.getView();
    expect(view.status).toBe('briefing'); expect(view.tracks).toEqual([]); expect(view.events).toEqual([]);
    expect(() => engine.completedRecord()).toThrow('only after');
    const serialized = JSON.stringify(view);
    for (const key of ['rubric', 'weights', 'origin', 'velocity', 'significant', 'truthCategory', 'degradation']) expect(serialized).not.toContain(`"${key}"`);
    expect(view.scenario).not.toHaveProperty('tracks');
  });
  it('delivers actual moving observations only when their delay expires', () => {
    const e = testEngine({ delaySeconds: 2 }); e.start(); e.advance(2); expect(e.getView().tracks).toHaveLength(0);
    e.advance(1); expect(e.getView().tracks).toHaveLength(1);
    const first = e.getView().tracks[0].latest; expect(first.capturedAt).toBe(1); expect(first.deliveredAt).toBe(3);
    e.advance(4); expect(e.getView().tracks[0].latest.x).not.toBe(first.x);
  });
  it('preserves elapsed simulation time and event ordering across pause and resume', () => {
    const e = testEngine(); e.start(); e.advance(5); e.pause(); const paused = e.getView(); e.advance(20);
    expect(e.getView()).toEqual(paused); expect(() => e.action({ kind: 'track', trackId: 'T01' })).toThrow('Resume');
    e.resume(); expect(e.getView().elapsedSeconds).toBe(5); e.advance(2); expect(e.getView().elapsedSeconds).toBe(7);
    expect(e.getView().events.filter(e => e.type === 'paused' || e.type === 'resumed').map(e => e.time)).toEqual([5,5]);
    expect(e.getView().events.map(e => e.order)).toEqual(e.getView().events.map((_,i) => i+1));
  });
  it('prevents invalid state transitions without changing the log', () => {
    const e = testEngine(); expect(() => e.pause()).toThrow(); expect(() => e.resume()).toThrow(); expect(() => e.finish()).toThrow();
    expect(e.getView().events).toHaveLength(0); e.start(); expect(() => e.start()).toThrow();
    e.pause(); expect(() => e.pause()).toThrow(); e.resume(); expect(() => e.resume()).toThrow();
  });
  it('validates the decision workflow and preserves rejected-action atomicity', () => {
    const e = testEngine(); e.start();
    expect(() => e.action({ kind: 'track', trackId: 'T01' })).toThrow('no delivered');
    e.advance(1); const before = e.getView().events.length;
    expect(() => e.action({ kind: 'classify', trackId: 'T01', category: 'routine', confidence: 50 })).toThrow('Mark');
    expect(e.getView().events).toHaveLength(before);
    e.action({ kind: 'track', trackId: 'T01' }); expect(() => e.action({ kind: 'track', trackId: 'T01' })).toThrow('already');
    expect(() => e.action({ kind: 'report', trackId: 'T01', decision: 'observe', summary: 'Sufficiently long report' })).toThrow('category');
    expect(() => e.action({ kind: 'classify', trackId: 'T01', category: 'routine', confidence: Infinity })).toThrow();
    expect(() => e.action({ kind: 'classify', trackId: 'T01', category: 'secret', confidence: 50 })).toThrow();
    e.action({ kind: 'classify', trackId: 'T01', category: 'unknown', confidence: 40 });
    expect(() => e.action({ kind: 'report', trackId: 'T01', decision: 'observe', summary: 'short' })).toThrow();
    e.action({ kind: 'report', trackId: 'T01', decision: 'observe', summary: 'Only one clear observation; continue collecting evidence.' });
    expect(() => e.action({ kind: 'classify', trackId: 'T01', category: 'routine', confidence: 80 })).toThrow('final');
    expect(() => e.action({ kind: 'report', trackId: 'T01', decision: 'log', summary: 'A duplicate final report.' })).toThrow('final');
    expect(e.getView().tracks[0].report?.decision).toBe('observe');
  });
  it('schedules an additional observation attempt and enforces its cooldown', () => {
    const e = testEngine(); e.start(); e.advance(1); e.action({ kind: 'request_observation', trackId: 'T01' });
    expect(() => e.action({ kind: 'request_observation', trackId: 'T01' })).toThrow('Wait 8');
    e.advance(2); expect(e.getView().tracks[0].observations.map(o => o.capturedAt)).toContain(3);
    e.advance(6); expect(() => e.action({ kind: 'request_observation', trackId: 'T01' })).not.toThrow();
  });
  it('completes exactly at the duration, unlocks evaluator data and never advances again', () => {
    const e = testEngine(); e.start(); e.advance(300); const view = e.getView();
    expect(view.status).toBe('completed'); expect(view.elapsedSeconds).toBe(60); expect(view.events.at(-1)?.type).toBe('finished');
    const record = e.completedRecord(); expect(record.scenario.tracks).toHaveLength(1); expect(record.events).toEqual(view.events);
    e.advance(10); expect(e.getView()).toEqual(view); expect(() => e.finish()).toThrow(); expect(() => e.action({ kind: 'select', trackId: 'T01' })).toThrow();
  });
  it('marks an early exit partial, including while paused', () => {
    const e = testEngine(); e.start(); e.advance(5); e.pause(); e.finish();
    const record = e.completedRecord(); expect(record.status).toBe('aborted'); expect(record.elapsedSeconds).toBe(5); expect(record.evaluation.comparable).toBe(false);
  });
  it('fresh engine reset replays the seed but has fresh IDs, zero clock and empty log', () => {
    const a = testEngine({}, 'old'); a.start(); a.advance(9); const oldObs = a.getView().tracks[0].observations;
    const b = testEngine({}, 'new'); expect(b.getView().status).toBe('briefing'); expect(b.getView().events).toEqual([]); expect(b.getView().elapsedSeconds).toBe(0);
    expect(b.getView().scenario.id).toBe(a.getView().scenario.id); b.start(); b.advance(9); expect(b.getView().tracks[0].observations).toEqual(oldObs);
    expect(b.getView().events[0].id).not.toBe(a.getView().events[0].id);
  });
  it('does not expose references that can mutate authoritative state', () => {
    const e = testEngine(); e.start(); e.advance(1); const view = e.getView(); view.events.length = 0; view.tracks[0].latest.x = 999; view.scenario.config.objectives.length = 0;
    expect(e.getView().events.length).toBeGreaterThan(0); expect(e.getView().tracks[0].latest.x).toBeLessThanOrEqual(100); expect(e.getView().scenario.config.objectives.length).toBe(5);
  });
  it('produces identical observations regardless of advance chunking or speed control', () => {
    const a = testEngine(); const b = testEngine(); a.start(); b.start(); a.advance(60); b.setSpeed(4);
    for (let i = 0; i < 60; i++) b.advance(1);
    expect(a.completedRecord().events).toEqual(b.completedRecord().events); expect(a.completedRecord().evaluation).toEqual(b.completedRecord().evaluation);
  });
  it.each([-1, 1.2, NaN, Infinity, 3601])('rejects invalid clock steps %s', value => { expect(() => testEngine().advance(value)).toThrow(); });
  it('rejects invalid identities and playback speeds', () => {
    expect(() => new SimulationEngine(testConfig(), { sessionId: '', profileId: 'p', startedAt: 'bad' })).toThrow();
    expect(() => testEngine().setSpeed(3)).toThrow();
  });
});

describe('fixed-step wall-clock adapter', () => {
  it('accumulates fractions, excludes pauses and applies speed only to active deltas', () => {
    const clock = new FixedStepClock(); expect(clock.consume(500,true,1)).toBe(0);
    expect(clock.consume(9000,false,1)).toBe(0); expect(clock.consume(500,true,1)).toBe(1);
    expect(clock.consume(250,true,4)).toBe(1); clock.consume(500,true,1); clock.reset(); expect(clock.consume(500,true,1)).toBe(0);
  });
  it.each([-1, NaN, Infinity])('rejects invalid wall-clock delta %s', ms => { expect(() => new FixedStepClock().consume(ms,true,1)).toThrow(); });
});

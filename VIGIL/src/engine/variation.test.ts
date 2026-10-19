import { describe, expect, it } from 'vitest';
import { cloneConfig, configErrors, PRESETS, validateConfig } from '../domain/config';
import { inClutterZone, sensorConditions, URBAN_CLUTTER_ZONES } from '../domain/conditions';
import { observationSchema } from '../domain/events';
import { SCHEMA_VERSION } from '../domain/types';
import type { Observation, ScenarioConfig, SimulationEvent, TrafficPattern, WorkerResponse } from '../domain/types';
import { testConfig, testEngine } from '../test/fixtures';
import { SimulationRuntime } from '../workers/runtime';
import { applyEvidenceEvent } from './evidence';
import { validateSessionLog } from './log';
import { generateScenario } from './scenario';
import { captureObservation, syntheticPosition } from './sensor';
import { SimulationEngine } from './SimulationEngine';

const patterns: TrafficPattern[] = ['independent', 'crossing', 'grouped'];
function run(config: ScenarioConfig, chunked = false) {
  const e = new SimulationEngine(config, { sessionId: 'variation', profileId: 'p', startedAt: '2026-10-17T10:00:00.000Z' }, () => '2026-10-17T10:05:00.000Z');
  e.start(); if (chunked) { e.setSpeed(4); for (let i = 0; i < config.durationSeconds; i++) e.advance(1); } else e.advance(config.durationSeconds);
  return e.completedRecord();
}
function samples(config: ScenarioConfig, health: 'nominal' | 'degraded' = 'nominal', requested = false) {
  const s = generateScenario(config);
  return Array.from({ length: 300 }, (_, i) => captureObservation(s, s.tracks[0], i + 1, health, requested)).filter((o): o is Observation => o !== null);
}
const mean = (values: number[]) => values.reduce((sum, n) => sum + n, 0) / values.length;
function diameter(points: { x: number; y: number }[]) {
  return Math.max(...points.flatMap(a => points.map(b => Math.hypot(a.x - b.x, a.y - b.y))));
}

describe('versioned configuration and procedural patterns', () => {
  it('versions serialized definitions/public views without relabelling the old generator', () => {
    const s = generateScenario(testConfig()); const e = testEngine();
    expect(SCHEMA_VERSION).toBe(3); expect(s).toMatchObject({ schemaVersion: 3, generatorVersion: 'generator-2', sensorVersion: 'sensor-2' });
    expect(s.id).toMatch(/^v2-/); expect(e.getView().scenario).toMatchObject({ generatorVersion: 'generator-2', sensorVersion: 'sensor-2' });
  });
  it('requires an explicit pattern, valid count and helpful cross-field errors', () => {
    const config = testConfig(); const { trafficPattern: omitted, ...missing } = config; expect(omitted).toBe('independent');
    expect(() => validateConfig(missing)).toThrow();
    expect(configErrors({ ...config, trafficPattern: 'crossing' }).join(' ')).toContain('at least 2');
    expect(configErrors({ ...config, trafficPattern: 'grouped', trackCount: 2 }).join(' ')).toContain('at least 3');
    expect(() => validateConfig({ ...config, trafficPattern: 'operational' })).toThrow();
    expect(validateConfig({ ...config, trafficPattern: 'grouped', trackCount: 3 }).trackCount).toBe(3);
  });
  it('curates distinct day/dusk/night live models rather than title-only presets', () => {
    const configs = PRESETS.slice(0, 3).map(p => p.config);
    expect(configs.map(c => c.trafficPattern)).toEqual(patterns);
    const models = configs.map(sensorConditions);
    expect(models[0].returnSetting).toBeGreaterThan(models[1].returnSetting);
    expect(models[1].returnSetting).toBeGreaterThan(models[2].returnSetting);
    expect(models[0].spatialNoise).toBeLessThan(models[1].spatialNoise);
    expect(models[1].spatialNoise).toBeLessThan(models[2].spatialNoise);
    const records = configs.map(c => run(c));
    for (const r of records) expect(new Set(r.events.filter(e => e.type === 'observation').map(e => e.data.observation.trackId)).size).toBe(r.scenario.config.trackCount);
    const observations = records.map(r => r.events.filter(e => e.type === 'observation').map(e => e.data.observation));
    expect(mean(observations[0].map(o => o.confidence))).toBeGreaterThan(mean(observations[1].map(o => o.confidence)));
    expect(mean(observations[1].map(o => o.confidence))).toBeGreaterThan(mean(observations[2].map(o => o.confidence)));
    expect(mean(observations[0].map(o => o.deliveredAt - o.capturedAt))).toBeLessThan(mean(observations[2].map(o => o.deliveredAt - o.capturedAt)));
  });
  it.each(patterns)('%s reproduces definitions, logs and evaluation across seed/config key order and chunk/speed', pattern => {
    const config = testConfig({ trafficPattern: pattern, trackCount: 4, environment: 'urban', lighting: 'dusk', weather: 'haze', delaySeconds: 3 });
    expect(JSON.stringify(generateScenario(config))).toBe(JSON.stringify(generateScenario(Object.fromEntries(Object.entries(config).reverse()))));
    expect(run(config)).toEqual(run(config, true));
    const a = generateScenario(config); const b = generateScenario({ ...config, seed: config.seed + 7919 });
    expect(a.tracks).not.toEqual(b.tracks); expect(a.id).not.toBe(b.id);
  });
  it('crossing paths meet near a shared seeded region, not copied independent paths', () => {
    const s = generateScenario(testConfig({ trafficPattern: 'crossing', trackCount: 4, durationSeconds: 150 }));
    const widths = Array.from({ length: 100 }, (_, i) => diameter(s.tracks.map(t => syntheticPosition(t, i + 20))));
    expect(Math.min(...widths)).toBeLessThan(9);
    expect(diameter(s.tracks.map(t => syntheticPosition(t, 20)))).toBeGreaterThan(20);
    expect(new Set(s.tracks.map(t => JSON.stringify(t.velocity))).size).toBe(4);
  });
  it('grouped returns share motion but not evaluator category labels or exact positions', () => {
    const s = generateScenario(testConfig({ trafficPattern: 'grouped', trackCount: 8, durationSeconds: 300 }));
    expect(new Set(s.tracks.map(t => JSON.stringify(t.velocity))).size).toBe(1);
    expect(new Set(s.tracks.map(t => t.category)).size).toBeGreaterThan(1);
    for (const time of [10, 60, 120, 250, 300]) expect(diameter(s.tracks.map(t => syntheticPosition(t, time)))).toBeLessThan(16);
    expect(new Set(s.tracks.map(t => JSON.stringify(t.origin))).size).toBe(8);
  });
  it.each(patterns)('%s difficulty changes actual bounded motion, not just its label', trafficPattern => {
    const a = generateScenario(testConfig({ trafficPattern, trackCount: 4, durationSeconds: 300, difficulty: 1 }));
    const b = generateScenario(testConfig({ trafficPattern, trackCount: 4, durationSeconds: 300, difficulty: 5 }));
    expect(Math.hypot(b.tracks[0].velocity.x, b.tracks[0].velocity.y)).toBeGreaterThan(Math.hypot(a.tracks[0].velocity.x, a.tracks[0].velocity.y));
  });
  it('keeps many-seed extreme paths and observations finite, timed and within documented bounds', () => {
    let observed = 0;
    for (const trafficPattern of patterns) for (let seed = 0; seed < 24; seed++) {
      const config = testConfig({ trafficPattern, seed: seed % 2 ? 4294967295 - seed : seed, trackCount: 8, durationSeconds: 300, difficulty: seed % 2 ? 5 : 1, environment: seed % 2 ? 'urban' : 'rural', lighting: seed % 2 ? 'night' : 'day', weather: seed % 2 ? 'rain' : 'clear', reliability: seed % 2 ? .35 : 1, noise: seed % 2 ? .3 : 0, delaySeconds: seed % 2 ? 8 : 0 });
      const s = generateScenario(config);
      expect(s.tracks).toHaveLength(8);
      for (const track of s.tracks) {
        expect(track.spawnAt).toBeGreaterThan(0); expect(track.spawnAt).toBeLessThan(config.durationSeconds);
        expect(track.origin.x).toBeGreaterThanOrEqual(0); expect(track.origin.x).toBeLessThanOrEqual(100);
        for (let time = track.spawnAt; time <= 300; time += 11) {
          const position = syntheticPosition(track, time);
          expect(position.x).toBeGreaterThanOrEqual(5); expect(position.x).toBeLessThanOrEqual(95);
          expect(position.y).toBeGreaterThanOrEqual(5); expect(position.y).toBeLessThanOrEqual(95);
          const o = captureObservation(s, track, time, seed % 3 ? 'nominal' : 'degraded', seed % 4 === 0);
          if (o) { observed++; expect(observationSchema.safeParse(o).success).toBe(true); expect(o.deliveredAt - time).toBeGreaterThanOrEqual(0); expect(o.deliveredAt - time).toBeLessThanOrEqual(19); }
        }
      }
    }
    expect(observed).toBeGreaterThan(1000);
  });
});

describe('isolated actual synthetic sensor effects', () => {
  it('lower reliability removes returns rather than merely changing a display number', () => {
    const reliable = samples(testConfig()); const intermittent = samples(testConfig({ reliability: .35 }));
    expect(reliable).toHaveLength(300); expect(intermittent.length).toBeLessThan(150); expect(intermittent.length).toBeGreaterThan(50);
    expect(intermittent.every(o => reliable.some(r => r.id === o.id))).toBe(true);
  });
  it('noise changes positions/uncertainty while dropout and capture IDs stay paired', () => {
    const s = generateScenario(testConfig()); const clear = samples(testConfig()); const noisy = samples(testConfig({ noise: .3 }));
    expect(clear.map(o => o.id)).toEqual(noisy.map(o => o.id));
    const error = (os: Observation[]) => mean(os.map(o => { const p = syntheticPosition(s.tracks[0], o.capturedAt); return Math.hypot(o.x - p.x, o.y - p.y); }));
    expect(error(noisy)).toBeGreaterThan(error(clear) + 1);
    expect(mean(noisy.map(o => o.uncertainty))).toBeGreaterThan(mean(clear.map(o => o.uncertainty)));
    expect(mean(noisy.map(o => o.confidence))).toBeLessThan(mean(clear.map(o => o.confidence)));
  });
  it('configured delay shifts only delivery time in otherwise identical rural/day captures', () => {
    const a = samples(testConfig()); const b = samples(testConfig({ delaySeconds: 8 }));
    expect(b.map(o => ({ ...o, deliveredAt: o.deliveredAt - 8 }))).toEqual(a);
  });
  it.each([{ weather: 'rain' } as const, { lighting: 'night' } as const, { environment: 'urban' } as const])('condition %j changes real quality, availability and delay', patch => {
    const base = samples(testConfig()); const affected = samples(testConfig(patch));
    expect(affected.length).toBeLessThan(base.length);
    expect(mean(affected.map(o => o.confidence))).toBeLessThan(mean(base.map(o => o.confidence)));
    expect(mean(affected.map(o => o.uncertainty))).toBeGreaterThan(mean(base.map(o => o.uncertainty)));
    expect(mean(affected.map(o => o.deliveredAt - o.capturedAt))).toBeGreaterThan(0);
  });
  it('public hatched clutter geometry matches the actual sensor penalty region', () => {
    const zone = URBAN_CLUTTER_ZONES[0]; expect(inClutterZone(zone.x + 1, zone.y + 1)).toBe(true); expect(inClutterZone(5, 5)).toBe(false);
    const s = generateScenario(testConfig({ environment: 'urban' }));
    const inside = { ...s.tracks[0], origin: { x: 43, y: 50 }, velocity: { x: 0, y: 0 } };
    const outside = { ...inside, origin: { x: 10, y: 10 } };
    const a: Observation[] = []; const b: Observation[] = [];
    for (let t = 1; t <= 300; t++) { const i = captureObservation(s, inside, t, 'nominal'); const o = captureObservation(s, outside, t, 'nominal'); if (i) a.push(i); if (o) b.push(o); }
    expect(a.length).toBeLessThan(b.length); expect(mean(a.map(o => o.confidence))).toBeLessThan(mean(b.map(o => o.confidence)));
    for (const i of a) { const o = b.find(o => o.id === i.id)!; expect(i.deliveredAt - o.deliveredAt).toBe(2); }
  });
  it('requested attempts improve paired quality/availability but are not guaranteed', () => {
    const config = testConfig({ reliability: .35, noise: .17, weather: 'rain', lighting: 'night' });
    const regular = samples(config); const requested = samples(config, 'nominal', true);
    expect(requested.length).toBeGreaterThan(regular.length); expect(requested.length).toBeLessThan(300);
    for (const r of regular) { const q = requested.find(o => o.id === r.id)!; expect(q.confidence).toBeGreaterThanOrEqual(r.confidence); expect(q.uncertainty).toBeLessThanOrEqual(r.uncertainty); }
    expect(requested.every(o => o.source === 'requested')).toBe(true);
  });
});

describe('request provenance, delayed evidence and runtime isolation', () => {
  it('coalesces a request and regular capture at the same second into one requested observation', () => {
    const e = testEngine(); e.start(); e.advance(3); e.action({ kind: 'request_observation', trackId: 'T01' }); e.advance(2);
    const atFive = e.getView().tracks[0].observations.filter(o => o.capturedAt === 5);
    expect(atFive).toHaveLength(1); expect(atFive[0].source).toBe('requested');
  });
  it('records actual successful and dropped requests without fabricating failed returns', () => {
    let successes = 0; let failures = 0;
    for (let seed = 0; seed < 24; seed++) {
      const config = testConfig({ seed }); const s = generateScenario(config); const e = testEngine({ seed });
      e.start(); e.advance(s.degradation!.startsAt); e.action({ kind: 'request_observation', trackId: 'T01' });
      const capture = s.degradation!.startsAt + 2;
      const expected = captureObservation(s, s.tracks[0], capture, 'degraded', true);
      e.advance(60 - s.degradation!.startsAt);
      const delivered = e.completedRecord().events.filter(event => event.type === 'observation' && event.data.observation.capturedAt === capture);
      if (expected) { successes++; expect(delivered).toHaveLength(1); if (delivered[0].type === 'observation') expect(delivered[0].data.observation).toEqual(expected); }
      else { failures++; expect(delivered).toHaveLength(0); }
    }
    expect(successes).toBeGreaterThan(0); expect(failures).toBeGreaterThan(0);
  });
  it('extra requests do not change unrelated scheduled captures or another session', () => {
    const a = testEngine(); const b = testEngine(); a.start(); b.start(); a.advance(1); b.advance(1);
    a.action({ kind: 'request_observation', trackId: 'T01' }); a.advance(59); b.advance(59);
    const aObs = a.completedRecord().events.filter(e => e.type === 'observation').map(e => e.data.observation);
    const bObs = b.completedRecord().events.filter(e => e.type === 'observation').map(e => e.data.observation);
    expect(aObs.filter(o => o.source === 'scheduled')).toEqual(bObs);
  });
  it('rejects requested provenance with no matching prior action', () => {
    const r = run(testConfig()); const events = structuredClone(r.events); const first = events.find(e => e.type === 'observation')!;
    if (first.type === 'observation') first.data.observation.source = 'requested';
    expect(() => validateSessionLog(r.scenario, events)).toThrow('source must match');
  });
  it('keeps delivery history but never rewinds latest capture after a late old return', () => {
    const e = testEngine(); e.start(); e.advance(5); const o = e.getView().tracks[0].latest;
    const newer = { ...o, capturedAt: 5, deliveredAt: 9, x: 80 };
    const older = { ...o, id: 'T01:o001', capturedAt: 1, deliveredAt: 10, x: 20 };
    const tracks = new Map();
    const event = (observation: Observation, order: number): SimulationEvent => ({ id: `e${order}`, sessionId: 's', order, time: observation.deliveredAt, type: 'observation', data: { observation } });
    applyEvidenceEvent(tracks, event(newer, 1)); applyEvidenceEvent(tracks, event(older, 2));
    expect(tracks.get('T01').latest).toEqual(newer); expect(tracks.get('T01').observations).toEqual([newer, older]);
  });
  it('generates genuine out-of-capture-order arrivals and retains newest-capture snapshots', () => {
    let inversions = 0;
    for (let seed = 0; seed < 24; seed++) {
      const e = testEngine({ seed, environment: 'urban', lighting: 'night', weather: 'rain', trackCount: 8, delaySeconds: 8, durationSeconds: 90 }); e.start();
      for (let t = 1; t <= 90; t++) {
        e.advance(1);
        for (const track of e.getView().tracks) {
          expect(track.latest.capturedAt).toBe(Math.max(...track.observations.map(o => o.capturedAt)));
          // Real requests create captures closer together than the regular four-second cadence.
          if (t < 90 && (track.lastRequestedAt === null || t - track.lastRequestedAt >= 8)) e.action({ kind: 'request_observation', trackId: track.id });
        }
      }
      for (const track of e.getView().tracks) inversions += track.observations.filter((o, i, arr) => i > 0 && o.capturedAt < arr[i - 1].capturedAt).length;
    }
    expect(inversions).toBeGreaterThan(0);
  });
  it('drops pending late deliveries on exact termination and reset, without adding them to review', () => {
    const e = testEngine({ delaySeconds: 8 }); e.start(); e.advance(60); const old = e.completedRecord();
    expect(old.events.filter(e => e.type === 'observation').every(e => e.data.observation.deliveredAt <= 60)).toBe(true);
    const fresh = testEngine({ delaySeconds: 8 }, 'fresh'); fresh.start(); fresh.advance(8); expect(fresh.getView().tracks).toHaveLength(0);
    fresh.advance(1); expect(fresh.getView().tracks[0].latest.capturedAt).toBe(1);
  });
  it.each(PRESETS)('keeps private answers/paths/future schedule out of $name snapshots', preset => {
    const e = new SimulationEngine(cloneConfig(preset.config), { sessionId: 'public', profileId: 'p', startedAt: '2026-10-17T00:00:00.000Z' }); e.start();
    for (let t = 0; t < 3; t++) {
      e.advance(12); const view = e.getView(); const json = JSON.stringify(view);
      expect(view.scenario).not.toHaveProperty('tracks');
      for (const key of ['rubric','weights','origin','velocity','phase','truthCategory','significant','degradation','crossingAt','center']) expect(json).not.toContain(`"${key}"`);
      expect(view.tracks.every(track => track.observations.every(o => o.deliveredAt <= view.elapsedSeconds))).toBe(true);
    }
  });
  it('isolates simultaneous authoritative runtimes from another runtime actions and clock', () => {
    let now = 0; const messages: WorkerResponse[][] = [[],[],[]];
    const runtimes = messages.map(m => new SimulationRuntime(r => m.push(r), () => now, () => '2026-10-17T00:05:00.000Z'));
    runtimes.forEach((r, i) => { r.handle({ type: 'configure', config: testConfig({ seed: i === 0 ? 1 : 2 }), sessionId: i === 0 ? 'A' : 'B', profileId: 'p', startedAt: '2026-10-17T00:00:00.000Z' }); r.handle({ type: 'start' }); });
    now = 1000; runtimes.forEach(r => r.tick()); runtimes[0].handle({ type: 'action', action: { kind: 'request_observation', trackId: 'T01' } }); runtimes[0].handle({ type: 'pause' });
    now = 60000; runtimes.forEach(r => r.tick());
    expect(messages[1]).toEqual(messages[2]); expect(messages[1].some(m => m.type === 'completed')).toBe(true);
    expect(messages[0].some(m => m.type === 'completed')).toBe(false);
  });
});

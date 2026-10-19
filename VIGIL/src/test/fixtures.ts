import { cloneConfig, PRESETS } from '../domain/config';
import type { ScenarioConfig } from '../domain/types';
import { SimulationEngine } from '../engine/SimulationEngine';

export function testConfig(patch: Partial<ScenarioConfig> = {}): ScenarioConfig {
  return { ...cloneConfig(PRESETS[0].config), seed: 1, reliability: 1, noise: 0, delaySeconds: 0, durationSeconds: 60, ...patch };
}
export function testEngine(patch: Partial<ScenarioConfig> = {}, sessionId = 'test-session') {
  return new SimulationEngine(testConfig(patch), { sessionId, profileId: 'trainee-01', startedAt: '2026-10-17T10:00:00.000Z' }, () => '2026-10-17T10:01:00.000Z');
}

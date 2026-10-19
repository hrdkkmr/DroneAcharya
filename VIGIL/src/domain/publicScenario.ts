import type { PublicScenario, ScenarioDefinition } from './types';

/** Explicit whitelist: never spread the hidden definition into an active snapshot. */
export function publicScenario(scenario: ScenarioDefinition): PublicScenario {
  const c = scenario.config;
  return { schemaVersion: scenario.schemaVersion, generatorVersion: scenario.generatorVersion, sensorVersion: scenario.sensorVersion, id: scenario.id, seed: scenario.seed, config: {
    presetId: c.presetId, exerciseType: c.exerciseType, environment: c.environment, lighting: c.lighting, weather: c.weather,
    reliability: c.reliability, noise: c.noise, delaySeconds: c.delaySeconds, trackCount: c.trackCount, trafficPattern: c.trafficPattern,
    durationSeconds: c.durationSeconds, difficulty: c.difficulty, seed: c.seed, objectives: [...c.objectives],
  } };
}

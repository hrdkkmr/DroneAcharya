import { validateConfig } from '../domain/config';
import { SCHEMA_VERSION } from '../domain/types';
import type { HiddenTrack, ScenarioDefinition, TruthCategory } from '../domain/types';
import { createRubric } from '../scoring/rubric';
import { canonicalJson, hash32, mulberry32 } from './random';

export function generateScenario(raw: unknown): ScenarioDefinition {
  const config = validateConfig(raw);
  const rng = mulberry32(config.seed);
  const layout = mulberry32(hash32(`${config.seed}|layout-2`));
  const categories: TruthCategory[] = ['routine', 'review', 'background'];
  const crossingAt = Math.round(config.durationSeconds * (.42 + layout() * .16));
  const center = { x: 42 + layout() * 16, y: 42 + layout() * 16 };
  const groupHeading = layout() * Math.PI * 2;
  const groupSpeed = .16 + layout() * .12 + (config.difficulty - 1) * .025;
  const groupPhase = layout() * Math.PI * 2;
  const groupVelocity = { x: Math.cos(groupHeading) * groupSpeed, y: Math.sin(groupHeading) * groupSpeed };
  const tracks: HiddenTrack[] = Array.from({ length: config.trackCount }, (_, index) => {
    const category = categories[Math.floor(rng() * categories.length)];
    const angle = rng() * Math.PI * 2;
    const speed = .12 + rng() * .18 + (config.difficulty - 1) * .025;
    const track: HiddenTrack = {
      id: `T${String(index + 1).padStart(2, '0')}`, category, significant: category === 'review',
      spawnAt: index === 0 ? 1 : 4 + index * 2 + Math.floor(rng() * 4), endAt: config.durationSeconds,
      origin: { x: 22 + rng() * 56, y: 22 + rng() * 56 },
      velocity: { x: Math.cos(angle) * speed, y: Math.sin(angle) * speed }, phase: rng() * Math.PI * 2,
    };
    if (config.trafficPattern === 'crossing') {
      // Distinct headings, one seeded meeting region. Never sent to the trainee view.
      const heading = groupHeading + index * Math.PI * 2 / config.trackCount;
      const boundedSpeed = (16 + Math.min(1, (speed - .12) / .28) * 12) / crossingAt;
      track.velocity = { x: Math.cos(heading) * boundedSpeed, y: Math.sin(heading) * boundedSpeed };
      track.origin = { x: center.x - track.velocity.x * (crossingAt - track.spawnAt), y: center.y - track.velocity.y * (crossingAt - track.spawnAt) };
    } else if (config.trafficPattern === 'grouped') {
      track.spawnAt = 1 + index % 3;
      track.velocity = { ...groupVelocity };
      const offset = index * Math.PI * 2 / config.trackCount;
      track.origin = { x: center.x + Math.cos(offset) * 3 + groupVelocity.x * (track.spawnAt - 1), y: center.y + Math.sin(offset) * 3 + groupVelocity.y * (track.spawnAt - 1) };
      track.phase = groupPhase + track.spawnAt / 10;
    }
    return track;
  });
  const startsAt = 12 + Math.floor(rng() * 5);
  return {
    schemaVersion: SCHEMA_VERSION, generatorVersion: 'generator-2', sensorVersion: 'sensor-2',
    id: `v2-${config.seed}-${hash32(`generator-2|sensor-2|${canonicalJson(config)}`).toString(16).padStart(8, '0')}`,
    seed: config.seed, config, tracks, degradation: { startsAt, endsAt: startsAt + 18 }, rubric: createRubric(config),
  };
}

export { publicScenario } from '../domain/publicScenario';

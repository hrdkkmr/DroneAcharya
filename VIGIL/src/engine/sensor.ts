import { inClutterZone, sensorConditions } from '../domain/conditions';
import type { HiddenTrack, Observation, ScenarioDefinition, SensorHealth } from '../domain/types';
import { clamp, hash32, mulberry32 } from './random';

/** A normalized, deliberately fictional trajectory. No geospatial/operational model. */
function reflect(value: number): number { const n = ((value - 5) % 180 + 180) % 180; return 5 + (n <= 90 ? n : 180 - n); }
export function syntheticPosition(track: HiddenTrack, time: number): { x: number; y: number } {
  const t = Math.max(0, time - track.spawnAt);
  const variation = track.category === 'review' ? 3 : track.category === 'background' ? 1.6 : .6;
  return {
    x: reflect(track.origin.x + track.velocity.x * t + Math.sin(t / 9 + track.phase) * variation),
    y: reflect(track.origin.y + track.velocity.y * t + Math.cos(t / 11 + track.phase) * variation),
  };
}
export function captureObservation(scenario: ScenarioDefinition, track: HiddenTrack, time: number, health: SensorHealth, prioritized = false): Observation | null {
  const c = scenario.config;
  const settings = sensorConditions(c);
  const seed = `${scenario.seed}|${track.id}|${time}`;
  // Independent streams: changing noise or delay cannot consume a dropout draw.
  const dropout = mulberry32(hash32(`${seed}|capture-1`));
  const quality = mulberry32(hash32(`${seed}|quality-2`));
  const positionNoise = mulberry32(hash32(`${seed}|position-2`));
  const delay = mulberry32(hash32(`${seed}|delay-2`));
  const position = syntheticPosition(track, time);
  const clutter = c.environment === 'urban' && inClutterZone(position.x, position.y);
  const degraded = health === 'degraded';
  const reliability = clamp(settings.returnSetting * (clutter ? .65 : 1) * (degraded ? .3 : 1) + (prioritized ? .12 : 0), .05, 1);
  if (dropout() > reliability) return null;
  const noise = clamp(settings.spatialNoise * (degraded ? 1.8 : 1) + (degraded ? .04 : 0) + (clutter ? .03 : 0), 0, .6) * (prioritized ? .75 : 1);
  const confidence = Math.round(clamp(95 - noise * 120 - (1 - c.reliability) * 28 - settings.confidenceLoss - (clutter ? 6 : 0) - (degraded ? 28 : 0) + (prioritized ? 8 : 0) + (quality() - .5) * 12, 12, 98));
  const resolved = confidence >= scenario.rubric.clearConfidenceThreshold;
  const cues = {
    routine: { motion: 'steady', signature: 'regular' }, review: { motion: 'variable', signature: 'irregular' }, background: { motion: 'drifting', signature: 'diffuse' },
  } as const;
  return {
    id: `${track.id}:o${String(time).padStart(3, '0')}`, trackId: track.id,
    capturedAt: time, deliveredAt: time + settings.minimumDelay + Math.floor(delay() * (settings.jitterSeconds + 1)) + (clutter ? 2 : 0) + (degraded ? 2 : 0),
    source: prioritized ? 'requested' : 'scheduled',
    x: Math.round(clamp(position.x + (positionNoise() - .5) * noise * 20, 0, 100) * 100) / 100,
    y: Math.round(clamp(position.y + (positionNoise() - .5) * noise * 20, 0, 100) * 100) / 100,
    confidence, uncertainty: Math.round(clamp(2 + noise * 25 + (100 - confidence) / 20, 1, 25) * 10) / 10,
    motion: resolved ? cues[track.category].motion : 'unresolved', signature: resolved ? cues[track.category].signature : 'unresolved',
  };
}

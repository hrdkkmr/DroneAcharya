import type { ScenarioConfig, TrafficPattern } from './types';

/** Public model settings and schematic geometry only. Never import hidden engine state here. */
export type SensorConfig = Pick<ScenarioConfig, 'environment' | 'lighting' | 'weather' | 'reliability' | 'noise' | 'delaySeconds'>;
export const PATTERN_LABELS: Record<TrafficPattern, string> = {
  independent: 'Independent paths', crossing: 'Crossing paths', grouped: 'Grouped motion',
};
export const PATTERN_DESCRIPTIONS: Record<TrafficPattern, string> = {
  independent: 'Separate seeded paths. Start with one return or manage up to eight.',
  crossing: 'At least two seeded paths pass through a shared region. Keep track identity separate from proximity.',
  grouped: 'At least three returns share broad motion with small offsets. A group is not a classification.',
};
export const URBAN_CLUTTER_ZONES = [
  { id: 'A', x: 35, y: 32, width: 16, height: 38 },
  { id: 'B', x: 61, y: 53, width: 12, height: 22 },
] as const;
export function inClutterZone(x: number, y: number): boolean {
  return URBAN_CLUTTER_ZONES.some(z => x >= z.x && x <= z.x + z.width && y >= z.y && y <= z.y + z.height);
}
export interface SensorConditions {
  returnSetting: number;
  spatialNoise: number;
  confidenceLoss: number;
  minimumDelay: number;
  maximumDelay: number;
  jitterSeconds: number;
  notes: string[];
}
/** Derived from validated public settings. This is a model parameter, NOT measured recall. */
export function sensorConditions(c: SensorConfig): SensorConditions {
  const urban = c.environment === 'urban';
  const light = c.lighting === 'night' ? { reliability: .9, noise: .025, loss: 5, delay: 1, jitter: 1 }
    : c.lighting === 'dusk' ? { reliability: .96, noise: .01, loss: 2, delay: 0, jitter: 0 }
      : { reliability: 1, noise: 0, loss: 0, delay: 0, jitter: 0 };
  const weather = c.weather === 'rain' ? { reliability: .85, noise: .04, loss: 5.25, delay: 1, jitter: 2 }
    : c.weather === 'haze' ? { reliability: .93, noise: .02, loss: 2.45, delay: 0, jitter: 1 }
      : { reliability: 1, noise: 0, loss: 0, delay: 0, jitter: 0 };
  const minimumDelay = c.delaySeconds + (urban ? 1 : 0) + light.delay + weather.delay;
  const jitterSeconds = Math.min(4, (urban ? 2 : 0) + light.jitter + weather.jitter);
  return {
    returnSetting: c.reliability * (urban ? .9 : 1) * light.reliability * weather.reliability,
    spatialNoise: Math.min(.6, c.noise + (urban ? .03 : 0) + light.noise + weather.noise),
    confidenceLoss: (urban ? 6 : 0) + light.loss + weather.loss,
    minimumDelay, maximumDelay: minimumDelay + jitterSeconds + (urban ? 2 : 0), jitterSeconds,
    notes: [
      urban ? 'Hatched schematic clutter zones further weaken returns and add delay.' : 'Open schematic terrain; no urban clutter penalty.',
      c.lighting === 'night' ? 'Darkness lowers signal quality and increases uncertainty.' : c.lighting === 'dusk' ? 'Dusk slightly reduces signal quality.' : 'Daylight has no lighting penalty.',
      c.weather === 'rain' ? 'Rain adds noise, intermittent returns and delivery jitter.' : c.weather === 'haze' ? 'Haze adds noise and delivery jitter.' : 'Clear weather adds no weather penalty.',
      'A seeded disruption reduces return consistency and adds 2s delay. Requests improve an attempt, never guarantee one.',
    ],
  };
}

/** Absolute validated generator-2 / sensor-2 delivery bound, including disruption/clutter. */
export const MAX_DELIVERY_DELAY_SECONDS = 19;

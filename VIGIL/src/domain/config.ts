import { z } from 'zod';
import type { ScenarioConfig, ScenarioPreset, Skill, EvaluationWeights, MetricKey } from './types';

export const SKILL_LABELS: Record<Skill, string> = {
  detection: 'Detection', classification: 'Classification', uncertainty: 'Uncertainty handling',
  reporting: 'Reporting', decision: 'Decision quality',
};
export const METRIC_LABELS: Record<MetricKey, string> = { ...SKILL_LABELS, objectives: 'Training objectives' };
export const DEFAULT_WEIGHTS: EvaluationWeights = { detection: 20, classification: 20, uncertainty: 15, reporting: 20, decision: 15, objectives: 10 };
export const SKILLS = Object.keys(SKILL_LABELS) as Skill[];
export const evaluationWeightsSchema = z.object({
  detection: z.number().finite().min(0).max(100), classification: z.number().finite().min(0).max(100),
  uncertainty: z.number().finite().min(0).max(100), reporting: z.number().finite().min(0).max(100),
  decision: z.number().finite().min(0).max(100), objectives: z.number().finite().min(0).max(100),
}).strict().refine(v => Math.abs(Object.values(v).reduce((a, b) => a + b, 0) - 100) < 0.001, 'Evaluation weights must total 100%.');

export const scenarioConfigSchema = z.object({
  presetId: z.enum(['perimeter', 'urban-dusk', 'night-watch', 'rural-crossing', 'custom']),
  exerciseType: z.enum(['observation', 'assessment', 'reporting']),
  environment: z.enum(['urban', 'rural']), lighting: z.enum(['day', 'dusk', 'night']), weather: z.enum(['clear', 'haze', 'rain']),
  reliability: z.number().finite().min(0.35, 'Sensor reliability must be at least 35%.').max(1),
  noise: z.number().finite().min(0).max(0.3, 'Noise must not exceed 30%.'),
  delaySeconds: z.number().int().min(0).max(8), trackCount: z.number().int().min(1).max(8),
  trafficPattern: z.enum(['independent', 'crossing', 'grouped']),
  durationSeconds: z.number().int().min(60, 'Exercises must last at least 60 seconds.').max(300),
  difficulty: z.union([z.literal(1), z.literal(2), z.literal(3), z.literal(4), z.literal(5)]),
  seed: z.number().int().min(0).max(4294967295, 'Use an unsigned 32-bit seed (0–4294967295).'),
  objectives: z.array(z.enum(['detection', 'classification', 'uncertainty', 'reporting', 'decision'])).min(1, 'Choose at least one training objective.').max(5).refine(v => new Set(v).size === v.length, 'Objectives must be unique.'),
  weights: evaluationWeightsSchema,
}).strict().superRefine((config, context) => {
  const minimum = config.trafficPattern === 'grouped' ? 3 : config.trafficPattern === 'crossing' ? 2 : 1;
  if (config.trackCount < minimum) context.addIssue({ code: z.ZodIssueCode.custom, path: ['trackCount'], message: `${config.trafficPattern === 'grouped' ? 'Grouped motion needs at least 3 tracks' : 'Crossing paths need at least 2 tracks'}. Increase the count or choose independent paths.` });
});

export function validateConfig(value: unknown): ScenarioConfig {
  return scenarioConfigSchema.parse(value);
}
export function configErrors(value: unknown): string[] {
  const result = scenarioConfigSchema.safeParse(value);
  return result.success ? [] : result.error.issues.map(issue => `${issue.path.join('.')}: ${issue.message}`);
}
const base: ScenarioConfig = {
  presetId: 'perimeter', exerciseType: 'observation', environment: 'rural', lighting: 'day', weather: 'clear',
  reliability: 0.94, noise: 0.04, delaySeconds: 1, trackCount: 1, trafficPattern: 'independent', durationSeconds: 90, difficulty: 1,
  seed: 26247, objectives: [...SKILLS], weights: { ...DEFAULT_WEIGHTS },
};
export const PRESETS: ScenarioPreset[] = [
  { id: 'perimeter', name: 'Perimeter watch', description: 'Build a clear picture. Follow a single synthetic track in a low-noise environment.', focus: 'Observation fundamentals', config: { ...base } },
  { id: 'urban-dusk', name: 'Urban ambiguity', description: 'Follow crossing returns through schematic clutter, variable delay and dusk haze.', focus: 'Classification & uncertainty', config: { ...base, presetId: 'urban-dusk', trafficPattern: 'crossing', exerciseType: 'assessment', environment: 'urban', lighting: 'dusk', weather: 'haze', reliability: 0.8, noise: 0.1, delaySeconds: 2, trackCount: 3, durationSeconds: 120, difficulty: 2, seed: 26248 } },
  { id: 'night-watch', name: 'Nightfall protocol', description: 'Follow grouped returns in rain and darkness. Request evidence without assuming a return.', focus: 'Reporting under uncertainty', config: { ...base, presetId: 'night-watch', trafficPattern: 'grouped', exerciseType: 'reporting', environment: 'rural', lighting: 'night', weather: 'rain', reliability: 0.63, noise: 0.17, delaySeconds: 4, trackCount: 4, durationSeconds: 150, difficulty: 3, seed: 26249 } },
  { id: 'rural-crossing', name: 'Rural crossing', description: 'Manage multiple observed tracks and deliver timely, complete training reports.', focus: 'Track management & reporting', config: { ...base, presetId: 'rural-crossing', trafficPattern: 'crossing', exerciseType: 'reporting', weather: 'haze', reliability: 0.87, noise: 0.07, trackCount: 2, durationSeconds: 120, difficulty: 2, seed: 26250 } },
];
export function cloneConfig(config: ScenarioConfig): ScenarioConfig {
  return { ...config, objectives: [...config.objectives], weights: { ...config.weights } };
}
export function presetName(id: string): string {
  return PRESETS.find(preset => preset.id === id)?.name ?? 'Custom exercise';
}

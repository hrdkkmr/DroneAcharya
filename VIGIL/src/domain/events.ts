import { z } from 'zod';
import { traineeActionSchema } from './actions';

export const observationSchema = z.object({
  id: z.string().min(1).max(100), trackId: z.string().regex(/^T\d{2}$/),
  capturedAt: z.number().int().nonnegative(), deliveredAt: z.number().int().nonnegative(),
  source: z.enum(['scheduled', 'requested']),
  x: z.number().finite().min(0).max(100), y: z.number().finite().min(0).max(100),
  confidence: z.number().finite().int().min(0).max(100), uncertainty: z.number().finite().min(0).max(25),
  motion: z.enum(['steady', 'variable', 'drifting', 'unresolved']), signature: z.enum(['regular', 'irregular', 'diffuse', 'unresolved']),
}).strict();
const base = { id: z.string().min(1).max(140), sessionId: z.string().min(1).max(100), order: z.number().int().positive(), time: z.number().int().nonnegative() };
export const simulationEventSchema = z.discriminatedUnion('type', [
  z.object({ ...base, type: z.literal('started'), data: z.object({ scenarioId: z.string().min(1) }).strict() }).strict(),
  z.object({ ...base, type: z.literal('observation'), data: z.object({ observation: observationSchema }).strict() }).strict(),
  z.object({ ...base, type: z.literal('sensor_change'), data: z.object({ health: z.enum(['nominal', 'degraded']), reason: z.string().min(1) }).strict() }).strict(),
  z.object({ ...base, type: z.literal('action'), data: z.object({ action: traineeActionSchema }).strict() }).strict(),
  z.object({ ...base, type: z.literal('paused'), data: z.object({ source: z.literal('trainee') }).strict() }).strict(),
  z.object({ ...base, type: z.literal('resumed'), data: z.object({ source: z.literal('trainee') }).strict() }).strict(),
  z.object({ ...base, type: z.literal('finished'), data: z.object({ outcome: z.enum(['completed', 'aborted']) }).strict() }).strict(),
]);

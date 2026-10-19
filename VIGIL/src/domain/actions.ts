import { z } from 'zod';
import type { SessionStatus, TrackEvidence, TraineeAction } from './types';
import { TRAINING_RULES } from './training';

export class TrainingError extends Error {
  constructor(public readonly code: string, message: string) { super(message); this.name = 'TrainingError'; }
}
const trackId = z.string().regex(/^T\d{2}$/, 'Choose an observed synthetic track.');
export const traineeActionSchema = z.discriminatedUnion('kind', [
  z.object({ kind: z.literal('select'), trackId }).strict(),
  z.object({ kind: z.literal('track'), trackId }).strict(),
  z.object({ kind: z.literal('request_observation'), trackId }).strict(),
  z.object({ kind: z.literal('classify'), trackId, category: z.enum(['routine', 'review', 'background', 'unknown']), confidence: z.number().finite().int().min(0).max(100) }).strict(),
  z.object({ kind: z.literal('report'), trackId, decision: z.enum(['log', 'observe', 'escalate']), summary: z.string().trim().min(12, 'Add an observation summary of at least 12 characters.').max(500, 'Keep the report within 500 characters.') }).strict(),
]);

/** Validation is shared by live commands and evaluator input checking. */
export function validateAction(raw: unknown, status: SessionStatus, track: TrackEvidence | undefined, now: number): TraineeAction {
  const action = traineeActionSchema.parse(raw);
  if (status !== 'running') throw new TrainingError('NOT_RUNNING', 'Resume or start the exercise before recording a decision.');
  if (!track || track.id !== action.trackId) throw new TrainingError('NOT_OBSERVED', 'That track has no delivered observation. Choose a visible track.');
  if (action.kind === 'select') return action;
  if (track.report) throw new TrainingError('REPORT_FINAL', 'This track’s report is final for this exercise. You can still inspect its observations.');
  if (action.kind === 'track' && track.trackedAt !== null) throw new TrainingError('ALREADY_TRACKED', 'This track is already marked as tracked.');
  if (action.kind === 'classify' && track.trackedAt === null) throw new TrainingError('TRACK_FIRST', 'Mark the track as tracked before recording an assessment.');
  if (action.kind === 'report' && !track.classification) throw new TrainingError('ASSESS_FIRST', 'Record a category and confidence before submitting a report.');
  if (action.kind === 'request_observation' && track.lastRequestedAt !== null && now - track.lastRequestedAt < TRAINING_RULES.requestCooldownSeconds) {
    throw new TrainingError('REQUEST_COOLDOWN', `Wait ${TRAINING_RULES.requestCooldownSeconds - (now - track.lastRequestedAt)} simulation seconds before requesting again.`);
  }
  return action;
}

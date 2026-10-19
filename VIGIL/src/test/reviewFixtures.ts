import { testEngine } from './fixtures';
import type { SessionRecord } from '../domain/types';

export function recordedExercise(sessionId = 'test-session'): SessionRecord {
  const e = testEngine({}, sessionId); e.start(); e.advance(1);
  e.action({ kind: 'select', trackId: 'T01' }); e.action({ kind: 'track', trackId: 'T01' });
  e.pause(); e.resume(); e.action({ kind: 'request_observation', trackId: 'T01' }); e.advance(4);
  e.action({ kind: 'classify', trackId: 'T01', category: 'unknown', confidence: 40 });
  e.action({ kind: 'report', trackId: 'T01', decision: 'observe', summary: 'Recorded evidence remains uncertain in this controlled fixture.' });
  e.advance(55); return e.completedRecord();
}

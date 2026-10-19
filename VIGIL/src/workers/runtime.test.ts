import { describe, expect, it } from 'vitest';
import type { ActiveSessionView, WorkerResponse } from '../domain/types';
import { testConfig } from '../test/fixtures';
import { SimulationRuntime } from './runtime';
function harness() {
  let now = 0; const messages: WorkerResponse[] = [];
  const runtime = new SimulationRuntime(m => messages.push(m), () => now, () => '2026-10-17T10:01:00.000Z');
  const configure = () => runtime.handle({ type: 'configure', config: testConfig(), profileId: 'trainee-01', sessionId: 'worker-test', startedAt: '2026-10-17T10:00:00.000Z' });
  const advance = (ms: number) => { now += ms; runtime.tick(); };
  const view = (): ActiveSessionView => { const m = messages.filter(m => m.type === 'view' || m.type === 'completed').at(-1); if (!m || !('view' in m)) throw new Error('Missing snapshot'); return m.view; };
  return { runtime, messages, configure, advance, view };
}
describe('module worker protocol and lifecycle', () => {
  it('responds with useful errors before configuration and for malformed commands', () => {
    const h = harness(); h.runtime.handle({ type: 'start' }); expect(h.messages.at(-1)).toMatchObject({ type: 'error', code: 'NOT_CONFIGURED' });
    h.runtime.handle({ type: 'configure', config: {} }); expect(h.messages.at(-1)).toMatchObject({ type: 'error', code: 'VALIDATION' });
    h.runtime.handle({ type: 'speed', value: 3 }); expect(h.messages.at(-1)).toMatchObject({ type: 'error', code: 'VALIDATION' });
  });
  it('never serializes the private answer key or rubric during an active exercise', () => {
    const h = harness(); h.configure(); h.runtime.handle({ type: 'start' }); h.advance(9000);
    for (const message of h.messages) if (message.type === 'view') {
      const s = JSON.stringify(message);
      for (const key of ['rubric', 'weights', 'origin', 'velocity', 'truthCategory', 'significant', 'degradation']) expect(s).not.toContain(`"${key}"`);
      expect(message.view.scenario).not.toHaveProperty('tracks');
    }
    expect(h.view().tracks.length).toBe(1);
  });
  it('accounts for partial active seconds but not paused wall-clock time', () => {
    const h = harness(); h.configure(); h.runtime.handle({ type: 'start' }); h.advance(1500); h.runtime.handle({ type: 'pause' });
    h.advance(30000); expect(h.view().elapsedSeconds).toBe(1); h.runtime.handle({ type: 'resume' }); h.advance(500);
    expect(h.view().elapsedSeconds).toBe(2); h.runtime.handle({ type: 'speed', value: 4 }); h.advance(250); expect(h.view().elapsedSeconds).toBe(3);
  });
  it('publishes one terminal record, identical to its public recorded log, only at termination', () => {
    const h = harness(); h.configure(); h.runtime.handle({ type: 'start' }); h.advance(60000); h.advance(60000);
    const completed = h.messages.filter(m => m.type === 'completed'); expect(completed).toHaveLength(1);
    if (completed[0].type === 'completed') { expect(completed[0].record.events).toEqual(completed[0].view.events); expect(completed[0].record.status).toBe('completed'); expect(completed[0].record.scenario.tracks).toHaveLength(1); }
  });
  it('keeps an active exercise after a rejected reconfiguration or action', () => {
    const h = harness(); h.configure(); h.runtime.handle({ type: 'start' }); h.advance(1000); const before = h.view();
    h.configure(); expect(h.messages.at(-1)).toMatchObject({ type: 'error', code: 'ACTIVE_EXERCISE' });
    h.runtime.handle({ type: 'action', action: { kind: 'classify', trackId: 'T01', category: 'review', confidence: 80 } }); expect(h.messages.at(-1)).toMatchObject({ type: 'error', code: 'TRACK_FIRST' });
    expect(h.view()).toEqual(before); h.runtime.handle({ type: 'action', action: { kind: 'track', trackId: 'T01' } }); expect(h.view().tracks[0].trackedAt).toBe(1);
  });
  it('caps a long background timer delta at the exercise duration, not an invalid step', () => {
    const h = harness(); h.configure(); h.runtime.handle({ type: 'start' }); h.advance(1000 * 7200);
    expect(h.view().elapsedSeconds).toBe(60); expect(h.view().status).toBe('completed');
  });
});

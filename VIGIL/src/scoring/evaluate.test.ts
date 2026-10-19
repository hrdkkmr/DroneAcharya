import { describe, expect, it } from 'vitest';
import { testConfig, testEngine } from '../test/fixtures';
import { generateScenario } from '../engine/scenario';
import { evaluateSession } from './evaluate';
import type { SessionRecord, SimulationEvent } from '../domain/types';

function perfectRecord(): SessionRecord {
  const e = testEngine(); const truth = generateScenario(testConfig()).tracks[0].category;
  e.start(); e.advance(1); e.action({ kind: 'track', trackId: 'T01' }); e.advance(4);
  e.action({ kind: 'classify', trackId: 'T01', category: truth, confidence: 85 });
  e.action({ kind: 'report', trackId: 'T01', decision: truth === 'review' ? 'escalate' : 'log', summary: 'Two clear synthetic deliveries support this training assessment.' });
  e.advance(55); return e.completedRecord();
}

describe('deterministic baseline rubric', () => {
  it('awards the documented full-credit path without random scores', () => {
    const record = perfectRecord(); expect(record.evaluation.score).toBe(100); expect(record.evaluation.penaltyPoints).toBe(0);
    expect(record.evaluation.metrics.map(m => m.score)).toEqual([100,100,100,100,100,100]);
    expect(record.evaluation.tracks[0].detectionLatencySeconds).toBe(0);
    expect(evaluateSession(record.scenario, record.events)).toEqual(record.evaluation);
  });
  it('rewards appropriate early unknown/observe with exactly 95 baseline points', () => {
    const e = testEngine(); e.start(); e.advance(1); e.action({ kind: 'track', trackId: 'T01' });
    e.action({ kind: 'classify', trackId: 'T01', category: 'unknown', confidence: 40 });
    e.action({ kind: 'report', trackId: 'T01', decision: 'observe', summary: 'Only one clear delivery; more evidence is needed.' });
    e.advance(59); const result = e.completedRecord().evaluation;
    expect(result.score).toBe(95); expect(result.penaltyPoints).toBe(0); expect(result.metrics.find(m => m.key === 'classification')?.score).toBe(75);
    expect(result.metrics.find(m => m.key === 'uncertainty')?.score).toBe(100);
  });
  it('does not use observations delivered later to retrospectively justify certainty', () => {
    const e = testEngine(); e.start(); e.advance(1); e.action({ kind: 'track', trackId: 'T01' });
    e.action({ kind: 'classify', trackId: 'T01', category: 'review', confidence: 90 });
    e.action({ kind: 'report', trackId: 'T01', decision: 'escalate', summary: 'An intentionally unsupported certainty test report.' });
    e.advance(59); const r = e.completedRecord().evaluation;
    expect(r.tracks[0].clearEvidenceCount).toBe(1); expect(r.tracks[0].expectedDecision).toBe('observe');
    expect(r.findings.filter(f => f.appliedPenalty).map(f => [f.ruleId,f.points])).toEqual([['P1',4],['P2',8]]);
    expect(r.score).toBe(57.8);
  });
  it('penalizes a significant delivered track with no report once, not per observation', () => {
    const e = testEngine(); e.start(); e.advance(60); const r = e.completedRecord().evaluation;
    expect(r.score).toBe(0); expect(r.penaltyPoints).toBe(5);
    expect(r.findings.filter(f => f.ruleId === 'P3')).toHaveLength(1);
    expect(r.metrics.every(m => m.score === 0)).toBe(true);
  });
  it('handles zero delivered evidence and zero denominators without phantom missed tracks', () => {
    const e = testEngine({ delaySeconds: 8 }); e.start(); e.finish(); const r = e.completedRecord().evaluation;
    expect(r.score).toBe(0); expect(r.penaltyPoints).toBe(0); expect(r.comparable).toBe(false);
    expect(r.metrics.filter(m => m.key !== 'objectives').every(m => m.denominator === 0)).toBe(true);
    expect(r.findings.map(f => f.ruleId)).toEqual(['E0']);
    expect(r.tracks[0].firstObservedAt).toBeNull(); expect(r.tracks[0].missed).toBe(false);
  });
  it('excludes an unobserved hidden track from a mixed-evidence denominator and missed penalties', () => {
    const e = testEngine({ trackCount: 2 }); e.start(); e.advance(1); e.finish();
    const r = e.completedRecord().evaluation;
    expect(r.tracks).toHaveLength(2); expect(r.tracks.filter(t => t.firstObservedAt !== null)).toHaveLength(1);
    expect(r.metrics.filter(m => m.key !== 'objectives').every(m => m.denominator === 1)).toBe(true);
    const hidden = r.tracks.find(t => t.firstObservedAt === null)!;
    expect(hidden.missed).toBe(false);
    expect(r.findings.filter(f => f.appliedPenalty).every(f => f.trackId !== hidden.trackId)).toBe(true);
  });
  it('uses first delivery, not hidden spawn or capture, for detection latency', () => {
    const e = testEngine({ delaySeconds: 3 }); e.start(); e.advance(4); e.action({ kind: 'track', trackId: 'T01' }); e.advance(56);
    const t = e.completedRecord().evaluation.tracks[0]; expect(t.firstObservedAt).toBe(4); expect(t.detectionLatencySeconds).toBe(0);
  });
  it('applies documented detection/reporting windows with bounded results', () => {
    const e = testEngine(); e.start(); e.advance(31); e.action({ kind: 'track', trackId: 'T01' });
    e.action({ kind: 'classify', trackId: 'T01', category: 'unknown', confidence: 40 });
    e.advance(29); const r = e.completedRecord().evaluation;
    expect(r.metrics.find(m => m.key === 'detection')?.score).toBe(0); expect(r.metrics.find(m => m.key === 'reporting')?.score).toBe(0);
    expect(r.score).toBeGreaterThanOrEqual(0); expect(r.score).toBeLessThanOrEqual(100);
  });
  it('allows correction before the final report; a corrected assessment is evaluated', () => {
    const e = testEngine(); e.start(); e.advance(1); e.action({ kind: 'track', trackId: 'T01' });
    e.action({ kind: 'classify', trackId: 'T01', category: 'routine', confidence: 90 }); e.advance(4);
    e.action({ kind: 'classify', trackId: 'T01', category: 'review', confidence: 85 });
    e.action({ kind: 'report', trackId: 'T01', decision: 'escalate', summary: 'Corrected using two clear delivered observations.' }); e.advance(55);
    expect(e.completedRecord().evaluation.score).toBe(100); expect(e.completedRecord().evaluation.penaltyPoints).toBe(0);
  });
  it('respects configured zero weights and selected-objective denominators', () => {
    const e = testEngine({ objectives: ['detection'], weights: { detection: 100, classification: 0, uncertainty: 0, reporting: 0, decision: 0, objectives: 0 } });
    e.start(); e.advance(1); e.action({ kind: 'track', trackId: 'T01' }); e.advance(59);
    const r = e.completedRecord().evaluation; expect(r.weightedScore).toBe(100); expect(r.score).toBe(95);
    expect(r.metrics.find(m => m.key === 'objectives')?.denominator).toBe(1);
  });
  it('traces every deduction to real IDs and distinguishes component losses from penalties', () => {
    const e = testEngine(); e.start(); e.advance(60); const record = e.completedRecord(); const ids = new Set(record.events.map(e => e.id));
    for (const f of record.evaluation.findings) { expect(f.eventIds.length).toBeGreaterThan(0); expect(f.eventIds.every(id => ids.has(id))).toBe(true); }
    expect(record.evaluation.findings.some(f => !f.appliedPenalty)).toBe(true);
    expect(record.evaluation.findings.some(f => f.appliedPenalty)).toBe(true);
    expect(record.evaluation.score).toBe(Math.max(0, record.evaluation.weightedScore - record.evaluation.penaltyPoints));
  });

  it('awards only reporting completeness when the final report is more than 60s late', () => {
    const e = testEngine({ durationSeconds: 90 }); e.start(); e.advance(1); e.action({ kind: 'track', trackId: 'T01' });
    e.advance(64); e.action({ kind: 'classify', trackId: 'T01', category: 'review', confidence: 85 });
    e.action({ kind: 'report', trackId: 'T01', decision: 'escalate', summary: 'A complete but intentionally late synthetic report.' }); e.advance(25);
    expect(e.completedRecord().evaluation.metrics.find(m => m.key === 'reporting')?.score).toBe(40);
  });
  it('gives partial category credit to unknown with sufficient evidence without penalizing safe observation', () => {
    const e = testEngine(); e.start(); e.advance(1); e.action({ kind: 'track', trackId: 'T01' }); e.advance(4);
    e.action({ kind: 'classify', trackId: 'T01', category: 'unknown', confidence: 40 });
    e.action({ kind: 'report', trackId: 'T01', decision: 'observe', summary: 'More evidence requested despite two clear deliveries.' }); e.advance(55);
    const r = e.completedRecord().evaluation; expect(r.score).toBe(84.3); expect(r.penaltyPoints).toBe(0);
    expect(r.metrics.find(m => m.key === 'classification')?.score).toBe(50); expect(r.metrics.find(m => m.key === 'uncertainty')?.score).toBe(75);
  });
  it('gives half decision credit to continued observation instead of a supported training escalation', () => {
    const e = testEngine(); e.start(); e.advance(1); e.action({ kind: 'track', trackId: 'T01' }); e.advance(4);
    e.action({ kind: 'classify', trackId: 'T01', category: 'review', confidence: 85 });
    e.action({ kind: 'report', trackId: 'T01', decision: 'observe', summary: 'Continue observing instead of the supported review report.' }); e.advance(55);
    const r = e.completedRecord().evaluation; expect(r.metrics.find(m => m.key === 'decision')?.score).toBe(50); expect(r.penaltyPoints).toBe(0);
  });
  it('grades incorrect specific classifications and unjustified escalation against hidden truth', () => {
    const e = testEngine({ seed: 0 }); e.start(); e.advance(1); e.action({ kind: 'track', trackId: 'T01' }); e.advance(4);
    e.action({ kind: 'classify', trackId: 'T01', category: 'review', confidence: 85 });
    e.action({ kind: 'report', trackId: 'T01', decision: 'escalate', summary: 'Deliberately incorrect classification and escalation.' }); e.advance(55);
    const r = e.completedRecord().evaluation; expect(r.tracks[0].truthCategory).toBe('routine');
    expect(r.metrics.find(m => m.key === 'classification')?.score).toBe(0); expect(r.metrics.find(m => m.key === 'uncertainty')?.score).toBe(0);
    expect(r.findings.filter(f => f.appliedPenalty).map(f => f.ruleId)).toEqual(['P2']);
  });
  it('keeps partial aborts out of comparable results', () => {
    const e = testEngine(); e.start(); e.advance(5); e.finish(); expect(e.completedRecord().evaluation.comparable).toBe(false);
  });
});

describe('scoring-input error handling', () => {
  it.each(['duplicate-id','wrong-order','wrong-session','backwards-time','bad-observation','wrong-scenario','early-completed','after-finish','untracked-classification'])('rejects %s logs', kind => {
    const record = perfectRecord(); const events = structuredClone(record.events);
    if (kind === 'duplicate-id') events[1].id = events[0].id;
    if (kind === 'wrong-order') events[1].order = 99;
    if (kind === 'wrong-session') events[1].sessionId = 'other-session';
    if (kind === 'backwards-time') events[2].time = 0;
    if (kind === 'bad-observation' && events[1].type === 'observation') events[1].data.observation.confidence = 101;
    if (kind === 'wrong-scenario' && events[0].type === 'started') events[0].data.scenarioId = 'other';
    if (kind === 'early-completed') events[events.length - 1].time = 59;
    if (kind === 'after-finish') events.push({ ...events[0], order: events.length + 1, id: 'extra', time: 60 } as SimulationEvent);
    if (kind === 'untracked-classification') { const trackIndex = events.findIndex(e => e.type === 'action' && e.data.action.kind === 'track'); if (events[trackIndex].type === 'action') events[trackIndex].data.action = { kind: 'classify', trackId: 'T01', category: 'unknown', confidence: 40 }; }
    expect(() => evaluateSession(record.scenario, events)).toThrow();
  });
  it('rejects unfinished history and invalid numeric rubric rules', () => {
    const r = perfectRecord(); expect(() => evaluateSession(r.scenario, r.events.slice(0,-1))).toThrow();
    r.scenario.rubric.detectionWindowSeconds = 0; expect(() => evaluateSession(r.scenario, r.events)).toThrow('thresholds');
  });
});

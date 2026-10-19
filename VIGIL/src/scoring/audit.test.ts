import { describe, expect, it } from 'vitest';
import { testEngine } from '../test/fixtures';
import { evaluateSession } from './evaluate';
import type { EvaluationRubric, SessionRecord } from '../domain/types';

function unsupported(): SessionRecord {
  const e = testEngine(); e.start(); e.advance(1); e.action({kind:'track',trackId:'T01'});
  e.action({kind:'classify',trackId:'T01',category:'review',confidence:90});
  e.action({kind:'report',trackId:'T01',decision:'escalate',summary:'Controlled unsupported certainty and disposition fixture.'});
  e.advance(59); return e.completedRecord();
}
function supported(): SessionRecord {
  const e = testEngine(); e.start(); e.advance(1); e.action({kind:'track',trackId:'T01'}); e.advance(4);
  e.action({kind:'classify',trackId:'T01',category:'review',confidence:85});
  e.action({kind:'report',trackId:'T01',decision:'escalate',summary:'Two clear deliveries support the controlled final assessment.'});
  e.advance(55); return e.completedRecord();
}

describe('complete rubric-1 timing, evidence and audit gate', () => {
  it.each([[0,100],[5,100],[6,96],[17,52],[29,4],[30,0],[31,0]])('D1 latency %ss earns %s%% using the first delivered observation', (latency,score) => {
    const e = testEngine({durationSeconds:90}); e.start(); e.advance(1+latency); e.action({kind:'track',trackId:'T01'}); e.advance(89-latency);
    const r = e.completedRecord(); const metric = r.evaluation.metrics.find(m=>m.key==='detection')!;
    expect(metric.score).toBe(score); const trace = r.evaluation.tracks[0].metrics.find(m=>m.key==='detection')!;
    const anchor = r.events.find(event=>event.id===trace.anchorEventId)!;
    expect(anchor.type).toBe('action'); if(anchor.type==='action') expect(anchor.data.action.kind).toBe('track');
    expect(trace.eventIds).toContain(anchor.id); expect(trace.explanation).toContain(`${latency}s`);
  });
  it.each([[0,100],[15,100],[16,98.7],[30,80],[59,41.3],[60,40],[61,40]])('R1 report latency %ss earns %s%%, including completeness', (latency,score) => {
    const e = testEngine({durationSeconds:120}); e.start(); e.advance(1); e.action({kind:'track',trackId:'T01'});
    e.action({kind:'classify',trackId:'T01',category:'unknown',confidence:40}); e.advance(latency);
    e.action({kind:'report',trackId:'T01',decision:'observe',summary:'A complete controlled report at the requested boundary time.'}); e.advance(119-latency);
    expect(e.completedRecord().evaluation.metrics.find(m=>m.key==='reporting')?.score).toBe(score);
  });
  it.each([[70,false],[71,true]])('P1 certainty boundary %s has penalty=%s', (confidence,penalty) => {
    const e = testEngine(); e.start(); e.advance(1); e.action({kind:'track',trackId:'T01'}); e.action({kind:'classify',trackId:'T01',category:'review',confidence}); e.advance(59);
    expect(e.completedRecord().evaluation.findings.some(f=>f.ruleId==='P1')).toBe(penalty);
  });
  it.each([59,60])('clear-signal boundary %s respects the stored threshold and resolved cues', signal => {
    const record = supported(); const assessed = record.events.find(e=>e.type==='action'&&e.data.action.kind==='classify')!;
    for(const event of record.events) if(event.type==='observation'&&event.order<assessed.order) event.data.observation.confidence=signal;
    const r=evaluateSession(record.scenario,record.events);
    expect(r.tracks[0].clearEvidenceCount).toBe(signal===60?2:0); expect(r.findings.some(f=>f.ruleId==='P1')).toBe(signal<60);
  });
  it('unresolved cues do not count as clear just because signal confidence is high', () => {
    const record=supported(); for(const event of record.events) if(event.type==='observation') event.data.observation.motion='unresolved';
    const r=evaluateSession(record.scenario,record.events); expect(r.tracks[0].clearEvidenceCount).toBe(0); expect(r.findings.some(f=>f.ruleId==='P1')).toBe(true);
  });
  it('later evidence can support the report branch but never an earlier unsupported assessment', () => {
    const e=testEngine(); e.start(); e.advance(1); e.action({kind:'track',trackId:'T01'}); e.action({kind:'classify',trackId:'T01',category:'review',confidence:90}); e.advance(4);
    e.action({kind:'report',trackId:'T01',decision:'escalate',summary:'Later delivered evidence supports disposition, not earlier certainty.'}); e.advance(55);
    const record=e.completedRecord(); const r=record.evaluation;
    expect(r.findings.filter(f=>f.appliedPenalty).map(f=>f.ruleId)).toEqual(['P1']); expect(r.tracks[0].expectedDecision).toBe('escalate');
    const p1=r.findings.find(f=>f.ruleId==='P1')!; const anchor=record.events.find(e=>e.id===p1.anchorEventId)!;
    expect(p1.eventIds.every(id=>record.events.find(e=>e.id===id)!.order<=anchor.order)).toBe(true);
    expect(r.tracks[0].metrics.find(m=>m.key==='decision')!.eventIds.length).toBeGreaterThan(p1.eventIds.length);
  });
  it('only the corrected final assessment is scored; earlier mistakes remain replayable, not extra penalties', () => {
    const e=testEngine(); e.start(); e.advance(1); e.action({kind:'track',trackId:'T01'});
    for(const confidence of [80,90,100]) e.action({kind:'classify',trackId:'T01',category:'routine',confidence});
    e.action({kind:'classify',trackId:'T01',category:'unknown',confidence:30}); e.action({kind:'report',trackId:'T01',decision:'observe',summary:'Final correction to uncertainty before the report is allowed.'}); e.advance(59);
    const record=e.completedRecord(); expect(record.evaluation.penaltyPoints).toBe(0); expect(record.evaluation.score).toBe(95);
    const final=record.events.filter(e=>e.type==='action'&&e.data.action.kind==='classify').at(-1)!;
    expect(record.evaluation.tracks[0].metrics.find(m=>m.key==='classification')!.anchorEventId).toBe(final.id);
  });
  it('stores per-track credits with the eligible denominator, not submitted-action count', () => {
    const e=testEngine({trackCount:3}); e.start(); e.advance(1); e.action({kind:'track',trackId:'T01'}); e.advance(59);
    const record=e.completedRecord(); const n=record.evaluation.tracks.filter(t=>t.firstObservedAt!==null).length;
    const audits=record.evaluation.tracks.flatMap(t=>t.metrics).filter(m=>m.key==='detection');
    expect(audits).toHaveLength(n); for(const audit of audits) expect(audit.available).toBe(20/n);
    expect(audits.reduce((sum,a)=>sum+a.earned,0)).toBeCloseTo(20/n);
  });
  it('missing and excluded actions use actual termination, never a fictional missing-action ID', () => {
    const e=testEngine({trackCount:2}); e.start(); e.advance(1); e.finish(); const record=e.completedRecord(); const finish=record.events.at(-1)!;
    const eligible=record.evaluation.tracks.filter(t=>t.firstObservedAt!==null); const excluded=record.evaluation.tracks.filter(t=>t.firstObservedAt===null);
    expect(excluded).toHaveLength(1); expect(excluded[0].metrics).toEqual([]);
    for(const track of eligible) for(const trace of track.metrics) { expect(trace.anchorEventId).toBe(finish.id); expect(trace.eventIds).toContain(finish.id); }
    const p3=record.evaluation.findings.find(f=>f.ruleId==='P3')!; expect(p3.eventIds).toHaveLength(2); expect(p3.anchorEventId).toBe(finish.id);
  });
  it('explains a missing-report branch from termination-time evidence without awarding a report', () => {
    const e=testEngine(); e.start(); e.advance(5); e.action({kind:'track',trackId:'T01'}); e.action({kind:'classify',trackId:'T01',category:'review',confidence:85}); e.advance(55);
    const r=e.completedRecord().evaluation; expect(r.tracks[0].expectedDecision).toBe('escalate'); expect(r.tracks[0].actualDecision).toBeNull(); expect(r.metrics.find(m=>m.key==='decision')?.score).toBe(0);
  });
  it('keeps fractional penalties unrounded until aggregation and final clipping', () => {
    const record=unsupported(); record.scenario.rubric.unsupportedCertaintyPenalty=.04; record.scenario.rubric.unjustifiedEscalationPenalty=.04;
    const r=evaluateSession(record.scenario,record.events); expect(r.findings.filter(f=>f.appliedPenalty).map(f=>f.points)).toEqual([.04,.04]);
    expect(r.penaltyPoints).toBe(.1); expect(r.score).toBe(69.7);
    record.scenario.rubric.unsupportedCertaintyPenalty=100; record.scenario.rubric.unjustifiedEscalationPenalty=100;
    const clipped=evaluateSession(record.scenario,record.events); expect(clipped.penaltyPoints).toBe(200); expect(clipped.score).toBe(0);
  });
  it('uses configured stored thresholds in calculations and explanations, not hardcoded guide text', () => {
    const record=supported(); record.scenario.rubric.detectionGraceSeconds=0; record.scenario.rubric.detectionWindowSeconds=10;
    record.scenario.rubric.reportingGraceSeconds=2; record.scenario.rubric.reportingWindowSeconds=20; record.scenario.rubric.minimumClearObservations=3;
    const r=evaluateSession(record.scenario,record.events); const audits=r.tracks[0].metrics;
    expect(audits.find(m=>m.key==='detection')!.explanation).toContain('0s grace; 10s window');
    expect(audits.find(m=>m.key==='reporting')!.explanation).toContain('2s grace; 20s window'); expect(audits.find(m=>m.key==='uncertainty')!.explanation).toContain('3-delivery rule');
    expect(r.findings.find(f=>f.ruleId==='P1')!.reason).toContain('3 clear deliveries');
  });
  it('all rule-specific references/anchors exist and never cite later support for an action', () => {
    for(const record of [supported(),unsupported()]) {
      for(const trace of [...record.evaluation.findings,...record.evaluation.tracks.flatMap(t=>t.metrics)]) {
        const anchor=record.events.find(e=>e.id===trace.anchorEventId)!; expect(anchor).toBeDefined(); expect(trace.eventIds).toContain(anchor.id);
        for(const id of trace.eventIds) expect(record.events.find(e=>e.id===id)!.order).toBeLessThanOrEqual(anchor.order);
      }
      for(const metric of record.evaluation.metrics) { expect(metric.evidenceIds).toContain(metric.anchorEventId); expect(metric.evidenceIds.every(id=>record.events.some(e=>e.id===id))).toBe(true); }
    }
  });
});

describe('strict evaluation/log inputs for audit replay', () => {
  it.each(['missing-rule','string-rule','nan','infinity','negative-penalty','huge-penalty','fractional-count','invalid-threshold','invalid-window','unknown-field','mismatched-weights'])('rejects %s rubric rather than returning NaN/plausible score', kind => {
    const record=supported(); const r=record.scenario.rubric;
    if(kind==='missing-rule') delete (r as Partial<EvaluationRubric>).detectionGraceSeconds;
    if(kind==='string-rule') r.detectionGraceSeconds='five' as unknown as number;
    if(kind==='nan') r.reportingGraceSeconds=NaN;
    if(kind==='infinity') r.missedSignificantPenalty=Infinity;
    if(kind==='negative-penalty') r.unsupportedCertaintyPenalty=-1;
    if(kind==='huge-penalty') r.unjustifiedEscalationPenalty=101;
    if(kind==='fractional-count') r.minimumClearObservations=1.5;
    if(kind==='invalid-threshold') r.clearConfidenceThreshold=101;
    if(kind==='invalid-window') r.detectionWindowSeconds=r.detectionGraceSeconds;
    if(kind==='unknown-field') Object.assign(r,{bonus:50});
    if(kind==='mismatched-weights') {r.weights.detection=25;r.weights.classification=15;}
    expect(()=>evaluateSession(record.scenario,record.events)).toThrow();
  });
  it('rejects duplicate track/capture evidence even with a different observation ID', () => {
    const record=supported(); const duplicate=structuredClone(record.events.find(e=>e.type==='observation')!); duplicate.id='duplicate-event';
    if(duplicate.type==='observation') duplicate.data.observation.id='duplicate-return';
    record.events.splice(2,0,duplicate); record.events.forEach((event,i)=>event.order=i+1);
    expect(()=>evaluateSession(record.scenario,record.events)).toThrow('unique');
  });
  it('rejects a coalesced requested capture mislabelled as scheduled', () => {
    const e=testEngine();e.start();e.advance(3);e.action({kind:'request_observation',trackId:'T01'});e.advance(57);const record=e.completedRecord();
    const event=record.events.find(e=>e.type==='observation'&&e.data.observation.capturedAt===5)!;
    if(event.type!=='observation') throw new Error('fixture'); expect(event.data.observation.source).toBe('requested');event.data.observation.source='scheduled';
    expect(()=>evaluateSession(record.scenario,record.events)).toThrow('source');
  });
  it('rejects a physically impossible model delay without repairing event time/order', () => {
    const record=supported();const first=structuredClone(record.events.find(e=>e.type==='observation')!);
    if(first.type!=='observation') throw new Error('fixture');first.time=21;first.data.observation.deliveredAt=21;
    const events=[record.events[0],first,...record.events.filter(e=>e.time>21)];events.forEach((event,i)=>event.order=i+1);
    expect(()=>evaluateSession(record.scenario,events)).toThrow('Observation');
  });
});

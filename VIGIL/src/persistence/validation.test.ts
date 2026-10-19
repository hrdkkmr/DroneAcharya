import { describe,it,expect } from 'vitest';
import { historyRecord } from '../test/historyFixtures';
import { INITIAL_PROFILES, makeBundle, parseBundle, validateStoredRecord, validateBundle, MAX_IMPORT_BYTES, mergeImmutable, validateProfile } from './validation';

describe('portable format-1 integrity boundaries',()=>{
  it('round-trips actual complete/aborted records without changing scenario, events, evaluation or version',()=>{const a=historyRecord('a'),b=historyRecord('b','aborted');const bundle=makeBundle(INITIAL_PROFILES,[a,b]);expect(parseBundle(JSON.stringify(bundle))).toEqual(bundle);expect(bundle.schemaVersion).toBe(3);expect(bundle.formatVersion).toBe(1);});
  it.each([
    ['unsupported envelope', (r:ReturnType<typeof makeBundle>)=>{(r as unknown as {formatVersion:number}).formatVersion=2;}],
    ['unknown field',(r:ReturnType<typeof makeBundle>)=>{Object.assign(r,{answers:[]});}],
    ['old record schema',(r:ReturnType<typeof makeBundle>)=>{Object.assign(r.sessions[0],{schemaVersion:2});}],
    ['noncanonical event text',(r:ReturnType<typeof makeBundle>)=>{const e=r.sessions[0].events.find(e=>e.type==='action'&&e.data.action.kind==='report');if(e?.type==='action'&&e.data.action.kind==='report')e.data.action.summary='  '+e.data.action.summary;}],
    ['changed score',(r:ReturnType<typeof makeBundle>)=>{r.sessions[0].evaluation.score=12.3;}],
    ['changed raw audit',(r:ReturnType<typeof makeBundle>)=>{r.sessions[0].evaluation.metrics[0].earned+=1;}],
    ['changed truth',(r:ReturnType<typeof makeBundle>)=>{r.sessions[0].scenario.tracks[0].category='background';}],
    ['changed seed',(r:ReturnType<typeof makeBundle>)=>{r.sessions[0].scenario.seed+=1;}],
    ['changed rubric',(r:ReturnType<typeof makeBundle>)=>{r.sessions[0].scenario.rubric.certaintyThreshold+=1;}],
    ['orphan profile',(r:ReturnType<typeof makeBundle>)=>{r.sessions[0].profileId='absent';}],
    ['duplicate session',(r:ReturnType<typeof makeBundle>)=>{r.sessions.push(structuredClone(r.sessions[0]));}],
    ['duplicate profile name',(r:ReturnType<typeof makeBundle>)=>{r.profiles[1].name=r.profiles[0].name.toUpperCase();}],
    ['end before start',(r:ReturnType<typeof makeBundle>)=>{r.sessions[0].endedAt='2026-10-16T10:00:00.000Z';}],
    ['missing termination',(r:ReturnType<typeof makeBundle>)=>{r.sessions[0].events.pop();}],
    ['foreign identity',(r:ReturnType<typeof makeBundle>)=>{r.sessions[0].id='foreign';}],
    ['false outcome',(r:ReturnType<typeof makeBundle>)=>{r.sessions[0].status='aborted';}],
    ['false elapsed',(r:ReturnType<typeof makeBundle>)=>{r.sessions[0].elapsedSeconds=30;}],
    ['out-of-order event',(r:ReturnType<typeof makeBundle>)=>{r.sessions[0].events[2].order=99;}],
    ['future delivery',(r:ReturnType<typeof makeBundle>)=>{const e=r.sessions[0].events.find(e=>e.type==='observation');if(e?.type==='observation')e.data.observation.capturedAt=e.time+1;}],
    ['dangling evaluator anchor',(r:ReturnType<typeof makeBundle>)=>{r.sessions[0].evaluation.metrics[0].anchorEventId='invented';}],
    ['event count limit',(r:ReturnType<typeof makeBundle>)=>{r.sessions[0].events=Array.from({length:5001},()=>r.sessions[0].events[0]);}],
    ['unbounded identity',(r:ReturnType<typeof makeBundle>)=>{r.sessions[0].id='../invalid';}],
    ['unbounded weight',(r:ReturnType<typeof makeBundle>)=>{r.sessions[0].scenario.config.weights.detection=Infinity;}],
  ])('rejects %s instead of repairing or accepting it',(_label,change)=>{const bundle=makeBundle(INITIAL_PROFILES,[historyRecord()]);change(bundle);expect(()=>validateBundle(bundle)).toThrow();});
  it('rejects malformed/empty/oversized input before mutation',()=>{expect(()=>parseBundle('{')).toThrow('valid JSON');expect(()=>parseBundle('')).toThrow();expect(()=>parseBundle(' '.repeat(MAX_IMPORT_BYTES+1))).toThrow('20 MiB');expect(()=>validateBundle({})).toThrow();});
  it('requires canonical anonymous names and dates, rejecting controls and extra fields',()=>{expect(()=>validateProfile({...INITIAL_PROFILES[0],name:' Alpha '})).toThrow();expect(()=>validateProfile({...INITIAL_PROFILES[0],name:'A\nB'})).toThrow();expect(()=>validateProfile({...INITIAL_PROFILES[0],createdAt:'yesterday'})).toThrow();expect(()=>validateProfile({...INITIAL_PROFILES[0],email:'x@y.test'})).toThrow();});
  it('deduplicates immutable equality but never overwrites a same-ID difference',()=>{const record=historyRecord();expect(mergeImmutable([record],[structuredClone(record)])).toHaveLength(1);expect(()=>mergeImmutable([record],[{...record,endedAt:'2026-10-17T11:00:00.000Z'}])).toThrow('Conflicting');});
  it('rejects null evaluation with a useful score-validation error rather than a rendering crash',()=>{const r=historyRecord();expect(()=>validateStoredRecord({...r,evaluation:null})).toThrow('Stored score or audit');});
});

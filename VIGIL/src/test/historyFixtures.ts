import { SimulationEngine } from '../engine/SimulationEngine';
import { testConfig } from './fixtures';
import type { SessionRecord, TraineeProfile } from '../domain/types';
import { INITIAL_PROFILES } from '../persistence/validation';
export function historyRecord(id='history-a',kind:'perfect'|'unknown'|'none'|'aborted'='perfect',profileId='trainee-01'):SessionRecord {
  const e=new SimulationEngine(testConfig(),{sessionId:id,profileId,startedAt:'2026-10-17T10:00:00.000Z'},()=>'2026-10-17T10:01:00.000Z');e.start();
  if(kind==='aborted'){e.finish();return e.completedRecord();}
  if(kind==='none'){e.advance(60);return e.completedRecord();}
  e.advance(1);e.action({kind:'track',trackId:'T01'});
  if(kind==='perfect')e.advance(4);
  e.action({kind:'classify',trackId:'T01',category:kind==='perfect'?'review':'unknown',confidence:kind==='perfect'?70:40});
  e.action({kind:'report',trackId:'T01',decision:kind==='perfect'?'escalate':'observe',summary:'Actual controlled test-engine exercise, not initialized product history.'});e.advance(kind==='perfect'?55:59);return e.completedRecord();
}
export function anonymousProfile(id='cadet-a',name='Cadet Alpha'):TraineeProfile{return {...structuredClone(INITIAL_PROFILES[0]),id,name};}

import { SimulationEngine } from '../engine/SimulationEngine';
import { generateScenario } from '../engine/scenario';
import { clearObservations } from '../engine/evidence';
import { testConfig } from './fixtures';
import type { ScenarioConfig, SessionRecord } from '../domain/types';

export type PracticeStyle = 'strong' | 'perfect' | 'none' | 'late-track' | 'late-report' | 'uncertain-specific' | 'wrong-category' | 'wrong-branch' | 'aborted';
/** Actual engine/evaluator records for controlled policy tests only. Never initialized in the app. */
export function practiceRecord(order=1, style:PracticeStyle='strong', patch:Partial<ScenarioConfig>={}, profileId='trainee-01'):SessionRecord {
  const config=testConfig({seed:order,...patch});
  const date=new Date(Date.UTC(2026,9,17,10,0,order)).toISOString();
  const engine=new SimulationEngine(config,{sessionId:`practice-${profileId}-${order}-${style}`,profileId,startedAt:date},()=>date);
  const definition=generateScenario(config);engine.start();
  if(style==='aborted'){engine.finish();return engine.completedRecord();}
  if(style==='none'){engine.advance(config.durationSeconds);return engine.completedRecord();}
  while(!engine.getView().tracks.length&&engine.clockState().elapsedSeconds<config.durationSeconds-1)engine.advance(1);
  const track=engine.getView().tracks[0];
  if(!track){engine.advance(config.durationSeconds-engine.clockState().elapsedSeconds);return engine.completedRecord();}
  if(style==='late-track')engine.advance(Math.min(30,config.durationSeconds-engine.clockState().elapsedSeconds-1));
  engine.action({kind:'track',trackId:track.id});
  const truth=definition.tracks.find(t=>t.id===track.id)!.category;
  const strongAssessment=style==='perfect'||style==='late-report'||style==='wrong-category';
  if(strongAssessment)while(clearObservations(engine.getView().tracks[0].observations,definition.rubric).length<2&&engine.clockState().elapsedSeconds<config.durationSeconds-2)engine.advance(1);
  const isSpecific=strongAssessment||style==='uncertain-specific';
  const category=style==='wrong-category'?(truth==='routine'?'review':'routine'):isSpecific?truth:'unknown';
  engine.action({kind:'classify',trackId:track.id,category,confidence:isSpecific?70:40});
  if(style==='late-report')engine.advance(config.durationSeconds-engine.clockState().elapsedSeconds-1);
  const hasClear=clearObservations(engine.getView().tracks[0].observations,definition.rubric).length>=2;
  const expected=category==='unknown'||!hasClear?'observe':truth==='review'?'escalate':'log';
  engine.action({kind:'report',trackId:track.id,decision:style==='wrong-branch'?'escalate':expected,summary:'Actual controlled engine exercise for policy verification. Not pre-populated training history.'});
  engine.advance(config.durationSeconds-engine.clockState().elapsedSeconds);
  return engine.completedRecord();
}

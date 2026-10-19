import { SKILLS } from '../domain/config';
import type { SessionRecord, Skill } from '../domain/types';

export interface DescriptiveSummary {
  saved:number; completed:number; aborted:number; noncomparable:number; eligible:number;
  meanScore:number|null; minimumScore:number|null; maximumScore:number|null;
  components:Record<Skill,number|null>;
  detection:{mean:number|null;n:number;missing:number};
  reporting:{mean:number|null;n:number;missing:number};
  trend:SessionRecord[];
  difficulties:{level:number;n:number;mean:number|null}[];
}
const mean=(values:readonly number[])=>values.length?values.reduce((a,b)=>a+b,0)/values.length:null;
/** Descriptive only: saved, completed, comparable attempts; never impute missing latency as zero. */
export function summarizeHistory(records:readonly SessionRecord[],savedIds:ReadonlySet<string>,profileId?:string):DescriptiveSummary {
  const saved=records.filter(s=>savedIds.has(s.id)&&(!profileId||s.profileId===profileId));
  const eligible=saved.filter(s=>s.status==='completed'&&s.evaluation.comparable);
  const detection:number[]=[];const reporting:number[]=[];let missingDetection=0;let missingReport=0;
  for(const record of eligible)for(const track of record.evaluation.tracks.filter(t=>t.firstObservedAt!==null)){
    if(track.detectionLatencySeconds===null)missingDetection++;else detection.push(track.detectionLatencySeconds);
    const report=record.events.find(e=>e.type==='action'&&e.data.action.kind==='report'&&e.data.action.trackId===track.trackId);
    if(report)reporting.push(report.time-track.firstObservedAt!);else missingReport++;
  }
  const scores=eligible.map(s=>s.evaluation.score);
  return {
    saved:saved.length,completed:saved.filter(s=>s.status==='completed').length,aborted:saved.filter(s=>s.status==='aborted').length,noncomparable:saved.filter(s=>s.status==='completed'&&!s.evaluation.comparable).length,eligible:eligible.length,
    meanScore:mean(scores),minimumScore:scores.length?Math.min(...scores):null,maximumScore:scores.length?Math.max(...scores):null,
    components:Object.fromEntries(SKILLS.map(key=>[key,mean(eligible.map(s=>s.evaluation.metrics.find(m=>m.key===key)!.score))])) as Record<Skill,number|null>,
    detection:{mean:mean(detection),n:detection.length,missing:missingDetection},reporting:{mean:mean(reporting),n:reporting.length,missing:missingReport},
    trend:[...eligible].sort((a,b)=>Date.parse(a.endedAt)-Date.parse(b.endedAt)||a.id.localeCompare(b.id)),
    difficulties:[1,2,3,4,5].map(level=>{const values=eligible.filter(s=>s.scenario.config.difficulty===level).map(s=>s.evaluation.score);return {level,n:values.length,mean:mean(values)};}),
  };
}
export function compareRecords(a:SessionRecord,b:SessionRecord){
  const canCompare=a.id!==b.id&&a.status==='completed'&&b.status==='completed'&&a.evaluation.comparable&&b.evaluation.comparable;
  const keys=['exerciseType','environment','lighting','weather','difficulty','trackCount','trafficPattern','reliability','noise','delaySeconds','durationSeconds'] as const;
  const differences=keys.filter(key=>a.scenario.config[key]!==b.scenario.config[key]);
  const weightsDiffer=Object.keys(a.scenario.config.weights).some(key=>a.scenario.config.weights[key as keyof typeof a.scenario.config.weights]!==b.scenario.config.weights[key as keyof typeof b.scenario.config.weights]);
  const objectivesDiffer=[...a.scenario.config.objectives].sort().join(',')!==[...b.scenario.config.objectives].sort().join(',');
  return {canCompare,delta:canCompare?b.evaluation.score-a.evaluation.score:null,differentConditions:differences.length>0||weightsDiffer||objectivesDiffer};
}

import { z } from 'zod';
import { cloneConfig, PRESETS, scenarioConfigSchema } from '../domain/config';
import { simulationEventSchema } from '../domain/events';
import { SCHEMA_VERSION, type HistoryMeta, type SessionExport, type SessionRecord, type TraineeProfile, type WorkspacePreferences } from '../domain/types';
import { canonicalJson } from '../engine/random';
import { generateScenario } from '../engine/scenario';
import { evaluateSession } from '../scoring/evaluate';
import { createReplayTimeline } from '../replay/replay';

export const PORTABLE_FORMAT = 'vigil-session-export' as const;
export const MAX_IMPORT_BYTES = 20 * 1024 * 1024;
export const MAX_RECORD_BYTES = 2 * 1024 * 1024;
export const MAX_IMPORT_SESSIONS = 500;
export const MAX_PROFILES = 500;
const id = z.string().regex(/^[A-Za-z0-9][A-Za-z0-9._:-]{0,99}$/, 'Use a bounded stable identifier.');
const iso = z.string().datetime({ offset: true });
const cleanText = (min:number,max:number) => z.string().min(min).max(max).refine(s=>s===s.trim()&&!/[\u0000-\u001f\u007f]/.test(s),'Use trimmed text without control characters.');
export const profileSchema = z.object({ schemaVersion:z.literal(SCHEMA_VERSION), id, name:cleanText(3,24), unit:cleanText(1,60), createdAt:iso }).strict();
export const preferencesSchema = z.object({config:scenarioConfigSchema,profileId:id,selectedSessionId:id.nullable()}).strict();
export const metaSchema = z.object({key:z.literal('workspace'),version:z.literal(1),epoch:id,revision:z.number().int().nonnegative(),preferences:preferencesSchema}).strict();
export const INITIAL_PROFILES: TraineeProfile[] = [1,2,3].map(n=>({schemaVersion:SCHEMA_VERSION,id:`trainee-${String(n).padStart(2,'0')}`,name:`Trainee ${String(n).padStart(2,'0')}`,unit:'Demonstration unit',createdAt:'2026-10-17T00:00:00.000Z'}));
export function initialPreferences(): WorkspacePreferences { return {config:cloneConfig(PRESETS[0].config),profileId:INITIAL_PROFILES[0].id,selectedSessionId:null}; }
export function initialMeta(): HistoryMeta { return {key:'workspace',version:1,epoch:crypto.randomUUID(),revision:0,preferences:initialPreferences()}; }
export const sameData = (a:unknown,b:unknown) => canonicalJson(a) === canonicalJson(b);
export const bytes = (text:string) => new TextEncoder().encode(text).byteLength;
export function errorMessage(cause:unknown):string {
  if(cause instanceof z.ZodError)return 'Invalid or unsupported data: '+cause.issues.slice(0,3).map(issue=>`${issue.path.join('.')||'file'}: ${issue.message}`).join('; ')+(cause.issues.length>3?` (${cause.issues.length} validation issues total)`:'');
  return cause instanceof Error ? cause.message : 'The local history operation failed.';
}
export function validateProfile(raw:unknown):TraineeProfile { return profileSchema.parse(raw); }

const recordSchema = z.object({
  schemaVersion:z.literal(SCHEMA_VERSION),id,profileId:id,startedAt:iso,endedAt:iso,status:z.enum(['completed','aborted']),elapsedSeconds:z.number().int().min(0).max(300),
  scenario:z.object({schemaVersion:z.literal(SCHEMA_VERSION),generatorVersion:z.literal('generator-2'),sensorVersion:z.literal('sensor-2'),id,seed:z.number().int().min(0).max(4294967295),config:scenarioConfigSchema,tracks:z.array(z.unknown()).min(1).max(8),degradation:z.unknown(),rubric:z.unknown()}).strict(),
  events:z.array(simulationEventSchema).min(2).max(5000),evaluation:z.unknown(),
}).strict();

/** Consistency validation, not an authenticity certificate. Never used to regenerate replay. */
export function validateStoredRecord(raw:unknown):SessionRecord {
  if (bytes(JSON.stringify(raw))>MAX_RECORD_BYTES) throw new Error('A single report exceeds the 2 MiB validation limit.');
  const parsed=recordSchema.parse(raw);
  if(!sameData(parsed,raw))throw new Error('Recorded fields must already be canonical. No event content was trimmed or repaired.');
  if(Date.parse(parsed.endedAt)<Date.parse(parsed.startedAt))throw new Error('The end date cannot precede the start date.');
  const generated=generateScenario(parsed.scenario.config);
  if(!sameData(parsed.scenario,generated))throw new Error('Scenario identity, seed, hidden definition or declared rubric does not match generator-2 / sensor-2. No regeneration or repair was substituted.');
  const record=parsed as SessionRecord;
  const computed=evaluateSession(record.scenario,record.events);
  if(!sameData(record.evaluation,computed))throw new Error('Stored score or audit does not match the single evaluator applied to the recorded events.');
  createReplayTimeline(record);
  return structuredClone(record);
}

export function assertUniqueProfiles(profiles:readonly TraineeProfile[]) {
  if(profiles.length>MAX_PROFILES)throw new Error(`Local history supports at most ${MAX_PROFILES} anonymous profiles.`);
  const ids=new Set<string>();const names=new Set<string>();
  for(const profile of profiles) { const name=profile.name.toLocaleLowerCase('en');if(ids.has(profile.id)||names.has(name))throw new Error('Profile identifiers and anonymous names must be unique.');ids.add(profile.id);names.add(name); }
}
export function mergeImmutable<T extends {id:string}>(existing:readonly T[],incoming:readonly T[]):T[] {
  const map=new Map(existing.map(value=>[value.id,value]));
  for(const value of incoming) { const prior=map.get(value.id);if(prior&&!sameData(prior,value))throw new Error(`Conflicting record ID ${value.id}. Existing data was not overwritten.`);map.set(value.id,value); }
  return [...map.values()];
}
const bundleSchema=z.object({format:z.literal(PORTABLE_FORMAT),formatVersion:z.literal(1),schemaVersion:z.literal(SCHEMA_VERSION),exportedAt:iso,profiles:z.array(profileSchema).min(1).max(MAX_PROFILES),sessions:z.array(z.unknown()).max(MAX_IMPORT_SESSIONS)}).strict();
export function validateBundle(raw:unknown):SessionExport {
  if(bytes(JSON.stringify(raw))>MAX_IMPORT_BYTES)throw new Error('Import exceeds the 20 MiB limit.');
  const parsed=bundleSchema.parse(raw);assertUniqueProfiles(parsed.profiles);const sessions=parsed.sessions.map(validateStoredRecord);const ids=new Set<string>();
  for(const record of sessions) { if(ids.has(record.id))throw new Error('Duplicate session ID inside the file.');ids.add(record.id);if(!parsed.profiles.some(p=>p.id===record.profileId))throw new Error('Every session must reference a profile included in this file.'); }
  return {...parsed,sessions};
}
export function parseBundle(text:string):SessionExport {
  if(bytes(text)>MAX_IMPORT_BYTES)throw new Error('Import exceeds the 20 MiB limit. Export fewer sessions at a time.');
  let raw:unknown;try{raw=JSON.parse(text);}catch{throw new Error('This is not valid JSON. Choose a VIGIL format-1 backup.');}
  return validateBundle(raw);
}
export function makeBundle(profiles:readonly TraineeProfile[],sessions:readonly SessionRecord[],now=new Date().toISOString()):SessionExport {
  const result=validateBundle({format:PORTABLE_FORMAT,formatVersion:1,schemaVersion:SCHEMA_VERSION,exportedAt:now,profiles:[...profiles],sessions:[...sessions]});
  if(bytes(JSON.stringify(result))>MAX_IMPORT_BYTES)throw new Error('Backup exceeds 20 MiB. Export individual reports instead.');
  return result;
}

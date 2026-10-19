import { scenarioConfigSchema } from '../domain/config';
import type { HistoryRepository, LoadedHistory, QuarantinedEntry, ScenarioConfig, SessionExport, SessionRecord, TraineeProfile, WorkspacePreferences } from '../domain/types';
import { assertUniqueProfiles, errorMessage, INITIAL_PROFILES, initialPreferences, mergeImmutable, sameData, validateBundle, validateProfile } from './validation';
import { HistoryResetConflict } from './repository';

export const HISTORY_RELOAD_NOTICE='Saved history changed in another tab. Reload saved history to include those records.';
export interface HistorySnapshot {
  needsReload:boolean;
  phase:'loading'|'saved'|'saving'|'unavailable';
  busy:'import'|'reset'|'reload'|null;
  profiles:TraineeProfile[];
  sessions:SessionRecord[];
  preferences:WorkspacePreferences;
  savedSessionIds:ReadonlySet<string>;
  quarantined:QuarantinedEntry[];
  pending:number;
  invalidDraft:boolean;
  error:string|null;
  info:string|null;
}
const ordered=(sessions:readonly SessionRecord[])=>[...sessions].sort((a,b)=>Date.parse(b.endedAt)-Date.parse(a.endedAt)||a.id.localeCompare(b.id));

/** External state machine: one serial writer, transaction acknowledgements, no live simulation. */
export class HistoryStore {
  private state:HistorySnapshot={needsReload:false,phase:'loading',busy:null,profiles:structuredClone(INITIAL_PROFILES),sessions:[],preferences:initialPreferences(),savedSessionIds:new Set(),quarantined:[],pending:0,invalidDraft:false,error:null,info:null};
  private listeners=new Set<()=>void>();
  private pendingProfiles=new Map<string,TraineeProfile>();
  private pendingSessions=new Map<string,SessionRecord>();
  private epoch:string|null=null;
  private metaVersion=0;
  private savedMetaVersion=0;
  private validConfig=this.state.preferences.config;
  private interacted=false;
  private working=false;
  private work:Promise<void>=Promise.resolve();
  private initialization:Promise<void>|null=null;
  private channel:BroadcastChannel|null=null;
  private stale=false;
  private readonly client=crypto.randomUUID();
  constructor(private readonly repository:HistoryRepository){}
  getSnapshot=()=>this.state;
  subscribe=(listener:()=>void)=>{
    this.listeners.add(listener);
    if(!this.channel&&typeof BroadcastChannel!=='undefined'){
      try { this.channel=new BroadcastChannel('vigil-history-v1'); } catch { this.channel=null; }
      if(this.channel)this.channel.onmessage=event=>{
        const data=event.data as {source?:string;epoch?:string;kind?:string};if(data.source===this.client||typeof data.epoch!=='string')return;
        if(this.epoch&&data.epoch!==this.epoch){this.stale=true;this.publish({phase:'unavailable',error:new HistoryResetConflict().message,savedSessionIds:new Set(),info:null});}
        else this.publish({needsReload:true,info:HISTORY_RELOAD_NOTICE});
      };
    }
    return ()=>{this.listeners.delete(listener);if(!this.listeners.size){this.channel?.close();this.channel=null;}};
  };
  private publish(patch:Partial<HistorySnapshot>={}){
    this.state={...this.state,...patch,pending:this.pendingProfiles.size+this.pendingSessions.size+(this.metaVersion!==this.savedMetaVersion?1:0)};
    for(const listener of this.listeners)listener();
  }
  private failed(cause:unknown){
    if(cause instanceof HistoryResetConflict){this.stale=true;this.publish({phase:'unavailable',error:cause.message,savedSessionIds:new Set()});}
    else this.publish({phase:'unavailable',error:errorMessage(cause)});
  }
  private notify(kind:'changed'|'reset'){this.channel?.postMessage({source:this.client,epoch:this.epoch,kind});}
  private mutable(){if(this.state.phase==='loading'||this.state.busy)throw new Error('Wait for the local history operation to finish.');}
  private persistedPreferences():WorkspacePreferences{return {...this.state.preferences,config:structuredClone(this.validConfig)};}
  private applyLoaded(data:LoadedHistory,preserve:boolean){
    if(this.epoch!==null&&this.epoch!==data.meta.epoch)throw new HistoryResetConflict();
    const localProfiles=preserve?this.state.profiles:[...this.pendingProfiles.values()];
    const localSessions=preserve?this.state.sessions:[...this.pendingSessions.values()];
    const profiles=mergeImmutable(data.profiles,localProfiles);assertUniqueProfiles(profiles);
    const sessions=mergeImmutable(data.sessions,localSessions);
    // A corrupt/missing stored copy must not destroy the previously valid in-memory report.
    for(const p of localProfiles)if(!data.profiles.some(v=>v.id===p.id))this.pendingProfiles.set(p.id,p);
    for(const r of localSessions)if(!data.sessions.some(v=>v.id===r.id))this.pendingSessions.set(r.id,r);
    for(const p of data.profiles)if(this.pendingProfiles.has(p.id)&&sameData(this.pendingProfiles.get(p.id),p))this.pendingProfiles.delete(p.id);
    for(const s of data.sessions)if(this.pendingSessions.has(s.id)&&sameData(this.pendingSessions.get(s.id),s))this.pendingSessions.delete(s.id);
    this.epoch=data.meta.epoch;
    const available=profiles.length?profiles:structuredClone(INITIAL_PROFILES);
    const preferred=preserve?this.persistedPreferences():data.meta.preferences;
    const displayConfig=preserve?this.state.preferences.config:preferred.config;
    const invalidDraft=preserve&&this.state.invalidDraft;
    const profileId=available.some(p=>p.id===preferred.profileId)?preferred.profileId:available[0].id;
    const selectedSessionId=sessions.some(s=>s.id===preferred.selectedSessionId)?preferred.selectedSessionId:null;
    this.validConfig=preferred.config;
    if(!profiles.length)for(const p of available)this.pendingProfiles.set(p.id,p);
    this.publish({profiles:available,sessions:ordered(sessions),preferences:{...preferred,config:displayConfig,profileId,selectedSessionId},savedSessionIds:new Set(data.sessions.map(s=>s.id)),quarantined:data.quarantined,phase:'saved',needsReload:false,error:null,invalidDraft,info:data.quarantined.length?`${data.quarantined.length} stored entr${data.quarantined.length===1?'y was':'ies were'} quarantined. Valid history is available; invalid data was not deleted.`:null});
  }
  initialize():Promise<void>{
    if(!this.initialization)this.initialization=(async()=>{try{this.applyLoaded(await this.repository.load(),false);}catch(cause){this.failed(cause);}})();
    return this.initialization;
  }
  private schedule(){
    if(this.working||this.state.busy||this.state.error||!this.epoch)return;
    if(!this.pendingProfiles.size&&!this.pendingSessions.size&&this.metaVersion===this.savedMetaVersion)return;
    this.working=true;this.publish({phase:'saving'});
    this.work=(async()=>{
      try{
        while(this.pendingProfiles.size||this.pendingSessions.size||this.metaVersion!==this.savedMetaVersion){
          const profiles=[...this.pendingProfiles.values()];const sessions=[...this.pendingSessions.values()];const version=this.metaVersion;
          await this.repository.commit(this.epoch!,{profiles,sessions,preferences:this.persistedPreferences()});
          if(this.stale)throw new HistoryResetConflict();
          for(const p of profiles)if(this.pendingProfiles.get(p.id)===p)this.pendingProfiles.delete(p.id);
          for(const s of sessions)if(this.pendingSessions.get(s.id)===s)this.pendingSessions.delete(s.id);
          this.savedMetaVersion=version;this.publish({savedSessionIds:new Set([...this.state.savedSessionIds,...sessions.map(s=>s.id)])});this.notify('changed');
        }
        this.publish({phase:'saved',error:null});
      }catch(cause){this.failed(cause);}
      finally{this.working=false;this.schedule();}
    })();
  }
  async settled(){for(;;){const work=this.work;await work;if(work===this.work)break;}}
  setConfig(config:ScenarioConfig){
    this.mutable();this.interacted=true;const result=scenarioConfigSchema.safeParse(config);
    if(result.success){this.validConfig=result.data;this.metaVersion++;}
    this.publish({preferences:{...this.state.preferences,config:structuredClone(config)},invalidDraft:!result.success});this.schedule();
  }
  selectProfile(id:string){this.mutable();if(!this.state.profiles.some(p=>p.id===id))throw new Error('That anonymous profile is not in this workspace.');this.interacted=true;this.metaVersion++;this.publish({preferences:{...this.state.preferences,profileId:id,selectedSessionId:null}});this.schedule();}
  selectRecord(id:string){this.mutable();if(!this.state.sessions.some(s=>s.id===id))throw new Error('That report is not available in this browser.');this.interacted=true;this.metaVersion++;this.publish({preferences:{...this.state.preferences,selectedSessionId:id}});this.schedule();}
  addProfile(profile:TraineeProfile){
    this.mutable();const next=validateProfile(profile);const profiles=mergeImmutable(this.state.profiles,[next]);assertUniqueProfiles(profiles);this.interacted=true;this.pendingProfiles.set(next.id,next);this.metaVersion++;
    this.publish({profiles,preferences:{...this.state.preferences,profileId:next.id,selectedSessionId:null}});this.schedule();
  }
  acceptRecord(record:SessionRecord){
    const detached=structuredClone(record);const prior=this.state.sessions.find(s=>s.id===record.id);
    if(prior){if(!sameData(prior,detached))throw new Error('A different result reused an existing session ID.');return;}
    if(!this.state.profiles.some(p=>p.id===detached.profileId))throw new Error('The result profile is not available.');
    this.interacted=true;this.pendingSessions.set(detached.id,detached);this.metaVersion++;
    this.publish({sessions:ordered([detached,...this.state.sessions]),preferences:{...this.state.preferences,selectedSessionId:detached.id}});this.schedule();
  }
  async retry(){
    this.mutable();this.publish({busy:'reload'});
    try{
      await this.work;this.applyLoaded(await this.repository.load(),this.interacted);this.publish({busy:null});this.schedule();await this.work;
      if(this.state.error)throw new Error(this.state.error);
    }catch(cause){this.publish({busy:null});this.failed(cause);throw cause;}
  }
  async import(bundle:SessionExport):Promise<{added:number;duplicates:number;profilesAdded:number}>{
    this.mutable();const valid=validateBundle(bundle);this.publish({busy:'import'});
    try{
      await this.work;
      if(!this.epoch)this.applyLoaded(await this.repository.load(),this.interacted);
      const profiles=mergeImmutable(this.state.profiles,valid.profiles);assertUniqueProfiles(profiles);const sessions=mergeImmutable(this.state.sessions,valid.sessions);
      const added=valid.sessions.filter(s=>!this.state.sessions.some(p=>p.id===s.id)).length;const profilesAdded=valid.profiles.filter(p=>!this.state.profiles.some(v=>v.id===p.id)).length;
      const pendingProfiles=[...this.pendingProfiles.values()];const pendingSessions=[...this.pendingSessions.values()];const version=this.metaVersion;
      const committingProfiles=mergeImmutable(pendingProfiles,valid.profiles);const committingSessions=mergeImmutable(pendingSessions,valid.sessions);
      await this.repository.commit(this.epoch!,{profiles:committingProfiles,sessions:committingSessions,preferences:this.persistedPreferences()});
      if(this.stale)throw new HistoryResetConflict();
      for(const p of pendingProfiles)if(this.pendingProfiles.get(p.id)===p)this.pendingProfiles.delete(p.id);
      for(const r of pendingSessions)if(this.pendingSessions.get(r.id)===r)this.pendingSessions.delete(r.id);
      this.savedMetaVersion=version;
      this.publish({profiles:mergeImmutable(this.state.profiles,profiles),sessions:ordered(mergeImmutable(this.state.sessions,sessions)),savedSessionIds:new Set([...this.state.savedSessionIds,...committingSessions.map(s=>s.id)]),phase:'saved',busy:null,error:null,info:`Imported ${added} new report${added===1?'':'s'}; ${valid.sessions.length-added} duplicate${valid.sessions.length-added===1?'':'s'} skipped.`});this.notify('changed');this.schedule();
      return {added,duplicates:valid.sessions.length-added,profilesAdded};
    }catch(cause){this.publish({busy:null});this.failed(cause);throw cause;}
  }
  async reset(){
    this.mutable();this.publish({busy:'reset'});
    try{
      await this.work;const data=await this.repository.reset(this.epoch);this.pendingProfiles.clear();this.pendingSessions.clear();this.metaVersion=0;this.savedMetaVersion=0;this.interacted=false;this.epoch=null;this.stale=false;
      this.applyLoaded(data,false);this.publish({busy:null,info:'Local history was reset. Anonymous demo profiles have zero training history.'});this.notify('reset');
    }catch(cause){this.publish({busy:null});this.failed(cause);throw cause;}
  }
  rawBackup(){return this.repository.rawBackup();}
}

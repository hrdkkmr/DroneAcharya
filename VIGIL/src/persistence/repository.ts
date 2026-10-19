import type { HistoryDelta, HistoryRepository, LoadedHistory, QuarantinedEntry, SessionRecord, TraineeProfile } from '../domain/types';
import { assertUniqueProfiles, INITIAL_PROFILES, initialMeta, mergeImmutable, metaSchema, preferencesSchema, sameData, validateProfile, validateStoredRecord } from './validation';

export const DATABASE_NAME='vigil-training-history';
export const DATABASE_VERSION=1;
const STORES=['profiles','sessions','meta'];
export class HistoryResetConflict extends Error { constructor(){super('History was reset or replaced in this browser. Another tab or cleared browser data may be responsible. Export unsaved reports and reload this tab; retry cannot undo that reset.');this.name='HistoryResetConflict';} }
function storageError(cause:unknown):Error {
  if(cause instanceof HistoryResetConflict)return cause;
  const name=typeof cause==='object'&&cause&&'name'in cause ? String(cause.name) : '';
  if(name==='QuotaExceededError')return new Error('Browser storage is full. The in-memory report is retained. Export a backup, free space, then retry.');
  if(name==='SecurityError'||name==='InvalidStateError'||name==='UnknownError')return new Error('Local browser storage is unavailable or blocked. In-memory reports are retained; enable storage and retry, or download a backup.');
  return cause instanceof Error ? cause : new Error(typeof cause==='object'&&cause&&'message'in cause ? String(cause.message) : 'Local history could not be saved. The in-memory report is retained.');
}
function openDatabase(factory:()=>IDBFactory|undefined):Promise<IDBDatabase> {
  return new Promise((resolve,reject)=>{
    let settled=false;
    try {
      const idb=factory();if(!idb)throw new Error('IndexedDB is unavailable. Training can continue in memory; reports will not survive reload until saved.');
      const request=idb.open(DATABASE_NAME,DATABASE_VERSION);
      request.onupgradeneeded=()=>{const db=request.result;for(const name of STORES)if(!db.objectStoreNames.contains(name))db.createObjectStore(name,{keyPath:name==='meta'?'key':'id'});};
      request.onerror=()=>{settled=true;reject(storageError(request.error));};
      request.onblocked=()=>{settled=true;reject(new Error('History is blocked by another open connection. Close other VIGIL tabs and retry. No data was overwritten.'));};
      request.onsuccess=()=>{if(settled){request.result.close();return;}settled=true;request.result.onversionchange=()=>request.result.close();resolve(request.result);};
    } catch(cause){reject(storageError(cause));}
  });
}
function gather(requests:IDBRequest[],done:(values:unknown[])=>void,fail:(cause:unknown)=>void) {
  const values:unknown[]=new Array(requests.length);let remaining=requests.length;
  requests.forEach((request,index)=>{request.onsuccess=()=>{values[index]=request.result;if(--remaining===0)try{done(values);}catch(cause){fail(cause);}};});
}

/** No async work inside an IDB transaction. Resolve only after its atomic completion. */
export function createHistoryRepository(factory?:()=>IDBFactory|undefined):HistoryRepository {
  let captured:IDBFactory|undefined;
  if(!factory)try{captured=globalThis.indexedDB;}catch{/* Surface access denial asynchronously, without crashing the UI. */}
  const getFactory=factory??(()=>captured??globalThis.indexedDB);
  async function transaction<T>(mode:IDBTransactionMode,body:(tx:IDBTransaction,result:(value:T)=>void,fail:(cause:unknown)=>void)=>void):Promise<T> {
    const db=await openDatabase(getFactory);
    return new Promise<T>((resolve,reject)=>{
      let tx:IDBTransaction;
      try{tx=db.transaction(STORES,mode);}catch(cause){db.close();reject(storageError(cause));return;}
      let value:T;let failure:unknown;
      const fail=(cause:unknown)=>{failure=cause;try{tx.abort();}catch{/* Already aborted by the failing request. */}};
      tx.oncomplete=()=>{db.close();resolve(value);};
      tx.onabort=()=>{db.close();reject(storageError(failure??tx.error??new Error('The transaction was aborted; no partial write was committed.')));};
      tx.onerror=()=>{failure??=tx.error;};
      try{body(tx,next=>{value=next;},fail);}catch(cause){fail(cause);}
    });
  }
  async function load():Promise<LoadedHistory> {
    const raw=await transaction<{profiles:unknown[];sessions:unknown[];meta:unknown}>('readwrite',(tx,result,fail)=>{
      gather([tx.objectStore('profiles').getAll(),tx.objectStore('sessions').getAll(),tx.objectStore('meta').get('workspace')],([p,s,m])=>{
        const profiles=p as unknown[];const sessions=s as unknown[];
        if(m===undefined){
          if(profiles.length||sessions.length)throw new Error('History metadata is missing. Existing records were not overwritten. Export raw storage or confirm a workspace reset.');
          const meta=initialMeta();for(const profile of INITIAL_PROFILES)tx.objectStore('profiles').add(profile);tx.objectStore('meta').add(meta);result({profiles:structuredClone(INITIAL_PROFILES),sessions:[],meta});
        } else result({profiles,sessions,meta:m});
      },fail);
    });
    const meta=metaSchema.parse(raw.meta);const profiles:TraineeProfile[]=[];const sessions:SessionRecord[]=[];const quarantined:QuarantinedEntry[]=[];
    const label=(value:unknown)=>typeof value==='object'&&value&&'id'in value?String(value.id).slice(0,100):'Unknown ID';
    for(const value of raw.profiles)try{const p=validateProfile(value);assertUniqueProfiles([...profiles,p]);profiles.push(p);}catch(cause){quarantined.push({store:'profiles',id:label(value),reason:cause instanceof Error?cause.message:'Invalid profile'});}
    for(const value of raw.sessions)try{const s=validateStoredRecord(value);if(!profiles.some(p=>p.id===s.profileId))throw new Error('The referenced profile is missing or quarantined.');sessions.push(s);}catch(cause){quarantined.push({store:'sessions',id:label(value),reason:cause instanceof Error?cause.message:'Invalid report'});}
    return {profiles,sessions,meta,quarantined};
  }
  async function commit(epoch:string,delta:HistoryDelta):Promise<void> {
    const profiles=delta.profiles.map(validateProfile);assertUniqueProfiles(profiles);const sessions=delta.sessions.map(validateStoredRecord);const preferences=preferencesSchema.parse(delta.preferences);
    await transaction<void>('readwrite',(tx,result,fail)=>{
      const requests:IDBRequest[]=[tx.objectStore('meta').get('workspace'),tx.objectStore('profiles').getAll(),tx.objectStore('sessions').getAllKeys(),...sessions.map(s=>tx.objectStore('sessions').get(s.id))];
      gather(requests,([m,p,keys,...prior])=>{
        const meta=metaSchema.parse(m);if(meta.epoch!==epoch)throw new HistoryResetConflict();
        const existing=p as TraineeProfile[];
        // Quarantine is non-destructive. A bad existing ID cannot be silently replaced.
        for(const incoming of profiles){const raw=existing.find(v=>v.id===incoming.id);if(raw&&!sameData(raw,incoming))throw new Error(`Conflicting profile ID ${incoming.id}. Existing data was not overwritten.`);}
        const valid=existing.flatMap(value=>{try{return [validateProfile(value)];}catch{return [];}});const merged=mergeImmutable(valid,profiles);assertUniqueProfiles(merged);
        const knownIds=new Set(merged.map(p=>p.id));const knownSessions=new Set((keys as IDBValidKey[]).map(String));
        sessions.forEach((record,index)=>{if(!knownIds.has(record.profileId))throw new Error('Cannot save an orphan session without its profile.');if(prior[index]&&!sameData(prior[index],record))throw new Error(`Conflicting session ID ${record.id}. Existing data was not overwritten.`);knownSessions.add(record.id);});
        if(!knownIds.has(preferences.profileId)||(preferences.selectedSessionId!==null&&!knownSessions.has(preferences.selectedSessionId)))throw new Error('Saved selection must reference a known profile/report.');
        for(const profile of profiles)tx.objectStore('profiles').put(profile);for(const record of sessions)tx.objectStore('sessions').put(record);
        tx.objectStore('meta').put({...meta,revision:meta.revision+1,preferences});result(undefined);
      },fail);
    });
  }
  async function reset(epoch:string|null):Promise<LoadedHistory> {
    return transaction<LoadedHistory>('readwrite',(tx,result,fail)=>{
      gather([tx.objectStore('meta').get('workspace')],([raw])=>{
        if(epoch!==null&&metaSchema.parse(raw).epoch!==epoch)throw new HistoryResetConflict();
        const meta=initialMeta();for(const store of STORES)tx.objectStore(store).clear();for(const profile of INITIAL_PROFILES)tx.objectStore('profiles').add(profile);tx.objectStore('meta').add(meta);
        result({profiles:structuredClone(INITIAL_PROFILES),sessions:[],meta,quarantined:[]});
      },fail);
    });
  }
  async function rawBackup():Promise<unknown> {
    return transaction('readonly',(tx,result,fail)=>gather(STORES.map(s=>tx.objectStore(s).getAll()),values=>result({format:'vigil-raw-storage-diagnostic',databaseVersion:DATABASE_VERSION,exportedAt:new Date().toISOString(),profiles:values[0],sessions:values[1],meta:values[2]}),fail));
  }
  return {load,commit,reset,rawBackup};
}

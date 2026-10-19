import { SCHEMA_VERSION } from '../domain/types';
import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, useSyncExternalStore, type ReactNode } from 'react';
import { cloneConfig, SKILL_LABELS, validateConfig } from '../domain/config';
import type { AdaptiveRecommendation, Route, ScenarioConfig, SessionExport, SessionRecord, TraineeProfile } from '../domain/types';
import { useSimulation } from './useSimulation';
import { HISTORY_RELOAD_NOTICE, HistoryStore, type HistorySnapshot } from '../persistence/HistoryStore';
import { createHistoryRepository } from '../persistence/repository';
import { recommendNext } from '../adaptive/policy';
import { backupJson, downloadText, printableBody, reportHtml, REPORT_CSS, summaryCsv } from '../analytics/exports';

export const ROUTES: Route[] = ['home', 'lab', 'console', 'aar', 'progress', 'unit', 'instructor'];
export const ROUTE_LABELS: Record<Route, string> = { home: 'Overview', lab: 'Scenario Lab', console: 'Live console', aar: 'After-action review', progress: 'Individual progress', unit: 'Unit performance', instructor: 'Instructor desk' };
export function routeFromHash(hash: string): Route {
  const candidate = hash.replace(/^#\/?/, '').split('?')[0];
  return ROUTES.includes(candidate as Route) ? candidate as Route : 'home';
}
interface WorkspaceContext {
  route: Route; navigate: (route: Route) => void;
  config: ScenarioConfig; setConfig: (config: ScenarioConfig) => void;
  briefing: ScenarioConfig | null; prepareBriefing: () => void;
  profiles: TraineeProfile[]; profile: TraineeProfile;
  setProfileId: (id: string) => void; addProfile: (name: string,unit?:string) => void;
  simulation: ReturnType<typeof useSimulation>; isActive: boolean;
  startExercise: () => void; resetExercise: () => void;
  sessions: SessionRecord[]; currentRecord: SessionRecord | null; reviewSession: (id: string) => void;
  storage:HistorySnapshot; historyReady:boolean;
  nextPractice:AdaptiveRecommendation|null; prepareNextPractice:()=>void;
  retryHistory:()=>Promise<void>;
  importHistory:(bundle:SessionExport)=>ReturnType<HistoryStore['import']>;
  resetHistory:()=>Promise<void>;
  exportHistory:(kind:'json'|'csv',scope?:'all'|'profile')=>void;
  exportRecord:(id:string,kind:'json'|'html')=>void;
  printableRecord:(id:string)=>{body:string;css:string};
  exportRawStorage:()=>Promise<void>;
  notice:string|null; dismissNotice:()=>void;
}
const Context = createContext<WorkspaceContext | null>(null);
export function WorkspaceProvider({ children }: { children: ReactNode }) {
  const [route, setRoute] = useState<Route>(() => routeFromHash(window.location.hash));
  const [briefing, setBriefing] = useState<ScenarioConfig | null>(null);
  const [history]=useState(()=>new HistoryStore(createHistoryRepository()));
  const storage=useSyncExternalStore(history.subscribe,history.getSnapshot);
  const {profiles,sessions,preferences}=storage;const {config,profileId,selectedSessionId}=preferences;
  const historyReady=storage.phase!=='loading'&&!storage.busy;
  const [notice, setNotice] = useState<string | null>(null);
  const recordedIds = useRef(new Set<string>());
  const simulation = useSimulation();
  const { view, record, send, starting } = simulation;
  const isActive = starting || view?.status === 'running' || view?.status === 'paused';
  const activeRef=useRef(isActive);activeRef.current=isActive;
  const nextPractice=useMemo(()=>!isActive&&!storage.needsReload&&storage.phase==='saved'&&!storage.busy&&!storage.error&&storage.pending===0
    ? recommendNext(sessions,storage.savedSessionIds,profileId) : null,
    [isActive,storage.needsReload,storage.phase,storage.busy,storage.error,storage.pending,sessions,storage.savedSessionIds,profileId]);
  useEffect(()=>{void history.initialize();},[history]);
  useEffect(() => {
    const listener = () => setRoute(routeFromHash(window.location.hash));
    window.addEventListener('hashchange', listener);return () => window.removeEventListener('hashchange', listener);
  }, []);
  const navigate = useCallback((next: Route) => { window.location.hash = `/${next}`; setRoute(next); }, []);
  useEffect(() => {
    if (view?.status === 'running' && route !== 'console' && simulation.connected) { send({ type: 'pause' }); setNotice('Your exercise was paused when you left the console. Return to continue; no simulation time is lost.'); }
  }, [route, view?.status, simulation.connected, send]);
  useEffect(() => {
    if (!isActive&&!storage.pending) return;
    const warn = (event: BeforeUnloadEvent) => { event.preventDefault(); event.returnValue = ''; };
    window.addEventListener('beforeunload', warn);return () => window.removeEventListener('beforeunload', warn);
  }, [isActive,storage.pending]);
  useEffect(() => {
    if (!record || recordedIds.current.has(record.id)) return;
    try{history.acceptRecord(record);recordedIds.current.add(record.id);setNotice(null);}
    catch(cause){setNotice(`The actual Worker report is retained, but could not enter local history: ${cause instanceof Error?cause.message:'Unknown recording error'}`);}
    navigate('aar');
  }, [record, navigate,history]);
  function guard(action:string){
    if(activeRef.current)throw new Error(`End or reset the current exercise before ${action}. Prior evaluator reports and private exports stay locked during live attempts.`);
    if(history.getSnapshot().phase==='loading'||history.getSnapshot().busy)throw new Error('Wait for local history to finish loading or saving this operation.');
  }
  function setConfig(next:ScenarioConfig){guard('changing the configuration');history.setConfig(cloneConfig(next));}
  function prepareBriefing() {
    if (isActive) { navigate('console'); return; }
    guard('preparing another exercise');if(view)simulation.prepare();
    setBriefing(cloneConfig(validateConfig(config)));setNotice(null);navigate('console');
  }
  function prepareNextPractice(){
    guard('planning the next exercise');
    const state=history.getSnapshot();
    if(state.needsReload)throw new Error(HISTORY_RELOAD_NOTICE);
    if(state.phase!=='saved'||state.pending||state.error)throw new Error('Wait for acknowledged local history, or recover storage, before applying a history-based plan. Manual configuration is still available.');
    const plan=recommendNext(state.sessions,state.savedSessionIds,state.preferences.profileId);
    simulation.prepare();
    history.setConfig(cloneConfig(plan.config));setBriefing(cloneConfig(plan.config));
    setNotice(`Rule-based ${plan.policyVersion}: ${SKILL_LABELS[plan.target]} practice from ${plan.sampleSize} distinct matching-context completions. ${plan.difficultyChange==='hold'?'Difficulty held':plan.difficultyChange==='increase'?'Difficulty raised one level':'Difficulty reduced one level'} at Level ${plan.config.difficulty}. Review the briefing; Start remains explicit.`);
    navigate('console');
  }
  function startExercise() {
    if(isActive){navigate('console');return;}
    guard('starting an exercise');
    if(!briefing){setNotice('Choose a valid configuration before starting.');navigate('lab');return;}
    activeRef.current=true;simulation.start(briefing,profileId);
  }
  function resetExercise(){simulation.reset();activeRef.current=false;setNotice(null);navigate('console');}
  function setProfileId(id:string){
    try{guard('changing training profiles');history.selectProfile(id);}catch(cause){setNotice(cause instanceof Error?cause.message:'The profile could not be selected.');}
  }
  function addProfile(name:string,unit='Demonstration unit'){
    guard('changing training profiles');const clean=name.trim();
    if(clean.length<3||clean.length>24)throw new Error('Use an anonymous identifier between 3 and 24 characters.');
    if(history.getSnapshot().profiles.some(p=>p.name.toLowerCase()===clean.toLowerCase()))throw new Error('That profile name already exists.');
    history.addProfile({schemaVersion:SCHEMA_VERSION,id:`trainee-${crypto.randomUUID()}`,name:clean,unit:unit.trim()||'Demonstration unit',createdAt:new Date().toISOString()});
  }
  function reviewSession(id:string){
    try{guard('reviewing evaluator answers');history.selectRecord(id);navigate('aar');}catch(cause){setNotice(cause instanceof Error?cause.message:'That result is not available in this browser.');}
  }
  function exportHistory(kind:'json'|'csv',scope:'all'|'profile'='all'){
    guard('exporting private history');const state=history.getSnapshot();const p=scope==='profile'?state.profiles.filter(p=>p.id===state.preferences.profileId):state.profiles;
    const rows=scope==='profile'?state.sessions.filter(s=>s.profileId===state.preferences.profileId):state.sessions;
    downloadText(`vigil-${scope}-${new Date().toISOString().slice(0,10)}.${kind}`,kind==='json'?backupJson(p,rows):summaryCsv(rows,p,state.savedSessionIds),kind==='json'?'application/json;charset=utf-8':'text/csv;charset=utf-8');
  }
  function allowedRecord(id:string){guard('exporting an evaluator report');const state=history.getSnapshot();const found=state.sessions.find(s=>s.id===id)??(record?.id===id?record:null);if(!found)throw new Error('That actual report is unavailable.');return {found,profile:state.profiles.find(p=>p.id===found.profileId)};}
  function exportRecord(id:string,kind:'json'|'html'){
    const {found,profile}=allowedRecord(id);if(!profile)throw new Error('The referenced anonymous profile is unavailable.');
    downloadText(`vigil-report-${id.replace(/[^a-z0-9._-]/gi,'_')}.${kind}`,kind==='json'?backupJson([profile],[found]):reportHtml(found,profile),kind==='json'?'application/json;charset=utf-8':'text/html;charset=utf-8');
  }
  function printableRecord(id:string){const {found,profile}=allowedRecord(id);return {body:printableBody(found,profile),css:REPORT_CSS};}
  async function retryHistory(){guard('reloading saved history');await history.retry();}
  async function importHistory(bundle:SessionExport){guard('importing reports');return history.import(bundle);}
  async function resetHistory(){guard('resetting local history');await history.reset();simulation.reset();recordedIds.current.clear();setBriefing(null);setNotice(null);}
  async function exportRawStorage(){guard('exporting raw local data');const raw=await history.rawBackup();guard('exporting raw local data');downloadText('vigil-raw-storage-diagnostic.json',JSON.stringify(raw,null,2),'application/json;charset=utf-8');}
  const profile=profiles.find(p=>p.id===profileId)??profiles[0];
  const currentRecord=sessions.find(s=>s.id===selectedSessionId)??sessions.find(s=>s.profileId===profileId)??(record?.profileId===profileId?record:null);
  return <Context.Provider value={{route,navigate,config,setConfig,briefing,prepareBriefing,profiles,profile,setProfileId,addProfile,simulation,isActive,startExercise,resetExercise,sessions,currentRecord,reviewSession,storage,historyReady,nextPractice,prepareNextPractice,retryHistory,importHistory,resetHistory,exportHistory,exportRecord,printableRecord,exportRawStorage,notice,dismissNotice:()=>setNotice(null)}}>{children}</Context.Provider>;
}
export function useWorkspace(){const context=useContext(Context);if(!context)throw new Error('WorkspaceProvider is required.');return context;}

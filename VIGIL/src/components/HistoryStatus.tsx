import { useState } from 'react';
import { AlertTriangle, Database, Download, HardDrive, RefreshCw } from 'lucide-react';
import { useWorkspace } from '../hooks/useWorkspace';
import { Badge, Button } from './UI';

export function HistoryPill(){
  const {storage}=useWorkspace();const label=storage.busy==='import'?'Importing history':storage.busy==='reset'?'Resetting history':storage.busy==='reload'?'Checking local history':storage.phase==='loading'?'Loading history':storage.phase==='saving'?'Saving locally':storage.error?'Storage needs attention':storage.quarantined.length?'History partially validated':storage.pending?'Unsaved changes':'Saved on device';
  return <span title={label} data-testid="history-state" data-state={storage.busy?'saving':storage.phase} data-pending={storage.pending}><Badge tone={storage.error||storage.pending||storage.quarantined.length?'amber':storage.phase==='saved'?'green':'neutral'}><HardDrive size={12}/><span className="storage-pill-text">{label}</span></Badge></span>;
}
export function HistoryStatus(){
  const {storage,retryHistory,exportHistory,exportRawStorage,isActive,historyReady}=useWorkspace();const [error,setError]=useState('');
  const locked=isActive||!historyReady;
  function backup(){try{exportHistory('json');setError('');}catch(cause){setError(cause instanceof Error?cause.message:'Backup failed.');}}
  async function raw(){try{await exportRawStorage();setError('');}catch(cause){setError(cause instanceof Error?cause.message:'Raw backup failed.');}}
  if(!storage.error&&!storage.quarantined.length&&!storage.info&&!storage.invalidDraft)return null;
  return <section className={`history-status ${storage.error||storage.quarantined.length?'history-status--error':''}`} aria-label="Local history status">
    {storage.error&&<div className="history-status-main" role="alert" data-testid="storage-alert"><AlertTriangle size={19}/><div><strong>{storage.pending?'Changes are not saved yet.':'Local history needs attention.'}</strong><p>{storage.error}</p><p>Saved data was not silently replaced. You may continue training in memory; download unsaved reports before reload. Private-data actions stay locked during a live attempt.</p></div></div>}
    {!storage.error&&storage.info&&<div className="history-status-main"><Database size={18}/><p>{storage.info}</p></div>}
    {storage.invalidDraft&&<p className="draft-warning">Invalid configuration edits are not stored. The last valid draft is preserved; correct the fields before starting.</p>}
    {!!storage.quarantined.length&&<details className="quarantine-details"><summary>{storage.quarantined.length} quarantined stored entr{storage.quarantined.length===1?'y':'ies'} · inspect validation failures</summary><p>Invalid stored entries are excluded from reports and analytics. Original entries are untouched; a previously valid in-memory copy, if available, is marked unsaved. A normal backup contains valid history only; the raw diagnostic backup preserves these entries but is not an importable report.</p><ul>{storage.quarantined.slice(0,20).map((q,i)=><li key={`${q.store}-${q.id}-${i}`}><strong>{q.store} · {q.id}</strong><span>{q.reason.slice(0,260)}</span></li>)}</ul>{storage.quarantined.length>20&&<p>First 20 entries shown. Download raw data to inspect the remainder.</p>}</details>}
    {(storage.error||storage.info||!!storage.quarantined.length)&&<div className="history-status-actions"><Button variant="secondary" disabled={locked} onClick={()=>{void retryHistory().catch(()=>{});}}><RefreshCw size={14}/>{storage.busy==='reload'?'Reloading…':'Reload / retry saving'}</Button>{storage.error&&<Button variant="secondary" disabled={locked} onClick={backup}><Download size={14}/>Backup available reports</Button>}{!!storage.quarantined.length&&<Button variant="ghost" disabled={locked} onClick={()=>void raw()}>Download raw data</Button>}</div>}
    {error&&<p className="form-error" role="alert">{error}</p>}
  </section>;
}

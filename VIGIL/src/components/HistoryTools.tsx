import { useRef, useState, type ChangeEvent } from 'react';
import { Database, Download, FileJson, FileSpreadsheet, ShieldCheck, Trash2, Upload } from 'lucide-react';
import { useWorkspace } from '../hooks/useWorkspace';
import type { SessionExport } from '../domain/types';
import { assertUniqueProfiles, errorMessage, MAX_IMPORT_BYTES, mergeImmutable, parseBundle } from '../persistence/validation';
import { Badge, Button, SectionHeading } from './UI';
import { ConfirmDialog } from './ConfirmDialog';

export function HistoryTools(){
  const {storage,sessions,profiles,isActive,historyReady,exportHistory,exportRawStorage,importHistory,resetHistory}=useWorkspace();
  const [preview,setPreview]=useState<SessionExport|null>(null);const [reading,setReading]=useState(false);const [confirm,setConfirm]=useState<'import'|'reset'|null>(null);const [error,setError]=useState('');const [success,setSuccess]=useState('');
  const input=useRef<HTMLInputElement>(null);const locked=isActive||!historyReady||reading;
  function download(kind:'json'|'csv'){try{exportHistory(kind);setError('');}catch(cause){setError(cause instanceof Error?cause.message:'The export could not be created.');}}
  async function choose(event:ChangeEvent<HTMLInputElement>){
    const file=event.target.files?.[0];setPreview(null);setError('');setSuccess('');if(!file)return;
    if(file.size>MAX_IMPORT_BYTES){setError('Import exceeds the 20 MiB limit. No data was changed.');return;}
    setReading(true);try{
      const bundle=parseBundle(await file.text());mergeImmutable(sessions,bundle.sessions);assertUniqueProfiles(mergeImmutable(profiles,bundle.profiles));setPreview(bundle);
    }catch(cause){setError(`Import rejected. ${errorMessage(cause)} No data was changed.`);}finally{setReading(false);}
  }
  async function commit(){
    const action=confirm;setConfirm(null);setError('');setSuccess('');
    try{
      if(action==='import'&&preview){const result=await importHistory(preview);setSuccess(`Import complete: ${result.added} new report${result.added===1?'':'s'}, ${result.duplicates} duplicate${result.duplicates===1?'':'s'} skipped; ${result.profilesAdded} profiles added.`);}
      else if(action==='reset'){await resetHistory();setPreview(null);if(input.current)input.current.value='';setSuccess('Local history reset. No scores or historical results were regenerated.');}
    }catch(cause){setError(`${cause instanceof Error?cause.message:'The transaction failed.'} Existing stored records were not overwritten.`);}
  }
  return <section className="surface history-tools" aria-label="Portable history and local data">
    <SectionHeading title="Your history, on your device" subtitle="IndexedDB v1 · Portable format1 / record schema3 · No cloud account or authenticated role" action={<Badge tone="blue"><Database size={12}/>{storage.savedSessionIds.size} saved reports</Badge>}/>
    <div className="history-tools-grid"><div className="history-tool-card"><span className="history-tool-icon"><Download size={21}/></span><h3>Keep a portable backup.</h3><p>JSON includes actual records and anonymous profiles, including unsaved in-memory reports. CSV is a labelled summary, not an import format. Empty history exports no invented sessions.</p><div className="history-button-row"><Button variant="secondary" disabled={locked} onClick={()=>download('json')}><FileJson size={15}/>Download JSON backup</Button><Button variant="secondary" disabled={locked} onClick={()=>download('csv')}><FileSpreadsheet size={15}/>Export summary CSV</Button></div><p className="checkpoint-note">Browser/origin-local storage can be evicted or cleared. Backups are manual. Active simulation state is not recovered after refresh.</p></div>
    <div className="history-tool-card"><span className="history-tool-icon"><Upload size={21}/></span><h3>Merge validated history.</h3><p>Choose a format1 JSON backup, up to 20 MiB /500 reports. Supported schemas, profile references, deterministic definitions, real event order and the single evaluator’s computed result are checked before confirmation.</p><label className="file-label" htmlFor="history-import">Choose JSON backup</label><input ref={input} id="history-import" type="file" accept=".json,application/json" disabled={locked} onChange={event=>void choose(event)}/>{reading&&<p aria-live="polite">Validating file. No data has changed…</p>}{preview&&<div className="import-preview" data-testid="import-preview"><strong>Validated · {preview.sessions.length} reports / {preview.profiles.length} profiles</strong><p>{preview.sessions.filter(s=>!sessions.some(v=>v.id===s.id)).length} new reports. Equal IDs are deduplicated; conflicting data is rejected atomically.</p><Button disabled={locked} onClick={()=>setConfirm('import')}><Upload size={14}/>Review & import</Button></div>}</div></div>
    <div className="history-data-footer"><div><ShieldCheck size={17}/><p><strong>Consistency is not authenticity.</strong> Imports do not prove who performed a run. Quarantined entries are excluded, never silently deleted. {isActive?'End or reset the live exercise to unlock private-data operations.':'Keep identifiers anonymous; this local prototype has no access control or signed records.'}</p></div><div className="history-button-row">{(storage.error||!!storage.quarantined.length)&&<Button variant="ghost" disabled={locked} onClick={()=>{void exportRawStorage().catch(cause=>setError(cause instanceof Error?cause.message:'Raw export failed.'));}}>Download raw storage</Button>}<Button variant="ghost" disabled={locked} onClick={()=>setConfirm('reset')}><Trash2 size={14}/>Reset local history</Button></div></div>
    {error&&<p className="form-error history-tool-message" role="alert" data-testid="history-tool-error">{error}</p>}{success&&<p className="inline-success history-tool-message" role="status">{success}</p>}
    {confirm&&<ConfirmDialog title={confirm==='import'?'Import validated history?':'Reset all local history?'} description={confirm==='import'?'Merge this validated file in one transaction. Exact duplicates will not be counted twice. Conflicting identifiers or a storage failure reject the entire incoming merge. This does not certify authorship.':'Permanently delete all local reports, added profiles and saved preferences, including quarantined and unsaved data. Demo identities will return with zero history. Download a backup first if needed. This cannot be undone.'} confirmLabel={confirm==='import'?'Merge history':'Delete local history'} confirmVariant={confirm==='import'?'primary':'danger'} onCancel={()=>setConfirm(null)} onConfirm={()=>void commit()}/>}
  </section>;
}

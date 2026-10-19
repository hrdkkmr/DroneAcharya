import { useState } from 'react';
import { createPortal, flushSync } from 'react-dom';
import { Download, FileJson, Printer } from 'lucide-react';
import { useWorkspace } from '../hooks/useWorkspace';
import { Button } from './UI';

export function ReportActions({id}:{id:string}){
  const {exportRecord,printableRecord,isActive}=useWorkspace();const [error,setError]=useState('');const [printing,setPrinting]=useState<{body:string;css:string}|null>(null);
  function download(kind:'json'|'html'){try{exportRecord(id,kind);setError('');}catch(cause){setError(cause instanceof Error?cause.message:'Report export failed.');}}
  function print(){try{const report=printableRecord(id);flushSync(()=>setPrinting(report));window.print();setError('');}catch(cause){setError(cause instanceof Error?cause.message:'Printing is unavailable. Download HTML instead.');}finally{setPrinting(null);}}
  return <><div className="report-actions" role="group" aria-label="Export this actual report"><Button variant="secondary" disabled={isActive} onClick={()=>download('json')}><FileJson size={14}/>Report JSON</Button><Button variant="secondary" disabled={isActive} onClick={()=>download('html')}><Download size={14}/>Printable HTML</Button><Button variant="secondary" disabled={isActive} onClick={print}><Printer size={14}/>Print / save PDF</Button><small>Actual score, audit and recorded events · PDF uses your browser’s print dialog</small></div>{error&&<p className="form-error" role="alert">{error}</p>}{printing&&!isActive&&createPortal(<article className="vigil-print"><style>{`@media print{${printing.css}}`}</style><div dangerouslySetInnerHTML={{__html:printing.body}}/></article>,document.body)}</>;
}

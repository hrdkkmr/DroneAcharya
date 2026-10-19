import { useEffect, useId, useRef } from 'react';
import { createPortal } from 'react-dom';
import { AlertTriangle } from 'lucide-react';
import { Button } from './UI';

export function ConfirmDialog({ title, description, confirmLabel, onConfirm, onCancel, confirmVariant = 'danger' }: { title: string; description: string; confirmLabel: string; onConfirm: () => void; onCancel: () => void; confirmVariant?: 'primary' | 'danger' }) {
  const titleId = useId(); const descriptionId = useId();
  const cancelRef = useRef<HTMLButtonElement>(null);
  useEffect(() => {
    const prior = document.activeElement as HTMLElement | null;
    const root = document.getElementById('root'); const priorInert = root?.inert ?? false;
    if (root) root.inert = true;
    cancelRef.current?.focus();
    return () => { if (root) root.inert = priorInert; if (prior?.isConnected) prior.focus(); };
  }, []);
  return createPortal(<div className="modal-backdrop" onClick={onCancel}><section className="modal confirmation-dialog" role="dialog" aria-modal="true" aria-labelledby={titleId} aria-describedby={descriptionId} onClick={e => e.stopPropagation()} onKeyDown={e => {
    if (e.key === 'Escape') { e.stopPropagation(); onCancel(); }
    if (e.key !== 'Tab') return;
    const buttons = Array.from(e.currentTarget.querySelectorAll<HTMLButtonElement>('button:not([disabled])'));
    const first = buttons[0]; const last = buttons.at(-1);
    if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last?.focus(); }
    else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first?.focus(); }
  }}><span className="confirmation-icon"><AlertTriangle size={23}/></span><h2 id={titleId}>{title}</h2><p id={descriptionId}>{description}</p><div className="confirmation-actions"><button ref={cancelRef} className="button button--secondary" onClick={onCancel}>Cancel</button><Button variant={confirmVariant} onClick={onConfirm}>{confirmLabel}</Button></div></section></div>, document.body);
}

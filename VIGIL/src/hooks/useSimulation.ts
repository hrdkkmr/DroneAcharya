import { useCallback, useEffect, useRef, useState } from 'react';
import type { ActiveSessionView, ScenarioConfig, SessionRecord, WorkerCommand, WorkerResponse } from '../domain/types';

/** Only this bridge communicates with the worker. There is deliberately no main-thread engine fallback. */
export function useSimulation() {
  const worker = useRef<Worker | null>(null);
  const launchTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const [view, setView] = useState<ActiveSessionView | null>(null);
  const [record, setRecord] = useState<SessionRecord | null>(null);
  const [starting, setStarting] = useState(false);
  const [connected, setConnected] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const clearLaunchTimer = useCallback(() => { if (launchTimer.current) clearTimeout(launchTimer.current); launchTimer.current = null; }, []);
  const ensureWorker = useCallback(() => {
    if (worker.current) return worker.current;
    if (typeof Worker === 'undefined') throw new Error('This browser cannot start a module Web Worker. Use a current desktop browser; no fabricated exercise was started.');
    const next = new Worker(new URL('../workers/simulation.worker.ts', import.meta.url), { type: 'module', name: 'vigil-authoritative-simulation' });
    next.onmessage = (event: MessageEvent<WorkerResponse>) => {
      const response = event.data;
      if (response.type === 'ready') { setConnected(true); return; }
      if (response.type === 'error') { setError(response.message); setStarting(false); clearLaunchTimer(); return; }
      setView(response.view);
      if (response.view.status !== 'briefing') { setStarting(false); clearLaunchTimer(); }
      if (response.type === 'completed') { setRecord(response.record); setError(null); }
    };
    next.onerror = event => {
      event.preventDefault(); clearLaunchTimer(); setStarting(false); setConnected(false);
      setError('The simulation worker stopped responding. The last observation snapshot is retained. Reset to retry; no result has been invented.');
      next.terminate(); if (worker.current === next) worker.current = null;
    };
    next.onmessageerror = () => { clearLaunchTimer(); setStarting(false); setConnected(false); setError('A simulation message could not be decoded. Reset the exercise to retry.'); next.terminate(); if (worker.current === next) worker.current = null; };
    worker.current = next; return next;
  }, [clearLaunchTimer]);
  useEffect(() => {
    // Eagerly load the local worker so a loaded exercise can run without later internet access.
    if (typeof Worker !== 'undefined') { try { ensureWorker(); } catch (cause) { setError(cause instanceof Error ? cause.message : 'Could not load the simulation worker.'); } }
    return () => { clearLaunchTimer(); worker.current?.terminate(); worker.current = null; };
  }, [ensureWorker, clearLaunchTimer]);
  const send = useCallback((command: Exclude<WorkerCommand, { type: 'configure' }>) => {
    if (!worker.current) { setError('The simulation worker is not available. Reset the exercise or retry its briefing.'); return; }
    setError(null); worker.current.postMessage(command);
  }, []);
  const start = useCallback((config: ScenarioConfig, profileId: string) => {
    setError(null); setStarting(true); setRecord(null);
    try {
      const target = ensureWorker();
      target.postMessage({ type: 'configure', config, profileId, sessionId: crypto.randomUUID(), startedAt: new Date().toISOString() } satisfies WorkerCommand);
      target.postMessage({ type: 'start' } satisfies WorkerCommand);
      clearLaunchTimer();
      launchTimer.current = setTimeout(() => { setStarting(false); setConnected(false); setError('The local worker did not start within 8 seconds. Retry the briefing; no result was created.'); worker.current?.terminate(); worker.current = null; }, 8000);
    } catch (cause) { setStarting(false); setError(cause instanceof Error ? cause.message : 'Could not start the synthetic exercise.'); }
  }, [ensureWorker, clearLaunchTimer]);
  // A terminated healthy Runtime can accept a new configure command. Keep its already
  // loaded module alive so the next saved-history exercise also works without network.
  const prepare = useCallback(() => {
    clearLaunchTimer(); setView(null); setRecord(null); setError(null); setStarting(false);
    try { ensureWorker(); } catch (cause) { setError(cause instanceof Error ? cause.message : 'Could not prepare the local worker.'); }
  }, [ensureWorker, clearLaunchTimer]);
  const reset = useCallback(() => {
    clearLaunchTimer(); worker.current?.terminate(); worker.current = null;
    setView(null); setRecord(null); setError(null); setStarting(false); setConnected(false);
    try { ensureWorker(); } catch (cause) { setError(cause instanceof Error ? cause.message : 'Could not reload the simulation worker.'); }
  }, [ensureWorker, clearLaunchTimer]);
  return { view, record, starting, connected, error, start, send, prepare, reset, clearError: () => setError(null) };
}

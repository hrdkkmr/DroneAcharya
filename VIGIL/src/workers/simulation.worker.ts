import type { WorkerResponse } from '../domain/types';
import { SimulationRuntime } from './runtime';

const scope = self as unknown as { postMessage: (message: WorkerResponse) => void; onmessage: ((event: MessageEvent<unknown>) => void) | null };
const runtime = new SimulationRuntime(message => scope.postMessage(message));
scope.onmessage = event => runtime.handle(event.data);
setInterval(() => { try { runtime.tick(); } catch (error) { runtime.reportError(error); } }, 100);
scope.postMessage({ type: 'ready' });

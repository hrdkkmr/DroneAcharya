import '@testing-library/jest-dom/vitest';
import { cleanup } from '@testing-library/react';
import { afterEach, beforeEach, vi } from 'vitest';
import { IDBFactory } from 'fake-indexeddb';
beforeEach(() => { vi.stubGlobal('indexedDB', new IDBFactory()); });
afterEach(() => { cleanup(); window.location.hash = ''; });
Object.defineProperty(HTMLElement.prototype, 'scrollTo', { value: () => {}, configurable: true });

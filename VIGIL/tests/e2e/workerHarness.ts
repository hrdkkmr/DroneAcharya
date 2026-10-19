import { expect, type Page } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import type { ActiveSessionView, SessionRecord, WorkerCommand, WorkerResponse } from '../../src/domain/types';

declare global { interface Window { __vigilMessages: WorkerResponse[]; __vigilCommands: WorkerCommand[]; __vigilWorker?: Worker } }

/** Test-only observation of the real browser worker boundary; production has no debug API. */
export async function auditWorker(page: Page) {
  await page.addInitScript(() => {
    window.__vigilMessages = [];
    window.__vigilCommands = [];
    const NativeWorker = window.Worker;
    window.Worker = class AuditedWorker extends NativeWorker {
      constructor(url: string | URL, options?: WorkerOptions) {
        super(url, options);
        if (options?.name === 'vigil-authoritative-simulation') {
          window.__vigilWorker = this;
          this.addEventListener('message', (event: MessageEvent<WorkerResponse>) => window.__vigilMessages.push(event.data));
        }
      }
      postMessage(message: unknown, transferOrOptions?: Transferable[] | StructuredSerializeOptions) {
        if (this === window.__vigilWorker) window.__vigilCommands.push(structuredClone(message as WorkerCommand));
        if (Array.isArray(transferOrOptions)) super.postMessage(message, transferOrOptions);
        else super.postMessage(message, transferOrOptions);
      }
    };
  });
}
export async function lastView(page: Page): Promise<ActiveSessionView | null> {
  return page.evaluate(() => { for (let i = window.__vigilMessages.length - 1; i >= 0; i--) { const message = window.__vigilMessages[i]; if (message.type === 'view' || message.type === 'completed') return message.view; } return null; });
}
export async function finalRecord(page: Page): Promise<SessionRecord> {
  const record = await page.evaluate(() => { for (let i = window.__vigilMessages.length - 1; i >= 0; i--) { const message = window.__vigilMessages[i]; if (message.type === 'completed') return message.record; } return null; });
  if (!record) throw new Error('The real worker did not provide a terminated session record.');
  return record;
}
export async function prepare(page: Page, duration: number | null = 60) {
  await page.goto('/#/lab');
  if (duration !== null) await page.getByLabel('Exercise duration (seconds)').fill(String(duration));
  await page.getByRole('button', { name: 'Review briefing', exact: true }).click();
  await expect(page.getByText('Local worker ready', { exact: true })).toBeVisible();
}
export async function start(page: Page) {
  await prepare(page);
  await page.getByRole('button', { name: 'Start exercise', exact: true }).click();
  await expect(page.getByTestId('simulation-timer')).toBeVisible();
  await expect(page.getByRole('button', { name: 'Select track T01', exact: true })).toBeVisible({ timeout: 10000 });
}
export async function navigate(page: Page, label: string) {
  const opener = page.getByRole('button', { name: 'Open navigation' });
  if (await opener.isVisible()) await opener.click();
  await page.getByRole('navigation', { name: 'Main navigation' }).getByRole('button', { name: label, exact: true }).click();
}
export async function assertNoAnswerLeak(page: Page) {
  const messages = await page.evaluate(() => window.__vigilMessages.filter(m => m.type === 'view'));
  expect(messages.length).toBeGreaterThan(0);
  for (const message of messages) {
    if (message.type !== 'view') continue;
    expect(message.view.scenario).not.toHaveProperty('tracks');
    const json = JSON.stringify(message.view);
    for (const field of ['rubric', 'weights', 'origin', 'velocity', 'truthCategory', 'significant', 'degradation', 'phase', 'crossingAt', 'center']) expect(json).not.toContain(`"${field}"`);
  }
}
export async function assertAccessible(page: Page, state: string) {
  const results = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa', 'wcag21aa']).analyze();
  expect(results.violations, `${state}: ${JSON.stringify(results.violations.map(v => ({ id: v.id, targets: v.nodes.map(n => n.target) })))}`).toEqual([]);
}

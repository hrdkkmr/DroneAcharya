import { test, expect, type Page } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';

async function navigate(page: Page, label: string) {
  if (await page.getByRole('button', { name: 'Open navigation' }).isVisible()) await page.getByRole('button', { name: 'Open navigation' }).click();
  const nav = page.getByRole('navigation', { name: 'Main navigation' });
  if (label === 'Instructor desk') await page.getByRole('button', { name: label, exact: true }).click();
  else await nav.getByRole('button', { name: label, exact: true }).click();
}

test('all seven screens navigate without browser errors or horizontal overflow', async ({ page }) => {
  const errors: string[] = []; page.on('pageerror', error => errors.push(error.message));
  await page.goto('/');
  for (const label of ['Scenario Lab', 'Live console', 'After-action review', 'Individual progress', 'Unit performance', 'Instructor desk', 'Overview']) {
    await navigate(page, label);
    await expect(page.getByRole('heading', { level: 1 })).toBeVisible();
    expect(await page.locator('.main-content').evaluate(el => el.scrollWidth <= el.clientWidth + 1)).toBe(true);
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
  }
  expect(errors).toEqual([]);
});

test('valid configuration flows into the briefing without automatically starting the exercise', async ({ page }) => {
  await page.goto('/');
  await page.getByRole('button', { name: 'Configure Urban ambiguity' }).click();
  await expect(page.getByLabel('Synthetic tracks')).toHaveValue('3');
  await page.getByLabel('Exercise duration (seconds)').fill('60');
  await page.getByRole('button', { name: 'Night', exact: true }).click();
  await page.getByRole('button', { name: 'Review briefing' }).click();
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Custom exercise');
  await expect(page.getByText('urban · night')).toBeVisible();
  await expect(page.getByText(/no exercise has started/i)).toBeVisible();
  await expect(page.getByRole('button', { name: 'Start exercise', exact: true })).toBeEnabled();
  await expect(page.getByTestId('simulation-timer')).toHaveCount(0);
  await page.getByRole('button', { name: 'Edit configuration' }).click();
  await expect(page.getByLabel('Exercise duration (seconds)')).toHaveValue('60');
});

test('invalid inputs produce helpful errors; corrected configuration can proceed', async ({ page }) => {
  await page.goto('/#/lab');
  await page.getByLabel('Exercise duration (seconds)').fill('10');
  await page.getByLabel('Synthetic tracks').fill('9');
  await page.getByRole('button', { name: 'Review briefing' }).click();
  await expect(page.getByRole('alert')).toContainText('at least 60 seconds');
  await expect(page.getByRole('alert')).toContainText('trackCount');
  await page.getByLabel('Exercise duration (seconds)').fill('60');
  await page.getByLabel('Synthetic tracks').fill('1');
  await page.getByRole('button', { name: 'Review briefing' }).click();
  await expect(page.getByText('MISSION INTENT')).toBeVisible();
});

test('guide supports keyboard focus containment and Escape', async ({ page }) => {
  await page.goto('/');
  if (await page.getByRole('button', { name: 'Open navigation' }).isVisible()) await page.getByRole('button', { name: 'Open navigation' }).click();
  const trigger = page.getByRole('button', { name: 'Training guide' });
  await trigger.click();
  await expect(page.getByRole('button', { name: 'Close training guide' })).toBeFocused();
  await page.keyboard.press('Tab'); await expect(page.getByRole('button', { name: 'Understood' })).toBeFocused();
  await page.keyboard.press('Tab'); await expect(page.getByRole('button', { name: 'Close training guide' })).toBeFocused();
  await page.keyboard.press('Escape'); await expect(page.getByRole('dialog', { name: 'Evidence before certainty.' })).toHaveCount(0);
  await expect(trigger).toBeFocused();
});

test('screen accessibility checks include all routes and expanded instructor controls', async ({ page }) => {
  for (const route of ['home', 'lab', 'console', 'aar', 'progress', 'unit', 'instructor']) {
    await page.goto(`/#/${route}`);
    await expect(page.getByTestId('history-state')).toHaveAttribute('data-state','saved');
    if (route === 'lab') await page.getByRole('button', { name: /Instructor options/ }).click();
    const results = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa', 'wcag21aa']).analyze();
    expect(results.violations, `${route}: ${JSON.stringify(results.violations.map(v => ({ id: v.id, targets: v.nodes.map(n => n.target) })))}`).toEqual([]);
  }
  await page.goto('/#/lab');
  await page.getByRole('button', { name: 'Review briefing' }).click();
  const briefingResults = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa', 'wcag21aa']).analyze();
  expect(briefingResults.violations, 'configured briefing accessibility').toEqual([]);
  if (await page.getByRole('button', { name: 'Open navigation' }).isVisible()) await page.getByRole('button', { name: 'Open navigation' }).click();
  await page.getByRole('button', { name: 'Training guide' }).click();
  const guideResults = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa', 'wcag21aa']).analyze();
  expect(guideResults.violations, 'training guide accessibility').toEqual([]);
});

test('loaded shell navigates offline with no external resource requirements', async ({ page, context }) => {
  const external: string[] = [];
  page.on('request', req => { if (!req.url().startsWith('http://127.0.0.1:5173') && !req.url().startsWith('data:')) external.push(req.url()); });
  await page.goto('/'); await expect(page.getByRole('heading', { name: 'Ready for the next decision?' })).toBeVisible();
  await context.setOffline(true);
  await page.getByRole('button', { name: 'Start training' }).click();
  await expect(page.getByRole('heading', { name: 'Scenario Lab', level: 1 })).toBeVisible();
  await page.getByRole('button', { name: 'Review briefing' }).click();
  await expect(page.getByText('MISSION INTENT')).toBeVisible();
  expect(external).toEqual([]);
});

test('anonymous profile management updates the workspace, without fake history', async ({ page }) => {
  await page.goto('/#/instructor');
  await page.getByLabel('New anonymous profile').fill('Cadet Echo');
  await page.getByRole('button', { name: 'Add profile' }).click();
  await expect(page.getByLabel('Active trainee profile')).toHaveValue(/trainee-/);
  await expect(page.getByRole('status')).toHaveText('Cadet Echo added to this workspace. Check local save status before reload.');
  await navigate(page, 'Unit performance');
  await expect(page.getByRole('row', { name: /Cadet Echo/ })).toContainText('0 sessions');
});

test('captures the verified foundation UI', async ({ page }, testInfo) => {
  await page.goto('/');
  await expect(page.getByTestId('history-state')).toHaveAttribute('data-state','saved');
  await page.screenshot({ path: `docs/screenshots/phase6-home-${testInfo.project.name}.png`, animations: 'disabled' });
  await page.getByRole('button', { name: 'Start training' }).click();
  await expect(page.getByRole('heading', { name: 'Scenario Lab', level: 1 })).toBeVisible();
  await page.screenshot({ path: `docs/screenshots/phase6-lab-${testInfo.project.name}.png`, animations: 'disabled' });
});

test('navigation is keyboard-accessible and the mobile drawer closes with Escape', async ({ page }) => {
  await page.goto('/');
  const opener = page.getByRole('button', { name: 'Open navigation' });
  if (await opener.isVisible()) {
    await expect(page.locator('.sidebar')).toHaveAttribute('inert', '');
    await opener.click();
    await expect(page.getByRole('dialog', { name: 'Application sidebar' })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Close navigation', exact: true }).last()).toBeFocused();
    await page.keyboard.press('Escape');
    await expect(page.locator('.sidebar')).toHaveAttribute('inert', '');
    await expect(opener).toBeFocused();
  } else {
    await expect(page.getByRole('navigation', { name: 'Main navigation' })).toBeVisible();
    await expect(page.locator('.sidebar')).not.toHaveAttribute('inert', '');
  }
});

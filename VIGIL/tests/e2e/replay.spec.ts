import { expect, test, type Page } from '@playwright/test';
import { auditWorker, finalRecord, lastView, navigate, assertAccessible, assertNoAnswerLeak } from './workerHarness';
import { createReplayTimeline, replayFrame, seekReplayEvent, seekReplayTime } from '../../src/replay/replay';
import { formatTime } from '../../src/domain/training';
import type { SessionRecord } from '../../src/domain/types';

async function configure(page: Page, weak = false, delay = 0) {
  await page.goto('/#/lab');
  await page.getByLabel('Exercise duration (seconds)').fill('60');
  await page.getByLabel('Random seed', {exact:true}).fill('1');
  await page.getByRole('slider',{name:/Sensor reliability/}).press('End');
  await page.getByLabel('Observation noise',{exact:true}).selectOption(weak ? '0.25' : '0.02');
  await page.getByLabel('Observation delay (seconds)').fill(String(delay));
  if(weak) { await page.getByRole('button',{name:'Night',exact:true}).click();await page.getByLabel('Weather & visibility').selectOption('rain'); }
  await page.getByRole('button',{name:'Review briefing',exact:true}).click();
  await expect(page.getByText('Local worker ready',{exact:true})).toBeVisible();
}
/** Capture the real fixed-height workspace viewport, not an over-tall element clipped by its scroll parent. */
async function captureAt(page:Page, selector:string, path:string) {
  await page.locator('.main-content').evaluate((main,query)=>{ const target=main.querySelector(query);if(!target)throw new Error(`Missing capture target ${query}`);main.scrollTop+=target.getBoundingClientRect().top-main.getBoundingClientRect().top-14; },selector);
  await page.screenshot({path,animations:'disabled'});
}
async function startConfigured(page:Page) { await page.getByRole('button',{name:'Start exercise',exact:true}).click(); }
async function finishNaturally(page:Page) { await page.getByLabel('Clock',{exact:true}).selectOption('4');await expect(page.getByTestId('exercise-result')).toBeVisible({timeout:25000});return finalRecord(page); }
async function assertFrame(page:Page,record:SessionRecord,eventId?:string,time?:number) {
  const model=createReplayTimeline(record);const cursor=eventId ? seekReplayEvent(model,eventId) : seekReplayTime(model,time!);const frame=replayFrame(model,cursor);const panel=page.getByTestId('replay-panel');
  await expect(page.getByTestId('replay-event-count')).toHaveText(`${cursor.eventCount} / ${record.events.length}`);
  await expect(page.getByTestId('replay-time')).toHaveText(formatTime(cursor.time));
  await expect(page.getByTestId('replay-source-status')).toHaveAttribute('data-status',frame.view.status);
  await expect(panel.locator('.observed-marker')).toHaveCount(frame.view.tracks.length);
  for(const track of frame.view.tracks) { const marker=panel.getByTestId(`track-marker-${track.id}`);await expect(marker).toHaveAttribute('data-observed-x',String(track.latest.x));await expect(marker).toHaveAttribute('data-observed-y',String(track.latest.y));await expect(marker).toHaveAttribute('data-captured-at',String(track.latest.capturedAt));await expect(marker).toHaveAttribute('data-delivered-at',String(track.latest.deliveredAt)); }
  await expect(page.getByTestId('final-score')).toHaveText(record.evaluation.score.toFixed(1));
  expect(await page.locator('.main-content').evaluate(el=>el.scrollWidth<=el.clientWidth+1)).toBe(true);
}
async function jumpLog(page:Page,record:SessionRecord,eventId:string) { const event=record.events.find(e=>e.id===eventId)!;await page.locator(`.event-row[data-event-id="${eventId}"]`).getByRole('button',{name:`Replay event ${event.order} at ${formatTime(event.time)}`,exact:true}).click();await assertFrame(page,record,eventId); }

test('real offline replay: penalty anchors, exact prefixes, ordered same-second steps and read-only pacing',async({page,context},testInfo)=>{
  test.setTimeout(90000);const errors:string[]=[];page.on('pageerror',e=>errors.push(e.message));await auditWorker(page);await configure(page,true);
  await page.waitForLoadState('networkidle');await context.setOffline(true);await startConfigured(page);
  await expect(page.getByRole('button',{name:'Select track T01',exact:true})).toBeVisible({timeout:15000});await page.getByRole('button',{name:'Select track T01',exact:true}).click();await page.getByRole('button',{name:'Mark as tracked',exact:true}).click();
  await page.getByRole('button',{name:'Requires review',exact:true}).click();await page.getByRole('slider',{name:/Assessment confidence/}).press('End');await page.getByRole('button',{name:'Record assessment',exact:true}).click();
  await page.getByLabel('Training disposition',{exact:true}).selectOption('escalate');await page.getByLabel('Observation summary',{exact:true}).fill('Synthetic exercise: a deliberately overconfident early report used to audit evidence-linked feedback.');await page.getByRole('button',{name:'Submit report',exact:true}).click();await expect(page.getByText('Report recorded · Training escalation',{exact:true})).toBeVisible();
  await assertNoAnswerLeak(page);const record=await finishNaturally(page);const before=JSON.stringify(record);const commands=await page.evaluate(()=>window.__vigilCommands.length);
  const p1=record.evaluation.findings.find(f=>f.ruleId==='P1')!;const p2=record.evaluation.findings.find(f=>f.ruleId==='P2')!;
  expect(p1).toMatchObject({points:4,appliedPenalty:true});expect(p2).toMatchObject({points:8,appliedPenalty:true});expect(record.evaluation.penaltyPoints).toBe(12);
  await expect(page.getByTestId('replay-event-count')).toHaveText(`0 / ${record.events.length}`);await expect(page.getByTestId('replay-panel').locator('.observed-marker')).toHaveCount(0);
  await page.getByRole('button',{name:'Inspect P1 evidence for T01',exact:true}).click();await assertFrame(page,record,p1.anchorEventId);await expect(page.getByTestId('replay-assessment')).toContainText('Requires review');await expect(page.getByTestId('replay-report')).toHaveText('No report recorded');
  await page.getByRole('button',{name:'Inspect P2 evidence for T01',exact:true}).click();await assertFrame(page,record,p2.anchorEventId);await expect(page.getByTestId('replay-report')).toHaveText('Training escalation');
  const same=record.events.findIndex((event,index)=>index>0&&event.time===record.events[index-1].time);expect(same).toBeGreaterThan(0);
  await jumpLog(page,record,record.events[same-1].id);const next=page.getByRole('button',{name:'Next recorded event',exact:true});await next.focus();await page.keyboard.press('Enter');await assertFrame(page,record,record.events[same].id);await page.getByRole('button',{name:'Previous recorded event',exact:true}).click();await assertFrame(page,record,record.events[same-1].id);
  const scrub=page.getByLabel('Replay position in simulation seconds');await scrub.focus();await scrub.press('Home');await assertFrame(page,record,undefined,0);await scrub.press('ArrowRight');await assertFrame(page,record,undefined,1);await page.getByRole('button',{name:'Go to replay start',exact:true}).click();
  await page.getByLabel('Replay speed',{exact:true}).selectOption('4');await page.getByRole('button',{name:'Play replay',exact:true}).click();await expect(page.getByTestId('replay-time')).not.toHaveText('00:00');await page.getByRole('button',{name:'Pause replay',exact:true}).click();const paused=await page.getByTestId('replay-time').textContent();await page.waitForTimeout(650);await expect(page.getByTestId('replay-time')).toHaveText(paused!);
  await page.getByRole('button',{name:'Go to replay end',exact:true}).click();await assertFrame(page,record,record.events.at(-1)!.id);await expect(page.getByTestId('replay-playback-state')).toHaveText('At end');
  await page.getByRole('button',{name:'Inspect P1 evidence for T01',exact:true}).click();await page.getByTestId('replay-panel').getByText('Delivered observations',{exact:false}).click();await assertAccessible(page,'read-only replay with delivered evidence open');await captureAt(page,'[data-testid="replay-panel"]',`docs/screenshots/phase6-replay-${testInfo.project.name}.png`);await captureAt(page,'.replay-inspector',`docs/screenshots/phase6-replay-evidence-${testInfo.project.name}.png`);
  await page.getByText('How this score was calculated',{exact:true}).click();await page.getByText('Inspect audit',{exact:true}).click();const audit=page.getByTestId('audit-T01-classification');await audit.getByText(/recorded references/).click();await expect(audit.locator('[data-evidence-id]')).toHaveCount(record.evaluation.tracks[0].metrics.find(m=>m.key==='classification')!.eventIds.length);await assertAccessible(page,'expanded actual rubric and per-track audit');await captureAt(page,'.review-track-audits',`docs/screenshots/phase6-audit-${testInfo.project.name}.png`);
  expect(await page.evaluate(()=>window.__vigilCommands.length)).toBe(commands);expect(JSON.stringify(await finalRecord(page))).toBe(before);expect(errors).toEqual([]);
});

test('missing significant report links to the real terminal opportunity without invented decisions',async({page},testInfo)=>{
  test.setTimeout(60000);await auditWorker(page);await configure(page);await startConfigured(page);const record=await finishNaturally(page);
  const p3=record.evaluation.findings.find(f=>f.ruleId==='P3')!;expect(p3).toMatchObject({points:5,anchorEventId:record.events.at(-1)!.id});expect(record.evaluation.score).toBe(0);expect(record.events.filter(e=>e.type==='action')).toHaveLength(0);
  await page.getByRole('button',{name:'Inspect P3 evidence for T01',exact:true}).click();await assertFrame(page,record,p3.anchorEventId);await expect(page.getByTestId('replay-tracking')).toHaveText('Not recorded');await expect(page.getByTestId('replay-assessment')).toHaveText('Not recorded');await expect(page.getByTestId('replay-report')).toHaveText('No report recorded');
  await page.getByRole('button',{name:'Your actions',exact:true}).click();await expect(page.getByText('No trainee actions were recorded in this exercise.',{exact:true})).toBeVisible();await assertAccessible(page,'missing actions and terminal evidence opportunity');
  expect(await page.getByTestId('replay-panel').getAttribute('data-session-id')).toBe(record.id);expect(await page.locator('.main-content').evaluate(el=>el.scrollWidth<=el.clientWidth+1)).toBe(true);
  await captureAt(page,'[data-testid="replay-panel"]',`docs/screenshots/phase6-missing-report-${testInfo.project.name}.png`);
});

test('aborted before any arrival replays only its real lifecycle, including same-second empty partials',async({page},testInfo)=>{
  test.setTimeout(45000);await auditWorker(page);await configure(page,false,8);await startConfigured(page);await page.getByRole('button',{name:'End early',exact:true}).click();await page.getByRole('button',{name:'End & review partial result',exact:true}).click();await expect(page.getByTestId('exercise-result')).toBeVisible();const record=await finalRecord(page);
  expect(record.status).toBe('aborted');expect(record.events.map(e=>e.type)).toEqual(['started','paused','finished']);expect(record.elapsedSeconds).toBeLessThan(9);expect(record.evaluation.comparable).toBe(false);expect(record.evaluation.penaltyPoints).toBe(0);expect(record.evaluation.findings.some(f=>f.ruleId==='E0')).toBe(true);
  await page.getByRole('button',{name:'Next recorded event',exact:true}).click();await assertFrame(page,record,record.events[0].id);await page.getByRole('button',{name:'Next recorded event',exact:true}).click();await assertFrame(page,record,record.events[1].id);await expect(page.getByTestId('replay-panel').locator('.map-paused')).toHaveCount(0);await page.getByRole('button',{name:'Next recorded event',exact:true}).click();await assertFrame(page,record,record.events[2].id);await expect(page.getByTestId('replay-panel').locator('.observed-marker')).toHaveCount(0);await expect(page.getByText('Partial · aborted',{exact:true})).toBeVisible();await assertAccessible(page,'empty aborted recorded replay');
  await captureAt(page,'[data-testid="replay-panel"]',`docs/screenshots/phase6-empty-replay-${testInfo.project.name}.png`);
});

test('prior replay unmounts, all answers lock during a new live attempt, and session switching resets playback',async({page})=>{
  test.setTimeout(75000);await auditWorker(page);await configure(page);await startConfigured(page);const first=await finishNaturally(page);await page.getByRole('button',{name:'Go to replay end',exact:true}).click();await page.getByRole('button',{name:'Play replay again',exact:true}).click();
  await navigate(page,'Scenario Lab');await page.getByRole('button',{name:'Review briefing',exact:true}).click();await startConfigured(page);await expect.poll(async()=>(await lastView(page))?.sessionId).not.toBe(first.id);await navigate(page,'After-action review');
  await expect(page.getByText('Finish the exercise before reviewing answers',{exact:true})).toBeVisible();await expect(page.getByTestId('replay-panel')).toHaveCount(0);await expect(page.getByTestId('final-score')).toHaveCount(0);await expect(page.getByRole('region',{name:'Per-track scoring audit'})).toHaveCount(0);await expect(page.getByRole('region',{name:'Per-track evaluation outcomes'})).toHaveCount(0);await assertAccessible(page,'prior answers and replay locked during active attempt');
  await page.getByRole('button',{name:'Return to console',exact:true}).last().click();await page.getByRole('button',{name:'End early',exact:true}).click();await page.getByRole('button',{name:'End & review partial result',exact:true}).click();await expect(page.getByTestId('exercise-result')).toBeVisible();const second=await finalRecord(page);expect(second.id).not.toBe(first.id);await expect(page.getByTestId('replay-panel')).toHaveAttribute('data-session-id',second.id);await expect(page.getByTestId('replay-order')).toHaveText('#000');
  await page.getByLabel('Result session',{exact:true}).selectOption(first.id);await expect(page.getByTestId('replay-panel')).toHaveAttribute('data-session-id',first.id);await page.getByRole('button',{name:'Play replay',exact:true}).click();await page.getByLabel('Result session',{exact:true}).selectOption(second.id);await expect(page.getByTestId('replay-order')).toHaveText('#000');await expect(page.getByLabel('Replay speed',{exact:true})).toHaveValue('1');await page.waitForTimeout(1100);await expect(page.getByTestId('replay-order')).toHaveText('#000');
  await assertNoAnswerLeak(page);
});

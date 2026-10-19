import { describe, expect, it } from 'vitest';
import { testEngine } from '../test/fixtures';
import { recordedExercise } from '../test/reviewFixtures';
import type { ReplayCursor } from '../domain/types';
import { advanceReplay, beginReplay, createReplayTimeline, endReplay, isReplayEnd, replayFrame, seekReplayEvent, seekReplayTime, stepReplayEvent } from './replay';

describe('replay-1 recorded-prefix projection', () => {
  it('starts before the first event with no fictional observation/action', () => {
    const timeline = createReplayTimeline(recordedExercise()); const frame = replayFrame(timeline, beginReplay());
    expect(frame.view.events).toEqual([]); expect(frame.view.tracks).toEqual([]); expect(frame.view.status).toBe('briefing');
    expect(frame.lastEvent).toBeNull(); expect(frame.recordedSelectionId).toBeNull();
  });
  it('projects the exact recorded prefix at every event, never a later decision', () => {
    const record = recordedExercise(); const timeline = createReplayTimeline(record);
    for (const event of record.events) {
      const frame = replayFrame(timeline, seekReplayEvent(timeline, event.id));
      const prefix = record.events.slice(0,event.order);
      expect(frame.view.events).toEqual(prefix); expect(frame.lastEvent).toEqual(event);
      const delivered = prefix.filter(e => e.type === 'observation').map(e => e.data.observation);
      expect(frame.view.tracks.flatMap(t => t.observations).length).toBe(delivered.length);
      for (const track of frame.view.tracks) {
        const latestCapture = Math.max(...delivered.filter(o => o.trackId === track.id).map(o => o.capturedAt));
        expect(track.latest.capturedAt).toBe(latestCapture);
        const assessments = prefix.filter(e => e.type === 'action' && e.data.action.trackId === track.id && e.data.action.kind === 'classify');
        expect(track.classification?.eventId ?? null).toBe(assessments.at(-1)?.id ?? null);
        const reports = prefix.filter(e => e.type === 'action' && e.data.action.trackId === track.id && e.data.action.kind === 'report');
        expect(track.report?.eventId ?? null).toBe(reports.at(-1)?.id ?? null);
      }
    }
  });
  it('time seeks include all and only events at or before each recorded second', () => {
    const record = recordedExercise(); const timeline = createReplayTimeline(record);
    for (let time = 0; time <= record.elapsedSeconds; time++) {
      const cursor = seekReplayTime(timeline, time); const frame = replayFrame(timeline, cursor);
      expect(frame.view.events).toEqual(record.events.filter(e => e.time <= time)); expect(frame.view.elapsedSeconds).toBe(time);
    }
  });
  it('distinguishes assessment/report and pause/resume sharing the same second', () => {
    const timeline = createReplayTimeline(recordedExercise());
    const assessment = timeline.events.find(e => e.type === 'action' && e.data.action.kind === 'classify')!;
    const atAssessment = seekReplayEvent(timeline, assessment.id); const before = stepReplayEvent(timeline, atAssessment, -1);
    expect(before.time).toBe(atAssessment.time); expect(replayFrame(timeline,before).view.tracks[0].classification).toBeNull();
    expect(replayFrame(timeline,atAssessment).view.tracks[0].classification).not.toBeNull(); expect(replayFrame(timeline,atAssessment).view.tracks[0].report).toBeNull();
    expect(replayFrame(timeline,stepReplayEvent(timeline,atAssessment,1)).view.tracks[0].report).not.toBeNull();
    const paused = timeline.events.find(e => e.type === 'paused')!;
    const cursor = seekReplayEvent(timeline,paused.id);
    expect(replayFrame(timeline,cursor).view.status).toBe('paused'); expect(replayFrame(timeline,stepReplayEvent(timeline,cursor,1)).view.status).toBe('running');
  });
  it('uses delivered capture/arrival/source and recorded health, without projecting a gap', () => {
    const timeline = createReplayTimeline(recordedExercise());
    const a = replayFrame(timeline,seekReplayTime(timeline,1)); const b = replayFrame(timeline,seekReplayTime(timeline,2));
    expect(b.view.tracks[0].latest).toEqual(a.view.tracks[0].latest);
    expect(replayFrame(timeline,seekReplayTime(timeline,3)).view.tracks[0].latest.source).toBe('requested');
    const disruption = timeline.events.find(e => e.type === 'sensor_change' && e.data.health === 'degraded')!;
    expect(replayFrame(timeline,seekReplayTime(timeline,disruption.time - 1)).view.sensorHealth).toBe('nominal');
    expect(replayFrame(timeline,seekReplayEvent(timeline,disruption.id)).view.sensorHealth).toBe('degraded');
    expect(replayFrame(timeline,endReplay(timeline)).view.sensorHealth).toBe('nominal');
  });
  it('keeps recorded selection separate from inspector choices', () => {
    const timeline = createReplayTimeline(recordedExercise()); const select = timeline.events.find(e => e.type === 'action' && e.data.action.kind === 'select')!;
    expect(replayFrame(timeline,seekReplayEvent(timeline,select.id)).recordedSelectionId).toBe('T01');
    expect(replayFrame(timeline,stepReplayEvent(timeline,seekReplayEvent(timeline,select.id),-1)).recordedSelectionId).toBeNull();
  });
  it('does not import hidden paths, categories, rubric or future disruption into the timeline/frame', () => {
    const timeline = createReplayTimeline(recordedExercise());
    for (const value of [timeline, replayFrame(timeline,endReplay(timeline))]) for (const key of ['origin','velocity','phase','rubric','weights','significant','degradation']) expect(JSON.stringify(value)).not.toContain(`"${key}":`);
  });
  it('faithfully uses recorded coordinates rather than re-running seed/model truth', () => {
    const record = recordedExercise(); const event = record.events.find(e => e.type === 'observation')!;
    if (event.type !== 'observation') throw new Error('fixture'); event.data.observation.x = 97.12; event.data.observation.y = 3.4;
    const timeline = createReplayTimeline(record); const observed = replayFrame(timeline,seekReplayEvent(timeline,event.id)).view.tracks[0].latest;
    expect(observed.x).toBe(97.12); expect(observed.y).toBe(3.4);
  });
  it('detaches and freezes the timeline; frame/source mutation cannot affect future frames or scores', () => {
    const record = recordedExercise(); const before = structuredClone(record); const timeline = createReplayTimeline(record);
    const frame = replayFrame(timeline,endReplay(timeline)); frame.view.tracks[0].latest.x = 100; frame.view.events.length = 0;
    expect(record).toEqual(before); expect(replayFrame(timeline,endReplay(timeline)).view.tracks[0].latest.x).not.toBe(100);
    expect(() => { timeline.events[0].time = 1; }).toThrow();
    record.events.length = 0; expect(timeline.events.length).toBe(before.events.length);
  });
  it('reaches the same final frame with chunked playback, time seek and direct event stepping', () => {
    const timeline = createReplayTimeline(recordedExercise()); let cursor = beginReplay();
    for (let t = 0; t < 60; t += 4) cursor = advanceReplay(timeline,cursor,4);
    expect(cursor).toEqual(endReplay(timeline)); expect(isReplayEnd(timeline,cursor)).toBe(true);
    let steps = beginReplay(); for (const _ of timeline.events) steps = stepReplayEvent(timeline,steps,1);
    expect(replayFrame(timeline,steps)).toEqual(replayFrame(timeline,cursor));
    expect(stepReplayEvent(timeline,steps,1)).toEqual(steps);
    expect(advanceReplay(timeline,steps,999)).toEqual(steps);
  });
  it('previous from a gap returns to the most recent event before removing it', () => {
    const timeline = createReplayTimeline(recordedExercise()); const gap = seekReplayTime(timeline,2);
    const previous = stepReplayEvent(timeline,gap,-1); expect(previous.eventCount).toBe(gap.eventCount); expect(previous.time).toBe(1);
    expect(stepReplayEvent(timeline,previous,-1).eventCount).toBe(gap.eventCount-1);
    expect(stepReplayEvent(timeline,beginReplay(),-1)).toEqual(beginReplay());
  });
  it('clamps seeks but rejects nonfinite time, unknown events and invalid advance inputs', () => {
    const timeline = createReplayTimeline(recordedExercise());
    expect(seekReplayTime(timeline,-10)).toEqual(seekReplayTime(timeline,0)); expect(seekReplayTime(timeline,999)).toEqual(endReplay(timeline));
    expect(() => seekReplayTime(timeline,NaN)).toThrow(); expect(() => seekReplayEvent(timeline,'fiction')).toThrow();
    expect(() => advanceReplay(timeline,beginReplay(),-.1)).toThrow(); expect(advanceReplay(timeline,beginReplay(),0)).toEqual(beginReplay());
  });
  it.each([{time:NaN,eventCount:0},{time:2,eventCount:0},{time:0,eventCount:999},{time:0,eventCount:2},{time:1,eventCount:-1},{time:.5,eventCount:1}])('rejects an inconsistent cursor %j', cursor => {
    expect(() => replayFrame(createReplayTimeline(recordedExercise()),cursor as ReplayCursor)).toThrow();
  });
  it('replays zero-evidence zero-duration abort without dividing by zero or inventing time', () => {
    const e = testEngine({delaySeconds:8}); e.start(); e.finish(); const record = e.completedRecord(); const timeline = createReplayTimeline(record);
    expect(timeline.durationSeconds).toBe(0); expect(timeline.events).toHaveLength(2);
    const started = stepReplayEvent(timeline,beginReplay(),1); expect(started).toEqual({time:0,eventCount:1});
    expect(replayFrame(timeline,started).view.status).toBe('running');
    expect(replayFrame(timeline,stepReplayEvent(timeline,started,1)).view.status).toBe('aborted');
    expect(replayFrame(timeline,endReplay(timeline)).view.tracks).toEqual([]);
  });
  it('ends an aborted partial at its actual duration, not the planned duration', () => {
    const e = testEngine(); e.start(); e.advance(7); e.finish(); const timeline = createReplayTimeline(e.completedRecord());
    expect(endReplay(timeline).time).toBe(7); expect(replayFrame(timeline,seekReplayTime(timeline,60)).view.status).toBe('aborted');
  });
  it('retains latest-capture semantics on genuine out-of-order delivered evidence', () => {
    let inversions = 0;
    for (let seed = 0; seed < 24; seed++) {
      const e = testEngine({seed,environment:'urban',lighting:'night',weather:'rain',reliability:1,noise:.02,durationSeconds:90}); e.start();
      for (let t = 0; t < 90; t++) { const track = e.getView().tracks[0]; if (track && (track.lastRequestedAt === null || t-track.lastRequestedAt >= 8)) e.action({kind:'request_observation',trackId:track.id}); e.advance(1); }
      const timeline = createReplayTimeline(e.completedRecord()); let max = -1;
      for (const event of timeline.events) if (event.type === 'observation') {
        if (event.data.observation.capturedAt < max) { inversions++; expect(replayFrame(timeline,seekReplayEvent(timeline,event.id)).view.tracks[0].latest.capturedAt).toBe(max); }
        max = Math.max(max,event.data.observation.capturedAt);
      }
    }
    expect(inversions).toBeGreaterThan(0);
  });
  it.each(['schema','session','outcome','duration','order','missing-finish','unknown-reference','future-reference','unknown-anchor'])('rejects %s rather than sorting or repairing a plausible replay', kind => {
    const record = recordedExercise();
    if (kind === 'schema') record.schemaVersion = 2 as 3;
    if (kind === 'session') record.id = 'other';
    if (kind === 'outcome') record.status = 'aborted';
    if (kind === 'duration') record.elapsedSeconds--;
    if (kind === 'order') record.events[1].order = 999;
    if (kind === 'missing-finish') record.events.pop();
    if (kind === 'unknown-reference') record.evaluation.metrics[0].evidenceIds.push('fiction');
    if (kind === 'future-reference') record.evaluation.findings[0].eventIds.push(record.events.at(-1)!.id);
    if (kind === 'unknown-anchor') record.evaluation.findings[0].anchorEventId = 'fiction';
    expect(() => createReplayTimeline(record)).toThrow();
  });
});

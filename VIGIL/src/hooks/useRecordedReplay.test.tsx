import { act, cleanup, renderHook } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { recordedExercise } from '../test/reviewFixtures';
import { testEngine } from '../test/fixtures';
import { createReplayTimeline } from '../replay/replay';
import { useRecordedReplay } from './useRecordedReplay';

afterEach(() => { cleanup(); vi.useRealTimers(); });
const timeline = () => createReplayTimeline(recordedExercise());

describe('read-only recorded playback lifecycle', () => {
  it('initializes paused before Start, without a pacing timer', () => {
    vi.useFakeTimers(); const {result}=renderHook(()=>useRecordedReplay(timelineStable));
    expect(result.current.cursor).toEqual({time:0,eventCount:0});expect(result.current.playing).toBe(false);expect(vi.getTimerCount()).toBe(0);
  });
  const timelineStable=timeline();
  it('paces 1x/2x/4x from actual recorded seconds, not generated data', () => {
    vi.useFakeTimers();const {result}=renderHook(()=>useRecordedReplay(timelineStable));
    act(()=>result.current.toggle());act(()=>vi.advanceTimersByTime(2000));expect(result.current.cursor.time).toBe(2);
    act(()=>result.current.setSpeed(2));act(()=>vi.advanceTimersByTime(1000));expect(result.current.cursor.time).toBe(4);
    act(()=>result.current.setSpeed(4));act(()=>vi.advanceTimersByTime(1000));expect(result.current.cursor.time).toBe(8);
    expect(result.current.frame.view.events.every(e=>e.time<=8)).toBe(true);
  });
  it('pause freezes the cursor across wall time and cleans its timer', () => {
    vi.useFakeTimers();const {result}=renderHook(()=>useRecordedReplay(timelineStable));
    act(()=>result.current.toggle());act(()=>vi.advanceTimersByTime(1000));act(()=>result.current.pause());const cursor=result.current.cursor;
    act(()=>vi.advanceTimersByTime(5000));expect(result.current.cursor).toEqual(cursor);expect(vi.getTimerCount()).toBe(0);
  });
  it('seek, exact event jump, step and inspector selection stop playback without new actions', () => {
    vi.useFakeTimers();const {result}=renderHook(()=>useRecordedReplay(timelineStable));
    act(()=>result.current.toggle());act(()=>result.current.seekTime(4));expect(result.current.playing).toBe(false);
    const assessment=timelineStable.events.find(e=>e.type==='action'&&e.data.action.kind==='classify')!;
    act(()=>result.current.seekEvent(assessment.id,'T01'));expect(result.current.cursor.eventCount).toBe(assessment.order);expect(result.current.frame.view.tracks[0].report).toBeNull();
    act(()=>result.current.step(1));expect(result.current.frame.view.tracks[0].report).not.toBeNull();
    const events=JSON.stringify(result.current.frame.view.events);act(()=>result.current.inspectTrack('T01'));expect(JSON.stringify(result.current.frame.view.events)).toBe(events);
    expect(result.current.inspectedTrackId).toBe('T01');expect(vi.getTimerCount()).toBe(0);
  });
  it('stops exactly at the actual end and supports Play again from the beginning', () => {
    vi.useFakeTimers();const {result}=renderHook(()=>useRecordedReplay(timelineStable));
    act(()=>{result.current.setSpeed(4);result.current.toggle();});act(()=>vi.advanceTimersByTime(16000));
    expect(result.current.atEnd).toBe(true);expect(result.current.playing).toBe(false);expect(result.current.cursor.time).toBe(60);expect(vi.getTimerCount()).toBe(0);
    act(()=>result.current.toggle());expect(result.current.cursor.eventCount).toBe(0);expect(result.current.playing).toBe(true);
  });
  it('begin/end reset precisely and do not mutate the underlying record/evaluation', () => {
    const record=recordedExercise();const before=structuredClone(record);const model=createReplayTimeline(record);const {result}=renderHook(()=>useRecordedReplay(model));
    act(()=>result.current.end());expect(result.current.atEnd).toBe(true);act(()=>result.current.begin());expect(result.current.cursor.eventCount).toBe(0);expect(result.current.inspectedTrackId).toBeNull();expect(record).toEqual(before);
  });
  it('new shorter/zero-duration record safely resets position, speed, selection and playback', () => {
    vi.useFakeTimers();const a=timeline();const e=testEngine({delaySeconds:8},'second-empty');e.start();e.finish();const b=createReplayTimeline(e.completedRecord());
    const {result,rerender}=renderHook(({model})=>useRecordedReplay(model),{initialProps:{model:a}});
    act(()=>{result.current.seekTime(30);result.current.setSpeed(4);result.current.inspectTrack('T01');result.current.toggle();});
    rerender({model:b});expect(result.current.cursor).toEqual({time:0,eventCount:0});expect(result.current.speed).toBe(1);expect(result.current.playing).toBe(false);expect(result.current.inspectedTrackId).toBeNull();expect(vi.getTimerCount()).toBe(0);
    act(()=>result.current.step(1));expect(result.current.frame.view.status).toBe('running');act(()=>result.current.step(1));expect(result.current.frame.view.status).toBe('aborted');
  });
  it('unmount removes the timer so leaving review cannot keep advancing a hidden player', () => {
    vi.useFakeTimers();const {result,unmount}=renderHook(()=>useRecordedReplay(timelineStable));act(()=>result.current.toggle());expect(vi.getTimerCount()).toBe(1);unmount();expect(vi.getTimerCount()).toBe(0);
  });
});

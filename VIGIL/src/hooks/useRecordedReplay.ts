import { useEffect, useMemo, useState } from 'react';
import type { ReplayCursor, ReplayTimeline } from '../domain/types';
import { advanceReplay, beginReplay, endReplay, eventTrackId, isReplayEnd, replayFrame, seekReplayEvent, seekReplayTime, stepReplayEvent } from '../replay/replay';

type Speed = 1 | 2 | 4;
interface PlaybackState { timeline: ReplayTimeline; cursor: ReplayCursor; speed: Speed; playing: boolean; inspectedTrackId: string | null }
const initial = (timeline: ReplayTimeline): PlaybackState => ({ timeline, cursor: beginReplay(), speed: 1, playing: false, inspectedTrackId: null });

/** Playback pacing only. Does not import a Worker, generator, scorer or workspace/session writer. */
export function useRecordedReplay(timeline: ReplayTimeline) {
  const [stored, setStored] = useState<PlaybackState>(() => initial(timeline));
  // A shorter/empty new record cannot render once using the previous record's out-of-range cursor.
  const state = stored.timeline === timeline ? stored : initial(timeline);
  useEffect(() => { setStored(initial(timeline)); }, [timeline]);
  const update = (change: (state: PlaybackState) => PlaybackState) => setStored(previous => change(previous.timeline === timeline ? previous : initial(timeline)));
  useEffect(() => {
    if (!state.playing) return;
    const timer = window.setInterval(() => setStored(previous => {
      if (previous.timeline !== timeline || !previous.playing) return previous;
      const cursor = advanceReplay(timeline, previous.cursor, 1);
      return { ...previous, cursor, playing: !isReplayEnd(timeline, cursor) };
    }), 1000 / state.speed);
    return () => window.clearInterval(timer);
  }, [timeline, state.playing, state.speed]);
  const frame = useMemo(() => replayFrame(timeline, state.cursor), [timeline, state.cursor]);
  return {
    timeline, frame, cursor: state.cursor, playing: state.playing, speed: state.speed, inspectedTrackId: state.inspectedTrackId,
    atEnd: isReplayEnd(timeline, state.cursor),
    toggle: () => update(s => ({ ...s, cursor: isReplayEnd(timeline, s.cursor) ? beginReplay() : s.cursor, playing: !s.playing })),
    pause: () => update(s => ({ ...s, playing: false })),
    setSpeed: (speed: Speed) => update(s => ({ ...s, speed })),
    begin: () => update(s => ({ ...s, cursor: beginReplay(), playing: false, inspectedTrackId: null })),
    end: () => update(s => ({ ...s, cursor: endReplay(timeline), playing: false })),
    seekTime: (seconds: number) => update(s => ({ ...s, cursor: seekReplayTime(timeline, seconds), playing: false })),
    seekEvent: (id: string, trackId?: string | null) => update(s => {
      const cursor = seekReplayEvent(timeline, id);
      return { ...s, cursor, playing: false, inspectedTrackId: trackId ?? eventTrackId(timeline.events[cursor.eventCount - 1]) };
    }),
    step: (direction: -1 | 1) => update(s => ({ ...s, cursor: stepReplayEvent(timeline, s.cursor, direction), playing: false })),
    inspectTrack: (id: string) => update(s => ({ ...s, inspectedTrackId: id, playing: false })),
  };
}
export type ReplayController = ReturnType<typeof useRecordedReplay>;

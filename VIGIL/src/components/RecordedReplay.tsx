import { ChevronLeft, ChevronRight, Clock3, ListOrdered, Pause, Play, Radio, ShieldCheck, SkipBack, SkipForward } from 'lucide-react';
import type { ReplayController } from '../hooks/useRecordedReplay';
import { CATEGORY_LABELS, DECISION_LABELS, describeEvent, formatTime } from '../domain/training';
import { observationAge } from '../domain/evidence';
import { ObservationMap } from './ObservationMap';

const SOURCE_STATUS = { briefing: 'Not started', running: 'Running', paused: 'Paused', completed: 'Completed', aborted: 'Aborted' };

/** Receives only a public replay controller; no hidden scenario or score/command writer. */
export function RecordedReplay({ replay }: { replay: ReplayController }) {
  const { frame, timeline, cursor } = replay; const { view } = frame;
  const chosen = replay.inspectedTrackId ?? frame.recordedSelectionId ?? view.tracks[0]?.id ?? null;
  const track = view.tracks.find(t => t.id === chosen);
  const delivered = view.events.filter(e => e.type === 'observation').length;
  const actions = view.events.filter(e => e.type === 'action').length;
  const x = (time: number) => 28 + time / Math.max(1,timeline.durationSeconds) * 844;
  return <section className="recorded-replay" aria-label="Recorded exercise replay" data-testid="replay-panel" data-session-id={timeline.sessionId}>
    <div className="replay-heading"><div><p className="eyebrow">RETURN TO THE EVIDENCE</p><h2>Recorded exercise replay</h2><p>See what had arrived before a decision—not what became clear later.</p></div><span className="replay-readonly"><ShieldCheck size={13}/>READ-ONLY · ACTUAL EVENTS</span></div>
    <div className="replay-transport">
      <div className="replay-controls"><button onClick={replay.begin} aria-label="Go to replay start" className="replay-icon" title="Before the first event"><SkipBack size={16}/></button><button onClick={() => replay.step(-1)} disabled={cursor.eventCount === 0} aria-label="Previous recorded event" className="replay-icon"><ChevronLeft size={17}/></button><button onClick={replay.toggle} disabled={timeline.durationSeconds === 0} className="replay-play" aria-label={replay.playing ? 'Pause replay' : replay.atEnd ? 'Play replay again' : 'Play replay'}>{replay.playing ? <Pause size={15}/> : <Play size={15}/>}<span>{replay.playing ? 'Pause' : replay.atEnd ? 'Play again' : 'Play'}</span></button><button onClick={() => replay.step(1)} disabled={cursor.eventCount === timeline.events.length} aria-label="Next recorded event" className="replay-icon"><ChevronRight size={17}/></button><button onClick={replay.end} aria-label="Go to replay end" className="replay-icon"><SkipForward size={16}/></button></div>
      <div className="replay-rate"><label htmlFor="replay-speed">Playback</label><select id="replay-speed" aria-label="Replay speed" value={replay.speed} onChange={e => replay.setSpeed(Number(e.target.value) as 1|2|4)}><option value="1">1×</option><option value="2">2×</option><option value="4">4×</option></select><span data-testid="replay-playback-state">{replay.playing ? 'Playing' : replay.atEnd ? 'At end' : 'Paused'}</span></div>
      <div className="replay-time"><Clock3 size={14}/><output data-testid="replay-time">{formatTime(cursor.time)}</output><span>/ {formatTime(timeline.durationSeconds)}</span></div>
    </div>
    <div className="replay-timeline"><div className="replay-timeline-caption"><span><ListOrdered size={12}/>RECORDED EVENT ORDER</span><span data-testid="replay-event-count">{cursor.eventCount} / {timeline.events.length}</span></div>
      <svg viewBox="0 0 900 78" role="img" aria-label={`${timeline.events.length} actual recorded events across ${timeline.durationSeconds} simulation seconds. The time scrubber includes all events at a second; event buttons inspect exact order.`}>
        <path d="M28 18H872M28 38H872M28 58H872" stroke="#3d5965" strokeWidth=".6" strokeDasharray="3 6"/>
        {timeline.events.map(event => { const y = event.type === 'observation' ? 18 : event.type === 'action' ? 38 : 58; const applied = event.order <= cursor.eventCount; const color = event.type === 'observation' ? '#8fcdbb' : event.type === 'action' ? '#c4d5e7' : '#edc58e'; return <circle key={event.id} cx={x(event.time)} cy={y} r={frame.lastEvent?.id === event.id ? 4 : 2.3} fill={color} opacity={applied ? 1 : .45}/>; })}
        <path d={`M${x(cursor.time)} 5V66`} stroke="#dfede8" strokeWidth="1.2"/>
      </svg>
      <label className="sr-only" htmlFor="replay-position">Replay position in simulation seconds</label><input id="replay-position" type="range" min="0" max={timeline.durationSeconds} step="1" value={cursor.time} disabled={timeline.durationSeconds === 0} aria-valuetext={`${formatTime(cursor.time)}, ${cursor.eventCount} of ${timeline.events.length} events applied`} onChange={e => replay.seekTime(Number(e.target.value))}/>
      <div className="replay-timeline-legend"><span><i/>Observation</span><span><i/>Trainee action</span><span><i/>Lifecycle / link</span><span>Same second? Step by event.</span></div>
    </div>
    <div className="replay-now"><span className="replay-event-number" data-testid="replay-order">#{String(cursor.eventCount).padStart(3,'0')}</span><p aria-live="polite" aria-atomic="true" data-testid="replay-current-event">{frame.lastEvent ? describeEvent(frame.lastEvent) : 'Before Start. No observations or decisions have been applied.'}</p><span className="replay-recorded-status">Recorded state <strong data-testid="replay-source-status" data-status={view.status}>{SOURCE_STATUS[view.status]}</strong></span></div>
    <div className="replay-evidence-grid"><div className="replay-map-panel"><div className="replay-panel-title"><Radio size={14}/><h3>What had been delivered</h3><span>{delivered} returns · {actions} actions</span></div><ObservationMap mode="replay" view={view} selectedId={track?.id ?? null} onSelect={replay.inspectTrack}/><div className="replay-prefix-facts"><span>Link at cursor: <strong>{view.sensorHealth}</strong></span><span>Recorded selection: <strong>{frame.recordedSelectionId ?? 'None'}</strong></span></div></div>
      <aside className="replay-inspector" aria-label="Recorded trainee evidence at cursor"><div className="replay-panel-title"><h3>Evidence at this moment</h3><span>NO HINDSIGHT</span></div>
        {view.tracks.length > 0 && <div className="replay-track-picker" aria-label="Inspect recorded tracks">{view.tracks.map(t => <button key={t.id} onClick={() => replay.inspectTrack(t.id)} aria-pressed={t.id === chosen} aria-label={`Inspect recorded track ${t.id}`}>{t.id}</button>)}</div>}
        {track ? <div className="replay-track-detail" data-testid="replay-track-detail" data-track-id={track.id}><div className="replay-selected-track"><strong>{track.id}</strong><span>{track.latest.confidence}% signal · {observationAge(track.latest,view.elapsedSeconds)}s capture age</span></div><dl className="replay-capture-facts"><div><dt>Captured</dt><dd>{formatTime(track.latest.capturedAt)}</dd></div><div><dt>Arrived</dt><dd>{formatTime(track.latest.deliveredAt)}</dd></div><div><dt>Actual delay</dt><dd>{track.latest.deliveredAt-track.latest.capturedAt}s</dd></div><div><dt>Source</dt><dd>{track.latest.source}</dd></div></dl>
          <dl className="replay-decision-facts"><div><dt>Tracking mark</dt><dd data-testid="replay-tracking">{track.trackedAt === null ? 'Not recorded' : formatTime(track.trackedAt)}</dd></div><div><dt>Assessment</dt><dd data-testid="replay-assessment">{track.classification ? `${CATEGORY_LABELS[track.classification.category]} · ${track.classification.confidence}%` : 'Not recorded'}</dd></div><div><dt>Final disposition</dt><dd data-testid="replay-report">{track.report ? DECISION_LABELS[track.report.decision] : 'No report recorded'}</dd></div></dl>
          {track.report && <div className="replay-recorded-summary"><span>ORIGINAL REPORT SUMMARY</span><p>{track.report.summary}</p></div>}
          <details className="replay-delivery-table"><summary>Delivered observations <span>{track.observations.length} so far</span></summary><div tabIndex={0} role="region" aria-label={`Replay delivered evidence for ${track.id}`}><table><thead><tr><th>Capture</th><th>Arrival</th><th>Signal</th><th>Source</th></tr></thead><tbody>{track.observations.slice(-6).map(o => <tr key={o.id}><td>{formatTime(o.capturedAt)}</td><td>{formatTime(o.deliveredAt)}</td><td>{o.confidence}%</td><td>{o.source}</td></tr>)}</tbody></table></div><p>Latest 6 actual arrivals in this prefix. The marker uses the newest capture.</p></details>
        </div> : <div className="replay-no-evidence"><Radio size={24}/><h4>{chosen ? `${chosen} had not been observed yet` : 'No delivered evidence yet'}</h4><p>Only observations already delivered at this cursor can appear. Step forward or follow an evidence link.</p></div>}
      </aside>
    </div>
    <p className="replay-footnote">Simulation-time replay. Original wall-clock pauses and speed changes were not recorded and are not reconstructed. Playback never adds actions or changes this score.{timeline.durationSeconds === 0 && ' This zero-duration partial has same-second events; use the event-step controls.'}</p>
  </section>;
}

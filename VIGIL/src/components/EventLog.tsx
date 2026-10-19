import { useState } from 'react';
import { Activity, ArrowDownLeft, ArrowUpRight, ClipboardCheck, Eye, Pause, Radio, Play } from 'lucide-react';
import type { SimulationEvent } from '../domain/types';
import { describeEvent, formatTime } from '../domain/training';

export function EventLog({ events, dark = false, limit, title = 'Recorded event log', selectedEventId, onInspect }: { events: readonly SimulationEvent[]; dark?: boolean; limit?: number; title?: string; selectedEventId?: string | null; onInspect?: (eventId: string) => void }) {
  const [filter, setFilter] = useState<'all' | 'action'>('all');
  const filtered = filter === 'all' ? events : events.filter(e => e.type === 'action');
  const shown = limit ? filtered.slice(-limit).reverse() : filtered;
  const hiddenSelection = selectedEventId && !shown.some(e => e.id === selectedEventId);
  return <section className={`event-log ${dark ? 'event-log--dark' : ''} ${onInspect ? 'event-log--linked' : ''}`} aria-label={title}>
    <div className="event-log-heading"><div><Activity size={15}/><h2>{title}</h2><span className="event-count" data-testid="event-count">{events.length} events</span></div><div className="log-filters" aria-label="Event filters"><button onClick={() => setFilter('all')} aria-pressed={filter === 'all'}>All events</button><button onClick={() => setFilter('action')} aria-pressed={filter === 'action'}>Your actions</button></div></div>
    {onInspect && hiddenSelection && <div className="event-filter-notice">The current replay event is hidden by this filter.<button onClick={() => setFilter('all')}>Show current event</button></div>}
    <div className="event-log-scroll" tabIndex={0} role="region" aria-label={`${title} entries`}>
      {shown.length === 0 ? <p className="event-log-empty">{onInspect ? 'No trainee actions were recorded in this exercise.' : filter === 'action' ? 'Your decisions will be recorded here.' : 'The event log begins when the exercise starts.'}</p> : <ol>{shown.map(event => {
        const Icon = event.type === 'observation' ? Radio : event.type === 'action' ? event.data.action.kind === 'report' ? ClipboardCheck : Eye : event.type === 'paused' ? Pause : event.type === 'resumed' || event.type === 'started' ? Play : ArrowDownLeft;
        return <li key={event.id} className={`event-row event-row--${event.type} ${selectedEventId === event.id ? 'event-row--current' : ''}`} data-event-id={event.id} aria-current={selectedEventId === event.id ? 'step' : undefined}><span className="event-order">#{String(event.order).padStart(3, '0')}</span><time>{formatTime(event.time)}</time><Icon size={13}/><p>{describeEvent(event)}</p>{onInspect && <button className="event-replay-link" onClick={() => onInspect(event.id)} aria-label={`Replay event ${event.order} at ${formatTime(event.time)}`}><ArrowUpRight size={12}/><span>Replay</span></button>}</li>;
      })}</ol>}
    </div>
    {limit && filtered.length > limit && <p className="event-log-foot">Latest {limit} of {filtered.length} matching events. The full log is retained for the result.</p>}
  </section>;
}

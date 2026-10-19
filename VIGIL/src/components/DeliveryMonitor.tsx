import { Radio } from 'lucide-react';
import type { ActiveSessionView } from '../domain/types';
import { deliveryFacts, isClearObservation, isStaleObservation } from '../domain/evidence';
import { formatTime } from '../domain/training';

/** Every point and statistic folds delivered public events, never hidden capture attempts. */
export function DeliveryMonitor({ view }: { view: ActiveSessionView }) {
  const facts = deliveryFacts(view.events);
  const start = Math.max(0, view.elapsedSeconds - 30); const end = Math.max(1, view.elapsedSeconds);
  const recent = facts.observations.filter(o => o.deliveredAt >= start);
  const stale = view.tracks.filter(t => isStaleObservation(t.latest, view.elapsedSeconds)).length;
  const description = `${facts.count} actual delivered observations; ${facts.requested} from requests; ${stale} observed tracks have stale evidence. Mean delivery delay ${facts.meanDelay === null ? 'not available' : `${facts.meanDelay.toFixed(1)} seconds`}.`;
  return <section className="delivery-monitor" aria-label="Delivered evidence monitor">
    <div className="workspace-panel-heading"><div><Radio size={14}/><h2>Delivery monitor</h2></div><span>ACTUAL DELIVERIES · LAST 30s</span></div>
    <div className="delivery-facts"><div><span>Delivered so far</span><strong data-testid="feed-delivered">{facts.count}</strong></div><div><span>Mean delay · n={facts.count}</span><strong data-testid="feed-delay">{facts.meanDelay === null ? '—' : `${facts.meanDelay.toFixed(1)}s`}</strong></div><div><span>Stale observed tracks</span><strong data-testid="feed-stale">{stale}<small> / {view.tracks.length}</small></strong></div></div>
    <svg viewBox="0 0 600 82" role="img" aria-label={description} className="delivery-timeline">
      <path d="M28 54H572M28 12V54M300 12V54M572 12V54" fill="none" stroke="#a9c3ca" strokeOpacity=".16" strokeDasharray="2 4"/>
      {recent.map(o => {
        const x = 28 + (o.deliveredAt - start) / (end - start) * 544;
        const index = Math.max(0, view.tracks.findIndex(t => t.id === o.trackId));
        const y = 20 + index * Math.min(5, 28 / Math.max(1, view.tracks.length)); const fill = isClearObservation(o) ? '#9bd9b7' : '#ebc88d';
        return o.source === 'requested' ? <rect key={o.id} x={x - 2.5} y={y - 2.5} width="5" height="5" fill={fill} transform={`rotate(45 ${x} ${y})`} data-testid="requested-delivery-point"/> : <circle key={o.id} cx={x} cy={y} r="2.5" fill={fill}/>;
      })}
      <g fill="#a9c0ca" fontSize="9" fontFamily="monospace"><text x="28" y="73">{formatTime(start)}</text><text x="300" y="73" textAnchor="middle">DELIVERY TIME</text><text x="572" y="73" textAnchor="end">{formatTime(end)}</text></g>
    </svg>
    <p className="delivery-monitor-note"><span>● Scheduled · ◆ Requested</span><span>Gaps mean no delivered evidence—not proof that a return disappeared.</span></p>
  </section>;
}

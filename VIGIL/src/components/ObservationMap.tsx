import { useId } from 'react';
import { Crosshair, Pause, Radio } from 'lucide-react';
import type { ActiveSessionView } from '../domain/types';
import { isStaleObservation } from '../domain/evidence';
import { SceneConditions } from './SceneConditions';
import { layoutObservationLabels, projectObservation } from './observationLayout';

/** Presentation reads only delivered observations. No hidden path or extrapolated position. */
export function ObservationMap({ view, selectedId, onSelect, mode = 'live' }: { mode?: 'live' | 'replay'; view: ActiveSessionView; selectedId: string | null; onSelect: (id: string) => void }) {
  const id = useId().replace(/:/g, ''); const c = view.scenario.config;
  const labels = layoutObservationLabels(view.tracks);
  return <div className={`observation-map observation-map--${c.lighting}`} data-testid="observation-map" data-mode={mode} data-pattern={c.trafficPattern} data-environment={c.environment} data-weather={c.weather}>
    <div className="observation-map-label"><span><Crosshair size={13}/>SECTOR A · SYNTHETIC TRAINING GRID</span><span>0–100 normalized units</span></div>
    <svg viewBox="0 0 600 460" role="group" aria-label={`Synthetic delivered observations, ${c.environment}, ${c.lighting}, ${c.weather}`} className="observation-svg">
      <defs><pattern id={`${id}grid`} width="38" height="38" patternUnits="userSpaceOnUse"><path d="M38 0H0V38" fill="none" stroke="currentColor" strokeOpacity=".12" strokeWidth=".7"/></pattern><clipPath id={`${id}bounds`}><rect x="35" y="20" width="530" height="405" rx="4"/></clipPath></defs>
      <g clipPath={`url(#${id}bounds)`}>
        <rect width="600" height="460" fill="var(--map-surface)"/><rect width="600" height="460" fill={`url(#${id}grid)`}/>
        {c.environment === 'urban' ? <g stroke="#7da3b2" strokeOpacity=".09" fill="none"><path d="m-30 145 200-90 450 240M90-20l40 160 330 340M-20 400 490 30M180 490 520 255l140 65" strokeWidth="12"/><path d="m220 90 57-35 48 35-60 40Zm150 130 62-35 55 50-75 30ZM70 270l45-25 38 33-43 28Z" fill="#72a7a0" fillOpacity=".14"/></g> : <g fill="none" stroke="#77a98d" strokeOpacity=".13"><path d="M-30 110Q120 12 210 135T420 130 650 40M-30 128Q120 30 210 153T420 148 650 58M-30 360Q100 240 220 330T640 300M-30 378Q100 258 220 348T640 318" strokeWidth="2"/><path d="M445-30q-100 150-70 200t-90 320" strokeWidth="12" strokeOpacity=".1"/></g>}
        <SceneConditions environment={c.environment} weather={c.weather}/>
        {[65,130,195].map(r => <circle key={r} cx="300" cy="225" r={r} fill="none" stroke="currentColor" strokeOpacity={r === 195 ? '.28' : '.15'} strokeDasharray={r === 195 ? '3 6' : undefined}/>)}
        <path d="M300 20v410M35 225h530" stroke="currentColor" strokeOpacity=".18" strokeWidth=".7"/>
        <circle cx="300" cy="225" r="3" fill="currentColor" opacity=".65"/><circle cx="300" cy="225" r="8" stroke="currentColor" opacity=".25" fill="none"/>
        {view.tracks.map(track => {
          const o = track.latest; const { x, y } = projectObservation(o); const label = labels[track.id];
          const lx = label.x - x; const ly = label.y - y;
          const stale = isStaleObservation(o, view.elapsedSeconds);
          const selected = selectedId === track.id;
          const color = stale || o.confidence < 60 ? '#e7bd80' : track.report ? '#a6b8c4' : '#8bdcba';
          const points = track.observations.slice().sort((a, b) => a.capturedAt - b.capturedAt || a.deliveredAt - b.deliveredAt).slice(-12).map(o => `${45 + o.x * 5.1},${425 - o.y * 4}`).join(' ');
          return <g key={track.id}>
            <polyline points={points} fill="none" stroke={color} strokeOpacity={selected ? '.6' : '.3'} strokeWidth="1.2" strokeDasharray="3 4"/>
            <g transform={`translate(${x}, ${y})`} className="observed-marker" role="button" tabIndex={0} aria-label={`Select ${track.id}, ${o.confidence}% signal confidence${stale ? ', stale observation' : ''}`} aria-pressed={selected} data-testid={`track-marker-${track.id}`} data-observed-x={o.x} data-observed-y={o.y} data-delivered-at={o.deliveredAt} data-captured-at={o.capturedAt} onClick={() => onSelect(track.id)} onKeyDown={e => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); e.stopPropagation(); onSelect(track.id); } }}>
              <circle r={Math.max(13, o.uncertainty * 2.2)} fill={color} fillOpacity=".025" stroke={color} strokeOpacity={selected ? '.7' : '.35'} strokeDasharray="3 5"/>
              {selected && <><path d="M-17-10v-7h7m20 0h7v7m0 20v7h-7m-20 0h-7v-7" stroke={color} fill="none" strokeWidth="1.5"/><circle r="23" fill="none" stroke={color} strokeOpacity=".12"/></>}
              <circle r="15" fill="transparent"/>
              <rect width="9" height="9" x="-4.5" y="-4.5" rx="1" transform="rotate(45)" fill={color}/>
              <path d={`M8 0L${lx - 3} ${ly + 12}`} stroke={color} strokeOpacity=".4" strokeWidth=".8" pointerEvents="none"><title>Identity label leader, not a motion path</title></path>
              <g aria-hidden="true"><rect x={lx - 3} y={ly - 2} width="66" height="28" rx="3" fill="var(--map-surface)" fillOpacity=".9"/><text x={lx} y={ly + 10} fill={color} fontSize="11" fontFamily="monospace">{track.id}</text><text x={lx} y={ly + 23} fill={color} fontSize="8" fontFamily="monospace">{stale ? 'STALE' : `${o.confidence}%`}</text></g>
            </g>
          </g>;
        })}
      </g>
      <g fill="currentColor" opacity=".65" fontSize="9" fontFamily="monospace"><text x="298" y="14">N</text><text x="575" y="230">E</text><text x="298" y="448">S</text><text x="18" y="230">W</text><text x="45" y="444">OBSERVED POSITIONS ONLY · NOT A TRUE TRAJECTORY</text></g>
    </svg>
    {view.tracks.length === 0 && <div className="map-waiting"><Radio size={24}/><strong>{mode === 'replay' ? 'No observations had been delivered yet' : 'Listening for a delivered observation'}</strong><span>{mode === 'replay' ? 'This is the recorded evidence at this cursor—not hidden truth or future arrivals.' : 'No hidden tracks are drawn. Capture and delivery may be delayed.'}</span></div>}
    {mode === 'live' && view.status === 'paused' && <div className="map-paused"><Pause size={25}/><strong>Exercise paused</strong><span>Clock, capture and delivery are stopped.</span></div>}
    <div className="map-legend"><span><i className="legend-diamond"/>Observed return</span><span><i className="legend-circle"/>Uncertainty area</span><span><i className="legend-stale"/>Stale / low confidence</span>{c.environment === 'urban' && <span><i className="legend-clutter"/>Schematic clutter</span>}</div>
  </div>;
}

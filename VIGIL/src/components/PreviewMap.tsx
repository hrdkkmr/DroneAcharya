import { useId } from 'react';
import type { Environment, Lighting, TrafficPattern, Weather } from '../domain/types';

/** Static design illustration, explicitly labelled as a preview. Never used as live telemetry. */
export function PreviewMap({ environment = 'urban', lighting = 'dusk', weather = 'clear', trafficPattern = 'independent', miniature = false, tracks = 3 }: { environment?: Environment; lighting?: Lighting; weather?: Weather; trafficPattern?: TrafficPattern; miniature?: boolean; tracks?: number }) {
  const id = useId().replace(/:/g, '');
  const points = trafficPattern === 'grouped' ? [[264, 145], [283, 162], [252, 177], [277, 188], [295, 177], [245, 151], [306, 156], [260, 199]] : trafficPattern === 'crossing' ? [[190, 142], [264, 194], [278, 120], [167, 213], [245, 218], [215, 115], [300, 159], [159, 165]] : [[288, 124], [171, 214], [341, 248], [115, 134], [258, 283], [364, 170], [208, 95], [92, 249]];
  const light = lighting === 'day';
  const accent = lighting === 'night' ? '#96ace5' : '#6bceb0';
  return <div className={`preview-map preview-map--${lighting} ${miniature ? 'preview-map--mini' : ''}`}>
    <svg viewBox="0 0 440 340" preserveAspectRatio={miniature ? 'xMidYMid slice' : 'xMidYMid meet'} fill="none" role="img" aria-label={`${environment} ${lighting} synthetic scenario illustration, not live telemetry`}>
      <defs><pattern id={`${id}grid`} width="34" height="34" patternUnits="userSpaceOnUse"><path d="M34 0H0V34" stroke={light ? '#6a9a91' : '#91b6b2'} strokeOpacity=".1" strokeWidth=".7"/></pattern><radialGradient id={`${id}glow`}><stop stopColor={accent} stopOpacity=".1"/><stop offset="1" stopColor={accent} stopOpacity="0"/></radialGradient><clipPath id={`${id}clip`}><rect width="440" height="340" rx="8"/></clipPath></defs>
      <g clipPath={`url(#${id}clip)`}>
        <rect width="440" height="340" fill={lighting === 'night' ? '#101b2c' : light ? '#18332e' : '#152c31'}/>
        <rect width="440" height="340" fill={`url(#${id}grid)`}/>
        {environment === 'urban' ? <g stroke="#8daba7" strokeOpacity=".13" fill="#c2dbd3" fillOpacity=".025"><path d="M-12 101 133 45l202 120 118-12M-4 260l116-69L342 38M174-12l-6 129L430 308M-8 321l148-90 229 103" strokeWidth="8"/><path d="m78 103 61-24 43 26-46 33Zm165 36 46-28 37 22-48 29Zm-47 86 37-23 46 27-37 24Zm121 20 48-30 38 32-42 30ZM55 233l36-22 31 16-38 27Z"/></g> : <g stroke="#88b49c" strokeOpacity=".14"><path d="M-40 104Q85 30 147 119T313 151 485 75M-30 120Q92 45 145 135T315 167 485 91M-15 302Q140 190 230 263T467 258M-10 317Q140 205 230 278T467 273" strokeWidth="2"/><path d="M329-10q-88 97-42 147t-43 208" strokeWidth="10" strokeOpacity=".1"/></g>}
        {weather === 'haze' && <rect width="440" height="340" fill="#d4d3bc" opacity=".05"/>}
        {weather === 'rain' && <g stroke="#9bb6d4" strokeOpacity=".15">{Array.from({ length: 18 }, (_, i) => <path key={i} d={`M${i * 29 - 20} 40l-20 45m30 90-20 45`}/>)}</g>}
        <circle cx="224" cy="173" r="151" fill={`url(#${id}glow)`}/>
        {[54, 101, 150].map(r => <circle key={r} cx="224" cy="173" r={r} stroke={accent} strokeOpacity={r === 150 ? '.3' : '.17'} strokeWidth=".9" strokeDasharray={r === 150 ? '3 5' : undefined}/>)}
        <path d="M224 13v320M64 173h320" stroke={accent} strokeOpacity=".17" strokeWidth=".7"/>
        <path d="M224 173 318 56A150 150 0 0 1 367 128Z" fill={accent} opacity=".055"/>
        <circle cx="224" cy="173" r="4" fill={accent}/><circle cx="224" cy="173" r="9" stroke={accent} strokeOpacity=".4"/>
        {points.slice(0, tracks).map(([x, y], index) => <g key={index}><path d={`M${x - 30} ${y + 17}l14-9 16-8`} stroke={index === 1 ? '#e9ba75' : accent} strokeOpacity=".45" strokeDasharray="3 4"/><circle cx={x} cy={y} r="17" stroke={index === 1 ? '#e9ba75' : accent} strokeOpacity=".2" strokeDasharray="3 4"/><rect x={x - 4} y={y - 4} width="8" height="8" rx="1" transform={`rotate(45 ${x} ${y})`} fill={index === 1 ? '#e9ba75' : accent}/>{!miniature && <text x={x + 13} y={y - 7} fill={index === 1 ? '#f0c484' : '#9cd3c5'} fontSize="9" fontFamily="monospace">{`T0${index + 1}`}</text>}</g>)}
        {!miniature && <g fill="#92b0ad" fontSize="9" fontFamily="monospace"><text x="221" y="19">N</text><text x="413" y="178">E</text><text x="221" y="334">S</text><text x="15" y="178">W</text><text x="18" y="319" fontSize="8" letterSpacing="1">NORMALIZED TRAINING GRID</text></g>}
      </g>
    </svg>
    {!miniature && <span className="map-preview-tag"><span/>SCENARIO PREVIEW · NOT LIVE</span>}
  </div>;
}

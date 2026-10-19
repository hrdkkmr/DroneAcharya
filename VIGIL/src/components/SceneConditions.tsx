import { useId } from 'react';
import { URBAN_CLUTTER_ZONES } from '../domain/conditions';
import type { Environment, Weather } from '../domain/types';

/** Static public schematic layers. Geometry is shared with sensor-2, never a hidden trajectory. */
export function SceneConditions({ environment, weather }: { environment: Environment; weather: Weather }) {
  const id = useId().replace(/:/g, '');
  return <g aria-hidden="true" pointerEvents="none" data-testid="scene-conditions" data-weather={weather}>
    {weather === 'haze' && <rect width="600" height="460" fill="#d6d2bb" opacity=".045"/>}
    {weather === 'rain' && <g stroke="#a1b8dd" strokeOpacity=".15" data-testid="rain-layer">{Array.from({ length: 28 }, (_, i) => <path key={i} d={`M${i * 27 - 70} 35l-18 42m32 81-18 42m32 81-18 42`}/>)}</g>}
    {environment === 'urban' && <>
      <defs><pattern id={`${id}clutter`} width="9" height="9" patternUnits="userSpaceOnUse"><path d="M-2 9 9-2M7 11 11 7" stroke="#d3c099" strokeOpacity=".2" strokeWidth="1"/></pattern></defs>
      <g data-testid="clutter-zones">{URBAN_CLUTTER_ZONES.map(z => <g key={z.id}><rect x={45 + z.x * 5.1} y={425 - (z.y + z.height) * 4} width={z.width * 5.1} height={z.height * 4} rx="4" fill={`url(#${id}clutter)`} stroke="#d6c49e" strokeOpacity=".22" strokeDasharray="4 6"/><text x={49 + z.x * 5.1} y={420 - z.y * 4} fill="#d1c5ae" opacity=".7" fontSize="7" fontFamily="monospace">CLUTTER {z.id}</text></g>)}</g>
    </>}
  </g>;
}

import { ChevronDown, SlidersHorizontal } from 'lucide-react';
import { PATTERN_LABELS, sensorConditions } from '../domain/conditions';
import type { ScenarioConfig } from '../domain/types';

/** Public configuration explanation. No private scenario or measured-performance claim. */
export function SensorSummary({ config }: { config: Omit<ScenarioConfig, 'weights'> }) {
  const settings = sensorConditions(config);
  const delay = settings.minimumDelay === settings.maximumDelay ? `${settings.minimumDelay}s` : `${settings.minimumDelay}–${settings.maximumDelay}s`;
  return <section className="condition-card" aria-label="Synthetic sensor model settings">
    <div className="condition-card-heading"><SlidersHorizontal size={15}/><span>CONDITION MODEL</span><span>sensor-2</span></div>
    <h3>{PATTERN_LABELS[config.trafficPattern]} <span>· {config.trackCount} return{config.trackCount === 1 ? '' : 's'}</span></h3>
    <dl className="condition-values"><div><dt>Nominal return setting</dt><dd>{Math.round(settings.returnSetting * 100)}<small>%</small></dd></div><div><dt>Position noise</dt><dd>±{(settings.spatialNoise * 10).toFixed(1)}<small>units</small></dd></div><div><dt>Nominal delay range</dt><dd>{delay}</dd></div></dl>
    <p className="condition-disclaimer">Synthetic configuration, not measured detection accuracy. Disruption can add 2s and further reduce quality.</p>
    <details className="condition-explanation"><summary>How conditions affect evidence<ChevronDown size={13}/></summary><ul>{settings.notes.map(note => <li key={note}>{note}</li>)}</ul></details>
  </section>;
}

import { describe, expect, it } from 'vitest';
import { cloneConfig, configErrors, DEFAULT_WEIGHTS, PRESETS, validateConfig } from './config';

const valid = () => cloneConfig(PRESETS[0].config);
describe('versioned configuration contract', () => {
  it('validates every curated preset without a network dependency', () => {
    for (const preset of PRESETS) expect(validateConfig(preset.config)).toEqual(preset.config);
  });
  it('provides three distinct lighting presets and both environments', () => {
    expect(new Set(PRESETS.map(p => p.config.lighting)).size).toBe(3);
    expect(new Set(PRESETS.map(p => p.config.environment)).size).toBe(2);
    expect(new Set(PRESETS.map(p => p.id)).size).toBe(PRESETS.length);
  });
  it.each([
    ['trackCount', 0], ['trackCount', 9], ['trackCount', 1.5], ['durationSeconds', 59], ['durationSeconds', 301],
    ['reliability', 0.2], ['reliability', 1.01], ['noise', 0.31], ['delaySeconds', -1], ['delaySeconds', 9],
    ['seed', -1], ['seed', 4294967296], ['seed', NaN], ['seed', Infinity], ['difficulty', 6], ['environment', 'live'],
  ])('rejects invalid %s=%s', (key, value) => { expect(() => validateConfig({ ...valid(), [key]: value })).toThrow(); });
  it('requires nonempty, unique objectives', () => {
    expect(() => validateConfig({ ...valid(), objectives: [] })).toThrow();
    expect(() => validateConfig({ ...valid(), objectives: ['detection', 'detection'] })).toThrow();
  });
  it('requires finite nonnegative weights summing to 100', () => {
    expect(Object.values(DEFAULT_WEIGHTS).reduce((a,b) => a + b, 0)).toBe(100);
    expect(() => validateConfig({ ...valid(), weights: { ...DEFAULT_WEIGHTS, detection: 10 } })).toThrow('total 100%');
    expect(() => validateConfig({ ...valid(), weights: { ...DEFAULT_WEIGHTS, detection: -1, objectives: 31 } })).toThrow();
  });
  it('rejects undeclared hidden fields and reports helpful error paths', () => {
    expect(() => validateConfig({ ...valid(), tracks: [] })).toThrow();
    expect(configErrors({ ...valid(), durationSeconds: 10 }).join(' ')).toContain('durationSeconds');
    expect(configErrors(valid())).toEqual([]);
  });
  it('clones nested objectives and weights, preserving preset definitions', () => {
    const config = valid(); config.weights.detection = 99; config.objectives.pop();
    expect(PRESETS[0].config.weights.detection).toBe(20);
    expect(PRESETS[0].config.objectives).toHaveLength(5);
  });
});

import { describe, expect, it } from 'vitest';
import { testEngine } from '../test/fixtures';
import { layoutObservationLabels, projectObservation, type LabelBox } from './observationLayout';

function tracks() { const e = testEngine({ trackCount: 8 }); e.start(); e.advance(30); return e.getView().tracks; }
function overlaps(a: LabelBox, b: LabelBox) { return a.x < b.x + b.width && a.x + a.width > b.x && a.y < b.y + b.height && a.y + a.height > b.y; }
function valid(labels: Record<string, LabelBox>) {
  const boxes = Object.values(labels);
  for (const box of boxes) { expect(box.x).toBeGreaterThanOrEqual(40); expect(box.x + box.width).toBeLessThanOrEqual(563); expect(box.y).toBeGreaterThanOrEqual(24); expect(box.y + box.height).toBeLessThanOrEqual(423); }
  for (let i = 0; i < boxes.length; i++) for (let j = i + 1; j < boxes.length; j++) expect(overlaps(boxes[i], boxes[j])).toBe(false);
}

describe('observation-only label decluttering', () => {
  it('separates eight coincident observed identities without moving a marker', () => {
    const observed = tracks().map(t => ({ ...t, latest: { ...t.latest, x: 50, y: 50 } }));
    const before = structuredClone(observed); const labels = layoutObservationLabels(observed);
    expect(Object.keys(labels)).toHaveLength(8); valid(labels); expect(observed).toEqual(before);
    expect(projectObservation(observed[0].latest)).toEqual({ x: 300, y: 225 });
  });
  it('keeps labels inside the plot at all observed-coordinate corners', () => {
    const observed = tracks().map((t,i) => ({ ...t, latest: { ...t.latest, x: i % 2 ? 100 : 0, y: i % 4 > 1 ? 100 : 0 } }));
    valid(layoutObservationLabels(observed));
  });
  it('is deterministic across input order and never invents an unseen identity', () => {
    const observed = tracks().slice(0, 3);
    const a = layoutObservationLabels(observed); const b = layoutObservationLabels([...observed].reverse());
    expect(a).toEqual(b); expect(Object.keys(a).sort()).toEqual(observed.map(t => t.id).sort());
  });
  it('maps coordinates by the same fixed public projection, not a guessed trajectory', () => {
    expect(projectObservation({ x: 0, y: 0 })).toEqual({ x: 45, y: 425 });
    expect(projectObservation({ x: 100, y: 100 })).toEqual({ x: 555, y: 25 });
  });
});

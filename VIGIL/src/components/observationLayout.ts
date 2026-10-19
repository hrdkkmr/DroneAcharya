import type { Observation, TrackEvidence } from '../domain/types';

export interface LabelBox { x: number; y: number; width: number; height: number }
export const projectObservation = (o: Pick<Observation, 'x' | 'y'>) => ({ x: 45 + o.x * 5.1, y: 425 - o.y * 4 });
const intersects = (a: LabelBox, b: LabelBox, gap = 4) => a.x < b.x + b.width + gap && a.x + a.width + gap > b.x && a.y < b.y + b.height + gap && a.y + a.height + gap > b.y;

/** Declutter identity text only. Marker coordinates remain the actual delivered coordinates. */
export function layoutObservationLabels(tracks: readonly Pick<TrackEvidence, 'id' | 'latest'>[]): Record<string, LabelBox> {
  const positions = tracks.map(t => projectObservation(t.latest));
  const occupied: LabelBox[] = []; const labels: Record<string, LabelBox> = {};
  for (const track of [...tracks].sort((a, b) => a.id.localeCompare(b.id))) {
    const p = projectObservation(track.latest);
    const candidates: LabelBox[] = [{ x: p.x + 15, y: p.y - 20, width: 64, height: 26 }];
    for (const radius of [32, 56, 80, 104, 128]) for (let step = 0; step < 8; step++) {
      const angle = step * Math.PI / 4;
      candidates.push({ x: p.x + Math.cos(angle) * radius - (Math.cos(angle) < -.2 ? 64 : 0), y: p.y + Math.sin(angle) * radius - 13, width: 64, height: 26 });
    }
    const grid: LabelBox[] = [];
    for (let y = 30; y <= 390; y += 32) for (let x = 42; x <= 498; x += 76) grid.push({ x, y, width: 64, height: 26 });
    grid.sort((a,b) => Math.hypot(a.x - p.x, a.y - p.y) - Math.hypot(b.x - p.x, b.y - p.y));
    const valid = (box: LabelBox) => box.x >= 40 && box.x + box.width <= 563 && box.y >= 24 && box.y + box.height <= 423
      && !occupied.some(other => intersects(box, other))
      && !positions.some(point => intersects(box, { x: point.x - 10, y: point.y - 10, width: 20, height: 20 }, 0));
    const box = [...candidates, ...grid].find(valid) ?? { x: 42, y: 30, width: 64, height: 26 };
    labels[track.id] = box; occupied.push(box);
  }
  return labels;
}

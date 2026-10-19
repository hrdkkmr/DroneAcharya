import { TrainingError } from '../domain/actions';
export class FixedStepClock {
  private remainderMs = 0;
  reset() { this.remainderMs = 0; }
  consume(milliseconds: number, running: boolean, speed: 1 | 2 | 4): number {
    if (!Number.isFinite(milliseconds) || milliseconds < 0) throw new TrainingError('BAD_CLOCK', 'Clock delta must be finite and nonnegative.');
    if (![1, 2, 4].includes(speed)) throw new TrainingError('BAD_SPEED', 'Use 1×, 2× or 4× simulation speed.');
    if (!running) return 0;
    this.remainderMs += milliseconds * speed;
    const steps = Math.floor(this.remainderMs / 1000);
    this.remainderMs -= steps * 1000;
    return steps;
  }
}

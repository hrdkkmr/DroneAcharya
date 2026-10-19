import { z } from 'zod';
import { scenarioConfigSchema } from '../domain/config';
import { TrainingError, traineeActionSchema } from '../domain/actions';
import type { WorkerResponse } from '../domain/types';
import { FixedStepClock } from '../engine/clock';
import { SimulationEngine } from '../engine/SimulationEngine';

const commandSchema = z.discriminatedUnion('type', [
  z.object({ type: z.literal('configure'), config: scenarioConfigSchema, sessionId: z.string().min(1).max(100), profileId: z.string().min(1).max(100), startedAt: z.string().datetime() }).strict(),
  ...(['start', 'pause', 'resume', 'finish'] as const).map(type => z.object({ type: z.literal(type) }).strict()),
  z.object({ type: z.literal('speed'), value: z.union([z.literal(1), z.literal(2), z.literal(4)]) }).strict(),
  z.object({ type: z.literal('action'), action: traineeActionSchema }).strict(),
]);

/** Worker host is separately testable with a controlled monotonic wall clock. */
export class SimulationRuntime {
  private engine: SimulationEngine | null = null;
  private readonly clock = new FixedStepClock();
  private anchor: number;
  private finalSent = false;
  constructor(private readonly send: (response: WorkerResponse) => void, private readonly now: () => number = () => performance.now(), private readonly nowIso: () => string = () => new Date().toISOString()) { this.anchor = now(); }
  handle(raw: unknown): void {
    try {
      const command = commandSchema.parse(raw);
      this.tick();
      if (command.type === 'configure') {
        const state = this.engine?.clockState().status;
        if (state === 'running' || state === 'paused') throw new TrainingError('ACTIVE_EXERCISE', 'Finish or explicitly reset the active exercise before configuring another.');
        this.engine = new SimulationEngine(command.config, { sessionId: command.sessionId, profileId: command.profileId, startedAt: command.startedAt }, this.nowIso);
        this.clock.reset(); this.anchor = this.now(); this.finalSent = false; this.publish(); return;
      }
      if (!this.engine) throw new TrainingError('NOT_CONFIGURED', 'Choose a scenario and review its briefing before starting.');
      switch (command.type) {
        case 'start': this.engine.start(); break;
        case 'pause': this.engine.pause(); break;
        case 'resume': this.engine.resume(); break;
        case 'finish': this.engine.finish(); break;
        case 'speed': this.engine.setSpeed(command.value); break;
        case 'action': this.engine.action(command.action); break;
      }
      this.anchor = this.now(); this.publish();
    } catch (error) { this.reportError(error); }
  }
  tick(): void {
    const now = this.now();
    if (!Number.isFinite(now) || now < this.anchor) throw new TrainingError('BAD_CLOCK', 'The monotonic clock moved backwards or became invalid. Reset the exercise.');
    const delta = now - this.anchor; this.anchor = now;
    if (!this.engine) return;
    const state = this.engine.clockState();
    const steps = this.clock.consume(delta, state.status === 'running', state.speed);
    if (steps === 0) return;
    const remaining = this.engine.getView().scenario.config.durationSeconds - state.elapsedSeconds;
    this.engine.advance(Math.min(steps, remaining)); this.publish();
  }
  private publish() {
    if (!this.engine) return;
    const view = this.engine.getView();
    if ((view.status === 'completed' || view.status === 'aborted') && !this.finalSent) {
      this.finalSent = true; this.send({ type: 'completed', record: this.engine.completedRecord(), view });
    } else this.send({ type: 'view', view });
  }
  reportError(error: unknown) {
    const message = error instanceof z.ZodError ? error.issues.map(issue => `${issue.path.join('.') || 'command'}: ${issue.message}`).join(' · ') : error instanceof Error ? error.message : 'The simulation command could not be processed.';
    this.send({ type: 'error', code: error instanceof TrainingError ? error.code : error instanceof z.ZodError ? 'VALIDATION' : 'ENGINE_ERROR', message });
  }
}

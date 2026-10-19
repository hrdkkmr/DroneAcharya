import { describe, expectTypeOf, it } from 'vitest';
import type { ActiveSessionView, PublicScenario, ScenarioDefinition, SimulationEvent, WorkerResponse } from './types';

describe('information boundary contracts', () => {
  it('keeps hidden tracks and rubric out of the public scenario and active view', () => {
    expectTypeOf<PublicScenario>().not.toHaveProperty('tracks');
    expectTypeOf<PublicScenario>().not.toHaveProperty('rubric');
    expectTypeOf<PublicScenario['config']>().not.toHaveProperty('weights');
    expectTypeOf<ActiveSessionView>().not.toHaveProperty('groundTruth');
    expectTypeOf<ScenarioDefinition>().toHaveProperty('tracks');
    expectTypeOf<ScenarioDefinition>().toHaveProperty('rubric');
  });
  it('requires stable ordered event metadata', () => {
    expectTypeOf<SimulationEvent['id']>().toBeString();
    expectTypeOf<SimulationEvent['sessionId']>().toBeString();
    expectTypeOf<SimulationEvent['order']>().toBeNumber();
    expectTypeOf<SimulationEvent['time']>().toBeNumber();
    expectTypeOf<Extract<WorkerResponse, { type: 'view' }>['view']>().toEqualTypeOf<ActiveSessionView>();
  });
});

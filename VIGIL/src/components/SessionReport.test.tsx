import { fireEvent, render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';
import { SessionReport } from '../pages/SessionReview';
import { recordedExercise } from '../test/reviewFixtures';
import { testEngine } from '../test/fixtures';
import { SCHEMA_VERSION, type SessionRecord, type TraineeProfile } from '../domain/types';
import { formatTime } from '../domain/training';

const profiles: TraineeProfile[]=[{schemaVersion:SCHEMA_VERSION,id:'trainee-01',name:'Trainee 01',unit:'Demo',createdAt:'2026-10-17T00:00:00.000Z'}];
const props=(record:SessionRecord)=>({record,profiles,sessions:[record],onConfigure:vi.fn(),onSelectRecord:vi.fn()});
function unsupportedRecord() { const e=testEngine();e.start();e.advance(1);e.action({kind:'track',trackId:'T01'});e.action({kind:'classify',trackId:'T01',category:'review',confidence:90});e.action({kind:'report',trackId:'T01',decision:'escalate',summary:'Controlled early unsupported report for evidence-link testing.'});e.advance(59);return e.completedRecord(); }

describe('evidence-linked terminated session report',()=>{
  it('renders the fixed evaluator result and a genuinely empty replay start',()=>{
    const record=recordedExercise();render(<SessionReport {...props(record)}/>);
    expect(screen.getByTestId('final-score')).toHaveTextContent(record.evaluation.score.toFixed(1));
    const replay=screen.getByTestId('replay-panel');expect(within(replay).queryByTestId('track-marker-T01')).not.toBeInTheDocument();expect(screen.getByTestId('replay-order')).toHaveTextContent('#000');
    expect(screen.getByText('Recorded review · not saved yet.')).toBeVisible();expect(screen.getByText(/Original wall-clock pauses/)).toBeVisible();
  });
  it('P1/P2 links use exact action order: earlier assessment does not contain the later report',async()=>{
    const record=unsupportedRecord();const before=structuredClone(record);render(<SessionReport {...props(record)}/>);const user=userEvent.setup();
    const p1=record.evaluation.findings.find(f=>f.ruleId==='P1')!;const assessment=record.events.find(e=>e.id===p1.anchorEventId)!;
    await user.click(screen.getByRole('button',{name:'Inspect P1 evidence for T01'}));expect(screen.getByTestId('replay-order')).toHaveTextContent(`#${String(assessment.order).padStart(3,'0')}`);
    expect(screen.getByTestId('replay-assessment')).toHaveTextContent('Requires review');expect(screen.getByTestId('replay-report')).toHaveTextContent('No report recorded');
    expect(document.querySelector(`.event-row[aria-current="step"]`)).toHaveAttribute('data-event-id',assessment.id);
    await user.click(screen.getByRole('button',{name:'Inspect P2 evidence for T01'}));expect(screen.getByTestId('replay-report')).toHaveTextContent('Training escalation');
    expect(record).toEqual(before);expect(screen.getByTestId('final-score')).toHaveTextContent(record.evaluation.score.toFixed(1));
  });
  it('supports keyboard event stepping at the same second and time scrubbing without retrospective state',async()=>{
    const record=recordedExercise();render(<SessionReport {...props(record)}/>);const user=userEvent.setup();
    await user.click(screen.getByRole('button',{name:'Inspect Classification component evidence'}));
    expect(screen.getByTestId('replay-assessment')).toHaveTextContent('Unknown');const time=screen.getByTestId('replay-time').textContent;
    const previous=screen.getByRole('button',{name:'Previous recorded event'});previous.focus();await user.keyboard('{Enter}');
    expect(screen.getByTestId('replay-time')).toHaveTextContent(time!);expect(screen.getByTestId('replay-assessment')).toHaveTextContent('Not recorded');
    fireEvent.change(screen.getByLabelText('Replay position in simulation seconds'),{target:{value:'2'}});expect(screen.getByTestId('replay-time')).toHaveTextContent('00:02');expect(screen.getByTestId('replay-assessment')).toHaveTextContent('Not recorded');
  });
  it('a recorded pause is inspectable without a live blocking pause overlay',async()=>{
    const record=recordedExercise();render(<SessionReport {...props(record)}/>);const paused=record.events.find(e=>e.type==='paused')!;
    await userEvent.click(screen.getByRole('button',{name:`Replay event ${paused.order} at ${formatTime(paused.time)}`}));
    expect(screen.getByTestId('replay-source-status')).toHaveAttribute('data-status','paused');expect(document.querySelector('.map-paused')).not.toBeInTheDocument();
    expect(screen.getByTestId('replay-panel')).toHaveTextContent('Not recorded');
  });
  it('shows stored thresholds and weights in the actual declared-rubric explanation',async()=>{
    const record=recordedExercise();render(<SessionReport {...props(record)}/>);await userEvent.click(screen.getByText('How this score was calculated'));
    const table=screen.getByRole('region',{name:'Declared scoring rubric'});expect(within(table).getAllByRole('row')).toHaveLength(7);expect(table).toHaveTextContent('5s');expect(table).toHaveTextContent('30s');expect(table).toHaveTextContent('20%');
  });
  it('opens per-track evaluator credits and real reference links rather than a second grade',async()=>{
    const record=recordedExercise();render(<SessionReport {...props(record)}/>);const user=userEvent.setup();
    await user.click(screen.getByText('Inspect audit'));
    const audit=screen.getByTestId('audit-T01-detection');expect(audit).toHaveTextContent('100.0%');
    await user.click(within(audit).getByText(/recorded references/));
    const trace=record.evaluation.tracks[0].metrics.find(m=>m.key==='detection')!;const event=record.events.find(e=>e.id===trace.anchorEventId)!;
    const link=await within(audit).findByRole('button',{name:`Replay event ${event.order} at ${formatTime(event.time)}`});await user.click(link);expect(screen.getByTestId('replay-order')).toHaveTextContent(`#${String(event.order).padStart(3,'0')}`);
  });
  it('renders missing observations and aborted result as empty/noncomparable, not fictional evidence',async()=>{
    const e=testEngine({delaySeconds:8});e.start();e.finish();const record=e.completedRecord();render(<SessionReport {...props(record)}/>);const user=userEvent.setup();
    expect(screen.getByTestId('final-score')).toHaveTextContent('0.0');expect(screen.getByText('Partial · aborted')).toBeVisible();expect(screen.getByText(/Not comparable · partial/)).toBeVisible();expect(screen.getByLabelText('Replay position in simulation seconds')).toBeDisabled();
    await user.click(screen.getByRole('button',{name:'Go to replay end'}));expect(screen.getByTestId('replay-source-status')).toHaveAttribute('data-status','aborted');expect(screen.queryByTestId('track-marker-T01')).not.toBeInTheDocument();
    await user.click(screen.getByRole('button',{name:'Your actions'}));expect(screen.getByText('No trainee actions were recorded in this exercise.')).toBeVisible();
  });
  it('keeps filtering honest if the currently linked observation is hidden by the action-only filter',async()=>{
    const record=recordedExercise();render(<SessionReport {...props(record)}/>);const user=userEvent.setup();
    await user.click(screen.getByRole('button',{name:'Your actions'}));await user.click(screen.getByRole('button',{name:'Go to replay end'}));
    expect(screen.getByText('The current replay event is hidden by this filter.')).toBeVisible();await user.click(screen.getByRole('button',{name:'Show current event'}));
    expect(document.querySelectorAll('.event-row')).toHaveLength(record.events.length);
  });
  it('switching records resets replay and never applies a longer previous cursor to an empty result',async()=>{
    const record=recordedExercise();const {rerender}=render(<SessionReport {...props(record)}/>);await userEvent.click(screen.getByRole('button',{name:'Go to replay end'}));
    const e=testEngine({delaySeconds:8},'second');e.start();e.finish();const next=e.completedRecord();rerender(<SessionReport {...props(next)}/>);
    expect(screen.getByTestId('replay-order')).toHaveTextContent('#000');expect(screen.getByTestId('replay-panel')).toHaveAttribute('data-session-id','second');expect(screen.getByTestId('replay-playback-state')).toHaveTextContent('Paused');
  });
  it('rejects a malformed record instead of showing a plausible replacement score/replay',()=>{
    const record=recordedExercise();record.events[1].order=999;render(<SessionReport {...props(record)}/>);
    expect(screen.getByRole('alert')).toHaveTextContent('No replacement replay or score was invented');expect(screen.queryByTestId('final-score')).not.toBeInTheDocument();expect(screen.queryByTestId('replay-panel')).not.toBeInTheDocument();
  });
});

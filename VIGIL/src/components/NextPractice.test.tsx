import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { NextPractice } from './NextPractice';
import { useWorkspace } from '../hooks/useWorkspace';
import { recommendNext } from '../adaptive/policy';
import { practiceRecord } from '../test/adaptiveFixtures';
import { INITIAL_PROFILES } from '../persistence/validation';

let workspace:ReturnType<typeof useWorkspace>;
vi.mock('../hooks/useWorkspace',()=>({useWorkspace:()=>workspace}));
const records=[practiceRecord(1)];
beforeEach(()=>{workspace={nextPractice:recommendNext(records,new Set(records.map(r=>r.id)),'trainee-01'),prepareNextPractice:vi.fn(),isActive:false,profile:INITIAL_PROFILES[0],storage:{quarantined:[],error:null},navigate:vi.fn(),reviewSession:vi.fn(),sessions:records} as unknown as ReturnType<typeof useWorkspace>;});

describe('honest heuristic next-practice presentation',()=>{
  it('shows actual estimate/target/held level and an explicit review, never a fabricated ML result',()=>{render(<NextPractice estimates/>);expect(screen.getByTestId('adaptive-target')).toHaveTextContent('Classification');expect(screen.getByTestId('adaptive-difficulty')).toHaveTextContent('Level 1 → 1 · hold');expect(screen.getByTestId('estimate-classification')).toHaveTextContent('75.0%');expect(screen.getByText(/not ML or a readiness rating/)).toBeVisible();expect(workspace.prepareNextPractice).not.toHaveBeenCalled();});
  it('keeps all five empty estimates unassessed rather than fake zero progressbars',()=>{workspace.nextPractice=recommendNext([],new Set(),'trainee-01');workspace.sessions=[];render(<NextPractice estimates/>);expect(screen.getByText(/no weakness has been inferred/)).toBeVisible();expect(screen.getByTestId('estimate-detection')).toHaveTextContent('—');expect(screen.queryByRole('progressbar')).not.toBeInTheDocument();expect(screen.getAllByText('No eligible evidence')).toHaveLength(5);});
  it('explains the actual source record and its fixed score, with a working review callback',async()=>{render(<NextPractice/>);const user=userEvent.setup();await user.click(screen.getByText('Why this exercise?',{exact:false}));const button=screen.getByRole('button',{name:`Review policy source ${records[0].id.slice(-6)}`});expect(button).toHaveTextContent(records[0].evaluation.score.toFixed(1));await user.click(button);expect(workspace.reviewSession).toHaveBeenCalledWith(records[0].id);});
  it('applies only through the root handler and retains manual choice',async()=>{render(<NextPractice/>);const user=userEvent.setup();await user.click(screen.getByRole('button',{name:'Review recommended exercise'}));expect(workspace.prepareNextPractice).toHaveBeenCalledTimes(1);await user.click(screen.getByRole('button',{name:'Choose manually instead'}));expect(workspace.navigate).toHaveBeenCalledWith('lab');});
  it('renders no planner/estimates/source data while a live attempt is active',()=>{workspace.isActive=true;render(<NextPractice estimates/>);expect(screen.getByTestId('adaptive-lock')).toBeVisible();expect(screen.queryByTestId('adaptive-plan')).not.toBeInTheDocument();expect(screen.queryByRole('button',{name:'Review recommended exercise'})).not.toBeInTheDocument();expect(screen.queryByTestId('estimate-detection')).not.toBeInTheDocument();});
  it('distinguishes saving/unavailable storage from an actual empty evidence plan',()=>{workspace.nextPractice=null;workspace.storage.error='Storage unavailable';render(<NextPractice estimates/>);expect(screen.getByTestId('adaptive-waiting')).toContainHTML('Save history before using adaptation');expect(screen.getByText(/unsaved attempt cannot become adaptive performance evidence/)).toBeVisible();expect(screen.queryByRole('region',{name:'Heuristic competency evidence'})).not.toBeInTheDocument();});
  it('surfaces root guard or concurrent-save failure without pretending to start',async()=>{workspace.prepareNextPractice=vi.fn(()=>{throw new Error('Wait for acknowledged local history.');});render(<NextPractice/>);await userEvent.setup().click(screen.getByRole('button',{name:'Review recommended exercise'}));expect(screen.getByRole('alert')).toHaveTextContent('acknowledged local history');});
  it('labels the sample as provisional, not probability or mastery, with an accessible data-table alternative',()=>{render(<NextPractice estimates/>);const region=screen.getByRole('region',{name:'Heuristic competency evidence'});expect(within(region).getByRole('table')).toBeVisible();expect(within(region).getAllByText('Provisional sample')).toHaveLength(5);expect(screen.getByText(/not a trained model, statistical confidence/)).toBeVisible();});
});

it('explains a known peer-tab change without displaying a stale plan or estimate',()=>{workspace.nextPractice=null;workspace.storage.needsReload=true;render(<NextPractice estimates/>);expect(screen.getByTestId('adaptive-waiting')).toHaveTextContent('Reload saved history to include those records');expect(screen.queryByTestId('adaptive-plan')).not.toBeInTheDocument();expect(screen.queryByTestId('estimate-detection')).not.toBeInTheDocument();});

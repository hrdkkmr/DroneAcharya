import { act, render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';
import App from './App';
import { routeFromHash } from './hooks/useWorkspace';

async function renderAt(route = 'home') { window.location.hash = `/${route}`; const result = render(<App/>); await waitFor(() => expect(screen.getByTestId('history-state')).toHaveAttribute('data-state', 'saved')); return result; }
describe('Phase 1 navigation and foundation', () => {
  it('handles valid, empty and unknown routes', () => {
    expect(routeFromHash('#/lab')).toBe('lab'); expect(routeFromHash('')).toBe('home');
    expect(routeFromHash('#/not-a-route')).toBe('home'); expect(routeFromHash('#/unit?tab=1')).toBe('unit');
  });
  it('renders honest zero-history home and a clearly labelled preview', async () => {
    await renderAt(); expect(screen.getByRole('heading', { name: 'Ready for the next decision?' })).toBeVisible();
    expect(screen.getByText('0', { exact: false, selector: '.stat-value' })).toHaveTextContent('0sessions');
    expect(screen.getByText('SCENARIO PREVIEW · NOT LIVE')).toBeVisible();
    expect(screen.getByText('Your next exercise is your first milestone.')).toBeVisible();
  });
  it.each([
    ['Scenario Lab', 'Scenario Lab'], ['Live console', 'Live console'], ['After-action review', 'After-action review'],
    ['Individual progress', 'Individual progress'], ['Unit performance', 'Unit performance'],
  ])('navigates to %s and marks the active navigation item', async (label, heading) => {
    const user = userEvent.setup(); await renderAt();
    const nav = screen.getByRole('navigation', { name: 'Main navigation' });
    const button = within(nav).getByRole('button', { name: label }); await user.click(button);
    expect(screen.getByRole('heading', { name: heading, level: 1 })).toBeVisible(); expect(button).toHaveAttribute('aria-current', 'page');
  });
  it('uses browser back/hash navigation', async () => {
    await renderAt(); act(() => { window.location.hash = '/progress'; window.dispatchEvent(new HashChangeEvent('hashchange')); });
    expect(screen.getByRole('heading', { name: 'Individual progress', level: 1 })).toBeVisible();
  });
  it('starts training by opening configuration, without inventing an exercise result', async () => {
    const user = userEvent.setup(); await renderAt(); await user.click(screen.getByRole('button', { name: 'Start training' }));
    expect(screen.getByRole('heading', { name: 'Scenario Lab', level: 1 })).toBeVisible();
    expect(screen.getByLabelText('Random seed')).toHaveValue(26247);
  });
  it('configures a selected scenario and carries validated values into the briefing', async () => {
    const user = userEvent.setup(); await renderAt(); await user.click(screen.getByRole('button', { name: 'Configure Urban ambiguity' }));
    expect(screen.getByLabelText('Synthetic tracks')).toHaveValue(3);
    await user.selectOptions(screen.getByLabelText('Environment'), 'rural');
    await user.click(screen.getByRole('button', { name: 'Review briefing' }));
    expect(screen.getByRole('heading', { name: 'Custom exercise', level: 1 })).toBeVisible();
    expect(screen.getByText('rural · dusk')).toBeVisible();
    expect(screen.getByText(/no exercise has started/i)).toBeVisible();
    await user.click(screen.getByRole('button', { name: 'Edit configuration' }));
    expect(screen.getByLabelText('Synthetic tracks')).toHaveValue(3);
  });
  it('rejects invalid configuration without leaving the lab', async () => {
    const user = userEvent.setup(); await renderAt('lab'); const duration = screen.getByLabelText('Exercise duration (seconds)');
    await user.clear(duration); await user.type(duration, '10'); await user.click(screen.getByRole('button', { name: 'Review briefing' }));
    expect(screen.getByRole('alert')).toHaveTextContent('at least 60 seconds');
    expect(screen.getByRole('heading', { name: 'Scenario Lab', level: 1 })).toBeVisible();
  });
  it('opens instructor options and validates the total weight', async () => {
    const user = userEvent.setup(); await renderAt('lab'); await user.click(screen.getByRole('button', { name: /Instructor options/ }));
    const detection = screen.getByLabelText('Detection', { selector: 'input[type=number]' });
    await user.clear(detection); await user.type(detection, '30'); await user.click(screen.getByRole('button', { name: 'Review briefing' }));
    expect(screen.getByRole('alert')).toHaveTextContent('must total 100%');
  });
  it('switches synthetic profiles and reflects the active identity', async () => {
    const user = userEvent.setup(); await renderAt('progress');
    await user.selectOptions(screen.getByLabelText('Active trainee profile'), 'trainee-02');
    expect(screen.getByText(/Trainee 02 · Actual saved training evidence/)).toBeVisible();
  });
  it('adds an actual local anonymous profile and rejects duplicates', async () => {
    const user = userEvent.setup(); await renderAt('instructor');
    await user.type(screen.getByLabelText('New anonymous profile'), 'Cadet Delta'); await user.click(screen.getByRole('button', { name: 'Add profile' }));
    expect(screen.getByLabelText('Active trainee profile')).toHaveDisplayValue('Cadet Delta');
    expect(screen.getByRole('status')).toHaveTextContent('added');
    await user.type(screen.getByLabelText('New anonymous profile'), 'cadet delta'); await user.click(screen.getByRole('button', { name: 'Add profile' }));
    expect(screen.getByRole('alert')).toHaveTextContent('already exists');
  });
  it('opens the guide, closes with Escape and restores focus', async () => {
    const user = userEvent.setup(); await renderAt(); const trigger = screen.getByRole('button', { name: 'Training guide' });
    await user.click(trigger); expect(screen.getByRole('dialog')).toBeVisible();
    expect(screen.getByRole('button', { name: 'Close training guide' })).toHaveFocus();
    await user.keyboard('{Escape}'); expect(screen.queryByRole('dialog')).not.toBeInTheDocument(); expect(trigger).toHaveFocus();
  });
  it('reports unavailable workers instead of inventing a simulation or score', async () => {
    vi.stubGlobal('Worker', undefined);
    const user = userEvent.setup(); await renderAt('lab');
    await user.click(screen.getByRole('button', { name: 'Review briefing' }));
    await user.click(screen.getByRole('button', { name: 'Start exercise' }));
    expect(screen.getByRole('alert')).toHaveTextContent('cannot start a module Web Worker');
    expect(screen.queryByTestId('simulation-timer')).not.toBeInTheDocument();
    expect(screen.queryByTestId('final-score')).not.toBeInTheDocument();
    vi.unstubAllGlobals();
  });

});

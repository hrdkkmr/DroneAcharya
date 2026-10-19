import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';
import App from '../App';
import { PRESETS } from '../domain/config';
import { deliveryFacts, isStaleObservation } from '../domain/evidence';
import { testConfig, testEngine } from '../test/fixtures';
import { DeliveryMonitor } from './DeliveryMonitor';
import { ObservationMap } from './ObservationMap';
import { SensorSummary } from './SensorSummary';
import { TrackWorkspace } from './TrackWorkspace';

function observed() { const e = testEngine(); e.start(); e.advance(5); return e.getView(); }

describe('public Phase 3 configuration and evidence presentation', () => {
  it('shows computed synthetic settings, not model-performance claims, and expands their explanation', async () => {
    render(<SensorSummary config={PRESETS[1].config}/>);
    const region = screen.getByRole('region', { name: 'Synthetic sensor model settings' });
    expect(region).toHaveTextContent('Crossing paths'); expect(region).toHaveTextContent('64%'); expect(region).toHaveTextContent('3–8s');
    expect(region).toHaveTextContent('not measured detection accuracy');
    await userEvent.click(screen.getByText('How conditions affect evidence'));
    expect(screen.getByText(/Hatched schematic clutter zones/)).toBeVisible();
  });
  it('rejects an impossible pattern/count and preserves a corrected grouped briefing', async () => {
    window.location.hash = '/lab'; render(<App/>); const user = userEvent.setup();
    await user.selectOptions(await screen.findByLabelText('Traffic pattern'), 'grouped');
    await user.click(screen.getByRole('button', { name: 'Review briefing' }));
    expect(screen.getByRole('alert')).toHaveTextContent('at least 3 tracks');
    const count = screen.getByLabelText('Synthetic tracks'); await user.clear(count); await user.type(count, '3');
    await user.click(screen.getByRole('button', { name: 'Review briefing' }));
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent('Custom exercise');
    expect(screen.getByRole('region', { name: 'Synthetic sensor model settings' })).toHaveTextContent('Grouped motion');
    expect(screen.queryByTestId('simulation-timer')).not.toBeInTheDocument();
  });
  it('marks old captured evidence stale even when it has just arrived', () => {
    const view = observed(); const track = view.tracks[0]; track.latest = { ...track.latest, capturedAt: 1, deliveredAt: 12 }; view.elapsedSeconds = 12;
    render(<TrackWorkspace track={track} now={12} disabled={false} onAction={vi.fn()}/>);
    expect(isStaleObservation(track.latest, 12)).toBe(true);
    expect(screen.getByText('STALE RETURN')).toBeVisible(); expect(screen.getByText('11s old')).toBeVisible();
    expect(screen.getByText(/arrived 00:12/)).toBeVisible();
  });
  it('draws only the newest-capture public marker with keyboard selection', async () => {
    const view = observed(); const select = vi.fn();
    const latest = view.tracks[0].latest; view.tracks[0].observations.push({ ...latest, id: 'old-late', capturedAt: 1, deliveredAt: 7, x: 99 }); view.elapsedSeconds = 7;
    render(<ObservationMap view={view} selectedId={null} onSelect={select}/>);
    const marker = screen.getByTestId('track-marker-T01');
    expect(marker).toHaveAttribute('data-observed-x', String(latest.x)); expect(marker).toHaveAttribute('data-captured-at', String(latest.capturedAt));
    marker.focus(); await userEvent.keyboard('{Enter}'); expect(select).toHaveBeenCalledWith('T01');
  });
  it('renders schematic weather/clutter from public settings, not secret track paths', () => {
    const view = observed(); view.scenario.config.environment = 'urban'; view.scenario.config.weather = 'rain';
    render(<ObservationMap view={view} selectedId={null} onSelect={vi.fn()}/>);
    expect(screen.getByTestId('clutter-zones')).toBeInTheDocument(); expect(screen.getByTestId('rain-layer')).toBeInTheDocument();
    expect(screen.getByText('Schematic clutter')).toBeVisible(); expect(screen.queryByText('Requires review')).not.toBeInTheDocument();
  });
  it('delivery facts use actual arrivals/denominators, never the configured hidden count', () => {
    const view = observed(); view.scenario.config.trackCount = 8;
    const facts = deliveryFacts(view.events);
    render(<DeliveryMonitor view={view}/>);
    expect(facts.count).toBe(2); expect(facts.meanDelay).toBe(0);
    expect(screen.getByTestId('feed-delivered')).toHaveTextContent('2'); expect(screen.getByTestId('feed-delay')).toHaveTextContent('0.0s');
    expect(screen.getByTestId('feed-stale')).toHaveTextContent('0 / 1');
    expect(screen.getByRole('img')).toHaveAccessibleName(/2 actual delivered observations/);
  });
  it('does not promise a requested delivery and only confirms provenance after an actual arrival', () => {
    const view = observed(); const track = view.tracks[0]; track.lastRequestedAt = 5;
    const { rerender } = render(<TrackWorkspace track={track} now={5} disabled={false} onAction={vi.fn()}/>);
    expect(screen.getByTestId('request-evidence-status')).toHaveTextContent('attempt queued for 00:07');
    rerender(<TrackWorkspace track={track} now={10} disabled={false} onAction={vi.fn()}/>);
    expect(screen.getByTestId('request-evidence-status')).toHaveTextContent('Delay or dropout is possible');
    track.observations.push({ ...track.latest, id: 'requested', capturedAt: 7, deliveredAt: 10, source: 'requested' });
    rerender(<TrackWorkspace track={track} now={10} disabled={false} onAction={vi.fn()}/>);
    expect(screen.getByTestId('request-evidence-status')).toHaveTextContent('Requested capture delivered at 00:10');
  });
  it('exposes actual capture/arrival/source rows rather than regenerating an evidence trace', async () => {
    const e = testEngine(testConfig()); e.start(); e.advance(1); e.action({ kind: 'request_observation', trackId: 'T01' }); e.advance(2);
    const track = e.getView().tracks[0]; render(<TrackWorkspace track={track} now={3} disabled={false} onAction={vi.fn()}/>);
    await userEvent.click(screen.getByText('Delivered evidence'));
    const table = screen.getByRole('region', { name: 'Delivered evidence for T01' });
    const rows = within(table).getAllByRole('row'); expect(rows).toHaveLength(3);
    expect(rows[2]).toHaveTextContent('00:0300:03'); expect(rows[2]).toHaveTextContent('requested');
  });
});

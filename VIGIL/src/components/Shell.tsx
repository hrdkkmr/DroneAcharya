import { useEffect, useRef, useState, type ReactNode } from 'react';
import { Activity, BookOpen, ChevronDown, ChevronRight, CircleHelp, ClipboardCheck, FlaskConical, LayoutDashboard, Menu, Monitor, PanelLeftClose, ShieldCheck, SlidersHorizontal, Target, Users, X } from 'lucide-react';
import { ROUTE_LABELS, useWorkspace } from '../hooks/useWorkspace';
import type { Route } from '../domain/types';
import { HistoryPill, HistoryStatus } from './HistoryStatus';
import { Button, Logo } from './UI';
import { formatTime } from '../domain/training';

const NAV = [
  { route: 'home', icon: LayoutDashboard }, { route: 'lab', icon: FlaskConical }, { route: 'console', icon: Monitor },
  { route: 'aar', icon: ClipboardCheck }, { route: 'progress', icon: Activity }, { route: 'unit', icon: Users },
] as const;

export function Shell({ children }: { children: ReactNode }) {
  const { route, navigate, profiles, profile, setProfileId, simulation, isActive, notice, dismissNotice, historyReady } = useWorkspace();
  const [mobileOpen, setMobileOpen] = useState(false);
  const [helpOpen, setHelpOpen] = useState(false);
  const [compactNavigation, setCompactNavigation] = useState(() => window.matchMedia?.('(max-width: 980px)').matches ?? false);
  const menuTrigger = useRef<HTMLButtonElement>(null);
  const sidebarRef = useRef<HTMLElement>(null);
  useEffect(() => {
    const query = window.matchMedia?.('(max-width: 980px)');
    if (!query) return;
    const listener = () => { setCompactNavigation(query.matches); if (!query.matches) setMobileOpen(false); };
    query.addEventListener('change', listener);
    return () => query.removeEventListener('change', listener);
  }, []);
  useEffect(() => {
    if (!compactNavigation || !mobileOpen) return;
    sidebarRef.current?.querySelector<HTMLButtonElement>('button')?.focus();
    return () => menuTrigger.current?.focus();
  }, [compactNavigation, mobileOpen]);
  const helpClose = useRef<HTMLButtonElement>(null);
  const helpTrigger = useRef<HTMLButtonElement>(null);
  const mainRef = useRef<HTMLElement>(null);
  useEffect(() => { setMobileOpen(false); mainRef.current?.scrollTo(0, 0); }, [route]);
  useEffect(() => {
    if (!helpOpen) return;
    helpClose.current?.focus();
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') setHelpOpen(false); };
    document.addEventListener('keydown', onKey);
    return () => { document.removeEventListener('keydown', onKey); helpTrigger.current?.focus(); };
  }, [helpOpen]);
  function go(next: Route) { navigate(next); }
  return <div className="app-shell">
    <a href="#main-content" className="skip-link" onClick={e => { e.preventDefault(); mainRef.current?.focus(); }}>Skip to main content</a>
    {mobileOpen && <button className="sidebar-backdrop" aria-label="Close navigation" onClick={() => setMobileOpen(false)}/>}
    <aside ref={sidebarRef} className={`sidebar ${mobileOpen ? 'sidebar--open' : ''}`} aria-label="Application sidebar" inert={helpOpen || (compactNavigation && !mobileOpen)} role={compactNavigation && mobileOpen ? 'dialog' : undefined} aria-modal={compactNavigation && mobileOpen && !helpOpen ? true : undefined} onKeyDown={e => { if (!compactNavigation || !mobileOpen) return; if (e.key === 'Escape') { setMobileOpen(false); return; } if (e.key !== 'Tab') return; const buttons = Array.from(e.currentTarget.querySelectorAll<HTMLButtonElement>('button')); const first = buttons[0]; const last = buttons[buttons.length - 1]; if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last?.focus(); } else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first?.focus(); } }}>
      <div className="sidebar-brand"><Logo/><button className="mobile-close icon-button" onClick={() => setMobileOpen(false)} aria-label="Close navigation"><PanelLeftClose size={20}/></button></div>
      <div className="workspace-label"><span className="workspace-symbol"><Target size={15}/></span><div><strong>Training workspace</strong><span>Local demonstration unit</span></div><ChevronDown size={14}/></div>
      <div className="nav-group-label">WORKSPACE</div>
      <nav aria-label="Main navigation">{NAV.map(({ route: item, icon: Icon }) => <button key={item} onClick={() => go(item)} className={`nav-item ${route === item ? 'nav-item--active' : ''}`} aria-current={route === item ? 'page' : undefined}><Icon size={18} strokeWidth={1.7}/><span>{ROUTE_LABELS[item]}</span>{route === item && <span className="nav-active-dot"/>}</button>)}</nav>
      <div className="nav-separator"/><div className="nav-group-label">MANAGEMENT</div>
      <button onClick={() => go('instructor')} className={`nav-item ${route === 'instructor' ? 'nav-item--active' : ''}`} aria-current={route === 'instructor' ? 'page' : undefined}><SlidersHorizontal size={18} strokeWidth={1.7}/><span>Instructor desk</span></button>
      <div className="sidebar-bottom"><div className="safe-training-card"><ShieldCheck size={20}/><strong>A safe space to prepare.</strong><p>Synthetic environments.<br/>Real learning. No live systems.</p><span>DESKTOP-FIRST · OFFLINE-FIRST</span></div><button ref={helpTrigger} className="nav-item help-button" onClick={() => { if (simulation.view?.status === 'running' && simulation.connected) simulation.send({ type: 'pause' }); setHelpOpen(true); }}><CircleHelp size={18}/><span>Training guide</span><BookOpen size={14}/></button><div className="sidebar-version"><span className="status-dot"/>VIGIL v1.0<span>SIH 2026</span></div></div>
    </aside>
    <div className="workspace-body" inert={helpOpen || (compactNavigation && mobileOpen)}>
      <header className="topbar"><div className="topbar-left"><button ref={menuTrigger} className="icon-button menu-toggle" aria-label="Open navigation" aria-expanded={mobileOpen} onClick={() => setMobileOpen(v => !v)}><Menu size={21}/></button><span className="breadcrumb-root">Workspace</span><ChevronRight size={13}/><span className="breadcrumb-current">{ROUTE_LABELS[route]}</span></div><div className="topbar-right"><HistoryPill/><span className="topbar-divider"/><div className="profile-avatar" aria-hidden="true">{profile.name.replace(/[^0-9]/g, '').slice(-2) || profile.name.slice(0, 2).toUpperCase()}</div><label className="sr-only" htmlFor="active-profile">Active trainee profile</label><select id="active-profile" className="profile-select" value={profile.id} disabled={isActive || !historyReady} title={isActive ? 'Profile locked for the active exercise' : 'Choose an anonymous trainee'} onChange={e => setProfileId(e.target.value)}>{profiles.map(p => <option key={p.id} value={p.id}>{p.name}</option>)}</select></div></header>
      <main id="main-content" className={`main-content ${route === 'console' ? 'main-content--console' : ''}`} ref={mainRef} tabIndex={-1}><HistoryStatus/>{notice && <div className="workspace-notice" role="status"><InfoIcon/><p>{notice}</p><button onClick={dismissNotice} aria-label="Dismiss workspace notice"><X size={15}/></button></div>}{isActive && route !== 'console' && <div className="active-exercise-banner"><Monitor size={15}/><span>Exercise {simulation.starting ? 'starting' : !simulation.connected ? 'disconnected' : simulation.view?.status === 'running' ? 'pausing' : 'paused'} · {formatTime(simulation.view?.elapsedSeconds ?? 0)}</span><button onClick={() => navigate('console')}>Return to console<ChevronRight size={14}/></button></div>}{children}<footer className="page-footer"><span>VIGIL — Adaptive Simulation & Training System</span><span>Synthetic training only <span className="footer-dot">·</span> PS 26247</span></footer></main>
    </div>
    {helpOpen && <div className="modal-backdrop" onClick={() => setHelpOpen(false)}><section className="modal guide-modal" role="dialog" aria-modal="true" aria-labelledby="guide-title" onClick={e => e.stopPropagation()} onKeyDown={e => { if (e.key !== 'Tab') return; const buttons = Array.from(e.currentTarget.querySelectorAll<HTMLButtonElement>('button')); const first = buttons[0]; const last = buttons[buttons.length - 1]; if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last?.focus(); } else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first?.focus(); } }}><div className="modal-header"><div><p className="eyebrow">TRAINING GUIDE</p><h2 id="guide-title">Evidence before certainty.</h2></div><button ref={helpClose} className="icon-button" aria-label="Close training guide" onClick={() => setHelpOpen(false)}><X size={20}/></button></div><ol className="guide-steps"><li><strong>Configure & brief</strong><p>Choose a synthetic environment and a learning objective. Your seed makes an exercise repeatable.</p></li><li><strong>Observe & assess</strong><p>Work only with delivered observations. Low-quality or missing evidence is a reason to remain uncertain.</p></li><li><strong>Report & review</strong><p>Record a complete training report. After the exercise, inspect the explainable score and replay the actual event sequence.</p></li></ol><div className="notice notice--green"><ShieldCheck size={18}/><p>This is a non-operational learning tool. No live sensors, targeting, weapons or interception controls are connected.</p></div><p className="checkpoint-note">Current checkpoint: synthetic exercises, explainable evaluation, actual-event replay, durable local history and portable reports. Save failures are visible; active attempts are not resumed after reload. Historical summaries are descriptive, not validated readiness. The rules-1 next-practice planner uses saved completed evidence and conservative level-change rules. It is not ML, a mastery probability or automatic exercise start.</p><Button variant="secondary" onClick={() => setHelpOpen(false)}>Understood</Button></section></div>}
  </div>;
}

function InfoIcon() { return <ShieldCheck size={16}/>; }

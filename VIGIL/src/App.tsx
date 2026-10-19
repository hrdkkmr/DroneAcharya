import { Component, type ErrorInfo, type ReactNode } from 'react';
import { AlertTriangle } from 'lucide-react';
import { Shell } from './components/Shell';
import { Button } from './components/UI';
import { WorkspaceProvider, useWorkspace } from './hooks/useWorkspace';
import { Home } from './pages/Home';
import { SimulationConsole } from './pages/SimulationConsole';
import { SessionReview } from './pages/SessionReview';
import { ScenarioLab } from './pages/ScenarioLab';
import { InstructorFoundation, ProgressFoundation, UnitFoundation } from './pages/FoundationPages';

function Screen() {
  const { route, storage } = useWorkspace();
  const screens = { home: <Home/>, lab: <ScenarioLab/>, console: <SimulationConsole/>, aar: <SessionReview/>, progress: <ProgressFoundation/>, unit: <UnitFoundation/>, instructor: <InstructorFoundation/> };
  return <Shell>{storage.phase === 'loading' ? <div className="page history-loading"><div className="surface" role="status"><h1>Loading local history</h1><p>Validating saved profiles and actual reports. No exercise can start until this finishes.</p></div></div> : screens[route]}</Shell>;
}
class ErrorBoundary extends Component<{ children: ReactNode }, { error: string | null }> {
  state: { error: string | null } = { error: null };
  static getDerivedStateFromError(error: Error) { return { error: error.message }; }
  componentDidCatch(error: Error, info: ErrorInfo) { console.error('VIGIL presentation error', error, info.componentStack); }
  render() { return this.state.error ? <main className="fatal-error"><AlertTriangle size={34}/><h1>The workspace could not be displayed.</h1><p>{this.state.error}</p><p>No stored training records have been deleted.</p><Button onClick={() => window.location.reload()}>Reload workspace</Button></main> : this.props.children; }
}
export default function App() { return <ErrorBoundary><WorkspaceProvider><Screen/></WorkspaceProvider></ErrorBoundary>; }

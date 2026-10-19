/** Shared, versioned contracts. Hidden scenario data must never enter ActiveSessionView. */
export const SCHEMA_VERSION = 3 as const;
export type SchemaVersion = typeof SCHEMA_VERSION;
export type Environment = 'urban' | 'rural';
export type Lighting = 'day' | 'dusk' | 'night';
export type Weather = 'clear' | 'haze' | 'rain';
export type TrafficPattern = 'independent' | 'crossing' | 'grouped';
export type Difficulty = 1 | 2 | 3 | 4 | 5;
export type PresetId = 'perimeter' | 'urban-dusk' | 'night-watch' | 'rural-crossing' | 'custom';
export type Category = 'routine' | 'review' | 'background' | 'unknown';
export type TruthCategory = Exclude<Category, 'unknown'>;
export type ReportDecision = 'log' | 'observe' | 'escalate';
export type Skill = 'detection' | 'classification' | 'uncertainty' | 'reporting' | 'decision';
export type MetricKey = Skill | 'objectives';
export type EvaluationWeights = Record<MetricKey, number>;
export type SessionStatus = 'briefing' | 'running' | 'paused' | 'completed' | 'aborted';
export type SensorHealth = 'nominal' | 'degraded';

export interface ScenarioConfig {
  presetId: PresetId;
  exerciseType: 'observation' | 'assessment' | 'reporting';
  environment: Environment;
  lighting: Lighting;
  weather: Weather;
  reliability: number;
  noise: number;
  delaySeconds: number;
  trackCount: number;
  trafficPattern: TrafficPattern;
  durationSeconds: number;
  difficulty: Difficulty;
  seed: number;
  objectives: Skill[];
  weights: EvaluationWeights;
}

export interface ScenarioPreset {
  id: Exclude<PresetId, 'custom'>;
  name: string;
  description: string;
  focus: string;
  config: ScenarioConfig;
}

/** Hidden evaluator-only synthetic state. Not a physical/operational sensor model. */
export interface HiddenTrack {
  id: string;
  category: TruthCategory;
  significant: boolean;
  spawnAt: number;
  endAt: number;
  origin: { x: number; y: number };
  velocity: { x: number; y: number };
  phase: number;
}

export interface EvaluationRubric {
  version: 'rubric-1';
  weights: EvaluationWeights;
  detectionGraceSeconds: number;
  detectionWindowSeconds: number;
  reportingGraceSeconds: number;
  reportingWindowSeconds: number;
  minimumClearObservations: number;
  clearConfidenceThreshold: number;
  certaintyThreshold: number;
  unjustifiedEscalationPenalty: number;
  unsupportedCertaintyPenalty: number;
  missedSignificantPenalty: number;
}

export interface ScenarioDefinition {
  schemaVersion: SchemaVersion;
  generatorVersion: 'generator-2';
  sensorVersion: 'sensor-2';
  id: string;
  seed: number;
  config: ScenarioConfig;
  tracks: HiddenTrack[];
  degradation: { startsAt: number; endsAt: number } | null;
  rubric: EvaluationRubric;
}

/** Whitelist of scenario information allowed across the worker boundary during an exercise. */
export interface PublicScenario {
  schemaVersion: SchemaVersion;
  generatorVersion: 'generator-2';
  sensorVersion: 'sensor-2';
  id: string;
  seed: number;
  config: Omit<ScenarioConfig, 'weights'>;
}

export interface Observation {
  id: string;
  trackId: string;
  capturedAt: number;
  deliveredAt: number;
  source: 'scheduled' | 'requested';
  x: number;
  y: number;
  confidence: number;
  uncertainty: number;
  motion: 'steady' | 'variable' | 'drifting' | 'unresolved';
  signature: 'regular' | 'irregular' | 'diffuse' | 'unresolved';
}

export type TraineeAction =
  | { kind: 'select'; trackId: string }
  | { kind: 'track'; trackId: string }
  | { kind: 'request_observation'; trackId: string }
  | { kind: 'classify'; trackId: string; category: Category; confidence: number }
  | { kind: 'report'; trackId: string; decision: ReportDecision; summary: string };

export interface EventData {
  started: { scenarioId: string };
  observation: { observation: Observation };
  sensor_change: { health: SensorHealth; reason: string };
  action: { action: TraineeAction };
  paused: { source: 'trainee' };
  resumed: { source: 'trainee' };
  finished: { outcome: 'completed' | 'aborted' };
}
export type EventType = keyof EventData;
export type SimulationEvent = {
  [K in EventType]: {
    id: string;
    sessionId: string;
    order: number;
    time: number;
    type: K;
    data: EventData[K];
  }
}[EventType];

export interface TrackEvidence {
  id: string;
  latest: Observation;
  observations: Observation[];
  trackedAt: number | null;
  classification: { category: Category; confidence: number; eventId: string } | null;
  report: { decision: ReportDecision; summary: string; eventId: string } | null;
  lastRequestedAt: number | null;
}
export interface ActiveSessionView {
  schemaVersion: SchemaVersion;
  sessionId: string;
  profileId: string;
  scenario: PublicScenario;
  status: SessionStatus;
  elapsedSeconds: number;
  speed: 1 | 2 | 4;
  sensorHealth: SensorHealth;
  tracks: TrackEvidence[];
  events: SimulationEvent[];
}

export type EvaluationRuleId = 'D1' | 'C1' | 'U1' | 'R1' | 'Q1' | 'O1' | 'P1' | 'P2' | 'P3' | 'E0';

/** Evaluator-owned, unrounded per-track credit. Display is rounded, calculation is not. */
export interface TrackMetricAudit {
  key: Skill;
  ruleId: EvaluationRuleId;
  credit: number;
  available: number;
  earned: number;
  explanation: string;
  eventIds: string[];
  anchorEventId: string;
}

export interface MetricResult {
  ruleId: EvaluationRuleId;
  anchorEventId: string;
  key: MetricKey;
  label: string;
  score: number;
  weight: number;
  earned: number;
  denominator: number;
  unit: string;
  explanation: string;
  evidenceIds: string[];
}
export interface EvaluationFinding {
  ruleId: EvaluationRuleId;
  anchorEventId: string;
  trackId: string | null;
  points: number;
  appliedPenalty: boolean;
  reason: string;
  eventIds: string[];
}
export interface TrackEvaluation {
  metrics: TrackMetricAudit[];
  trackId: string;
  truthCategory: TruthCategory;
  significant: boolean;
  firstObservedAt: number | null;
  detectedAt: number | null;
  detectionLatencySeconds: number | null;
  category: Category | null;
  confidence: number | null;
  expectedDecision: ReportDecision | null;
  actualDecision: ReportDecision | null;
  clearEvidenceCount: number;
  missed: boolean;
  findings: EvaluationFinding[];
}
export interface EvaluationResult {
  rubricVersion: 'rubric-1';
  score: number;
  weightedScore: number;
  penaltyPoints: number;
  metrics: MetricResult[];
  tracks: TrackEvaluation[];
  findings: EvaluationFinding[];
  strengths: string[];
  improvements: string[];
  objectivesCompleted: Skill[];
  comparable: boolean;
}
export interface SessionRecord {
  schemaVersion: SchemaVersion;
  id: string;
  profileId: string;
  startedAt: string;
  endedAt: string;
  status: 'completed' | 'aborted';
  elapsedSeconds: number;
  scenario: ScenarioDefinition;
  events: SimulationEvent[];
  evaluation: EvaluationResult;
}
/** Derived read-only replay contracts. No hidden scenario or evaluation in a timeline/frame. */
export interface ReplayCursor { readonly time: number; readonly eventCount: number }
export interface ReplayTimeline {
  readonly version: 'replay-1';
  readonly schemaVersion: SchemaVersion;
  readonly sessionId: string;
  readonly profileId: string;
  readonly scenario: PublicScenario;
  readonly durationSeconds: number;
  readonly events: readonly SimulationEvent[];
}
export interface ReplayFrame {
  cursor: ReplayCursor;
  view: ActiveSessionView;
  recordedSelectionId: string | null;
  lastEvent: SimulationEvent | null;
}
export interface SessionSummary {
  id: string;
  profileId: string;
  scenarioId: string;
  presetId: PresetId;
  endedAt: string;
  status: 'completed' | 'aborted';
  difficulty: Difficulty;
  score: number;
  eventCount: number;
}
export interface TraineeProfile {
  schemaVersion: SchemaVersion;
  id: string;
  name: string;
  unit: string;
  createdAt: string;
}
/** Derived heuristic learning evidence, never stored as a score or a calibrated probability. */
export interface CompetencyEstimate {
  skill: Skill;
  estimate: number | null;
  sampleSize: number;
  recentScores: number[];
  evidenceSessionIds: string[];
  spread: number | null;
  confidence: 'provisional' | 'developing' | 'established';
}
export type AdaptiveRule = 'foundation' | 'sparse' | 'mixed-context' | 'repeated' | 'inconsistent' | 'increase' | 'decrease' | 'ceiling' | 'floor' | 'consolidate';
export interface AdaptiveRecommendation {
  policyVersion: 'rules-1';
  method: 'rule-based';
  target: Skill;
  config: ScenarioConfig;
  reasons: string[];
  rule: AdaptiveRule;
  evidenceSessionIds: string[];
  decisionSessionIds: string[];
  sampleSize: number;
  eligibleCount: number;
  baselineDifficulty: Difficulty;
  difficultyChange: 'hold' | 'increase' | 'decrease';
  excluded: { unsaved: number; aborted: number; noEvidence: number; differentContext: number; repeated: number };
  competencies: CompetencyEstimate[];
}
export interface SessionExport {
  format: 'vigil-session-export';
  formatVersion: 1;
  schemaVersion: SchemaVersion;
  exportedAt: string;
  profiles: TraineeProfile[];
  sessions: SessionRecord[];
}

export type WorkerCommand =
  | { type: 'configure'; config: ScenarioConfig; profileId: string; sessionId: string; startedAt: string }
  | { type: 'start' | 'pause' | 'resume' | 'finish' }
  | { type: 'speed'; value: 1 | 2 | 4 }
  | { type: 'action'; action: TraineeAction };
export type WorkerResponse =
  | { type: 'ready' }
  | { type: 'view'; view: ActiveSessionView }
  | { type: 'completed'; record: SessionRecord; view: ActiveSessionView }
  | { type: 'error'; code: string; message: string };

export type Route = 'home' | 'lab' | 'console' | 'aar' | 'progress' | 'unit' | 'instructor';

/** Local history contracts are separate from the unchanged simulation record schema. */
export interface WorkspacePreferences {
  config: ScenarioConfig;
  profileId: string;
  selectedSessionId: string | null;
}
export interface HistoryMeta {
  key: 'workspace';
  version: 1;
  epoch: string;
  revision: number;
  preferences: WorkspacePreferences;
}
export interface QuarantinedEntry { store: 'profiles' | 'sessions'; id: string; reason: string }
export interface LoadedHistory {
  profiles: TraineeProfile[];
  sessions: SessionRecord[];
  meta: HistoryMeta;
  quarantined: QuarantinedEntry[];
}
export interface HistoryDelta {
  profiles: readonly TraineeProfile[];
  sessions: readonly SessionRecord[];
  preferences: WorkspacePreferences;
}
export interface HistoryRepository {
  load: () => Promise<LoadedHistory>;
  commit: (epoch: string, delta: HistoryDelta) => Promise<void>;
  reset: (epoch: string | null) => Promise<LoadedHistory>;
  rawBackup: () => Promise<unknown>;
}

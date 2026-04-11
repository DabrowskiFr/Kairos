import * as vscode from "vscode";

export type RpcRequestId = number | string;

export interface Loc {
  line: number;
  col: number;
  line_end: number;
  col_end: number;
}

export interface TextSpan {
  start_offset: number;
  end_offset: number;
}

export interface ProofDiagnostic {
  category: string;
  summary: string;
  detail: string;
  probable_cause: string | null;
  missing_elements: string[];
  goal_symbols: string[];
  analysis_method: string;
  solver_detail: string | null;
  native_unsat_core_solver: string | null;
  native_unsat_core_hypothesis_ids: number[];
  native_counterexample_solver: string | null;
  native_counterexample_model: string | null;
  kairos_core_hypotheses: string[];
  why3_noise_hypotheses: string[];
  relevant_hypotheses: string[];
  context_hypotheses: string[];
  unused_hypotheses: string[];
  suggestions: string[];
  limitations: string[];
}

export interface ProofTrace {
  goal_index: number;
  stable_id: string;
  goal_name: string;
  status: string;
  solver_status: string;
  time_s: number;
  source: string;
  node: string | null;
  transition: string | null;
  obligation_kind: string;
  obligation_family: string | null;
  obligation_category: string | null;
  vc_id: string | null;
  source_span: Loc | null;
  obc_span: TextSpan | null;
  why_span: TextSpan | null;
  vc_span: TextSpan | null;
  smt_span: TextSpan | null;
  dump_path: string | null;
  diagnostic: ProofDiagnostic;
}

export type GoalInfoTuple = [
  goal: string,
  status: string,
  time_s: number,
  dump_path: string | null,
  vcid: string | null
];

export interface StageMetaEntry {
  stage: string;
  entries: Array<[string, string]>;
}

export interface Outputs {
  obc_text: string;
  why_text: string;
  vc_text: string;
  smt_text: string;
  dot_text: string;
  labels_text: string;
  program_automaton_text: string;
  guarantee_automaton_text: string;
  assume_automaton_text: string;
  product_text: string;
  obligations_map_text: string;
  prune_reasons_text: string;
  program_dot: string;
  guarantee_automaton_dot: string;
  assume_automaton_dot: string;
  product_dot: string;
  stage_meta: Array<[string, Array<[string, string]>]>;
  goals: GoalInfoTuple[];
  proof_traces: ProofTrace[];
  obcplus_sequents: Array<[number, string]>;
  vc_locs: Array<[number, Loc]>;
  obcplus_spans: Array<[number, [number, number]]>;
  vc_locs_ordered: Loc[];
  obcplus_spans_ordered: Array<[number, number]>;
  vc_spans_ordered: Array<[number, number]>;
  why_spans: Array<[number, [number, number]]>;
  vc_ids_ordered: number[];
  obcplus_time_s: number;
  why_time_s: number;
  automata_generation_time_s: number;
  automata_build_time_s: number;
  why3_prep_time_s: number;
  dot_png: string | null;
  dot_png_error: string | null;
  program_png: string | null;
  program_png_error: string | null;
  guarantee_automaton_png: string | null;
  guarantee_automaton_png_error: string | null;
  assume_automaton_png: string | null;
  assume_automaton_png_error: string | null;
  product_png: string | null;
  product_png_error: string | null;
  historical_clauses_text: string;
  eliminated_clauses_text: string;
  eval_text?: string;
}

export interface AutomataOutputs {
  dot_text: string;
  labels_text: string;
  program_automaton_text: string;
  guarantee_automaton_text: string;
  assume_automaton_text: string;
  product_text: string;
  obligations_map_text: string;
  prune_reasons_text: string;
  program_dot: string;
  guarantee_automaton_dot: string;
  assume_automaton_dot: string;
  product_dot: string;
  dot_png: string | null;
  dot_png_error: string | null;
  program_png: string | null;
  program_png_error: string | null;
  guarantee_automaton_png: string | null;
  guarantee_automaton_png_error: string | null;
  assume_automaton_png: string | null;
  assume_automaton_png_error: string | null;
  product_png: string | null;
  product_png_error: string | null;
  stage_meta: Array<[string, Array<[string, string]>]>;
  historical_clauses_text: string;
  eliminated_clauses_text: string;
}

export interface GoalsReadyPayload {
  names: string[];
  vcIds: number[];
}

export interface GoalDonePayload {
  idx: number;
  goal: string;
  status: string;
  time_s: number;
  dump_path: string | null;
  vcid: string | null;
}

export interface OutputsReadyNotification {
  requestId: RpcRequestId;
  payload: Outputs;
}

export interface GoalsReadyNotification {
  requestId: RpcRequestId;
  payload: GoalsReadyPayload;
}

export interface GoalDoneNotification {
  requestId: RpcRequestId;
  payload: GoalDonePayload;
}

export interface OutlineEntry {
  name: string;
  line: number;
}

export interface OutlineSections {
  nodes: OutlineEntry[];
  transitions: OutlineEntry[];
  contracts: OutlineEntry[];
}

export interface OutlinePayload {
  source: OutlineSections;
  abstract: OutlineSections;
}

export interface GoalTreeEntry {
  idx: number;
  display_no: number;
  goal: string;
  status: string;
  time_s: number;
  dump_path: string | null;
  source: string;
  vcid: string | null;
}

export interface GoalTreeTransition {
  transition: string;
  source: string;
  succeeded: number;
  total: number;
  items: GoalTreeEntry[];
}

export interface GoalTreeNode {
  node: string;
  source: string;
  succeeded: number;
  total: number;
  transitions: GoalTreeTransition[];
}

export interface KairosRunConfig {
  inputFile: string;
  engine: string;
  wpOnly: boolean;
  smokeTests: boolean;
  timeoutS: number;
  maxProofGoals?: number;
  computeProofDiagnostics: boolean;
  prefixFields: boolean;
  prove: boolean;
  generateVcText: boolean;
  generateSmtText: boolean;
  generateMonitorText: boolean;
  generateDotPng: boolean;
}

export type RunPhase =
  | "idle"
  | "parsing"
  | "building"
  | "proving"
  | "eval"
  | "completed"
  | "failed"
  | "cancelled";

export interface ArtifactDescriptor {
  id: ArtifactId;
  label: string;
  kind: "text" | "graph" | "external";
  description: string;
}

export type ArtifactId =
  | "obc"
  | "why"
  | "vc"
  | "smt"
  | "labels"
  | "program"
  | "assume"
  | "guarantee"
  | "product"
  | "obligations_map"
  | "prune_reasons"
  | "eval";

export type GraphId = "program" | "assume" | "guarantee" | "product";

export interface RunHistoryEntry {
  id: string;
  command: string;
  file: string;
  startedAt: string;
  endedAt?: string;
  durationMs?: number;
  phase: RunPhase;
  success: boolean;
  summary: string;
}

export interface EvalHistoryEntry {
  traceText: string;
  withState: boolean;
  withLocals: boolean;
  createdAt: string;
  file: string;
}

export interface ExportRequest {
  graphId: GraphId;
  format: "png" | "svg" | "pdf";
}

export type PanelId = "automata" | "dashboard" | "explain" | "artifacts" | "eval" | "pipeline" | "compare";

export interface SessionSnapshot {
  activeFile: string | null;
  currentArtifact: ArtifactId;
  runHistory: RunHistoryEntry[];
  evalHistory: EvalHistoryEntry[];
  openPanels: PanelId[];
}

export interface WebviewContext {
  extensionUri: vscode.Uri;
}

export const ARTIFACTS: ArtifactDescriptor[] = [
  { id: "obc", label: "OBC+", kind: "text", description: "Abstract program" },
  { id: "why", label: "Why", kind: "text", description: "Generated Why3 file" },
  { id: "vc", label: "VC", kind: "text", description: "Verification conditions" },
  { id: "smt", label: "SMT", kind: "text", description: "SMT dump" },
  { id: "labels", label: "Labels", kind: "text", description: "Automata labels" },
  { id: "program", label: "Program Automaton", kind: "graph", description: "Program automaton" },
  { id: "assume", label: "Assume Automaton", kind: "graph", description: "Assumption automaton" },
  { id: "guarantee", label: "Guarantee Automaton", kind: "graph", description: "Guarantee automaton" },
  { id: "product", label: "Product Automaton", kind: "graph", description: "A x G x Program product" },
  {
    id: "obligations_map",
    label: "Obligations Map",
    kind: "text",
    description: "Node and transition obligations"
  },
  {
    id: "prune_reasons",
    label: "Prune Reasons",
    kind: "text",
    description: "Why transitions or states were pruned"
  },
  { id: "eval", label: "Eval", kind: "text", description: "Eval output" }
];

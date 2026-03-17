import * as vscode from "vscode";
import {
  ArtifactId,
  AutomataOutputs,
  EvalHistoryEntry,
  GoalDonePayload,
  GoalTreeEntry,
  GoalTreeNode,
  OutlinePayload,
  Outputs,
  ProofTrace,
  RunHistoryEntry,
  RunPhase
} from "./types";

function newId(): string {
  return `${Date.now()}-${Math.random().toString(16).slice(2, 10)}`;
}

export class KairosState {
  public outputs: Outputs | null = null;
  public previousOutputs: Outputs | null = null;
  public automata: AutomataOutputs | null = null;
  public goalsTree: GoalTreeNode[] = [];
  public goalEntries: GoalTreeEntry[] = [];
  public outline: OutlinePayload | null = null;
  public goalNames: string[] = [];
  public vcIds: number[] = [];
  public runPhase: RunPhase = "idle";
  public activeFile: string | null = null;
  public activeCommand: string | null = null;
  public statusMessage = "Idle";
  public stageSummary = "";
  public currentArtifact: ArtifactId = "obc";
  public activeGoal: GoalDonePayload | null = null;
  public activeProofTrace: ProofTrace | null = null;
  public runHistory: RunHistoryEntry[] = [];
  public evalHistory: EvalHistoryEntry[] = [];
  public startedAtMs: number | null = null;

  private readonly didChangeEmitter = new vscode.EventEmitter<void>();
  readonly onDidChange = this.didChangeEmitter.event;

  private readonly didHistoryEmitter = new vscode.EventEmitter<void>();
  readonly onDidChangeHistory = this.didHistoryEmitter.event;

  setOutputs(outputs: Outputs | null): void {
    if (outputs) {
      this.previousOutputs = this.outputs;
    }
    this.outputs = outputs;
    this.didChangeEmitter.fire();
  }

  setAutomata(automata: AutomataOutputs | null): void {
    this.automata = automata;
    this.didChangeEmitter.fire();
  }

  setGoalsTree(goalsTree: GoalTreeNode[]): void {
    this.goalsTree = goalsTree;
    this.didChangeEmitter.fire();
  }

  setGoalEntries(goalEntries: GoalTreeEntry[]): void {
    this.goalEntries = goalEntries;
    this.didChangeEmitter.fire();
  }

  updateGoalEntry(payload: GoalDonePayload): void {
    const next = [...this.goalEntries];
    const current = next[payload.idx];
    next[payload.idx] = {
      idx: payload.idx,
      display_no: payload.idx + 1,
      goal: payload.goal ?? current?.goal ?? "",
      status: payload.status ?? current?.status ?? "pending",
      time_s: typeof payload.time_s === "number" ? payload.time_s : (current?.time_s ?? 0),
      dump_path: payload.dump_path ?? current?.dump_path ?? null,
      source: payload.source ?? current?.source ?? "",
      vcid: payload.vcid ?? current?.vcid ?? null
    };
    this.goalEntries = next;
    this.didChangeEmitter.fire();
  }

  setOutline(outline: OutlinePayload | null): void {
    this.outline = outline;
    this.didChangeEmitter.fire();
  }

  setPendingGoals(names: string[], vcIds: number[]): void {
    this.goalNames = names;
    this.vcIds = vcIds;
    this.didChangeEmitter.fire();
  }

  reset(): void {
    this.outputs = null;
    this.automata = null;
    this.goalsTree = [];
    this.goalEntries = [];
    this.outline = null;
    this.goalNames = [];
    this.vcIds = [];
    this.activeGoal = null;
    this.activeProofTrace = null;
    this.currentArtifact = "obc";
    this.runPhase = "idle";
    this.activeCommand = null;
    this.statusMessage = "State reset";
    this.stageSummary = "";
    this.startedAtMs = null;
    this.didChangeEmitter.fire();
  }

  setCurrentArtifact(artifactId: ArtifactId): void {
    this.currentArtifact = artifactId;
    this.didChangeEmitter.fire();
  }

  setActiveProofTrace(trace: ProofTrace | null): void {
    this.activeProofTrace = trace;
    this.didChangeEmitter.fire();
  }

  setPhase(phase: RunPhase, message: string, command?: string): void {
    this.runPhase = phase;
    this.statusMessage = message;
    if (command !== undefined) {
      this.activeCommand = command;
    }
    if (phase === "building" || phase === "proving" || phase === "eval" || phase === "parsing") {
      this.startedAtMs = Date.now();
    }
    if (phase === "completed" || phase === "failed" || phase === "cancelled" || phase === "idle") {
      this.startedAtMs = null;
    }
    this.didChangeEmitter.fire();
  }

  setStageSummary(summary: string): void {
    this.stageSummary = summary;
    this.didChangeEmitter.fire();
  }

  beginRun(command: string, file: string, phase: RunPhase, summary: string): string {
    const entry: RunHistoryEntry = {
      id: newId(),
      command,
      file,
      startedAt: new Date().toISOString(),
      phase,
      success: false,
      summary
    };
    this.runHistory = [entry, ...this.runHistory].slice(0, 40);
    this.didHistoryEmitter.fire();
    return entry.id;
  }

  finishRun(runId: string | null, success: boolean, phase: RunPhase, summary: string): void {
    if (!runId) {
      return;
    }
    this.runHistory = this.runHistory.map((entry) => {
      if (entry.id !== runId) {
        return entry;
      }
      const endedAt = new Date().toISOString();
      const durationMs = Date.parse(endedAt) - Date.parse(entry.startedAt);
      return { ...entry, endedAt, durationMs, phase, success, summary };
    });
    this.didHistoryEmitter.fire();
  }

  addEvalHistory(entry: EvalHistoryEntry): void {
    this.evalHistory = [entry, ...this.evalHistory].slice(0, 20);
    this.didChangeEmitter.fire();
  }
}

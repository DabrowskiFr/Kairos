import * as fs from "fs";
import * as vscode from "vscode";
import { buildGoalSummary } from "./providers";
import { KairosState } from "./state";
import { ARTIFACTS, ArtifactId, GraphId, GoalTreeEntry, Loc, ProofTrace, TextSpan } from "./types";

function nonce(): string {
  return `${Date.now()}${Math.random().toString(16).slice(2)}`;
}

function escapeHtml(text: string): string {
  return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

function pngPathToDataUri(filePath: string | null | undefined): string {
  if (!filePath || !fs.existsSync(filePath)) {
    return "";
  }
  return `data:image/png;base64,${fs.readFileSync(filePath).toString("base64")}`;
}

function preferredViewColumn(): vscode.ViewColumn {
  return (
    vscode.window.activeTextEditor?.viewColumn ??
    vscode.window.visibleTextEditors[0]?.viewColumn ??
    vscode.ViewColumn.One
  );
}

export interface PanelHost {
  openArtifact(kind: ArtifactId): Promise<void>;
  openArtifactSpan(kind: ArtifactId, span: TextSpan | null): Promise<void>;
  openGraphPanel(): Promise<void>;
  openDashboardPanel(): Promise<void>;
  openExplainFailurePanel(trace?: ProofTrace | null): Promise<void>;
  rerunFocusedDiagnosis(trace: ProofTrace): Promise<void>;
  openEvalPanel(): Promise<void>;
  openPipelinePanel(): Promise<void>;
  openComparePanel(): Promise<void>;
  runEval(traceText: string, withState: boolean, withLocals: boolean): Promise<string>;
  openWhyForGoal(goal: GoalTreeEntry): Promise<void>;
  openSourceLocation(loc: Loc | null): Promise<void>;
  openDumpPath(path: string | null): Promise<void>;
  diffCurrentObcWithPrevious(): Promise<void>;
  showRunHistory(): Promise<void>;
  openTraceFile(): Promise<string | null>;
  saveTraceFile(contents: string): Promise<string | null>;
  exportHtmlReport(): Promise<void>;
}

export class AutomataPanel {
  private panel: vscode.WebviewPanel | null = null;
  private host: PanelHost | null = null;
  private renderTimer: ReturnType<typeof setTimeout> | null = null;
  private pendingGraphs: Record<string, { svg: string; pngSrc: string; renderError?: string | null }> | null = null;

  constructor(private readonly state: KairosState) {
    this.state.onDidChange(() => {
      if (this.renderTimer) clearTimeout(this.renderTimer);
      this.renderTimer = setTimeout(() => this.render(), 150);
    });
  }

  setHost(host: PanelHost): void {
    this.host = host;
  }

  show(): void {
    // Cancel any pending debounced render so it doesn't race with the one we trigger now.
    if (this.renderTimer) {
      clearTimeout(this.renderTimer);
      this.renderTimer = null;
    }
    const column = preferredViewColumn();
    if (!this.panel) {
      this.panel = vscode.window.createWebviewPanel("kairosAutomata", "Kairos Automata", column, {
        enableScripts: true,
        retainContextWhenHidden: true,
        localResourceRoots: []
      });
      this.panel.onDidDispose(() => {
        this.panel = null;
      });
      this.panel.webview.onDidReceiveMessage(async (message) => {
        if (message?.type === "ready") {
          // Webview script is loaded — send pending image data now.
          if (this.pendingGraphs && this.panel) {
            void this.panel.webview.postMessage({ type: "update", graphs: this.pendingGraphs });
          }
        } else if (message?.type === "openArtifact") {
          await this.host?.openArtifact(message.artifact as ArtifactId);
        }
      });
    }
    this.panel.reveal(column);
    this.render();
  }

  private render(): void {
    if (!this.panel) {
      return;
    }
    const webview = this.panel.webview;
    const a = this.state.automata ?? this.state.outputs;
    const graphs: Record<string, { pngSrc: string; error: string }> = {
      program:   { pngSrc: pngPathToDataUri(a?.program_png),             error: a?.program_png_error ?? "" },
      assume:    { pngSrc: pngPathToDataUri(a?.assume_automaton_png),    error: a?.assume_automaton_png_error ?? "" },
      guarantee: { pngSrc: pngPathToDataUri(a?.guarantee_automaton_png), error: a?.guarantee_automaton_png_error ?? "" },
      product:   { pngSrc: pngPathToDataUri(a?.product_png),             error: a?.product_png_error ?? "" },
    };
    const textData = {
      labels: a?.labels_text ?? "",
      obligations: a?.obligations_map_text ?? "",
      prune: a?.prune_reasons_text ?? ""
    };

    const graphIds = ["program", "assume", "guarantee", "product"] as const;
    // Each graph pane is pre-rendered in HTML — no JS needed to show the image.
    const panes = graphIds.map(id => {
      const g = graphs[id];
      const content = g.pngSrc
        ? `<img alt="${id} automaton" src="${escapeHtml(g.pngSrc)}">`
        : g.error
          ? `<div class="muted error">${escapeHtml(g.error)}</div>`
          : `<div class="muted">No image for ${id}.</div>`;
      return `<div class="pane" id="pane-${id}" style="display:none">${content}</div>`;
    }).join("\n");

    const scriptNonce = nonce();
    webview.html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src ${webview.cspSource} 'unsafe-inline'; script-src 'nonce-${scriptNonce}';">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    :root {
      color-scheme: light;
      --bg: var(--vscode-editor-background, #fbfbf9);
      --panel: color-mix(in srgb, var(--bg) 96%, #ffffff 4%);
      --fg: var(--vscode-editor-foreground, #202020);
      --muted: var(--vscode-descriptionForeground, #666);
      --accent: var(--vscode-focusBorder, #0f6cbd);
      --border: var(--vscode-panel-border, #d9d9d9);
      --soft: color-mix(in srgb, var(--accent) 10%, var(--bg) 90%);
    }
    body { margin: 0; font-family: var(--vscode-font-family); background: var(--bg); color: var(--fg); }
    .shell { display: grid; grid-template-rows: auto 1fr; height: 100vh; }
    .toolbar { display: flex; gap: 8px; align-items: center; padding: 10px 12px; border-bottom: 1px solid var(--border); background: var(--panel); flex-wrap: wrap; }
    button { font: inherit; border: 1px solid var(--border); border-radius: 8px; background: white; color: var(--fg); padding: 6px 10px; cursor: pointer; }
    .tab.active { background: var(--soft); border-color: var(--accent); }
    .layout { display: grid; grid-template-columns: minmax(0, 1fr) 320px; min-height: 0; }
    .canvasWrap { min-height: 0; overflow: auto; padding: 24px; background: var(--bg); }
    .canvasWrap img { max-width: 100%; background: white; border-radius: 12px; box-shadow: 0 4px 24px rgba(0,0,0,0.10); display: block; }
    .side { border-left: 1px solid var(--border); padding: 12px; overflow: auto; }
    pre { white-space: pre-wrap; word-break: break-word; background: white; border: 1px solid var(--border); border-radius: 8px; padding: 8px; font-size: 12px; }
    .muted { color: var(--muted); font-style: italic; }
    .error { color: #c00; }
    h3 { margin: 12px 0 4px; font-size: 11px; text-transform: uppercase; letter-spacing: 0.08em; color: var(--muted); }
  </style>
</head>
<body>
<div class="shell">
  <div class="toolbar">
    <button class="tab" data-graph="program">Program</button>
    <button class="tab" data-graph="assume">Assume</button>
    <button class="tab" data-graph="guarantee">Guarantee</button>
    <button class="tab" data-graph="product">Product</button>
  </div>
  <div class="layout">
    <div class="canvasWrap" id="canvas">
${panes}
    </div>
    <div class="side">
      <h3>Labels</h3><pre>${escapeHtml(textData.labels.slice(0, 4000))}</pre>
      <h3>Obligations</h3><pre>${escapeHtml(textData.obligations.slice(0, 4000))}</pre>
      <h3>Prune Reasons</h3><pre>${escapeHtml(textData.prune.slice(0, 4000))}</pre>
    </div>
  </div>
</div>
<script nonce="${scriptNonce}">
  var active = "program";
  function show(id) {
    active = id;
    ["program","assume","guarantee","product"].forEach(function(g) {
      var el = document.getElementById("pane-" + g);
      if (el) el.style.display = (g === id) ? "block" : "none";
    });
    document.querySelectorAll(".tab").forEach(function(t) {
      t.classList.toggle("active", t.dataset.graph === id);
    });
  }
  document.querySelectorAll(".tab").forEach(function(btn) {
    btn.addEventListener("click", function() { show(btn.dataset.graph); });
  });
  show("program");
</script>
</body>
</html>`;
  }
}

// ---------------------------------------------------------------------------
// IR Panel — visualizes the annotated, verified and kernel IR graphs
// ---------------------------------------------------------------------------

export interface IrNodeGraphs {
  name: string;
  annotatedPng: string; // base64 data URI, or "" if unavailable
  annotatedError: string;
  verifiedPng: string;
  verifiedError: string;
  kernelPng: string;
  kernelError: string;
}

export class IrPanel {
  private panel: vscode.WebviewPanel | null = null;

  show(nodes: IrNodeGraphs[]): void {
    const column = preferredViewColumn();
    if (!this.panel) {
      this.panel = vscode.window.createWebviewPanel("kairosIr", "Kairos IR", column, {
        enableScripts: true,
        retainContextWhenHidden: true,
        localResourceRoots: []
      });
      this.panel.onDidDispose(() => {
        this.panel = null;
      });
    }
    this.panel.reveal(column);
    this.renderNodes(nodes);
  }

  private renderNodes(nodes: IrNodeGraphs[]): void {
    if (!this.panel) {
      return;
    }
    const webview = this.panel.webview;
    const stages = ["annotated", "verified", "kernel"] as const;
    const stageLabels: Record<string, string> = {
      annotated: "Annotated",
      verified: "Verified",
      kernel: "Kernel"
    };

    const panes = nodes
      .flatMap((n) =>
        stages.map((s) => {
          const pngSrc = s === "annotated" ? n.annotatedPng : s === "verified" ? n.verifiedPng : n.kernelPng;
          const err = s === "annotated" ? n.annotatedError : s === "verified" ? n.verifiedError : n.kernelError;
          const content = pngSrc
            ? `<img alt="${escapeHtml(n.name)} ${s}" src="${escapeHtml(pngSrc)}">`
            : err
              ? `<div class="muted error">${escapeHtml(err)}</div>`
              : `<div class="muted">No ${s} IR graph for ${escapeHtml(n.name)}.</div>`;
          return `<div class="pane" id="pane-${escapeHtml(n.name)}-${s}" style="display:none">${content}</div>`;
        })
      )
      .join("\n");

    const nodeOptions =
      nodes.length > 1
        ? nodes
            .map((n) => `<option value="${escapeHtml(n.name)}">${escapeHtml(n.name)}</option>`)
            .join("")
        : "";

    const firstNode = nodes[0]?.name ?? "";
    const scriptNonce = nonce();

    webview.html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src ${webview.cspSource} 'unsafe-inline'; script-src 'nonce-${scriptNonce}';">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    :root {
      color-scheme: light;
      --bg: var(--vscode-editor-background, #fbfbf9);
      --panel: color-mix(in srgb, var(--bg) 96%, #ffffff 4%);
      --fg: var(--vscode-editor-foreground, #202020);
      --muted: var(--vscode-descriptionForeground, #666);
      --accent: var(--vscode-focusBorder, #0f6cbd);
      --border: var(--vscode-panel-border, #d9d9d9);
      --soft: color-mix(in srgb, var(--accent) 10%, var(--bg) 90%);
    }
    body { margin: 0; font-family: var(--vscode-font-family); background: var(--bg); color: var(--fg); }
    .shell { display: grid; grid-template-rows: auto 1fr; height: 100vh; }
    .toolbar { display: flex; gap: 8px; align-items: center; padding: 10px 12px; border-bottom: 1px solid var(--border); background: var(--panel); flex-wrap: wrap; }
    select, button { font: inherit; border: 1px solid var(--border); border-radius: 8px; background: white; color: var(--fg); padding: 6px 10px; cursor: pointer; }
    .tab.active { background: var(--soft); border-color: var(--accent); }
    .canvasWrap { min-height: 0; overflow: auto; padding: 24px; background: var(--bg); }
    .canvasWrap img { max-width: 100%; background: white; border-radius: 12px; box-shadow: 0 4px 24px rgba(0,0,0,0.10); display: block; }
    .muted { color: var(--muted); font-style: italic; padding: 16px; }
    .error { color: #c00; }
  </style>
</head>
<body>
<div class="shell">
  <div class="toolbar">
    ${nodeOptions ? `<select id="nodeSelect">${nodeOptions}</select>` : ""}
    ${stages.map((s) => `<button class="tab" data-stage="${s}">${stageLabels[s]}</button>`).join("\n    ")}
  </div>
  <div class="canvasWrap" id="canvas">
${panes}
  </div>
</div>
<script nonce="${scriptNonce}">
  var nodes = ${JSON.stringify(nodes.map((n) => n.name))};
  var stages = ["annotated","verified","kernel"];
  var currentNode = ${JSON.stringify(firstNode)};
  var currentStage = "annotated";

  function show() {
    nodes.forEach(function(n) {
      stages.forEach(function(s) {
        var el = document.getElementById("pane-" + n + "-" + s);
        if (el) el.style.display = (n === currentNode && s === currentStage) ? "block" : "none";
      });
    });
    document.querySelectorAll(".tab").forEach(function(t) {
      t.classList.toggle("active", t.dataset.stage === currentStage);
    });
  }

  document.querySelectorAll(".tab").forEach(function(btn) {
    btn.addEventListener("click", function() { currentStage = btn.dataset.stage; show(); });
  });

  var sel = document.getElementById("nodeSelect");
  if (sel) {
    sel.addEventListener("change", function() { currentNode = sel.value; show(); });
  }

  show();
</script>
</body>
</html>`;
  }
}

export class EvalPanel {
  private panel: vscode.WebviewPanel | null = null;
  private host: PanelHost | null = null;

  constructor(private readonly state: KairosState) {
    this.state.onDidChange(() => this.render());
  }

  setHost(host: PanelHost): void {
    this.host = host;
  }

  async show(): Promise<void> {
    const column = preferredViewColumn();
    if (!this.panel) {
      this.panel = vscode.window.createWebviewPanel("kairosEval", "Kairos Eval", column, {
        enableScripts: true,
        retainContextWhenHidden: true
      });
      this.panel.onDidDispose(() => {
        this.panel = null;
      });
      this.panel.webview.onDidReceiveMessage(async (message) => {
        if (message?.type === "runEval") {
          const result = await this.host?.runEval(message.traceText, !!message.withState, !!message.withLocals);
          await this.panel?.webview.postMessage({ type: "evalResult", result });
        } else if (message?.type === "openTraceFile") {
          const contents = await this.host?.openTraceFile();
          await this.panel?.webview.postMessage({ type: "traceOpened", contents });
        } else if (message?.type === "saveTraceFile") {
          const path = await this.host?.saveTraceFile(message.traceText ?? "");
          await this.panel?.webview.postMessage({ type: "traceSaved", path });
        }
      });
    }
    this.panel.reveal(column);
    this.render();
  }

  private render(): void {
    if (!this.panel) {
      return;
    }
    const scriptNonce = nonce();
    const latest = this.state.evalHistory[0];
    const examples = [
      "# one step per line\\nx=1, y=0",
      "reset=1, x=0\\nreset=0, x=5\\nreset=0, x=7",
      '{"x": 1, "reset": 0}\\n{"x": 2, "reset": 0}'
    ];
    this.panel.webview.html = `<!DOCTYPE html>
<html lang="en"><head>
  <meta charset="UTF-8">
  <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src ${this.panel.webview.cspSource} 'unsafe-inline'; script-src 'nonce-${scriptNonce}';">
  <style>
    :root { color-scheme: light; --bg: var(--vscode-editor-background, #fbfbf9); --fg: var(--vscode-editor-foreground, #202020); --border: var(--vscode-panel-border, #d9d9d9); --accent: var(--vscode-focusBorder, #0f6cbd); }
    body { margin: 0; font-family: var(--vscode-font-family); background: var(--bg); color: var(--fg); }
    .shell { display: grid; grid-template-rows: auto 1fr 1fr; height: 100vh; }
    .toolbar { display: flex; gap: 8px; align-items: center; padding: 12px; border-bottom: 1px solid var(--border); }
    textarea, pre { width: 100%; box-sizing: border-box; border-radius: 10px; border: 1px solid var(--border); padding: 12px; font: 12px/1.5 var(--vscode-editor-font-family, monospace); }
    textarea { min-height: 100%; resize: none; }
    .grid { padding: 12px; min-height: 0; }
    button, select { font: inherit; }
    button { border: 1px solid var(--border); border-radius: 8px; background: white; padding: 6px 10px; cursor: pointer; }
    button.primary { background: var(--accent); color: white; border-color: var(--accent); }
  </style>
</head>
<body>
  <div class="shell">
    <div class="toolbar">
      <button class="primary" id="run">Run Eval</button>
      <button id="open">Open Trace</button>
      <button id="save">Save Trace</button>
      <label><input type="checkbox" id="withState" ${latest?.withState ? "checked" : ""}> with_state</label>
      <label><input type="checkbox" id="withLocals" ${latest?.withLocals ? "checked" : ""}> with_locals</label>
      <select id="examples">
        <option value="">Examples</option>
        ${examples.map((_, idx) => `<option value="${idx}">Example ${idx + 1}</option>`).join("")}
      </select>
      <span>${escapeHtml(this.state.activeFile ?? "No active file")}</span>
    </div>
    <div class="grid">
      <textarea id="trace">${escapeHtml(latest?.traceText ?? "# one step per line: x=1, y=0")}</textarea>
    </div>
    <div class="grid">
      <pre id="result">${escapeHtml(this.state.outputs?.eval_text ?? "Eval results will appear here.")}</pre>
    </div>
  </div>
  <script nonce="${scriptNonce}">
    const vscode = acquireVsCodeApi();
    const examples = ${JSON.stringify(examples)};
    document.getElementById("run").addEventListener("click", () => {
      vscode.postMessage({
        type: "runEval",
        traceText: document.getElementById("trace").value,
        withState: document.getElementById("withState").checked,
        withLocals: document.getElementById("withLocals").checked
      });
    });
    document.getElementById("examples").addEventListener("change", (event) => {
      const value = event.target.value;
      if (value !== "") {
        document.getElementById("trace").value = examples[Number(value)];
      }
    });
    document.getElementById("open").addEventListener("click", () => {
      vscode.postMessage({ type: "openTraceFile" });
    });
    document.getElementById("save").addEventListener("click", () => {
      vscode.postMessage({ type: "saveTraceFile", traceText: document.getElementById("trace").value });
    });
    window.addEventListener("message", (event) => {
      if (event.data?.type === "evalResult") {
        document.getElementById("result").textContent = event.data.result || "";
      } else if (event.data?.type === "traceOpened" && typeof event.data.contents === "string") {
        document.getElementById("trace").value = event.data.contents;
      }
    });
    window.addEventListener("message", (event) => {
      if (event.data?.type === "traceSaved" && event.data.path) {
        document.getElementById("result").textContent = "Trace saved to " + event.data.path;
      }
    });
  </script>
</body></html>`;
  }
}

export class DashboardPanel {
  private panel: vscode.WebviewPanel | null = null;
  private host: PanelHost | null = null;

  constructor(private readonly state: KairosState) {
    this.state.onDidChange(() => this.render());
  }

  setHost(host: PanelHost): void {
    this.host = host;
  }

  async show(): Promise<void> {
    const column = preferredViewColumn();
    if (!this.panel) {
      this.panel = vscode.window.createWebviewPanel("kairosDashboard", "Kairos Proof Dashboard", column, {
        enableScripts: true,
        retainContextWhenHidden: true
      });
      this.panel.onDidDispose(() => {
        this.panel = null;
      });
      this.panel.webview.onDidReceiveMessage(async (message) => {
        if (message?.type === "explainGoal") {
          await this.host?.openExplainFailurePanel(message.trace as ProofTrace);
        } else if (message?.type === "openDump") {
          await this.host?.openDumpPath(message.path as string | null);
        } else if (message?.type === "showRuns") {
          await this.host?.showRunHistory();
        }
      });
    }
    this.panel.reveal(column);
    this.render();
  }

  private render(): void {
    if (!this.panel) {
      return;
    }
    const summary = buildGoalSummary(this.state.goalsTree);
    const tracesByIndex = new Map((this.state.outputs?.proof_traces ?? []).map((trace) => [trace.goal_index, trace]));
    const flattened = this.state.goalsTree.flatMap((node) =>
      node.transitions.flatMap((transition) =>
        transition.items.map((item) => {
          const trace = tracesByIndex.get(item.idx);
          return {
            node: node.node,
            transition: transition.transition,
            entry: item,
            trace:
              trace ?? {
                goal_index: item.idx,
                stable_id: item.vcid ?? `goal-${item.idx + 1}`,
                goal_name: item.goal,
                status: item.status,
                solver_status: item.status,
                time_s: item.time_s,
                source: item.source,
                node: node.node,
                transition: transition.transition,
                obligation_kind: "",
                obligation_family: null,
                obligation_category: null,
                origin_ids: [],
                vc_id: item.vcid,
                source_span: null,
                obc_span: null,
                why_span: null,
                vc_span: null,
                smt_span: null,
                dump_path: item.dump_path,
                diagnostic: {
                  category: "",
                  summary: "",
                  detail: "",
                  probable_cause: null,
                  missing_elements: [],
                  goal_symbols: [],
                  analysis_method: "",
                  solver_detail: null,
                  native_unsat_core_solver: null,
                  native_unsat_core_hypothesis_ids: [],
                  native_counterexample_solver: null,
                  native_counterexample_model: null,
                  kairos_core_hypotheses: [],
                  why3_noise_hypotheses: [],
                  relevant_hypotheses: [],
                  context_hypotheses: [],
                  unused_hypotheses: [],
                  suggestions: [],
                  limitations: []
                }
              }
          };
        })
      )
    );
    const scriptNonce = nonce();
    this.panel.webview.html = `<!DOCTYPE html>
<html lang="en"><head>
  <meta charset="UTF-8">
  <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src ${this.panel.webview.cspSource} 'unsafe-inline'; script-src 'nonce-${scriptNonce}';">
  <style>
    :root { color-scheme: light; --bg: var(--vscode-editor-background, #fbfbf9); --fg: var(--vscode-editor-foreground, #202020); --muted: var(--vscode-descriptionForeground, #666); --border: var(--vscode-panel-border, #d9d9d9); --ok: #2e8b57; --warn: #b26a00; --bad: #b42318; }
    body { margin: 0; font-family: var(--vscode-font-family); background: var(--bg); color: var(--fg); }
    .shell { display: grid; grid-template-rows: auto auto 1fr; height: 100vh; }
    .top, .filters { display: flex; align-items: center; gap: 12px; padding: 12px; border-bottom: 1px solid var(--border); }
    .cards { display: flex; gap: 12px; }
    .card { border: 1px solid var(--border); border-radius: 12px; padding: 10px 14px; background: white; min-width: 100px; }
    table { width: 100%; border-collapse: collapse; }
    th, td { text-align: left; padding: 10px 12px; border-bottom: 1px solid var(--border); vertical-align: top; }
    tbody tr:hover { background: rgba(15,108,189,0.06); cursor: pointer; }
    .status-proved { color: var(--ok); font-weight: 600; }
    .status-failed { color: var(--bad); font-weight: 600; }
    .status-pending { color: var(--warn); font-weight: 600; }
    .scroll { overflow: auto; }
    button, select { font: inherit; border: 1px solid var(--border); border-radius: 8px; background: white; padding: 6px 10px; cursor: pointer; }
  </style>
</head>
<body>
  <div class="shell">
    <div class="top">
      <div class="cards">
        <div class="card"><div class="muted">Total</div><strong>${summary.total}</strong></div>
        <div class="card"><div class="muted">Proved</div><strong>${summary.proved}</strong></div>
        <div class="card"><div class="muted">Pending</div><strong>${summary.pending}</strong></div>
        <div class="card"><div class="muted">Failed</div><strong>${summary.failed}</strong></div>
      </div>
      <button id="showRuns">Run history</button>
    </div>
    <div class="filters">
      <label>Status
        <select id="statusFilter">
          <option value="all">all</option>
          <option value="proved">proved</option>
          <option value="pending">pending</option>
          <option value="failed">failed</option>
        </select>
      </label>
      <label><input type="checkbox" id="failuresOnly"> show failures only</label>
      <label><input type="checkbox" id="collapseProved"> collapse proved groups</label>
    </div>
    <div class="scroll">
      <table>
        <thead><tr><th>Node</th><th>Transition</th><th>Status</th><th>Kind</th><th>Time</th><th>Source</th><th>VC</th><th>SMT</th></tr></thead>
        <tbody id="rows"></tbody>
      </table>
    </div>
  </div>
  <script nonce="${scriptNonce}">
    const vscode = acquireVsCodeApi();
    const rows = ${JSON.stringify(flattened)};
    const tbody = document.getElementById("rows");
    function category(status) {
      const normalized = (status || "").toLowerCase();
      if (normalized === "valid" || normalized === "proved") return "proved";
      if (normalized === "pending") return "pending";
      return "failed";
    }
    function render() {
      const statusFilter = document.getElementById("statusFilter").value;
      const failuresOnly = document.getElementById("failuresOnly").checked;
      const collapseProved = document.getElementById("collapseProved").checked;
      const byGroup = new Map();
      rows.forEach((row) => {
        const key = row.node + "::" + row.transition;
        const bucket = byGroup.get(key) || [];
        bucket.push(row);
        byGroup.set(key, bucket);
      });
      const html = [];
      byGroup.forEach((group) => {
        const allProved = group.every((row) => category(row.trace.status) === "proved");
        if (collapseProved && allProved) return;
        group.forEach((row) => {
          const cat = category(row.trace.status);
          if (failuresOnly && cat !== "failed") return;
          if (statusFilter !== "all" && cat !== statusFilter) return;
          html.push(\`<tr data-trace="\${encodeURIComponent(JSON.stringify(row.trace))}">
            <td>\${row.node}</td>
            <td>\${row.transition}</td>
            <td class="status-\${cat}">\${row.trace.status}</td>
            <td>\${row.trace.obligation_kind || row.entry.goal || ""}</td>
            <td>\${(row.trace.time_s || row.entry.time_s) ? (row.trace.time_s || row.entry.time_s).toFixed(3) + "s" : ""}</td>
            <td>\${row.trace.source || row.entry.source || ""}</td>
            <td>\${row.trace.vc_id || row.entry.vcid || row.trace.stable_id || ""}</td>
            <td>\${(row.trace.dump_path || row.entry.dump_path) ? "available" : ""}</td>
          </tr>\`);
        });
      });
      tbody.innerHTML = html.join("");
      tbody.querySelectorAll("tr").forEach((tr) => {
        tr.addEventListener("click", () => {
          const trace = JSON.parse(decodeURIComponent(tr.dataset.trace));
          vscode.postMessage({ type: "explainGoal", trace });
        });
      });
    }
    document.getElementById("statusFilter").addEventListener("change", render);
    document.getElementById("failuresOnly").addEventListener("change", render);
    document.getElementById("collapseProved").addEventListener("change", render);
    document.getElementById("showRuns").addEventListener("click", () => vscode.postMessage({ type: "showRuns" }));
    render();
  </script>
</body></html>`;
  }
}

export class ExplainFailurePanel {
  private panel: vscode.WebviewPanel | null = null;
  private host: PanelHost | null = null;

  constructor(private readonly state: KairosState) {
    this.state.onDidChange(() => this.render());
  }

  setHost(host: PanelHost): void {
    this.host = host;
  }

  async show(trace?: ProofTrace | null): Promise<void> {
    const column = preferredViewColumn();
    if (trace) {
      this.state.setActiveProofTrace(trace);
    }
    if (!this.panel) {
      this.panel = vscode.window.createWebviewPanel("kairosExplainFailure", "Kairos Explain Failure", column, {
        enableScripts: true,
        retainContextWhenHidden: true
      });
      this.panel.onDidDispose(() => {
        this.panel = null;
      });
      this.panel.webview.onDidReceiveMessage(async (message) => {
        const active = this.state.activeProofTrace;
        if (message?.type === "openSource") {
          await this.host?.openSourceLocation(active?.source_span ?? null);
        } else if (message?.type === "openArtifact") {
          const artifact = String(message.artifact ?? "") as ArtifactId;
          const span =
            artifact === "obc"
              ? active?.obc_span ?? null
              : artifact === "why"
                ? active?.why_span ?? null
                : artifact === "vc"
                  ? active?.vc_span ?? null
                  : active?.smt_span ?? null;
          await this.host?.openArtifactSpan(artifact, span);
        } else if (message?.type === "openDump") {
          await this.host?.openDumpPath(active?.dump_path ?? null);
        } else if (message?.type === "openDashboard") {
          await this.host?.openDashboardPanel();
        } else if (message?.type === "rerunFocused") {
          if (active) {
            await this.host?.rerunFocusedDiagnosis(active);
          }
        }
      });
    }
    this.panel.reveal(column);
    this.render();
  }

  private render(): void {
    if (!this.panel) {
      return;
    }
    const trace = this.state.activeProofTrace;
    const scriptNonce = nonce();
    if (!trace) {
      this.panel.webview.html = `<!DOCTYPE html><html lang="en"><body style="font-family:var(--vscode-font-family);padding:24px;">Select a failed goal from the dashboard or explorer to open an explanation.</body></html>`;
      return;
    }
    const chips = [
      trace.obligation_kind,
      trace.obligation_family,
      trace.obligation_category,
      trace.node,
      trace.transition
    ].filter(Boolean);
    const chain = [
      `Source ${trace.source_span ? "linked" : "unavailable"}`,
      `OBC ${trace.obc_span ? "linked" : "unavailable"}`,
      `Why ${trace.why_span ? "linked" : "unavailable"}`,
      `VC ${trace.vc_span ? "linked" : "unavailable"}`,
      `SMT ${trace.smt_span ? "linked" : "unavailable"}`
    ];
    this.panel.webview.html = `<!DOCTYPE html>
<html lang="en"><head>
  <meta charset="UTF-8">
  <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src ${this.panel.webview.cspSource} 'unsafe-inline'; script-src 'nonce-${scriptNonce}';">
  <style>
    :root { color-scheme: light; --bg: var(--vscode-editor-background, #fbfbf9); --panel: color-mix(in srgb, var(--bg) 95%, white 5%); --fg: var(--vscode-editor-foreground, #202020); --muted: var(--vscode-descriptionForeground, #666); --border: var(--vscode-panel-border, #d9d9d9); --accent: var(--vscode-focusBorder, #0f6cbd); --bad: #b42318; }
    body { margin: 0; font-family: var(--vscode-font-family); background: var(--bg); color: var(--fg); }
    .shell { display: grid; grid-template-rows: auto auto 1fr; min-height: 100vh; }
    .hero, .toolbar { padding: 16px 20px; border-bottom: 1px solid var(--border); background: var(--panel); }
    .hero h1 { margin: 0 0 8px; font-size: 22px; }
    .summary { color: var(--bad); font-weight: 700; }
    .toolbar, .buttons, .chips, .chain { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; }
    .content { display: grid; grid-template-columns: minmax(0, 1.2fr) minmax(320px, 0.8fr); min-height: 0; }
    .main, .side { padding: 20px; min-height: 0; overflow: auto; }
    .side { border-left: 1px solid var(--border); background: color-mix(in srgb, var(--bg) 96%, white 4%); }
    .card { border: 1px solid var(--border); border-radius: 14px; background: white; padding: 14px 16px; margin-bottom: 14px; }
    .label { font-size: 11px; text-transform: uppercase; letter-spacing: 0.08em; color: var(--muted); margin-bottom: 8px; }
    .chip, .chainItem { border: 1px solid var(--border); background: white; border-radius: 999px; padding: 6px 10px; font-size: 12px; }
    button { font: inherit; border: 1px solid var(--border); border-radius: 10px; background: white; padding: 7px 11px; cursor: pointer; }
    button.primary { background: var(--accent); color: white; border-color: var(--accent); }
    ul { margin: 0; padding-left: 18px; }
    pre { margin: 0; white-space: pre-wrap; word-break: break-word; }
  </style>
</head>
<body>
  <div class="shell">
    <div class="hero">
      <h1>Explain Failure</h1>
      <div class="summary">${escapeHtml(trace.diagnostic.summary)}</div>
      <div style="margin-top:8px;">${escapeHtml(trace.diagnostic.detail)}</div>
    </div>
    <div class="toolbar">
      <div class="buttons">
        <button class="primary" id="openSource">Source</button>
        <button data-artifact="obc">OBC</button>
        <button data-artifact="why">Why</button>
        <button data-artifact="vc">VC</button>
        <button data-artifact="smt">SMT</button>
        <button id="openDump">Dump</button>
        <button id="rerunFocused">Focused Diagnosis</button>
        <button id="openDashboard">Dashboard</button>
      </div>
      <div class="chips">${chips.map((chip) => `<span class="chip">${escapeHtml(String(chip))}</span>`).join("")}</div>
    </div>
    <div class="content">
      <div class="main">
        <div class="card">
          <div class="label">Human Summary</div>
          <pre>${escapeHtml(trace.diagnostic.summary)}</pre>
        </div>
        <div class="card">
          <div class="label">Probable Cause</div>
          <pre>${escapeHtml(trace.diagnostic.probable_cause ?? "No stronger backend-backed cause is available.")}</pre>
        </div>
        <div class="card">
          <div class="label">Solver Detail</div>
          <pre>${escapeHtml(trace.diagnostic.solver_detail ?? "No additional solver detail was recovered.")}</pre>
        </div>
        <div class="card">
          <div class="label">Minimal Relevant Context</div>
          <ul>${trace.diagnostic.relevant_hypotheses.map((item) => `<li>${escapeHtml(item)}</li>`).join("") || "<li>No focused hypothesis slice available.</li>"}</ul>
        </div>
        <div class="card">
          <div class="label">Investigation Suggestions</div>
          <ul>${trace.diagnostic.suggestions.map((item) => `<li>${escapeHtml(item)}</li>`).join("")}</ul>
        </div>
      </div>
      <div class="side">
        <div class="card">
          <div class="label">Trace Chain</div>
          <div class="chain">${chain.map((item) => `<span class="chainItem">${escapeHtml(item)}</span>`).join("")}</div>
        </div>
        <div class="card">
          <div class="label">Kairos Core</div>
          <ul>${trace.diagnostic.kairos_core_hypotheses.map((item) => `<li>${escapeHtml(item)}</li>`).join("") || "<li>No instrumented Kairos hypothesis was isolated for this failure.</li>"}</ul>
        </div>
        <div class="card">
          <div class="label">Native Unsat Core</div>
          <pre>${escapeHtml(
            trace.diagnostic.native_unsat_core_solver
              ? `${trace.diagnostic.native_unsat_core_solver}: [${trace.diagnostic.native_unsat_core_hypothesis_ids.join(", ")}]`
              : "No native solver unsat core was recovered for this goal."
          )}</pre>
        </div>
        <div class="card">
          <div class="label">Native Counterexample</div>
          <pre>${escapeHtml(
            trace.diagnostic.native_counterexample_solver && trace.diagnostic.native_counterexample_model
              ? `${trace.diagnostic.native_counterexample_solver}\n${trace.diagnostic.native_counterexample_model}`
              : "No native counterexample/model was recovered for this goal."
          )}</pre>
        </div>
        <div class="card">
          <div class="label">Broader Context</div>
          <ul>${trace.diagnostic.context_hypotheses.map((item) => `<li>${escapeHtml(item)}</li>`).join("") || "<li>No context slice available.</li>"}</ul>
        </div>
        <div class="card">
          <div class="label">Goal Symbols</div>
          <ul>${trace.diagnostic.goal_symbols.map((item) => `<li>${escapeHtml(item)}</li>`).join("") || "<li>No goal symbol analysis available.</li>"}</ul>
        </div>
        <div class="card">
          <div class="label">Why3 Auxiliary Context</div>
          <ul>${trace.diagnostic.why3_noise_hypotheses.map((item) => `<li>${escapeHtml(item)}</li>`).join("") || "<li>No auxiliary Why3 hypothesis was surfaced separately.</li>"}</ul>
        </div>
        <div class="card">
          <div class="label">Missing Or Weak Elements</div>
          <ul>${trace.diagnostic.missing_elements.map((item) => `<li>${escapeHtml(item)}</li>`).join("") || "<li>No specific missing element inferred from backend data.</li>"}</ul>
        </div>
        <div class="card">
          <div class="label">Deprioritized Hypotheses</div>
          <ul>${trace.diagnostic.unused_hypotheses.map((item) => `<li>${escapeHtml(item)}</li>`).join("") || "<li>No clearly irrelevant hypothesis was isolated.</li>"}</ul>
        </div>
        <div class="card">
          <div class="label">Analysis Method</div>
          <pre>${escapeHtml(trace.diagnostic.analysis_method)}</pre>
        </div>
        <div class="card">
          <div class="label">Limits</div>
          <ul>${trace.diagnostic.limitations.map((item) => `<li>${escapeHtml(item)}</li>`).join("")}</ul>
        </div>
      </div>
    </div>
  </div>
  <script nonce="${scriptNonce}">
    const vscode = acquireVsCodeApi();
    document.getElementById("openSource").addEventListener("click", () => vscode.postMessage({ type: "openSource" }));
    document.querySelectorAll("[data-artifact]").forEach((button) => button.addEventListener("click", () => {
      vscode.postMessage({ type: "openArtifact", artifact: button.dataset.artifact });
    }));
    document.getElementById("openDump").addEventListener("click", () => vscode.postMessage({ type: "openDump" }));
    document.getElementById("rerunFocused").addEventListener("click", () => vscode.postMessage({ type: "rerunFocused" }));
    document.getElementById("openDashboard").addEventListener("click", () => vscode.postMessage({ type: "openDashboard" }));
  </script>
</body></html>`;
  }
}

export class ArtifactsPanel {
  private panel: vscode.WebviewPanel | null = null;
  private host: PanelHost | null = null;

  constructor(private readonly state: KairosState) {
    this.state.onDidChange(() => this.render());
  }

  setHost(host: PanelHost): void {
    this.host = host;
  }

  async show(): Promise<void> {
    const column = preferredViewColumn();
    if (!this.panel) {
      this.panel = vscode.window.createWebviewPanel("kairosArtifacts", "Kairos Artifacts", column, {
        enableScripts: true,
        retainContextWhenHidden: true
      });
      this.panel.onDidDispose(() => {
        this.panel = null;
      });
      this.panel.webview.onDidReceiveMessage(async (message) => {
        if (message?.type === "openArtifact") {
          await this.host?.openArtifact(message.kind as ArtifactId);
        } else if (message?.type === "openAutomata") {
          await this.host?.openGraphPanel();
        } else if (message?.type === "diffObc") {
          await this.host?.diffCurrentObcWithPrevious();
        } else if (message?.type === "openPipeline") {
          await this.host?.openPipelinePanel();
        } else if (message?.type === "exportReport") {
          await this.host?.exportHtmlReport();
        }
      });
    }
    this.panel.reveal(column);
    this.render();
  }

  private render(): void {
    if (!this.panel) {
      return;
    }
    const previews: Record<ArtifactId, string> = {
      obc: this.state.outputs?.obc_text ?? "",
      why: this.state.outputs?.why_text ?? "",
      vc: this.state.outputs?.vc_text ?? "",
      smt: this.state.outputs?.smt_text ?? "",
      labels: this.state.outputs?.labels_text ?? this.state.automata?.labels_text ?? "",
      program: this.state.outputs?.program_automaton_text ?? this.state.automata?.program_automaton_text ?? "",
      assume: this.state.outputs?.assume_automaton_text ?? this.state.automata?.assume_automaton_text ?? "",
      guarantee: this.state.outputs?.guarantee_automaton_text ?? this.state.automata?.guarantee_automaton_text ?? "",
      product: this.state.outputs?.product_text ?? this.state.automata?.product_text ?? "",
      obligations_map: this.state.outputs?.obligations_map_text ?? this.state.automata?.obligations_map_text ?? "",
      prune_reasons: this.state.outputs?.prune_reasons_text ?? this.state.automata?.prune_reasons_text ?? "",
      eval: this.state.outputs?.eval_text ?? ""
    };
    const scriptNonce = nonce();
    this.panel.webview.html = `<!DOCTYPE html>
<html lang="en"><head>
  <meta charset="UTF-8">
  <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src ${this.panel.webview.cspSource} 'unsafe-inline'; script-src 'nonce-${scriptNonce}';">
  <style>
    :root { color-scheme: light; --bg: var(--vscode-editor-background, #fbfbf9); --fg: var(--vscode-editor-foreground, #202020); --border: var(--vscode-panel-border, #d9d9d9); --accent: var(--vscode-focusBorder, #0f6cbd); }
    body { margin: 0; font-family: var(--vscode-font-family); background: var(--bg); color: var(--fg); }
    .shell { display: grid; grid-template-columns: 280px 1fr; height: 100vh; }
    .list { border-right: 1px solid var(--border); padding: 12px; overflow: auto; }
    .content { padding: 12px; overflow: auto; }
    .item { border: 1px solid var(--border); border-radius: 10px; padding: 10px; margin-bottom: 8px; background: white; cursor: pointer; }
    .item.active { border-color: var(--accent); box-shadow: 0 0 0 1px var(--accent) inset; }
    pre { white-space: pre-wrap; word-break: break-word; border: 1px solid var(--border); border-radius: 12px; background: white; padding: 12px; }
    .actions { display: flex; gap: 8px; margin-bottom: 10px; }
    button { font: inherit; border: 1px solid var(--border); border-radius: 8px; background: white; padding: 6px 10px; cursor: pointer; }
  </style>
</head>
<body>
  <div class="shell">
    <div class="list" id="items"></div>
    <div class="content">
      <div class="actions">
        <button id="open">Open document</button>
        <button id="automata">Automata studio</button>
        <button id="diff">Diff OBC vs previous</button>
        <button id="pipeline">Pipeline</button>
        <button id="report">Export HTML report</button>
      </div>
      <h2 id="title"></h2>
      <p id="description"></p>
      <pre id="preview"></pre>
    </div>
  </div>
  <script nonce="${scriptNonce}">
    const vscode = acquireVsCodeApi();
    const artifacts = ${JSON.stringify(ARTIFACTS)};
    const previews = ${JSON.stringify(previews)};
    const state = vscode.getState() || { active: "${this.state.currentArtifact}" };
    function render() {
      const active = state.active;
      document.getElementById("items").innerHTML = artifacts.map((artifact) =>
        \`<div class="item \${artifact.id === active ? "active" : ""}" data-id="\${artifact.id}">
          <strong>\${artifact.label}</strong><br><span>\${artifact.description}</span>
        </div>\`
      ).join("");
      const current = artifacts.find((artifact) => artifact.id === active) || artifacts[0];
      document.getElementById("title").textContent = current.label;
      document.getElementById("description").textContent = current.description;
      document.getElementById("preview").textContent = (previews[active] || "No artifact available.").slice(0, 8000);
      document.querySelectorAll(".item").forEach((item) => item.addEventListener("click", () => {
        state.active = item.dataset.id;
        vscode.setState(state);
        render();
      }));
    }
    document.getElementById("open").addEventListener("click", () => vscode.postMessage({ type: "openArtifact", kind: state.active }));
    document.getElementById("automata").addEventListener("click", () => vscode.postMessage({ type: "openAutomata" }));
    document.getElementById("diff").addEventListener("click", () => vscode.postMessage({ type: "diffObc" }));
    document.getElementById("pipeline").addEventListener("click", () => vscode.postMessage({ type: "openPipeline" }));
    document.getElementById("report").addEventListener("click", () => vscode.postMessage({ type: "exportReport" }));
    render();
  </script>
</body></html>`;
  }
}

export class PipelinePanel {
  private panel: vscode.WebviewPanel | null = null;
  private host: PanelHost | null = null;

  constructor(private readonly state: KairosState) {
    this.state.onDidChange(() => this.render());
  }

  setHost(host: PanelHost): void {
    this.host = host;
  }

  async show(): Promise<void> {
    const column = preferredViewColumn();
    if (!this.panel) {
      this.panel = vscode.window.createWebviewPanel("kairosPipeline", "Kairos Pipeline", column, {
        enableScripts: true,
        retainContextWhenHidden: true
      });
      this.panel.onDidDispose(() => {
        this.panel = null;
      });
      this.panel.webview.onDidReceiveMessage(async (message) => {
        if (message?.type === "openAutomata") {
          await this.host?.openGraphPanel();
        } else if (message?.type === "exportReport") {
          await this.host?.exportHtmlReport();
        } else if (message?.type === "openCompare") {
          await this.host?.openComparePanel();
        }
      });
    }
    this.panel.reveal(column);
    this.render();
  }

  private render(): void {
    if (!this.panel) {
      return;
    }
    const stageMeta = this.state.outputs?.stage_meta ?? this.state.automata?.stage_meta ?? [];
    const stages = [
      { label: "Source", active: !!this.state.activeFile, detail: this.state.activeFile ?? "No file" },
      { label: "Program", active: !!(this.state.outputs?.program_png || this.state.automata?.program_png), detail: "Program automaton" },
      { label: "Assume", active: !!(this.state.outputs?.assume_automaton_png || this.state.automata?.assume_automaton_png), detail: "Assumption automaton" },
      { label: "Guarantee", active: !!(this.state.outputs?.guarantee_automaton_png || this.state.automata?.guarantee_automaton_png), detail: "Guarantee automaton" },
      { label: "Product", active: !!(this.state.outputs?.product_png || this.state.automata?.product_png), detail: "Product automaton" },
      { label: "OBC+", active: !!this.state.outputs?.obc_text, detail: "Abstract program" },
      { label: "Why", active: !!this.state.outputs?.why_text, detail: "Why3 translation" },
      { label: "Goals", active: this.state.goalsTree.length > 0, detail: `${buildGoalSummary(this.state.goalsTree).total} goals` }
    ];
    const scriptNonce = nonce();
    this.panel.webview.html = `<!DOCTYPE html>
<html lang="en"><head>
  <meta charset="UTF-8">
  <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src ${this.panel.webview.cspSource} 'unsafe-inline'; script-src 'nonce-${scriptNonce}';">
  <style>
    :root { color-scheme: light; --bg: var(--vscode-editor-background, #fbfbf9); --fg: var(--vscode-editor-foreground, #202020); --border: var(--vscode-panel-border, #d9d9d9); --accent: var(--vscode-focusBorder, #0f6cbd); --muted: var(--vscode-descriptionForeground, #666); }
    body { margin: 0; background: var(--bg); color: var(--fg); font-family: var(--vscode-font-family); }
    .shell { padding: 18px; display: grid; gap: 18px; }
    .pipeline { display: grid; grid-template-columns: repeat(8, minmax(100px, 1fr)); gap: 10px; }
    .stage { border: 1px solid var(--border); border-radius: 14px; padding: 12px; background: white; min-height: 80px; }
    .stage.active { border-color: var(--accent); box-shadow: 0 0 0 1px var(--accent) inset; background: #f8fbff; }
    .arrow { text-align: center; color: var(--muted); }
    pre { white-space: pre-wrap; background: white; border: 1px solid var(--border); border-radius: 12px; padding: 12px; }
    button { font: inherit; border: 1px solid var(--border); border-radius: 8px; background: white; padding: 6px 10px; cursor: pointer; }
    .toolbar { display: flex; gap: 8px; }
    .muted { color: var(--muted); }
  </style>
</head><body>
  <div class="shell">
    <div class="toolbar">
      <button id="automata">Open automata studio</button>
      <button id="compare">Compare current vs previous</button>
      <button id="report">Export HTML report</button>
    </div>
    <div class="pipeline">
      ${stages
        .map(
          (stage) =>
            `<div class="stage ${stage.active ? "active" : ""}"><strong>${stage.label}</strong><div class="muted">${escapeHtml(
              stage.detail
            )}</div></div>`
        )
        .join("")}
    </div>
    <div>
      <h3>Stage metadata</h3>
      <pre>${escapeHtml(
        stageMeta
          .map(([stage, entries]) => `${stage}\n${entries.map(([k, v]) => `  - ${k}: ${v}`).join("\n")}`)
          .join("\n\n")
      )}</pre>
    </div>
  </div>
  <script nonce="${scriptNonce}">
    const vscode = acquireVsCodeApi();
    document.getElementById("automata").addEventListener("click", () => vscode.postMessage({ type: "openAutomata" }));
    document.getElementById("compare").addEventListener("click", () => vscode.postMessage({ type: "openCompare" }));
    document.getElementById("report").addEventListener("click", () => vscode.postMessage({ type: "exportReport" }));
  </script>
</body></html>`;
  }
}

export class ComparePanel {
  private panel: vscode.WebviewPanel | null = null;
  private host: PanelHost | null = null;

  constructor(private readonly state: KairosState) {
    this.state.onDidChange(() => void this.render());
  }

  setHost(host: PanelHost): void {
    this.host = host;
  }

  async show(): Promise<void> {
    const column = preferredViewColumn();
    if (!this.panel) {
      this.panel = vscode.window.createWebviewPanel("kairosCompare", "Kairos Automata Compare", column, {
        enableScripts: true,
        retainContextWhenHidden: true,
        localResourceRoots: []
      });
      this.panel.onDidDispose(() => {
        this.panel = null;
      });
    }
    this.panel.reveal(column);
    await this.render();
  }

  private render(): void {
    if (!this.panel) {
      return;
    }
    const a = this.state.automata ?? this.state.outputs;
    const currentPng = pngPathToDataUri(a?.product_png);
    const current = currentPng
      ? `<img alt="Current product automaton" src="${currentPng}" />`
      : "<div>No current product automaton.</div>";
    const previousPng = pngPathToDataUri(this.state.previousOutputs?.product_png);
    const previous =
      previousPng !== ""
        ? `<img alt="Previous product automaton" src="${previousPng}" />`
        : "<div>No previous product automaton.</div>";
    const scriptNonce = nonce();
    this.panel.webview.html = `<!DOCTYPE html>
<html lang="en"><head>
  <meta charset="UTF-8">
  <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src ${this.panel.webview.cspSource} 'unsafe-inline'; script-src 'nonce-${scriptNonce}';">
  <style>
    :root { color-scheme: light; --bg: var(--vscode-editor-background, #fbfbf9); --fg: var(--vscode-editor-foreground, #202020); --border: var(--vscode-panel-border, #d9d9d9); }
    body { margin: 0; background: var(--bg); color: var(--fg); font-family: var(--vscode-font-family); }
    .grid { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; padding: 12px; }
    .pane { border: 1px solid var(--border); border-radius: 12px; padding: 12px; background: white; overflow: auto; min-height: 90vh; }
    img { display:block; max-width:none; }
  </style>
</head><body>
  <div class="grid">
    <div class="pane"><h3>Current Product</h3>${current}</div>
    <div class="pane"><h3>Previous Product</h3>${previous}</div>
  </div>
</body></html>`;
  }
}

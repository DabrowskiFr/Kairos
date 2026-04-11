import { execSync, execFileSync } from "child_process";
import * as fs from "fs";
import * as os from "os";
import * as path from "path";
import * as vscode from "vscode";
import { LanguageClient, LanguageClientOptions, ServerOptions } from "vscode-languageclient/node";
import { KairosDocProvider, kairosDocUri } from "./documents";
import { buildGoalsTreeFinalFallback, buildGoalsTreeFromEntries, buildGoalsTreePendingFallback } from "./goals";
import {
  ArtifactsPanel,
  AutomataPanel,
  ComparePanel,
  DashboardPanel,
  ExplainFailurePanel,
  EvalPanel,
  IrPanel,
  IrNodeGraphs,
  PanelHost,
  PipelinePanel
} from "./panels";
import {
  ArtifactsProvider,
  GoalsProvider,
  KairosCodeLensProvider,
  OutlineProvider,
  RunsProvider
} from "./providers";
import { KairosState } from "./state";
import {
  ArtifactId,
  AutomataOutputs,
  GoalDoneNotification,
  GoalDonePayload,
  GoalTreeEntry,
  GoalTreeNode,
  GoalsReadyNotification,
  GraphId,
  Loc,
  OutlinePayload,
  Outputs,
  OutputsReadyNotification,
  PanelId,
  ProofTrace,
  SessionSnapshot
} from "./types";

let client: LanguageClient | null = null;
let clientStartPromise: Promise<void> | null = null;

function resolveServerCommand(serverPath: string): string {
  if (path.isAbsolute(serverPath) && fs.existsSync(serverPath)) {
    return serverPath;
  }
  return serverPath;
}

function injectOpamEnv(env: NodeJS.ProcessEnv): void {
  if (env.OPAM_SWITCH_PREFIX) {
    return; // already set (VS Code launched from a terminal with opam env)
  }
  // Try common opam binary locations on macOS/Linux
  const home = env.HOME ?? "";
  const rawCandidates: string[] = [
    "/opt/homebrew/bin/opam",
    "/usr/local/bin/opam",
    "/usr/bin/opam",
    ...(home ? [`${home}/.local/bin/opam`] : [])
  ];
  const candidates = rawCandidates.filter((p) => fs.existsSync(p));
  const opamBin = candidates[0];
  if (!opamBin) {
    return;
  }
  try {
    const raw = execSync(`"${opamBin}" env`, { encoding: "utf8", timeout: 8000 });
    for (const line of raw.split("\n")) {
      // Parse lines like: VARNAME='value'; export VARNAME;
      const m = line.match(/^([A-Z_][A-Z_0-9]*)='([^']*)'; export/);
      if (m) {
        env[m[1]] = m[2];
      }
    }
  } catch (_) {
    // ignore; provers may not be available but basic LSP features still work
  }
}

function getRunSettings() {
  const cfg = vscode.workspace.getConfiguration("kairos");
  return {
    engine: cfg.get<string>("run.engine", "v2"),
    timeoutS: cfg.get<number>("run.timeoutS", 5),
    maxProofGoals: cfg.get<number | undefined>("run.maxProofGoals"),
    wpOnly: cfg.get<boolean>("run.wpOnly", false),
    smokeTests: cfg.get<boolean>("run.smokeTests", false),
    prefixFields: cfg.get<boolean>("run.prefixFields", false),
    generateVcText: cfg.get<boolean>("run.generateVcText", true),
    generateSmtText: cfg.get<boolean>("run.generateSmtText", true),
    generateMonitorText: cfg.get<boolean>("run.generateMonitorText", true),
    generateDotPng: cfg.get<boolean>("run.generateDotPng", false),
    openPanelsAfterProve: cfg.get<boolean>("ui.openDashboardAfterProve", true),
    restoreSession: cfg.get<boolean>("ui.restoreSession", true)
  };
}

function stripDotFieldsFromOutputs(outputs: Outputs): Outputs {
  return {
    ...outputs,
    dot_text: "",
    program_dot: "",
    guarantee_automaton_dot: "",
    assume_automaton_dot: "",
    product_dot: ""
  };
}

function stripDotFieldsFromAutomata(outputs: AutomataOutputs): AutomataOutputs {
  return {
    ...outputs,
    dot_text: "",
    program_dot: "",
    guarantee_automaton_dot: "",
    assume_automaton_dot: "",
    product_dot: ""
  };
}

function writeKirFiles(
  inputFile: string,
  productText: string,
  historicalClausesText: string,
  eliminatedClausesText: string
): void {
  try {
    const dir = path.dirname(inputFile);
    const base = path.basename(inputFile, path.extname(inputFile));
    fs.writeFileSync(path.join(dir, `${base}.kir`), productText, "utf8");
    fs.writeFileSync(path.join(dir, `${base}.hist.kir`), historicalClausesText, "utf8");
    fs.writeFileSync(path.join(dir, `${base}.plain.kir`), eliminatedClausesText, "utf8");
  } catch (err) {
    // Non-fatal: log but don't interrupt the run
    console.error("[Kairos] Failed to write .kir files:", err);
  }
}

function preferredEditorColumn(): vscode.ViewColumn {
  return (
    vscode.window.activeTextEditor?.viewColumn ??
    vscode.window.visibleTextEditors[0]?.viewColumn ??
    vscode.ViewColumn.One
  );
}

async function openKairosDoc(kind: ArtifactId): Promise<void> {
  const document = await vscode.workspace.openTextDocument(kairosDocUri(kind));
  await vscode.window.showTextDocument(document, { preview: true, viewColumn: preferredEditorColumn() });
}

async function revealOffsetSpan(kind: ArtifactId, startOffset: number, endOffset: number): Promise<void> {
  const document = await vscode.workspace.openTextDocument(kairosDocUri(kind));
  const editor = await vscode.window.showTextDocument(document, {
    preview: true,
    viewColumn: preferredEditorColumn()
  });
  const start = document.positionAt(startOffset);
  const end = document.positionAt(endOffset);
  const range = new vscode.Range(start, end);
  editor.selection = new vscode.Selection(start, end);
  editor.revealRange(range, vscode.TextEditorRevealType.InCenter);
}

function formatStageSummary(outputs: Outputs | null): string {
  if (!outputs) {
    return "";
  }
  const pieces: string[] = [];
  if (outputs.automata_generation_time_s > 0) {
    pieces.push(`automata ${outputs.automata_generation_time_s.toFixed(2)}s`);
  }
  if (outputs.obcplus_time_s > 0) {
    pieces.push(`obc ${outputs.obcplus_time_s.toFixed(2)}s`);
  }
  if (outputs.why_time_s > 0) {
    pieces.push(`why ${outputs.why_time_s.toFixed(2)}s`);
  }
  if (outputs.why3_prep_time_s > 0) {
    pieces.push(`prep ${outputs.why3_prep_time_s.toFixed(2)}s`);
  }
  if (outputs.automata_build_time_s > 0) {
    pieces.push(`prove ${outputs.automata_build_time_s.toFixed(2)}s`);
  }
  return pieces.join(" | ");
}

function statusLabel(state: KairosState): string {
  const elapsed =
    state.startedAtMs !== null ? `${((Date.now() - state.startedAtMs) / 1000).toFixed(1)}s` : null;
  const prefix = `Kairos ${state.runPhase}`;
  return [prefix, state.statusMessage, state.stageSummary, elapsed].filter(Boolean).join(" | ");
}

function defaultSessionSnapshot(): SessionSnapshot {
  return {
    activeFile: null,
    currentArtifact: "obc",
    runHistory: [],
    evalHistory: [],
    openPanels: []
  };
}

function escapeHtmlForReport(text: string): string {
  return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

async function copyGraphPngToCache(
  context: vscode.ExtensionContext,
  graphId: GraphId,
  sourcePath: string | null | undefined
): Promise<vscode.Uri | null> {
  if (!sourcePath || !fs.existsSync(sourcePath)) {
    return null;
  }
  await vscode.workspace.fs.createDirectory(context.globalStorageUri);
  const automataDir = vscode.Uri.joinPath(context.globalStorageUri, "automata");
  await vscode.workspace.fs.createDirectory(automataDir);
  const target = vscode.Uri.joinPath(automataDir, `${graphId}.png`);
  await vscode.workspace.fs.copy(vscode.Uri.file(sourcePath), target, { overwrite: true });
  return target;
}

export async function activate(context: vscode.ExtensionContext): Promise<void> {
  const lspConfig = vscode.workspace.getConfiguration("kairos.lsp");
  const serverPath = lspConfig.get<string>("serverPath", "kairos-lsp");
  const serverArgs = lspConfig.get<string[]>("serverArgs", []);
  const traceEnabled = lspConfig.get<boolean>("trace", false);
  const traceFile = lspConfig.get<string>("traceFile", "");

  const env = { ...process.env };
  injectOpamEnv(env);
  if (traceEnabled) {
    env.KAIROS_LSP_TRACE = "1";
    if (traceFile) {
      env.KAIROS_LSP_TRACE_FILE = traceFile;
    }
  }

  const output = vscode.window.createOutputChannel("Kairos");
  const statusBar = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 50);
  const statusCommand = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 49);
  statusCommand.command = "kairos.showRunHistory";
  statusCommand.text = "$(history) Kairos runs";
  statusCommand.tooltip = "Show local Kairos run history";
  statusCommand.show();
  statusBar.show();
  context.subscriptions.push(output, statusBar, statusCommand);

  const serverOptions: ServerOptions = {
    command: resolveServerCommand(serverPath),
    args: serverArgs,
    options: { env }
  };

  const clientOptions: LanguageClientOptions = {
    documentSelector: [{ scheme: "file", language: "kairos" }],
    outputChannel: output
  };

  client = new LanguageClient("kairosLsp", "Kairos LSP", serverOptions, clientOptions);

  const state = new KairosState();
  const session = context.workspaceState.get<SessionSnapshot>("kairos.session", defaultSessionSnapshot());
  state.activeFile = session.activeFile;
  state.currentArtifact = session.currentArtifact;
  state.runHistory = session.runHistory;
  state.evalHistory = session.evalHistory;
  const docProvider = new KairosDocProvider(state);
  const outlineProvider = new OutlineProvider(state);
  const goalsProvider = new GoalsProvider(state);
  const artifactsProvider = new ArtifactsProvider(state);
  const runsProvider = new RunsProvider(state);
  const codeLensProvider = new KairosCodeLensProvider(state);

  const updateStatusBar = () => {
    statusBar.text = statusLabel(state);
    statusBar.tooltip = state.activeFile ?? "No active file";
    if (state.runPhase === "failed") {
      statusBar.backgroundColor = new vscode.ThemeColor("statusBarItem.errorBackground");
    } else if (state.runPhase === "proving" || state.runPhase === "building" || state.runPhase === "eval") {
      statusBar.backgroundColor = new vscode.ThemeColor("statusBarItem.warningBackground");
    } else {
      statusBar.backgroundColor = undefined;
    }
  };
  state.onDidChange(updateStatusBar);
  updateStatusBar();
  const statusTicker = setInterval(() => {
    if (state.startedAtMs !== null) {
      updateStatusBar();
    }
  }, 1000);
  context.subscriptions.push({ dispose: () => clearInterval(statusTicker) });

  context.subscriptions.push(
    vscode.workspace.registerTextDocumentContentProvider("kairos", docProvider),
    vscode.window.registerTreeDataProvider("kairosOutline", outlineProvider),
    vscode.window.registerTreeDataProvider("kairosGoals", goalsProvider),
    vscode.window.registerTreeDataProvider("kairosArtifacts", artifactsProvider),
    vscode.window.registerTreeDataProvider("kairosRuns", runsProvider),
    vscode.languages.registerCodeLensProvider({ language: "kairos" }, codeLensProvider)
  );

  const automataPanel = new AutomataPanel(state);
  const evalPanel = new EvalPanel(state);
  const dashboardPanel = new DashboardPanel(state);
  const explainFailurePanel = new ExplainFailurePanel(state);
  const artifactsPanel = new ArtifactsPanel(state);
  const pipelinePanel = new PipelinePanel(state);
  const comparePanel = new ComparePanel(state);
  const irPanel = new IrPanel();
  const openPanels = new Set<PanelId>(session.openPanels);

  async function resolveKairosContext(
    options: { reveal?: boolean; showWarning?: boolean } = {}
  ): Promise<{ editor: vscode.TextEditor | null; inputFile: string } | null> {
    const showWarning = options.showWarning ?? true;
    const activeEditor = vscode.window.activeTextEditor;
    if (activeEditor && activeEditor.document.languageId === "kairos") {
      state.activeFile = activeEditor.document.uri.fsPath;
      return { editor: activeEditor, inputFile: activeEditor.document.uri.fsPath };
    }

    const visibleEditor =
      vscode.window.visibleTextEditors.find((editor) => editor.document.languageId === "kairos") ?? null;
    if (visibleEditor) {
      state.activeFile = visibleEditor.document.uri.fsPath;
      if (options.reveal) {
        await vscode.window.showTextDocument(visibleEditor.document, {
          preview: true,
          viewColumn: visibleEditor.viewColumn ?? preferredEditorColumn()
        });
      }
      return { editor: visibleEditor, inputFile: visibleEditor.document.uri.fsPath };
    }

    if (state.activeFile && fs.existsSync(state.activeFile)) {
      const document = await vscode.workspace.openTextDocument(state.activeFile);
      const editor = options.reveal
        ? await vscode.window.showTextDocument(document, {
            preview: true,
            viewColumn: preferredEditorColumn()
          })
        : null;
      return { editor, inputFile: document.uri.fsPath };
    }

    if (showWarning) {
      vscode.window.showWarningMessage("Open a .kairos file first, or rerun Kairos on the current source.");
    }
    return null;
  }

  let activeRunCancellation: vscode.CancellationTokenSource | null = null;
  clientStartPromise = client
    .start()
    .then(() => undefined)
    .catch((error) => {
      const message = `Kairos LSP failed to start: ${String(error)}`;
      output.appendLine(message);
      void vscode.window.showErrorMessage(
        `${message}. Check 'kairos.lsp.serverPath' and your opam environment.`
      );
      throw error;
    });
  context.subscriptions.push({ dispose: () => void client?.stop() });

  const persistSession = async (): Promise<void> => {
    await context.workspaceState.update("kairos.session", {
      activeFile: state.activeFile,
      currentArtifact: state.currentArtifact,
      runHistory: state.runHistory,
      evalHistory: state.evalHistory,
      openPanels: [...openPanels]
    } satisfies SessionSnapshot);
  };
  state.onDidChange(() => void persistSession());
  state.onDidChangeHistory(() => void persistSession());

  async function ensureClientReady(): Promise<void> {
    if (!client || !clientStartPromise) {
      throw new Error("Kairos LSP client is not available.");
    }
    await clientStartPromise;
  }

  async function refreshOutlineFromActiveEditor(): Promise<void> {
    if (!client) {
      return;
    }
    const context = await resolveKairosContext({ showWarning: false });
    if (!context) {
      return;
    }
    try {
      await ensureClientReady();
      const result = (await client.sendRequest("kairos/outline", {
        uri: vscode.Uri.file(context.inputFile).toString()
      })) as OutlinePayload;
      state.setOutline(result);
    } catch (error) {
      output.appendLine(`kairos/outline failed: ${String(error)}`);
    }
  }

  async function showKobjTextView(
    method: "kairos/kobjSummary" | "kairos/kobjClauses" | "kairos/kobjProduct",
    title: string
  ): Promise<void> {
    if (!client) {
      return;
    }
    const resolved = await resolveKairosContext({ reveal: false, showWarning: true });
    if (!resolved) {
      return;
    }
    try {
      await ensureClientReady();
      const text = (await client.sendRequest(method, {
        inputFile: resolved.inputFile,
        engine: getRunSettings().engine
      })) as string;
      const fileBase = path.basename(resolved.inputFile, path.extname(resolved.inputFile));
      const untitled = vscode.Uri.parse(
        `untitled:${title.replace(/\s+/g, "_")}_${fileBase}.txt`
      );
      const document = await vscode.workspace.openTextDocument(untitled);
      const editor = await vscode.window.showTextDocument(document, {
        preview: true,
        viewColumn: preferredEditorColumn()
      });
      await editor.edit((edit) => {
        edit.replace(
          new vscode.Range(
            document.positionAt(0),
            document.positionAt(document.getText().length)
          ),
          text
        );
      });
      await vscode.languages.setTextDocumentLanguage(document, "plaintext");
    } catch (error) {
      output.appendLine(`${method} failed: ${String(error)}`);
      vscode.window.showErrorMessage(`${title} failed: ${String(error)}`);
    }
  }

  async function computeGoalsTreeFinal(outputs: Outputs): Promise<void> {
    const entries =
      outputs.goals?.map((goal, idx) => ({
        idx,
        display_no: idx + 1,
        goal: String(goal?.[0] ?? ""),
        status: String(goal?.[1] ?? ""),
        time_s: typeof goal?.[2] === "number" ? goal[2] : 0,
        dump_path: goal?.[3] ?? null,
        source: "",
        vcid: goal?.[4] ?? null
      })) ?? [];
    state.setGoalEntries(entries);
    state.setGoalsTree(buildGoalsTreeFinalFallback(outputs.goals ?? []));
  }

  async function computeGoalsTreePending(): Promise<void> {
    const tree = buildGoalsTreePendingFallback(state.goalNames, state.vcIds);
    const entries = tree.flatMap((node) => node.transitions.flatMap((transition) => transition.items));
    state.setGoalEntries(entries);
    state.setGoalsTree(tree);
  }

  function updateGoalsTreeIncrementally(payload: GoalDonePayload): void {
    state.updateGoalEntry(payload);
    state.setGoalsTree(buildGoalsTreeFromEntries(state.goalEntries.filter(Boolean)));
  }

  async function openWhyForGoal(goal: GoalTreeEntry): Promise<void> {
    const outputs = state.outputs;
    if (!outputs) {
      return;
    }
    await openKairosDoc("why");
    const span = outputs.why_spans.find(([idx]) => idx === goal.idx);
    if (!span) {
      return;
    }
    const document = await vscode.workspace.openTextDocument(kairosDocUri("why"));
    const editor = await vscode.window.showTextDocument(document, {
      preview: true,
      viewColumn: preferredEditorColumn()
    });
    const start = document.positionAt(span[1][0]);
    const end = document.positionAt(span[1][1]);
    const range = new vscode.Range(start, end);
    editor.selection = new vscode.Selection(start, end);
    editor.revealRange(range, vscode.TextEditorRevealType.InCenter);
  }

  async function openArtifactSpan(kind: ArtifactId, span: { start_offset: number; end_offset: number } | null): Promise<void> {
    state.setCurrentArtifact(kind);
    if (!span) {
      await openKairosDoc(kind);
      return;
    }
    await revealOffsetSpan(kind, span.start_offset, span.end_offset);
  }

  async function openSourceLocation(loc: Loc | null): Promise<void> {
    const context = await resolveKairosContext({ reveal: true });
    if (!context?.editor || !loc) {
      return;
    }
    const start = new vscode.Position(Math.max(0, loc.line - 1), Math.max(0, loc.col - 1));
    const end = new vscode.Position(Math.max(0, loc.line_end - 1), Math.max(0, loc.col_end - 1));
    const range = new vscode.Range(start, end);
    context.editor.selection = new vscode.Selection(start, end);
    context.editor.revealRange(range, vscode.TextEditorRevealType.InCenter);
  }

  async function openDumpPath(filePath: string | null): Promise<void> {
    if (!filePath) {
      vscode.window.showInformationMessage("No SMT dump available for this goal.");
      return;
    }
    const uri = vscode.Uri.file(filePath);
    const document = await vscode.workspace.openTextDocument(uri);
    await vscode.window.showTextDocument(document, { preview: true, viewColumn: preferredEditorColumn() });
  }

  async function diffCurrentObcWithPrevious(): Promise<void> {
    if (!state.outputs?.obc_text || !state.previousOutputs?.obc_text) {
      vscode.window.showInformationMessage("A previous OBC artifact is required before a diff is available.");
      return;
    }
    const right = kairosDocUri("obc");
    const previousProvider = {
      provideTextDocumentContent: () => state.previousOutputs?.obc_text ?? ""
    };
    const registration = vscode.workspace.registerTextDocumentContentProvider("kairos-prev", previousProvider);
    context.subscriptions.push(registration);
    const previousUri = vscode.Uri.parse("kairos-prev:/obc");
    await vscode.commands.executeCommand("vscode.diff", previousUri, right, "Kairos OBC diff");
  }

  async function getGraphAssets(
    webview: vscode.Webview
  ): Promise<Record<GraphId, { svg: string; pngSrc: string; renderError?: string }>
  > {
    const pngByGraph: Record<GraphId, string | null | undefined> = {
      program: state.automata?.program_png ?? state.outputs?.program_png,
      assume: state.automata?.assume_automaton_png ?? state.outputs?.assume_automaton_png,
      guarantee: state.automata?.guarantee_automaton_png ?? state.outputs?.guarantee_automaton_png,
      product: state.automata?.product_png ?? state.outputs?.product_png
    };
    output.appendLine(`[Kairos] getGraphAssets: paths=${JSON.stringify(pngByGraph)}`);
    const pngErrorByGraph: Record<GraphId, string | null | undefined> = {
      program: state.automata?.program_png_error ?? state.outputs?.program_png_error,
      assume: state.automata?.assume_automaton_png_error ?? state.outputs?.assume_automaton_png_error,
      guarantee:
        state.automata?.guarantee_automaton_png_error ?? state.outputs?.guarantee_automaton_png_error,
      product: state.automata?.product_png_error ?? state.outputs?.product_png_error
    };
    const entries = await Promise.all(
      (Object.keys(pngByGraph) as GraphId[]).map(async (graphId) => {
        const sourcePath = pngByGraph[graphId];
        if (!sourcePath) {
          return [
            graphId,
            {
              svg: "",
              pngSrc: "",
              renderError: pngErrorByGraph[graphId] ?? "No PNG path was returned by Kairos."
            }
          ] as const;
        }
        if (!fs.existsSync(sourcePath)) {
          return [
            graphId,
            { svg: "", pngSrc: "", renderError: `PNG file does not exist: ${sourcePath}` }
          ] as const;
        }
        try {
          const cacheUri = await copyGraphPngToCache(context, graphId, sourcePath);
          if (!cacheUri) {
            return [graphId, { svg: "", pngSrc: "", renderError: `Unable to cache PNG: ${sourcePath}` }] as const;
          }
          const b64 = fs.readFileSync(cacheUri.fsPath).toString("base64");
          const dataUri = `data:image/png;base64,${b64}`;
          output.appendLine(`[Kairos] getGraphAssets: ${graphId} → data URI (${b64.length} chars)`);
          return [graphId, { svg: "", pngSrc: dataUri }] as const;
        } catch (error) {
          return [
            graphId,
            {
              svg: "",
              pngSrc: "",
              renderError: `PNG cache failed: ${error instanceof Error ? error.message : String(error)}`
            }
          ] as const;
        }
      })
    );
    return Object.fromEntries(entries) as Record<
      GraphId,
      { svg: string; pngSrc: string; renderError?: string }
    >;
  }

  async function openTraceFile(): Promise<string | null> {
    const selection = await vscode.window.showOpenDialog({
      canSelectMany: false,
      filters: { Trace: ["txt", "trace", "jsonl", "csv"] }
    });
    if (!selection?.[0]) {
      return null;
    }
    const bytes = await vscode.workspace.fs.readFile(selection[0]);
    return Buffer.from(bytes).toString("utf8");
  }

  async function saveTraceFile(contents: string): Promise<string | null> {
    const target = await vscode.window.showSaveDialog({
      filters: { Trace: ["txt", "trace", "jsonl", "csv"] }
    });
    if (!target) {
      return null;
    }
    await vscode.workspace.fs.writeFile(target, Buffer.from(contents, "utf8"));
    return target.fsPath;
  }

  function renderHtmlReport(): string {
    const outputs = state.outputs;
    const rows = state.goalsTree.flatMap((node) =>
      node.transitions.flatMap((transition) =>
        transition.items.map((item) => ({ node: node.node, transition: transition.transition, item }))
      )
    );
    return `<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><title>Kairos Report</title>
<style>
body{font-family:Arial,sans-serif;margin:32px;color:#222;background:#fff}
h1,h2{margin-top:0}.cards{display:flex;gap:12px;margin-bottom:20px}.card{border:1px solid #ddd;border-radius:10px;padding:12px 16px;min-width:140px}
pre{white-space:pre-wrap;border:1px solid #ddd;border-radius:10px;padding:12px;background:#fafafa}
table{width:100%;border-collapse:collapse}th,td{border-bottom:1px solid #ddd;padding:8px;text-align:left}
</style></head><body>
<h1>Kairos Report</h1>
<div class="cards">
<div class="card"><strong>File</strong><div>${escapeHtmlForReport(state.activeFile ?? "No file")}</div></div>
<div class="card"><strong>Status</strong><div>${escapeHtmlForReport(state.runPhase)}</div></div>
<div class="card"><strong>Summary</strong><div>${escapeHtmlForReport(state.stageSummary || state.statusMessage)}</div></div>
</div>
<h2>Pipeline Metadata</h2>
<pre>${escapeHtmlForReport(
  (outputs?.stage_meta ?? [])
    .map(([stage, entries]) => `${stage}\n${entries.map(([k, v]) => `  - ${k}: ${v}`).join("\n")}`)
    .join("\n\n")
)}</pre>
<h2>Goals</h2>
<table><thead><tr><th>Node</th><th>Transition</th><th>Status</th><th>Time</th><th>Source</th><th>VC</th></tr></thead><tbody>
${rows
  .map(
    ({ node, transition, item }) =>
      `<tr><td>${escapeHtmlForReport(node)}</td><td>${escapeHtmlForReport(transition)}</td><td>${escapeHtmlForReport(
        item.status
      )}</td><td>${item.time_s.toFixed(3)}s</td><td>${escapeHtmlForReport(item.source)}</td><td>${escapeHtmlForReport(
        item.vcid ?? ""
      )}</td></tr>`
  )
  .join("")}
</tbody></table>
<h2>OBC+</h2><pre>${escapeHtmlForReport(outputs?.obc_text ?? "")}</pre>
<h2>Why</h2><pre>${escapeHtmlForReport(outputs?.why_text ?? "")}</pre>
<h2>Obligations Map</h2><pre>${escapeHtmlForReport(outputs?.obligations_map_text ?? state.automata?.obligations_map_text ?? "")}</pre>
</body></html>`;
  }

  async function exportHtmlReport(): Promise<void> {
    const target = await vscode.window.showSaveDialog({
      filters: { HTML: ["html"] },
      defaultUri: vscode.Uri.file(path.join(vscode.workspace.workspaceFolders?.[0]?.uri.fsPath ?? "", "kairos-report.html"))
    });
    if (!target) {
      return;
    }
    await vscode.workspace.fs.writeFile(target, Buffer.from(renderHtmlReport(), "utf8"));
    vscode.window.showInformationMessage(`Kairos report exported to ${target.fsPath}`);
  }

  async function openPipelinePanel(): Promise<void> {
    openPanels.add("pipeline");
    await pipelinePanel.show();
  }

  async function openComparePanel(): Promise<void> {
    openPanels.add("compare");
    comparePanel.show();
  }

  async function openRecentFile(): Promise<void> {
    const recent = [...new Set(state.runHistory.map((entry) => entry.file))];
    if (!recent.length) {
      vscode.window.showInformationMessage("No recent Kairos file recorded yet.");
      return;
    }
    const pick = await vscode.window.showQuickPick(
      recent.map((file) => ({ label: path.basename(file), description: file })),
      { title: "Open recent Kairos file" }
    );
    if (!pick?.description) {
      return;
    }
    const document = await vscode.workspace.openTextDocument(pick.description);
    await vscode.window.showTextDocument(document, { viewColumn: preferredEditorColumn(), preview: false });
  }

  function hasAutomataPngs(): boolean {
    const paths = [
      state.automata?.program_png ?? state.outputs?.program_png,
      state.automata?.assume_automaton_png ?? state.outputs?.assume_automaton_png,
      state.automata?.guarantee_automaton_png ?? state.outputs?.guarantee_automaton_png,
      state.automata?.product_png ?? state.outputs?.product_png,
    ];
    return paths.some(p => p != null && fs.existsSync(p));
  }

  async function showAutomataPanel(): Promise<void> {
    const hasPngs = hasAutomataPngs();
    output.appendLine(`[Kairos] showAutomataPanel: hasAutomataPngs=${hasPngs}`);
    if (!hasPngs) {
      output.appendLine("[Kairos] showAutomataPanel: no valid PNGs on disk, triggering runAutomataPass.");
      await runAutomataPass();
      return;
    }
    output.appendLine("[Kairos] showAutomataPanel: PNGs found, showing panel.");
    openPanels.add("automata");
    automataPanel.show();
  }

  async function showIrPanel(): Promise<void> {
    const ctx = await resolveKairosContext({ showWarning: true });
    if (!ctx) {
      return;
    }
    const inputFile = ctx.inputFile;
    const lspCfg = vscode.workspace.getConfiguration("kairos.lsp");
    const lspPath = lspCfg.get<string>("serverPath", "kairos-lsp");
    // Derive CLI binary: replace 'kairos-lsp' with 'kairos-pipeline' in the path.
    const cliPath = path.isAbsolute(lspPath)
      ? path.join(path.dirname(lspPath), "kairos-pipeline")
      : "kairos-pipeline";
    const dotCfg = vscode.workspace.getConfiguration("kairos");
    const dotBin = dotCfg.get<string>("graphviz.dotPath", "dot");

    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "kairos-ir-"));
    try {
      try {
        execFileSync(cliPath, ["--dump-ir-dir", tmpDir, inputFile], {
          encoding: "utf8",
          timeout: 30_000,
          maxBuffer: 32 * 1024 * 1024
        });
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        vscode.window.showErrorMessage(`Kairos IR generation failed: ${msg}`);
        return;
      }

      // Collect node names from generated files.
      const files = fs.readdirSync(tmpDir);
      const nodeNames = [
        ...new Set(
          files
            .filter((f) => f.endsWith(".annotated.dot") || f.endsWith(".verified.dot") || f.endsWith(".kernel.dot"))
            .map((f) => f.replace(/\.(annotated|verified|kernel)\.dot$/, ""))
        )
      ].sort();

      if (nodeNames.length === 0) {
        vscode.window.showWarningMessage("No IR graphs were generated. The file may not have any nodes.");
        return;
      }

      function renderDotToPng(dotText: string): { png: string; error: string } {
        const dotCandidates = path.isAbsolute(dotBin)
          ? [dotBin]
          : [dotBin, "/opt/homebrew/bin/dot", "/usr/local/bin/dot", "/opt/local/bin/dot"];
        for (const candidate of dotCandidates) {
          if (path.isAbsolute(candidate) && !fs.existsSync(candidate)) {
            continue;
          }
          try {
            const buf = execFileSync(candidate, ["-Tpng"], {
              encoding: null,
              input: dotText,
              timeout: 15_000,
              maxBuffer: 32 * 1024 * 1024
            });
            return { png: `data:image/png;base64,${buf.toString("base64")}`, error: "" };
          } catch (e) {
            return { png: "", error: e instanceof Error ? e.message : String(e) };
          }
        }
        return { png: "", error: "Graphviz dot not found." };
      }

      function readDot(nodeName: string, suffix: string): string {
        const p = path.join(tmpDir, `${nodeName}.${suffix}.dot`);
        return fs.existsSync(p) ? fs.readFileSync(p, "utf8") : "";
      }

      const nodes: IrNodeGraphs[] = nodeNames.map((name) => {
        const aDot = readDot(name, "annotated");
        const vDot = readDot(name, "verified");
        const kDot = readDot(name, "kernel");
        const aResult = aDot ? renderDotToPng(aDot) : { png: "", error: "Not available." };
        const vResult = vDot ? renderDotToPng(vDot) : { png: "", error: "Not available." };
        const kResult = kDot ? renderDotToPng(kDot) : { png: "", error: "Not available." };
        return {
          name,
          annotatedPng: aResult.png,
          annotatedError: aResult.error,
          verifiedPng: vResult.png,
          verifiedError: vResult.error,
          kernelPng: kResult.png,
          kernelError: kResult.error
        };
      });

      irPanel.show(nodes);
    } finally {
      // Clean up tmp directory asynchronously (best effort)
      setTimeout(() => {
        try {
          fs.rmSync(tmpDir, { recursive: true, force: true });
        } catch (_) {
          /* ignore */
        }
      }, 5000);
    }
  }

  async function showDashboardPanel(): Promise<void> {
    openPanels.add("dashboard");
    await dashboardPanel.show();
  }

  async function showExplainFailurePanel(trace?: ProofTrace | null): Promise<void> {
    openPanels.add("explain");
    const selectedTrace =
      trace ??
      state.activeProofTrace ??
      state.outputs?.proof_traces.find((item) => {
        const normalized = (item.status ?? "").toLowerCase();
        return normalized !== "valid" && normalized !== "proved" && normalized !== "pending";
      }) ??
      null;
    await explainFailurePanel.show(selectedTrace);
  }

  async function showArtifactsPanel(): Promise<void> {
    openPanels.add("artifacts");
    await artifactsPanel.show();
  }

  async function showEvalPanel(): Promise<void> {
    openPanels.add("eval");
    await evalPanel.show();
  }

  const panelHost: PanelHost = {
    openArtifact: async (kind) => {
      if (kind === "program" || kind === "assume" || kind === "guarantee" || kind === "product") {
        await showAutomataPanel();
        return;
      }
      state.setCurrentArtifact(kind);
      await openKairosDoc(kind);
    },
    openArtifactSpan,
    openGraphPanel: showAutomataPanel,
    openDashboardPanel: showDashboardPanel,
    openExplainFailurePanel: showExplainFailurePanel,
    rerunFocusedDiagnosis: async (trace) => {
      await runWith("prove");
      const refreshed =
        state.outputs?.proof_traces.find((item) => item.goal_index === trace.goal_index) ?? trace;
      await showExplainFailurePanel(refreshed);
    },
    openEvalPanel: showEvalPanel,
    openPipelinePanel,
    openComparePanel,
    runEval: async (traceText, withState, withLocals) => runEval(traceText, withState, withLocals),
    openWhyForGoal,
    openSourceLocation,
    openDumpPath,
    diffCurrentObcWithPrevious,
    showRunHistory: async () => showRunHistory(),
    openTraceFile,
    saveTraceFile,
    exportHtmlReport
  };
  automataPanel.setHost(panelHost);
  evalPanel.setHost(panelHost);
  dashboardPanel.setHost(panelHost);
  explainFailurePanel.setHost(panelHost);
  artifactsPanel.setHost(panelHost);
  pipelinePanel.setHost(panelHost);
  comparePanel.setHost(panelHost);

  client.onNotification("kairos/outputsReady", async (notification: OutputsReadyNotification) => {
    const previousTraceId = state.activeProofTrace?.stable_id;
    const sanitized = stripDotFieldsFromOutputs(notification.payload);
    state.setOutputs(sanitized);
    if (previousTraceId) {
      state.setActiveProofTrace(
        sanitized.proof_traces.find((trace) => trace.stable_id === previousTraceId) ?? null
      );
    }
    state.setStageSummary(formatStageSummary(sanitized));
    docProvider.refreshAll();
    await computeGoalsTreeFinal(sanitized);
  });
  client.onNotification("kairos/goalsReady", async (notification: GoalsReadyNotification) => {
    state.setPendingGoals(notification.payload.names ?? [], notification.payload.vcIds ?? []);
    await computeGoalsTreePending();
  });
  client.onNotification("kairos/goalDone", async (notification: GoalDoneNotification) => {
    state.activeGoal = notification.payload;
    updateGoalsTreeIncrementally(notification.payload);
  });

  async function runWith(command: "build" | "prove" | "run"): Promise<void> {
    return runWithOptions(command);
  }

  async function runWithOptions(command: "build" | "prove" | "run"): Promise<void> {
    if (!client) {
      return;
    }
    const context = await resolveKairosContext();
    if (!context) {
      return;
    }
    const settings = getRunSettings();
    const inputFile = context.inputFile;
    state.activeFile = inputFile;
    const runId = state.beginRun(command, inputFile, command === "prove" ? "proving" : "building", `${command} started`);
    state.setPhase(command === "prove" ? "proving" : "building", `${command} in progress`, command);
    activeRunCancellation?.dispose();
    activeRunCancellation = new vscode.CancellationTokenSource();
    try {
      await ensureClientReady();
      const result = (await client.sendRequest(
        "kairos/run",
        {
          inputFile,
          engine: settings.engine,
          wpOnly: settings.wpOnly,
          smokeTests: settings.smokeTests,
          timeoutS: settings.timeoutS,
          maxProofGoals: settings.maxProofGoals,
          computeProofDiagnostics: false,
          prefixFields: settings.prefixFields,
          prove: command !== "build",
          generateVcText: settings.generateVcText,
          generateSmtText: settings.generateSmtText,
          generateMonitorText: settings.generateMonitorText,
          generateDotPng: settings.generateDotPng
        },
        activeRunCancellation.token
      )) as Outputs;
      const sanitized = stripDotFieldsFromOutputs(result);
      state.setOutputs(sanitized);
      writeKirFiles(inputFile, result.product_text, result.historical_clauses_text, result.eliminated_clauses_text);
      state.setStageSummary(formatStageSummary(sanitized));
      state.setPhase("completed", `${command} completed`, command);
      state.finishRun(runId, true, "completed", `${command} completed`);
      docProvider.refreshAll();
      await computeGoalsTreeFinal(sanitized);
      await refreshOutlineFromActiveEditor();
      if (command === "prove" && settings.openPanelsAfterProve) {
        await showDashboardPanel();
      }
    } catch (error) {
      const message = String(error);
      const cancelled = message.toLowerCase().includes("cancel");
      state.setPhase(cancelled ? "cancelled" : "failed", cancelled ? `${command} cancelled` : message, command);
      state.finishRun(runId, false, cancelled ? "cancelled" : "failed", cancelled ? `${command} cancelled` : message);
      if (!cancelled) {
        vscode.window.showErrorMessage(`Kairos ${command} failed: ${message}`);
      }
    } finally {
      activeRunCancellation?.dispose();
      activeRunCancellation = null;
    }
  }

  async function runAutomataPass(): Promise<void> {
    output.appendLine("[Kairos] runAutomataPass: called.");
    output.show(true);
    if (!client) {
      output.appendLine("[Kairos] runAutomataPass: LSP client is null, aborting.");
      vscode.window.showWarningMessage("Kairos: LSP not started. Open a .kairos file first.");
      return;
    }
    const context = await resolveKairosContext();
    if (!context) {
      output.appendLine("[Kairos] runAutomataPass: no Kairos context (no active .obc file?), aborting.");
      vscode.window.showWarningMessage("Kairos: no active .obc file found.");
      return;
    }
    const settings = getRunSettings();
    const inputFile = context.inputFile;
    output.appendLine(`[Kairos] runAutomataPass: inputFile=${inputFile}`);
    state.activeFile = inputFile;
    const runId = state.beginRun("automata", inputFile, "building", "Automata generation");
    state.setPhase("building", "Automata generation", "automata");
    activeRunCancellation?.dispose();
    activeRunCancellation = new vscode.CancellationTokenSource();
    try {
      await ensureClientReady();
      output.appendLine("[Kairos] runAutomataPass: sending kairos/instrumentationPass...");
      const result = await client.sendRequest(
        "kairos/instrumentationPass",
        {
          inputFile,
          generatePng: true,
          engine: settings.engine
        },
        activeRunCancellation.token
      );
      output.appendLine("[Kairos] runAutomataPass: response received.");
      const rawAutomata = result as AutomataOutputs;
      const automata = stripDotFieldsFromAutomata(rawAutomata);
      output.appendLine(`[Kairos] runAutomataPass: PNGs — program=${automata.program_png ?? "null"}, assume=${automata.assume_automaton_png ?? "null"}, guarantee=${automata.guarantee_automaton_png ?? "null"}, product=${automata.product_png ?? "null"}`);
      writeKirFiles(inputFile, rawAutomata.product_text, rawAutomata.historical_clauses_text, rawAutomata.eliminated_clauses_text);
      state.setAutomata(automata);
      state.setPhase("completed", "Automata ready", "automata");
      state.finishRun(runId, true, "completed", "Automata ready");
      docProvider.refreshAll();
      openPanels.add("automata");
      automataPanel.show();
    } catch (error) {
      const message = String(error);
      output.appendLine(`[Kairos] runAutomataPass: error — ${message}`);
      const cancelled = message.toLowerCase().includes("cancel");
      state.setPhase(cancelled ? "cancelled" : "failed", cancelled ? "Automata cancelled" : message, "automata");
      state.finishRun(runId, false, cancelled ? "cancelled" : "failed", message);
      if (!cancelled) {
        vscode.window.showErrorMessage(`Automata generation failed: ${message}`);
      }
    } finally {
      activeRunCancellation?.dispose();
      activeRunCancellation = null;
    }
  }

  async function runEval(traceText: string, withState: boolean, withLocals: boolean): Promise<string> {
    if (!client) {
      return "LSP client is not available.";
    }
    const context = await resolveKairosContext();
    if (!context) {
      return "No Kairos file is active.";
    }
    const settings = getRunSettings();
    const inputFile = context.inputFile;
    state.activeFile = inputFile;
    const runId = state.beginRun("eval", inputFile, "eval", "Eval run");
    state.setPhase("eval", "Eval running", "eval");
    try {
      await ensureClientReady();
      const result = (await client.sendRequest(
        "kairos/evalPass",
        {
          inputFile,
          traceText,
          withState,
          withLocals,
          engine: settings.engine
        }
      )) as string;
      state.setOutputs({ ...(state.outputs ?? ({} as Outputs)), eval_text: result } as Outputs);
      state.addEvalHistory({ traceText, withState, withLocals, createdAt: new Date().toISOString(), file: inputFile });
      state.setPhase("completed", "Eval completed", "eval");
      state.finishRun(runId, true, "completed", "Eval completed");
      docProvider.refresh("eval");
      return result;
    } catch (error) {
      const message = String(error);
      state.setPhase("failed", message, "eval");
      state.finishRun(runId, false, "failed", message);
      return `Eval failed: ${message}`;
    }
  }

  async function cancelRun(): Promise<void> {
    if (!activeRunCancellation) {
      vscode.window.showInformationMessage("No active Kairos run to cancel.");
      return;
    }
    activeRunCancellation.cancel();
    state.setPhase("cancelled", "Cancellation requested", state.activeCommand ?? undefined);
  }

  async function resetState(): Promise<void> {
    state.reset();
    docProvider.refreshAll();
    output.appendLine("Kairos state reset.");
  }

  async function showRunHistory(): Promise<void> {
    if (!state.runHistory.length) {
      vscode.window.showInformationMessage("No Kairos run history is available yet.");
      return;
    }
    const pick = await vscode.window.showQuickPick(
      state.runHistory.map((entry) => ({
        label: `${entry.command}: ${entry.summary}`,
        description: entry.durationMs ? `${(entry.durationMs / 1000).toFixed(2)}s` : entry.phase,
        detail: entry.file
      })),
      { title: "Kairos local run history" }
    );
    if (pick) {
      output.show(true);
    }
  }

  const taskProvider = vscode.tasks.registerTaskProvider("kairos", {
    provideTasks: () => {
      const editor = vscode.window.activeTextEditor;
      if (!editor || editor.document.languageId !== "kairos") {
        return [];
      }
      const taskFile = editor.document.uri.fsPath;
      const makeTask = (name: string, command: string) => {
        const task = new vscode.Task(
          { type: "kairos", task: name },
          vscode.TaskScope.Workspace,
          `Kairos ${name}`,
          "kairos",
          new vscode.ShellExecution(command)
        );
        task.detail = taskFile;
        return task;
      };
      return [
        makeTask("Build", "code --command kairos.build"),
        makeTask("Prove", "code --command kairos.prove"),
        makeTask("Automata", "code --command kairos.instrumentation")
      ];
    },
    resolveTask: () => undefined
  });
  context.subscriptions.push(taskProvider);

  context.subscriptions.push(
    vscode.commands.registerCommand("kairos.fetchOutline", refreshOutlineFromActiveEditor),
    vscode.commands.registerCommand("kairos.openOutlineLocation", async (line: number, target: "source" | "abstract") => {
      if (target === "source") {
        const context = await resolveKairosContext({ reveal: true });
        if (!context?.editor) {
          return;
        }
        const position = new vscode.Position(Math.max(0, line - 1), 0);
        context.editor.selection = new vscode.Selection(position, position);
        context.editor.revealRange(new vscode.Range(position, position), vscode.TextEditorRevealType.InCenter);
      } else {
        await openKairosDoc("obc");
      }
    }),
    vscode.commands.registerCommand("kairos.openWhyForVc", openWhyForGoal),
    vscode.commands.registerCommand("kairos.openArtifact", async (kind: ArtifactId) => {
      state.setCurrentArtifact(kind);
      await panelHost.openArtifact(kind);
    }),
    vscode.commands.registerCommand("kairos.openObc", async () => openKairosDoc("obc")),
    vscode.commands.registerCommand("kairos.openWhy", async () => openKairosDoc("why")),
    vscode.commands.registerCommand("kairos.openVc", async () => openKairosDoc("vc")),
    vscode.commands.registerCommand("kairos.openSmt", async () => openKairosDoc("smt")),
    vscode.commands.registerCommand("kairos.openLabels", async () => openKairosDoc("labels")),
    vscode.commands.registerCommand("kairos.openAssumeText", async () => openKairosDoc("assume")),
    vscode.commands.registerCommand("kairos.openGuaranteeText", async () => openKairosDoc("guarantee")),
    vscode.commands.registerCommand("kairos.openProductText", async () => openKairosDoc("product")),
    vscode.commands.registerCommand("kairos.openObligationsMap", async () => openKairosDoc("obligations_map")),
    vscode.commands.registerCommand("kairos.openPruneReasons", async () => openKairosDoc("prune_reasons")),
    vscode.commands.registerCommand("kairos.openKobjSummary", async () =>
      showKobjTextView("kairos/kobjSummary", "Kairos Kobj Summary")
    ),
    vscode.commands.registerCommand("kairos.openKobjClauses", async () =>
      showKobjTextView("kairos/kobjClauses", "Kairos Kobj Clauses")
    ),
    vscode.commands.registerCommand("kairos.openKobjProduct", async () =>
      showKobjTextView("kairos/kobjProduct", "Kairos Kobj Product")
    ),
    vscode.commands.registerCommand("kairos.run", async () => runWith("run")),
    vscode.commands.registerCommand("kairos.build", async () => runWith("build")),
    vscode.commands.registerCommand("kairos.prove", async () => runWith("prove")),
    vscode.commands.registerCommand("kairos.instrumentation", runAutomataPass),
    vscode.commands.registerCommand("kairos.cancelRun", cancelRun),
    vscode.commands.registerCommand("kairos.resetState", resetState),
    vscode.commands.registerCommand("kairos.automataPanel", showAutomataPanel),
    vscode.commands.registerCommand("kairos.dashboardPanel", showDashboardPanel),
    vscode.commands.registerCommand("kairos.explainFailure", async (trace?: ProofTrace | null) => showExplainFailurePanel(trace)),
    vscode.commands.registerCommand("kairos.artifactsPanel", showArtifactsPanel),
    vscode.commands.registerCommand("kairos.evalPanel", showEvalPanel),
    vscode.commands.registerCommand("kairos.pipelinePanel", openPipelinePanel),
    vscode.commands.registerCommand("kairos.compareAutomata", openComparePanel),
    vscode.commands.registerCommand("kairos.irPanel", showIrPanel),
    vscode.commands.registerCommand("kairos.exportHtmlReport", exportHtmlReport),
    vscode.commands.registerCommand("kairos.openRecentFile", openRecentFile),
    vscode.commands.registerCommand("kairos.eval", showEvalPanel),
    vscode.commands.registerCommand("kairos.diffObc", diffCurrentObcWithPrevious),
    vscode.commands.registerCommand("kairos.showRunHistory", showRunHistory),
    vscode.commands.registerCommand("kairos.openTraceLogs", async () => {
      output.show(true);
    }),
    vscode.commands.registerCommand("kairos.openDumpPath", openDumpPath)
  );

  context.subscriptions.push(
    vscode.window.onDidChangeActiveTextEditor(async (editor) => {
      if (editor?.document.languageId === "kairos") {
        state.activeFile = editor.document.uri.fsPath;
        await refreshOutlineFromActiveEditor();
      }
    }),
    vscode.workspace.onDidSaveTextDocument(async (document) => {
      if (document.languageId === "kairos") {
        state.activeFile = document.uri.fsPath;
        await refreshOutlineFromActiveEditor();
      }
    })
  );

  if (getRunSettings().restoreSession && vscode.window.activeTextEditor?.document.languageId === "kairos") {
    state.activeFile = vscode.window.activeTextEditor.document.uri.fsPath;
    await refreshOutlineFromActiveEditor();
  }
  if (getRunSettings().restoreSession) {
    for (const panelId of session.openPanels) {
      if (panelId === "automata") {
        automataPanel.show();
      } else if (panelId === "dashboard") {
        await dashboardPanel.show();
      } else if (panelId === "explain" && state.activeProofTrace) {
        await explainFailurePanel.show(state.activeProofTrace);
      } else if (panelId === "artifacts") {
        await artifactsPanel.show();
      } else if (panelId === "eval") {
        await evalPanel.show();
      } else if (panelId === "pipeline") {
        await pipelinePanel.show();
      } else if (panelId === "compare") {
        comparePanel.show();
      }
    }
  }
}

export async function deactivate(): Promise<void> {
  clientStartPromise = null;
  await client?.stop();
  client = null;
}

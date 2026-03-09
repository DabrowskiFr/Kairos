import * as path from "path";
import * as fs from "fs";
import * as vscode from "vscode";
import {
  LanguageClient,
  LanguageClientOptions,
  ServerOptions,
} from "vscode-languageclient/node";

type Outputs = any;
type AutomataOutputs = any;

let client: LanguageClient | null = null;
let output: vscode.OutputChannel | null = null;

class KairosState {
  outputs: Outputs | null = null;
  automata: AutomataOutputs | null = null;
  goalsTree: any[] = [];
  outline: any | null = null;
  goalNames: string[] = [];
  vcIds: number[] = [];
  readonly onDidChange = new vscode.EventEmitter<void>();

  setOutputs(out: Outputs | null) {
    this.outputs = out;
    this.onDidChange.fire();
  }

  setAutomata(out: AutomataOutputs | null) {
    this.automata = out;
    this.onDidChange.fire();
  }

  setGoalsTree(tree: any[]) {
    this.goalsTree = tree;
    this.onDidChange.fire();
  }

  setOutline(outline: any | null) {
    this.outline = outline;
    this.onDidChange.fire();
  }

  setPendingGoals(names: string[], vcIds: number[]) {
    this.goalNames = names;
    this.vcIds = vcIds;
    this.onDidChange.fire();
  }
}

class KairosDocProvider implements vscode.TextDocumentContentProvider {
  private readonly onDidChangeEmitter = new vscode.EventEmitter<vscode.Uri>();
  onDidChange = this.onDidChangeEmitter.event;
  constructor(private state: KairosState) {}

  refresh(uri: vscode.Uri) {
    this.onDidChangeEmitter.fire(uri);
  }

  provideTextDocumentContent(uri: vscode.Uri): string {
    const kind = uri.path.replace(/^\//, "");
    const out = this.state.outputs;
    const auto = this.state.automata;
    if (!out && !auto) return "No data yet. Run Kairos first.";
    switch (kind) {
      case "obc":
        return out?.obc_text ?? "";
      case "why":
        return out?.why_text ?? "";
      case "vc":
        return out?.vc_text ?? "";
      case "smt":
        return out?.smt_text ?? "";
      case "dot":
        return out?.dot_text ?? "";
      case "labels":
        return out?.labels_text ?? "";
      case "assume":
        return auto?.assume_automaton_text ?? out?.assume_automaton_text ?? "";
      case "guarantee":
        return auto?.guarantee_automaton_text ?? out?.guarantee_automaton_text ?? "";
      case "product":
        return auto?.product_text ?? out?.product_text ?? "";
      case "obligations_map":
        return auto?.obligations_map_text ?? out?.obligations_map_text ?? "";
      case "prune_reasons":
        return auto?.prune_reasons_text ?? out?.prune_reasons_text ?? "";
      case "eval":
        return (out as any)?.eval_text ?? "";
      default:
        return "";
    }
  }
}

type OutlineItemKind = "root" | "section" | "leaf";
class OutlineItem extends vscode.TreeItem {
  constructor(
    public readonly labelText: string,
    public readonly kind: OutlineItemKind,
    public readonly line?: number,
    public readonly target?: "source" | "abstract",
    public readonly group?: "nodes" | "transitions" | "contracts"
  ) {
    super(labelText, kind === "leaf" ? vscode.TreeItemCollapsibleState.None : vscode.TreeItemCollapsibleState.Expanded);
    if (kind === "leaf" && line && target) {
      this.command = {
        command: "kairos.openOutlineLocation",
        title: "Open",
        arguments: [line, target],
      };
    }
  }
}

class OutlineProvider implements vscode.TreeDataProvider<OutlineItem> {
  private readonly onDidChangeEmitter = new vscode.EventEmitter<void>();
  onDidChangeTreeData = this.onDidChangeEmitter.event;

  constructor(private state: KairosState) {
    this.state.onDidChange.event(() => this.refresh());
  }

  refresh() {
    this.onDidChangeEmitter.fire();
  }

  getTreeItem(element: OutlineItem): vscode.TreeItem {
    return element;
  }

  getChildren(element?: OutlineItem): Thenable<OutlineItem[]> {
    const outline = this.state.outline;
    if (!outline) {
      return Promise.resolve([new OutlineItem("No outline (run or save a file)", "section")]);
    }
    if (!element) {
      return Promise.resolve([
        new OutlineItem("Source", "section"),
        new OutlineItem("Abstract Program", "section"),
      ]);
    }
    if (element.label === "Source") {
      return Promise.resolve([
        new OutlineItem("Nodes", "section", undefined, "source", "nodes"),
        new OutlineItem("Transitions", "section", undefined, "source", "transitions"),
        new OutlineItem("Contracts", "section", undefined, "source", "contracts"),
      ]);
    }
    if (element.label === "Abstract Program") {
      return Promise.resolve([
        new OutlineItem("Nodes", "section", undefined, "abstract", "nodes"),
        new OutlineItem("Transitions", "section", undefined, "abstract", "transitions"),
        new OutlineItem("Contracts", "section", undefined, "abstract", "contracts"),
      ]);
    }
    if (element.group && element.target) {
      return Promise.resolve(this.buildOutlineChildren(outline, element.target, element.group));
    }
    return Promise.resolve([]);
  }

  private buildOutlineChildren(outline: any, target: "source" | "abstract", group: "nodes" | "transitions" | "contracts"): OutlineItem[] {
    const section = target === "source" ? outline.source : outline.abstract;
    const entries = section?.[group] ?? [];
    return entries.map((e: any) => new OutlineItem(e.name, "leaf", e.line, target));
  }
}

class GoalsItem extends vscode.TreeItem {
  constructor(
    public readonly labelText: string,
    public readonly kind: "node" | "transition" | "vc",
    public readonly payload?: any
  ) {
    super(labelText, kind === "vc" ? vscode.TreeItemCollapsibleState.None : vscode.TreeItemCollapsibleState.Collapsed);
    if (kind === "vc") {
      this.command = { command: "kairos.openWhyForVc", title: "Open Why at VC", arguments: [payload] };
      this.contextValue = "kairosGoalVc";
    }
  }
}

class GoalsProvider implements vscode.TreeDataProvider<GoalsItem> {
  private readonly onDidChangeEmitter = new vscode.EventEmitter<void>();
  onDidChangeTreeData = this.onDidChangeEmitter.event;

  constructor(private state: KairosState) {
    this.state.onDidChange.event(() => this.refresh());
  }

  refresh() {
    this.onDidChangeEmitter.fire();
  }

  getTreeItem(element: GoalsItem): vscode.TreeItem {
    return element;
  }

  getChildren(element?: GoalsItem): Thenable<GoalsItem[]> {
    const tree = this.state.goalsTree;
    if (!tree || tree.length === 0) {
      return Promise.resolve([new GoalsItem("No goals (run prove)", "node")]);
    }
    if (!element) {
      return Promise.resolve(
        tree.map((n: any) => {
          const item = new GoalsItem(`${n.node} (${n.succeeded}/${n.total})`, "node", n);
          item.description = `${n.succeeded}/${n.total}`;
          item.iconPath = n.total > 0 && n.succeeded === n.total
            ? new vscode.ThemeIcon("check")
            : new vscode.ThemeIcon("error");
          item.collapsibleState = n.total > 0 && n.succeeded === n.total
            ? vscode.TreeItemCollapsibleState.Collapsed
            : vscode.TreeItemCollapsibleState.Expanded;
          return item;
        })
      );
    }
    if (element.kind === "node") {
      const transitions = element.payload?.transitions ?? [];
      return Promise.resolve(
        transitions.map(
          (t: any) => {
            const item = new GoalsItem(`${t.transition} (${t.succeeded}/${t.total})`, "transition", t);
            item.description = `${t.succeeded}/${t.total}`;
            item.iconPath = t.total > 0 && t.succeeded === t.total
              ? new vscode.ThemeIcon("check")
              : new vscode.ThemeIcon("error");
            item.collapsibleState = t.total > 0 && t.succeeded === t.total
              ? vscode.TreeItemCollapsibleState.Collapsed
              : vscode.TreeItemCollapsibleState.Expanded;
            return item;
          }
        )
      );
    }
    if (element.kind === "transition") {
      const items = element.payload?.items ?? [];
      return Promise.resolve(
        items.map((g: any, idx: number) => {
          const status = (g?.status ?? "").toLowerCase();
          const item = new GoalsItem(`VC ${idx + 1}`, "vc", g);
          item.description = status;
          item.tooltip = g?.source ? `${g.source}` : undefined;
          item.iconPath =
            status === "valid" || status === "proved"
              ? new vscode.ThemeIcon("check")
              : status === "unknown"
              ? new vscode.ThemeIcon("question")
              : new vscode.ThemeIcon("error");
          return item;
        })
      );
    }
    return Promise.resolve([]);
  }
}

class ArtifactsProvider implements vscode.TreeDataProvider<vscode.TreeItem> {
  private readonly onDidChangeEmitter = new vscode.EventEmitter<void>();
  onDidChangeTreeData = this.onDidChangeEmitter.event;

  constructor(private state: KairosState) {
    this.state.onDidChange.event(() => this.refresh());
  }

  refresh() {
    this.onDidChangeEmitter.fire();
  }

  getTreeItem(element: vscode.TreeItem): vscode.TreeItem {
    return element;
  }

  getChildren(): Thenable<vscode.TreeItem[]> {
    const items: vscode.TreeItem[] = [];
    const mk = (label: string, command: string) => {
      const item = new vscode.TreeItem(label, vscode.TreeItemCollapsibleState.None);
      item.command = { command, title: label };
      return item;
    };
    items.push(mk("OBC+", "kairos.openObc"));
    items.push(mk("Why", "kairos.openWhy"));
    items.push(mk("VC", "kairos.openVc"));
    items.push(mk("SMT", "kairos.openSmt"));
    items.push(mk("DOT", "kairos.openDot"));
    items.push(mk("Labels", "kairos.openLabels"));
    items.push(mk("Assume Automaton", "kairos.openAssumeText"));
    items.push(mk("Guarantee Automaton", "kairos.openGuaranteeText"));
    items.push(mk("Product Automaton", "kairos.openProductText"));
    items.push(mk("Obligations Map", "kairos.openObligationsMap"));
    items.push(mk("Prune Reasons", "kairos.openPruneReasons"));
    items.push(mk("Assume PNG", "kairos.showAssumePng"));
    items.push(mk("Guarantee PNG", "kairos.showGuaranteePng"));
    items.push(mk("Product PNG", "kairos.showProductPng"));
    return Promise.resolve(items);
  }
}

type GoalTreeEntry = {
  idx: number;
  goal: string;
  status: string;
  time_s: number;
  dump_path?: string | null;
  source: string;
  vcid?: string | null;
};

function normalizeGoalStatus(status: string): string {
  return (status ?? "").trim().toLowerCase();
}

function parseSourceScope(sourceRaw: string): { node: string; transition: string } {
  const source = (sourceRaw ?? "").trim();
  if (!source) return { node: "Global", transition: "default" };
  const sep = source.indexOf(":");
  if (sep <= 0) return { node: source, transition: "default" };
  return {
    node: source.slice(0, sep).trim() || "Global",
    transition: source.slice(sep + 1).trim() || "default",
  };
}

function groupGoalEntries(entries: GoalTreeEntry[]): any[] {
  const byNode = new Map<string, { order: number; byTransition: Map<string, GoalTreeEntry[]> }>();
  entries.forEach((entry, order) => {
    const { node, transition } = parseSourceScope(entry.source);
    let n = byNode.get(node);
    if (!n) {
      n = { order, byTransition: new Map<string, GoalTreeEntry[]>() };
      byNode.set(node, n);
    }
    const bucket = n.byTransition.get(transition) ?? [];
    bucket.push(entry);
    n.byTransition.set(transition, bucket);
  });

  return [...byNode.entries()]
    .sort((a, b) => a[1].order - b[1].order)
    .map(([node, nodeInfo]) => {
      const transitions = [...nodeInfo.byTransition.entries()].map(([transition, items]) => {
        const total = items.length;
        const succeeded = items.filter((g) => {
          const st = normalizeGoalStatus(g.status);
          return st === "valid" || st === "proved";
        }).length;
        return {
          transition,
          source: `${node}: ${transition}`,
          succeeded,
          total,
          items,
        };
      });
      const total = transitions.reduce((acc, t) => acc + t.total, 0);
      const succeeded = transitions.reduce((acc, t) => acc + t.succeeded, 0);
      return { node, source: node, succeeded, total, transitions };
    });
}

function buildGoalsTreeFinalFallback(outputs: any): any[] {
  const goals = Array.isArray(outputs?.goals) ? outputs.goals : [];
  const entries: GoalTreeEntry[] = goals.map((g: any, idx: number) => ({
    idx,
    goal: String(g?.goal ?? ""),
    status: String(g?.status ?? ""),
    time_s: typeof g?.time_s === "number" ? g.time_s : 0,
    dump_path: g?.dump_path ?? null,
    source: String(g?.source ?? ""),
    vcid: g?.vcid ?? null,
  }));
  return groupGoalEntries(entries);
}

function buildGoalsTreePendingFallback(goalNames: string[], vcIds: number[], vcSources: any[]): any[] {
  const vcSourceById = new Map<number, string>();
  if (Array.isArray(vcSources)) {
    vcSources.forEach((p: any) => {
      if (Array.isArray(p) && p.length >= 2 && typeof p[0] === "number" && typeof p[1] === "string") {
        vcSourceById.set(p[0], p[1]);
      }
    });
  }

  const entries: GoalTreeEntry[] = goalNames.map((goal, idx) => {
    const vcid = typeof vcIds[idx] === "number" ? vcIds[idx] : null;
    return {
      idx,
      goal: String(goal ?? ""),
      status: "pending",
      time_s: 0,
      dump_path: null,
      source: vcid !== null ? vcSourceById.get(vcid) ?? "" : "",
      vcid: vcid !== null ? String(vcid) : null,
    };
  });
  return groupGoalEntries(entries);
}

function resolveServerCommand(serverPath: string): string {
  if (path.isAbsolute(serverPath) && fs.existsSync(serverPath)) {
    return serverPath;
  }
  return serverPath;
}

async function ensureClientReady(): Promise<void> {
  const c: any = client as any;
  if (c && typeof c.onReady === "function") {
    await c.onReady();
  }
}

function ensureKairosEditor(): vscode.TextEditor | null {
  const editor = vscode.window.activeTextEditor;
  if (!editor || editor.document.languageId !== "kairos") {
    vscode.window.showWarningMessage("Open a .kairos or .obc file first.");
    return null;
  }
  return editor;
}

function kairosDocUri(kind: string): vscode.Uri {
  return vscode.Uri.parse(`kairos:/${kind}`);
}

async function openKairosDoc(kind: string): Promise<void> {
  const doc = await vscode.workspace.openTextDocument(kairosDocUri(kind));
  await vscode.window.showTextDocument(doc, { preview: true });
}

async function showPng(title: string, base64: string): Promise<void> {
  const panel = vscode.window.createWebviewPanel(
    "kairosPng",
    title,
    vscode.ViewColumn.Active,
    {}
  );
  panel.webview.html = `<html><body style="margin:0;background:#1e1e1e"><img style="display:block;max-width:100%;height:auto;margin:0 auto" src="data:image/png;base64,${base64}"/></body></html>`;
}

export async function activate(context: vscode.ExtensionContext): Promise<void> {
  const cfg = vscode.workspace.getConfiguration("kairos.lsp");
  const serverPath = cfg.get<string>("serverPath", "kairos-lsp");
  const serverArgs = cfg.get<string[]>("serverArgs", []);
  const traceEnabled = cfg.get<boolean>("trace", false);
  const traceFile = cfg.get<string>("traceFile", "");

  const env = { ...process.env };
  if (traceEnabled) {
    env.KAIROS_LSP_TRACE = "1";
    if (traceFile) env.KAIROS_LSP_TRACE_FILE = traceFile;
  }

  const serverOptions: ServerOptions = {
    command: resolveServerCommand(serverPath),
    args: serverArgs,
    options: { env },
  };

  output = vscode.window.createOutputChannel("Kairos LSP");
  const clientOptions: LanguageClientOptions = {
    documentSelector: [{ scheme: "file", language: "kairos" }],
    outputChannel: output,
  };

  client = new LanguageClient(
    "kairosLsp",
    "Kairos LSP",
    serverOptions,
    clientOptions
  );

  const state = new KairosState();
  const docProvider = new KairosDocProvider(state);

  context.subscriptions.push(
    vscode.workspace.registerTextDocumentContentProvider("kairos", docProvider)
  );

  const outlineProvider = new OutlineProvider(state);
  const goalsProvider = new GoalsProvider(state);
  const artifactsProvider = new ArtifactsProvider(state);
  context.subscriptions.push(
    vscode.window.registerTreeDataProvider("kairosOutline", outlineProvider),
    vscode.window.registerTreeDataProvider("kairosGoals", goalsProvider),
    vscode.window.registerTreeDataProvider("kairosArtifacts", artifactsProvider)
  );

  const started = client.start() as any;
  if (started && typeof started.dispose === "function") {
    context.subscriptions.push(started as vscode.Disposable);
  } else {
    context.subscriptions.push({ dispose: () => client?.stop() });
  }

  const refreshAllDocs = () => {
    [
      "obc",
      "why",
      "vc",
      "smt",
      "dot",
      "labels",
      "assume",
      "guarantee",
      "product",
      "obligations_map",
      "prune_reasons",
      "eval",
    ].forEach((k) => docProvider.refresh(kairosDocUri(k)));
  };

  client.onNotification("kairos/outputsReady", async (p: any) => {
    state.setOutputs(p?.payload ?? null);
    refreshAllDocs();
    await computeGoalsTreeFinal();
  });
  client.onNotification("kairos/goalsReady", async (p: any) => {
    const names = p?.payload?.names ?? [];
    const vcIds = p?.payload?.vcIds ?? [];
    state.setPendingGoals(names, vcIds);
    await computeGoalsTreePending();
  });
  client.onNotification("kairos/goalDone", async () => {
    if (state.outputs) {
      await computeGoalsTreeFinal();
    }
  });

  async function refreshOutlineFromActiveEditor() {
    if (!client) return;
    const editor = ensureKairosEditor();
    if (!editor) return;
    try {
      await ensureClientReady();
      const uri = editor.document.uri.toString();
      const res = await client.sendRequest("kairos/outline", { uri });
      state.setOutline(res as any);
    } catch (e: any) {
      output?.appendLine(`kairos/outline failed: ${e?.message ?? String(e)}`);
    }
  }

  async function computeGoalsTreeFinal() {
    if (!client || !state.outputs) return;
    try {
      await ensureClientReady();
      const res = await client.sendRequest("kairos/goalsTreeFinal", {
        goals: state.outputs.goals ?? [],
        vcSources: state.outputs.vc_sources ?? [],
        vcText: state.outputs.vc_text ?? "",
      });
      if (Array.isArray(res)) {
        state.setGoalsTree(res as any[]);
        return;
      }
    } catch (e: any) {
      output?.appendLine(`kairos/goalsTreeFinal failed: ${e?.message ?? String(e)}`);
    }
    state.setGoalsTree(buildGoalsTreeFinalFallback(state.outputs));
  }

  async function computeGoalsTreePending() {
    if (!client) return;
    const vcSources = state.outputs?.vc_sources ?? [];
    try {
      await ensureClientReady();
      const res = await client.sendRequest("kairos/goalsTreePending", {
        goalNames: state.goalNames ?? [],
        vcIds: state.vcIds ?? [],
        vcSources,
      });
      if (Array.isArray(res)) {
        state.setGoalsTree(res as any[]);
        return;
      }
    } catch (e: any) {
      output?.appendLine(`kairos/goalsTreePending failed: ${e?.message ?? String(e)}`);
    }
    state.setGoalsTree(
      buildGoalsTreePendingFallback(state.goalNames ?? [], state.vcIds ?? [], vcSources)
    );
  }

  const fetchOutlineCmd = vscode.commands.registerCommand(
    "kairos.fetchOutline",
    async () => {
      await refreshOutlineFromActiveEditor();
      output?.appendLine("kairos/outline: updated");
      output?.show(true);
    }
  );

  const openOutlineLocationCmd = vscode.commands.registerCommand(
    "kairos.openOutlineLocation",
    async (line: number, target: "source" | "abstract") => {
      if (target === "source") {
        const editor = ensureKairosEditor();
        if (!editor) return;
        const pos = new vscode.Position(Math.max(0, line - 1), 0);
        editor.selection = new vscode.Selection(pos, pos);
        editor.revealRange(new vscode.Range(pos, pos), vscode.TextEditorRevealType.InCenter);
      } else {
        await openKairosDoc("obc");
      }
    }
  );

  const openWhyForVcCmd = vscode.commands.registerCommand(
    "kairos.openWhyForVc",
    async (goal: any) => {
      const out = state.outputs;
      if (!out) {
        vscode.window.showWarningMessage("No outputs yet. Run Kairos first.");
        return;
      }
      const vcId = typeof goal?.idx === "number" ? goal.idx : null;
      const span = Array.isArray(out.why_spans)
        ? out.why_spans.find((s: any) => Array.isArray(s) && s[0] === vcId)
        : null;
      await openKairosDoc("why");
      if (!span) return;
      const doc = await vscode.workspace.openTextDocument(kairosDocUri("why"));
      const editor = await vscode.window.showTextDocument(doc, { preview: true });
      const start = doc.positionAt(span[1][0]);
      const end = doc.positionAt(span[1][1]);
      const range = new vscode.Range(start, end);
      editor.selection = new vscode.Selection(start, end);
      editor.revealRange(range, vscode.TextEditorRevealType.InCenter);
    }
  );

  async function runWith(params: any) {
    if (!client) return;
    const editor = ensureKairosEditor();
    if (!editor) return;
    await ensureClientReady();
    const inputFile = editor.document.uri.fsPath;
    const res = await client.sendRequest("kairos/run", { inputFile, ...params });
    state.setOutputs(res as any);
    await computeGoalsTreeFinal();
    output?.appendLine("kairos/run done");
    output?.show(true);
  }

  const runCmd = vscode.commands.registerCommand("kairos.run", async () => {
    await runWith({
      prover: "z3",
      wpOnly: false,
      smokeTests: false,
      timeoutS: 5,
      prefixFields: false,
      prove: true,
      generateVcText: true,
      generateSmtText: true,
      generateMonitorText: true,
      generateDotPng: true,
    });
  });

  const buildCmd = vscode.commands.registerCommand("kairos.build", async () => {
    await runWith({
      prover: "z3",
      prove: false,
      generateVcText: true,
      generateSmtText: true,
      generateMonitorText: true,
      generateDotPng: true,
    });
  });

  const proveCmd = vscode.commands.registerCommand("kairos.prove", async () => {
    await runWith({ prover: "z3", prove: true });
  });

  const instrumentationCmd = vscode.commands.registerCommand(
    "kairos.instrumentation",
    async () => {
      if (!client) return;
      const editor = ensureKairosEditor();
      if (!editor) return;
      await ensureClientReady();
      const inputFile = editor.document.uri.fsPath;
      const res = await client.sendRequest("kairos/instrumentationPass", {
        inputFile,
        generatePng: true,
      });
      state.setAutomata(res as any);
      output?.appendLine("kairos/instrumentationPass done");
      output?.show(true);
    }
  );

  const evalCmd = vscode.commands.registerCommand("kairos.eval", async () => {
    if (!client) return;
    const editor = ensureKairosEditor();
    if (!editor) return;
    const traceText = await vscode.window.showInputBox({
      prompt: "Paste trace text for eval",
      placeHolder: "trace ...",
    });
    if (!traceText) return;
    await ensureClientReady();
    const inputFile = editor.document.uri.fsPath;
    const res = await client.sendRequest("kairos/evalPass", {
      inputFile,
      traceText,
      withState: true,
      withLocals: true,
    });
    const evalUri = kairosDocUri("eval");
    state.setOutputs({ ...(state.outputs ?? {}), eval_text: res });
    docProvider.refresh(evalUri);
    await openKairosDoc("eval");
  });

  const openObcCmd = vscode.commands.registerCommand("kairos.openObc", async () =>
    openKairosDoc("obc")
  );
  const openWhyCmd = vscode.commands.registerCommand("kairos.openWhy", async () =>
    openKairosDoc("why")
  );
  const openVcCmd = vscode.commands.registerCommand("kairos.openVc", async () =>
    openKairosDoc("vc")
  );
  const openSmtCmd = vscode.commands.registerCommand("kairos.openSmt", async () =>
    openKairosDoc("smt")
  );
  const openDotCmd = vscode.commands.registerCommand("kairos.openDot", async () =>
    openKairosDoc("dot")
  );
  const openLabelsCmd = vscode.commands.registerCommand("kairos.openLabels", async () =>
    openKairosDoc("labels")
  );
  const openAssumeCmd = vscode.commands.registerCommand("kairos.openAssumeText", async () =>
    openKairosDoc("assume")
  );
  const openGuaranteeCmd = vscode.commands.registerCommand(
    "kairos.openGuaranteeText",
    async () => openKairosDoc("guarantee")
  );
  const openProductCmd = vscode.commands.registerCommand("kairos.openProductText", async () =>
    openKairosDoc("product")
  );
  const openObligationsCmd = vscode.commands.registerCommand(
    "kairos.openObligationsMap",
    async () => openKairosDoc("obligations_map")
  );
  const openPruneCmd = vscode.commands.registerCommand("kairos.openPruneReasons", async () =>
    openKairosDoc("prune_reasons")
  );

  const showPngCmd = (kind: "assume" | "guarantee" | "product") =>
    vscode.commands.registerCommand(`kairos.show${kind[0].toUpperCase()}${kind.slice(1)}Png`, async () => {
      if (!client) return;
      const out = state.automata ?? state.outputs;
      let dot = "";
      if (kind === "assume") dot = out?.assume_automaton_dot ?? "";
      if (kind === "guarantee") dot = out?.guarantee_automaton_dot ?? "";
      if (kind === "product") dot = out?.product_dot ?? "";
      if (!dot) {
        vscode.window.showWarningMessage("No DOT text available.");
        return;
      }
      await ensureClientReady();
      const res = await client.sendRequest("kairos/dotPngFromText", { dotText: dot });
      const png = res as string | null;
      if (!png) {
        vscode.window.showWarningMessage("PNG generation failed.");
        return;
      }
      await showPng(`Kairos ${kind}`, png);
    });

  context.subscriptions.push(
    fetchOutlineCmd,
    openOutlineLocationCmd,
    openWhyForVcCmd,
    runCmd,
    buildCmd,
    proveCmd,
    instrumentationCmd,
    evalCmd,
    openObcCmd,
    openWhyCmd,
    openVcCmd,
    openSmtCmd,
    openDotCmd,
    openLabelsCmd,
    openAssumeCmd,
    openGuaranteeCmd,
    openProductCmd,
    openObligationsCmd,
    openPruneCmd,
    showPngCmd("assume"),
    showPngCmd("guarantee"),
    showPngCmd("product")
  );

  vscode.window.onDidChangeActiveTextEditor(async (ed) => {
    if (ed && ed.document.languageId === "kairos") {
      await refreshOutlineFromActiveEditor();
    }
  });
  vscode.workspace.onDidSaveTextDocument(async (doc) => {
    if (doc.languageId === "kairos") {
      await refreshOutlineFromActiveEditor();
    }
  });

}

export async function deactivate(): Promise<void> {
  if (!client) return;
  await client.stop();
  client = null;
}

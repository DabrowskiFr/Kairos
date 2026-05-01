import * as vscode from "vscode";
import { goalStatusCategory, goalStatusIcon } from "./goals";
import { KairosState } from "./state";
import { ARTIFACTS, ArtifactDescriptor, ArtifactId, GoalTreeEntry, GoalTreeNode, GoalTreeTransition } from "./types";

export class OutlineItem extends vscode.TreeItem {
  constructor(
    readonly labelText: string,
    readonly kind: "root" | "section" | "leaf",
    readonly line?: number,
    readonly target?: "source" | "abstract",
    readonly group?: "nodes" | "transitions" | "contracts"
  ) {
    super(
      labelText,
      kind === "leaf" ? vscode.TreeItemCollapsibleState.None : vscode.TreeItemCollapsibleState.Expanded
    );
    if (kind === "leaf" && typeof line === "number" && target) {
      this.command = {
        command: "kairos.openOutlineLocation",
        title: "Open outline location",
        arguments: [line, target]
      };
    }
  }
}

export class OutlineProvider implements vscode.TreeDataProvider<OutlineItem> {
  private readonly didChangeEmitter = new vscode.EventEmitter<void>();
  readonly onDidChangeTreeData = this.didChangeEmitter.event;

  constructor(private readonly state: KairosState) {
    this.state.onDidChange(() => this.refresh());
  }

  refresh(): void {
    this.didChangeEmitter.fire();
  }

  getTreeItem(element: OutlineItem): vscode.TreeItem {
    return element;
  }

  getChildren(element?: OutlineItem): Thenable<OutlineItem[]> {
    const outline = this.state.outline;
    if (!outline) {
      return Promise.resolve([new OutlineItem("No outline. Save or run the current file.", "section")]);
    }
    if (!element) {
      return Promise.resolve([
        new OutlineItem("Source", "root"),
        new OutlineItem("Abstract Program", "root")
      ]);
    }
    if (element.label === "Source") {
      return Promise.resolve([
        new OutlineItem("Nodes", "section", undefined, "source", "nodes"),
        new OutlineItem("Transitions", "section", undefined, "source", "transitions"),
        new OutlineItem("Contracts", "section", undefined, "source", "contracts")
      ]);
    }
    if (element.label === "Abstract Program") {
      return Promise.resolve([
        new OutlineItem("Nodes", "section", undefined, "abstract", "nodes"),
        new OutlineItem("Transitions", "section", undefined, "abstract", "transitions"),
        new OutlineItem("Contracts", "section", undefined, "abstract", "contracts")
      ]);
    }
    if (element.target && element.group) {
      const section = element.target === "source" ? outline.source : outline.abstract;
      const entries = section[element.group] ?? [];
      return Promise.resolve(entries.map((entry) => new OutlineItem(entry.name, "leaf", entry.line, element.target)));
    }
    return Promise.resolve([]);
  }
}

export class GoalsItem extends vscode.TreeItem {
  constructor(
    readonly labelText: string,
    readonly kind: "node" | "transition" | "goal",
    readonly payload?: GoalTreeNode | GoalTreeTransition | GoalTreeEntry
  ) {
    super(
      labelText,
      kind === "goal" ? vscode.TreeItemCollapsibleState.None : vscode.TreeItemCollapsibleState.Collapsed
    );
  }
}

export class GoalsProvider implements vscode.TreeDataProvider<GoalsItem> {
  private readonly didChangeEmitter = new vscode.EventEmitter<void>();
  readonly onDidChangeTreeData = this.didChangeEmitter.event;

  constructor(private readonly state: KairosState) {
    this.state.onDidChange(() => this.refresh());
  }

  refresh(): void {
    this.didChangeEmitter.fire();
  }

  getTreeItem(element: GoalsItem): vscode.TreeItem {
    if (element.kind === "goal" && element.payload) {
      const goal = element.payload as GoalTreeEntry;
      element.description = `${goal.status} ${goal.time_s > 0 ? `(${goal.time_s.toFixed(3)}s)` : ""}`.trim();
      element.tooltip = `${goal.goal}\n${goal.source}${goal.vcid ? `\nVC ${goal.vcid}` : ""}`;
      element.iconPath = new vscode.ThemeIcon(goalStatusIcon(goal.status));
      element.contextValue = "kairosGoalVc";
      element.command = {
        command: "kairos.openWhyForVc",
        title: "Open Why at VC",
        arguments: [goal]
      };
    }
    if (element.kind === "node") {
      const node = element.payload as GoalTreeNode;
      element.iconPath = new vscode.ThemeIcon(node.succeeded === node.total ? "check-all" : "warning");
      element.description = `${node.succeeded}/${node.total}`;
    }
    if (element.kind === "transition") {
      const transition = element.payload as GoalTreeTransition;
      element.iconPath = new vscode.ThemeIcon(transition.succeeded === transition.total ? "check" : "warning");
      element.description = `${transition.succeeded}/${transition.total}`;
    }
    return element;
  }

  getChildren(element?: GoalsItem): Thenable<GoalsItem[]> {
    if (!this.state.goalsTree.length) {
      return Promise.resolve([new GoalsItem("No goals. Run Prove to populate the dashboard.", "node")]);
    }
    if (!element) {
      return Promise.resolve(
        this.state.goalsTree.map((node) => new GoalsItem(`${node.node} (${node.succeeded}/${node.total})`, "node", node))
      );
    }
    if (element.kind === "node") {
      const node = element.payload as GoalTreeNode;
      return Promise.resolve(
        node.transitions.map(
          (transition) =>
            new GoalsItem(
              `${transition.transition} (${transition.succeeded}/${transition.total})`,
              "transition",
              transition
            )
        )
      );
    }
    if (element.kind === "transition") {
      const transition = element.payload as GoalTreeTransition;
      return Promise.resolve(
        transition.items.map((item) => new GoalsItem(`VC ${item.display_no}`, "goal", item))
      );
    }
    return Promise.resolve([]);
  }
}

export class ArtifactsProvider implements vscode.TreeDataProvider<vscode.TreeItem> {
  private readonly didChangeEmitter = new vscode.EventEmitter<void>();
  readonly onDidChangeTreeData = this.didChangeEmitter.event;

  constructor(private readonly state: KairosState) {
    this.state.onDidChange(() => this.refresh());
  }

  refresh(): void {
    this.didChangeEmitter.fire();
  }

  getTreeItem(element: vscode.TreeItem): vscode.TreeItem {
    return element;
  }

  getChildren(): Thenable<vscode.TreeItem[]> {
    const items = ARTIFACTS.map((artifact) => {
      const item = new vscode.TreeItem(artifact.label, vscode.TreeItemCollapsibleState.None);
      item.description = artifact.description;
      item.command = {
        command: "kairos.openArtifact",
        title: "Open artifact",
        arguments: [artifact.id]
      };
      if (artifact.kind === "graph") {
        item.iconPath = new vscode.ThemeIcon("graph");
      } else {
        item.iconPath = new vscode.ThemeIcon("file-code");
      }
      return item;
    });
    return Promise.resolve(items);
  }
}

export class RunsProvider implements vscode.TreeDataProvider<vscode.TreeItem> {
  private readonly didChangeEmitter = new vscode.EventEmitter<void>();
  readonly onDidChangeTreeData = this.didChangeEmitter.event;

  constructor(private readonly state: KairosState) {
    this.state.onDidChangeHistory(() => this.refresh());
  }

  refresh(): void {
    this.didChangeEmitter.fire();
  }

  getTreeItem(element: vscode.TreeItem): vscode.TreeItem {
    return element;
  }

  getChildren(): Thenable<vscode.TreeItem[]> {
    if (!this.state.runHistory.length) {
      return Promise.resolve([new vscode.TreeItem("No runs yet")]);
    }
    return Promise.resolve(
      this.state.runHistory.map((entry) => {
        const item = new vscode.TreeItem(
          `${entry.command}: ${entry.summary}`,
          vscode.TreeItemCollapsibleState.None
        );
        item.description = entry.durationMs ? `${(entry.durationMs / 1000).toFixed(2)}s` : entry.phase;
        item.tooltip = `${entry.file}\n${entry.startedAt}${entry.endedAt ? ` -> ${entry.endedAt}` : ""}`;
        item.iconPath = new vscode.ThemeIcon(entry.success ? "check" : "history");
        return item;
      })
    );
  }
}

export class KairosCodeLensProvider implements vscode.CodeLensProvider {
  private readonly didChangeEmitter = new vscode.EventEmitter<void>();
  readonly onDidChangeCodeLenses = this.didChangeEmitter.event;

  constructor(state: KairosState) {
    state.onDidChange(() => this.didChangeEmitter.fire());
  }

  provideCodeLenses(document: vscode.TextDocument): vscode.CodeLens[] {
    if (document.languageId !== "kairos") {
      return [];
    }
    const top = new vscode.Range(0, 0, 0, 0);
    const lenses = [
      new vscode.CodeLens(top, { command: "kairos.build", title: "Kairos: Build" }),
      new vscode.CodeLens(top, { command: "kairos.prove", title: "Kairos: Prove" }),
      new vscode.CodeLens(top, { command: "kairos.automataPanel", title: "Kairos: Automata" }),
      new vscode.CodeLens(top, { command: "kairos.irPanel", title: "Kairos: IR" })
    ];
    const regex = /^\s*(node|contract|transition)\b/mg;
    const text = document.getText();
    for (const match of text.matchAll(regex)) {
      const offset = match.index ?? 0;
      const position = document.positionAt(offset);
      const range = new vscode.Range(position, position);
      lenses.push(new vscode.CodeLens(range, { command: "kairos.prove", title: "Prove file" }));
      lenses.push(new vscode.CodeLens(range, { command: "kairos.fetchOutline", title: "Refresh outline" }));
    }
    return lenses;
  }
}

export function artifactDescriptorById(id: ArtifactId): ArtifactDescriptor {
  return ARTIFACTS.find((artifact) => artifact.id === id) ?? ARTIFACTS[0];
}

export function buildGoalSummary(tree: GoalTreeNode[]): { proved: number; failed: number; pending: number; total: number } {
  let proved = 0;
  let failed = 0;
  let pending = 0;
  tree.forEach((node) => {
    node.transitions.forEach((transition) => {
      transition.items.forEach((item) => {
        const category = goalStatusCategory(item.status);
        if (category === "proved") {
          proved += 1;
        } else if (category === "pending") {
          pending += 1;
        } else {
          failed += 1;
        }
      });
    });
  });
  return { proved, failed, pending, total: proved + failed + pending };
}

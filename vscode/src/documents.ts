import * as vscode from "vscode";
import { KairosState } from "./state";
import { ArtifactId } from "./types";

export const KAIROS_SCHEME = "kairos";

export function kairosDocUri(kind: ArtifactId): vscode.Uri {
  return vscode.Uri.parse(`${KAIROS_SCHEME}:/${kind}`);
}

export class KairosDocProvider implements vscode.TextDocumentContentProvider {
  private readonly onDidChangeEmitter = new vscode.EventEmitter<vscode.Uri>();
  readonly onDidChange = this.onDidChangeEmitter.event;

  constructor(private readonly state: KairosState) {}

  refresh(kind: ArtifactId): void {
    this.onDidChangeEmitter.fire(kairosDocUri(kind));
  }

  refreshAll(): void {
    const kinds: ArtifactId[] = [
      "obc",
      "why",
      "vc",
      "smt",
      "labels",
      "program",
      "assume",
      "guarantee",
      "product",
      "obligations_map",
      "prune_reasons"
    ];
    kinds.forEach((kind) => this.refresh(kind));
  }

  provideTextDocumentContent(uri: vscode.Uri): string {
    const kind = uri.path.replace(/^\//, "") as ArtifactId;
    const out = this.state.outputs;
    const automata = this.state.automata;
    if (!out && !automata) {
      return "No Kairos data available yet. Run Build, Prove or Automata first.";
    }
    switch (kind) {
      case "obc":
        return out?.obc_text ?? "";
      case "why":
        return out?.why_text ?? "";
      case "vc":
        return out?.vc_text ?? "";
      case "smt":
        return out?.smt_text ?? "";
      case "labels":
        return out?.labels_text ?? automata?.labels_text ?? "";
      case "program":
        return automata?.program_automaton_text ?? out?.program_automaton_text ?? "";
      case "assume":
        return automata?.assume_automaton_text ?? out?.assume_automaton_text ?? "";
      case "guarantee":
        return automata?.guarantee_automaton_text ?? out?.guarantee_automaton_text ?? "";
      case "product":
        return automata?.product_text ?? out?.product_text ?? "";
      case "obligations_map":
        return automata?.obligations_map_text ?? out?.obligations_map_text ?? "";
      case "prune_reasons":
        return automata?.prune_reasons_text ?? out?.prune_reasons_text ?? "";
      default:
        return "";
    }
  }
}

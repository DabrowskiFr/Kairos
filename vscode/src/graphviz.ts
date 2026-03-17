import * as fs from "fs";
import { execFileSync } from "child_process";
import * as vscode from "vscode";
import { GraphId } from "./types";

export interface RenderedGraph {
  svg: string;
  format: "svg";
}

function candidateDotPaths(configuredPath: string): string[] {
  const candidates = [configuredPath];
  if (!pathLooksAbsolute(configuredPath)) {
    candidates.push("/opt/homebrew/bin/dot", "/usr/local/bin/dot", "/opt/local/bin/dot");
  }
  return [...new Set(candidates)];
}

function pathLooksAbsolute(candidate: string): boolean {
  return candidate.startsWith("/");
}

export async function renderDot(
  dotPath: string,
  dotText: string,
  format: "svg" | "png" | "pdf"
): Promise<Buffer> {
  let lastError: unknown = null;
  for (const candidate of candidateDotPaths(dotPath)) {
    if (pathLooksAbsolute(candidate) && !fs.existsSync(candidate)) {
      continue;
    }
    try {
      const stdout = execFileSync(candidate, [`-T${format}`], {
        encoding: null,
        maxBuffer: 32 * 1024 * 1024,
        input: dotText
      });
      return stdout;
    } catch (error) {
      lastError = error;
    }
  }
  throw lastError instanceof Error ? lastError : new Error(`Unable to execute Graphviz dot via '${dotPath}'.`);
}

export async function writeGraphExport(
  dotPath: string,
  dotText: string,
  target: vscode.Uri,
  format: "dot" | "svg" | "png" | "pdf"
): Promise<void> {
  if (format === "dot") {
    await vscode.workspace.fs.writeFile(target, Buffer.from(dotText, "utf8"));
    return;
  }
  const output = await renderDot(dotPath, dotText, format);
  await vscode.workspace.fs.writeFile(target, output);
}

export function graphLabel(graphId: GraphId): string {
  switch (graphId) {
    case "program":
      return "Program";
    case "assume":
      return "Assume";
    case "guarantee":
      return "Guarantee";
    case "product":
      return "Product";
  }
}

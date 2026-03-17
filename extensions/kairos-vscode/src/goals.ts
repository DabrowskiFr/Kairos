import { GoalInfoTuple, GoalTreeEntry, GoalTreeNode } from "./types";

function normalizeGoalStatus(status: string): string {
  return (status ?? "").trim().toLowerCase();
}

function parseSourceScope(sourceRaw: string): { node: string; transition: string } {
  const source = (sourceRaw ?? "").trim();
  if (!source) {
    return { node: "Global", transition: "default" };
  }
  const sep = source.indexOf(":");
  if (sep <= 0) {
    return { node: source, transition: "default" };
  }
  return {
    node: source.slice(0, sep).trim() || "Global",
    transition: source.slice(sep + 1).trim() || "default"
  };
}

export function buildGoalsTreeFromEntries(entries: GoalTreeEntry[]): GoalTreeNode[] {
  const byNode = new Map<string, { order: number; byTransition: Map<string, GoalTreeEntry[]> }>();
  entries.forEach((entry, order) => {
    const { node, transition } = parseSourceScope(entry.source);
    const nodeInfo = byNode.get(node) ?? { order, byTransition: new Map<string, GoalTreeEntry[]>() };
    const bucket = nodeInfo.byTransition.get(transition) ?? [];
    bucket.push(entry);
    nodeInfo.byTransition.set(transition, bucket);
    byNode.set(node, nodeInfo);
  });

  return [...byNode.entries()]
    .sort((a, b) => a[1].order - b[1].order)
    .map(([node, nodeInfo]) => {
      const transitions = [...nodeInfo.byTransition.entries()].map(([transition, items]) => {
        const total = items.length;
        const succeeded = items.filter((item) => {
          const status = normalizeGoalStatus(item.status);
          return status === "valid" || status === "proved";
        }).length;
        return {
          transition,
          source: `${node}: ${transition}`,
          succeeded,
          total,
          items
        };
      });
      const total = transitions.reduce((sum, transition) => sum + transition.total, 0);
      const succeeded = transitions.reduce((sum, transition) => sum + transition.succeeded, 0);
      return { node, source: node, succeeded, total, transitions };
    });
}

export function buildGoalsTreeFinalFallback(goals: GoalInfoTuple[]): GoalTreeNode[] {
  const entries: GoalTreeEntry[] = goals.map((goal, idx) => ({
    idx,
    display_no: idx + 1,
    goal: String(goal?.[0] ?? ""),
    status: String(goal?.[1] ?? ""),
    time_s: typeof goal?.[2] === "number" ? goal[2] : 0,
    dump_path: goal?.[3] ?? null,
    source: String(goal?.[4] ?? ""),
    vcid: goal?.[5] ?? null
  }));
  return buildGoalsTreeFromEntries(entries);
}

export function buildGoalsTreePendingFallback(
  goalNames: string[],
  vcIds: number[],
  vcSources: Array<[number, string]>
): GoalTreeNode[] {
  const vcSourceById = new Map<number, string>(vcSources);
  const entries: GoalTreeEntry[] = goalNames.map((goal, idx) => {
    const vcId = typeof vcIds[idx] === "number" ? vcIds[idx] : null;
    return {
      idx,
      display_no: idx + 1,
      goal: String(goal ?? ""),
      status: "pending",
      time_s: 0,
      dump_path: null,
      source: vcId !== null ? vcSourceById.get(vcId) ?? "" : "",
      vcid: vcId !== null ? String(vcId) : null
    };
  });
  return buildGoalsTreeFromEntries(entries);
}

export function goalStatusIcon(status: string): string {
  const normalized = normalizeGoalStatus(status);
  if (normalized === "valid" || normalized === "proved") {
    return "check";
  }
  if (normalized === "pending") {
    return "clock";
  }
  if (normalized === "unknown") {
    return "question";
  }
  return "error";
}

export function goalStatusCategory(status: string): "proved" | "pending" | "failed" {
  const normalized = normalizeGoalStatus(status);
  if (normalized === "valid" || normalized === "proved") {
    return "proved";
  }
  if (normalized === "pending") {
    return "pending";
  }
  return "failed";
}

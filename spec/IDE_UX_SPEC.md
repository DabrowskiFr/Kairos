# IDE UX Spec (Professional Quality Target)

## 1. Scope

This spec defines the target UX for the Kairos IDE with three goals:
1. Fast diagnosis of proof failures.
2. Strong source-to-VC traceability.
3. Stable and accessible daily workflow.

## 2. Primary Personas

1. Verification engineer: iterates on contracts/invariants, needs fast VC feedback.
2. Language/tool contributor: inspects generated artifacts and pipeline stages.

## 3. Information Architecture

Main regions:

1. Top Action Bar
- Open / Save
- Parse / Build / Prove
- Prover selector
- Timeout field
- Global status badge

2. Left Sidebar
- Program tree: Nodes -> Transitions
- Diagnostics panel
- VC list (filterable, with grouping modes)

3. Center Panel (Primary)
- Kairos source editor
- Inline diagnostics markers

4. Right Inspector (Tabs)
- `Transition`
- `Requires/Ensures`
- `Automata`
- `OBC+ (read-only)`
- `Why VC`

5. Bottom Panel (Collapsible)
- Logs
- Pass timings
- Prover raw output

## 4. Core Screens

### 4.1 Editing (Default)

Visible by default:
- Center editor
- Left diagnostics + VC list
- Top status and actions

Hidden by default:
- Bottom logs panel (expand on demand)

### 4.2 Proof Analysis

When `Prove` is triggered:
- VC list becomes primary in left panel.
- Right inspector auto-switches to `Why VC` for selected failed VC.
- Source location is highlighted in editor.

### 4.3 Artifact Inspection

When inspecting generation:
- Right inspector `Automata` tab shows automata/product views.
- `Requires/Ensures` tab shows generated formulas for selected transition.
- `OBC+` is displayed as a rendered artifact from IR and is **read-only**.
- Allowed actions on `OBC+`: `Copy`, `Export`, `Diff with previous generation`, `Go to source transition`.

## 5. Interaction Model

## 5.1 Main Actions

1. Parse
- Runs parsing only.
- Updates diagnostics + stage status.

2. Build
- Runs until OBC+/Why generation (configurable target).
- Updates artifact tabs.

3. Prove
- Runs full pipeline + prover.
- Streams VC updates live.

Design rule:
- Kairos source is the only editable source of truth.
- Generated artifacts (`OBC+`, `Why`, DOT views) are non-editable in the IDE.

## 5.2 Selection and Traceability

Single source of truth: selected transition or selected VC.

On VC selection:
1. Jump editor to origin location.
2. Highlight owning transition in Program tree.
3. Show generated require/ensure and Why VC in inspector.

On transition selection:
1. Show transition code and generated formulas.
2. Show related VCs filtered in VC list.

On grouped VC header selection:
1. Node header: focus node scope in Program tree.
2. Transition header: focus exact transition in editor and Program tree.
3. Keep inspector synchronized with selected transition context.

## 5.3 Filters and Sorting

VC list filters:
- `all`
- `failed`
- `timeout`
- `unknown`
- `proved`

Sorting:
- source order (default)
- duration
- status severity

VC grouping modes:
- `Grouped by transition` (default)
- `Flat`

Grouped model:
1. Node
2. Transition (`src -> dst`, guard summary)
3. VC items (requires/ensures/coherency)

Group headers show aggregated counters, e.g. `3/8 failed`.

## 6. State Machine (UX)

Global run states:
1. `Idle`
2. `Parsing`
3. `Building`
4. `Proving`
5. `Completed`
6. `Failed`

Rules:
- Only one active run at a time.
- Buttons disabled/enabled by run state.
- Cancel action available in `Building`/`Proving`.

## 7. Status and Feedback

Top status badge includes:
- current state
- elapsed time
- short outcome text

Progress details:
- per-pass timing
- per-VC live status updates

Error style:
- concise headline
- expandable technical details
- always with navigation target when available

## 8. Accessibility Requirements

1. Full keyboard navigation for all key actions.
2. Command palette (`Cmd/Ctrl+K`) with searchable actions.
3. High-contrast default theme (AA minimum).
4. Scalable fonts and persistent UI scale.
5. No information conveyed by color alone.

## 9. Keyboard Shortcuts (Proposed)

- `Cmd/Ctrl+O`: Open
- `Cmd/Ctrl+S`: Save
- `Cmd/Ctrl+P`: Prove
- `Cmd/Ctrl+B`: Build
- `Cmd/Ctrl+R`: Parse
- `F8`: Next diagnostic
- `Shift+F8`: Previous diagnostic
- `Cmd/Ctrl+K`: Command palette

## 10. Feature Backlog by Priority

## P0 (must-have)
1. Stable 3-pane layout (left/center/right).
2. VC list with status filter and grouped-by-transition default view.
3. VC -> source jump + transition focus.
4. Global status + run progress.

## P1
1. Right inspector tabs fully linked to selection.
2. Bottom panel logs/timings.
3. Re-run single VC.

## P2
1. Artifact diffs (current vs previous run).
2. Export reproducibility bundle.
3. Session restore (open files, layout, last selection).

## 11. Non-Goals (for now)

1. Collaborative editing.
2. Multi-project workspace orchestration.
3. Automatic proof strategy synthesis.

## 12. Acceptance Criteria

1. From a failed VC, user reaches source transition in <= 2 clicks.
2. Proof run status is understandable without reading logs.
3. Layout remains stable during long proving sessions.
4. All P0 flows usable with keyboard only.
5. No regression on existing build/prove pipeline behavior.
6. In grouped mode, each VC appears under its originating transition, with correct failure counters.

## 13. Implementation Notes (Current Codebase Mapping)

- Action orchestration: `lib/pipeline/*`
- IDE UI: `bin/ide/obcwhy3_ide.ml`
- Stage metadata and diagnostics: `lib/core/stages/*`
- Artifact generation: `lib/backend/*`

Recommended implementation sequence:
1. Selection model unification (VC <-> transition <-> source).
2. Left panel VC/diagnostics refinement.
3. Right inspector binding and tab logic.
4. Status/progress and cancel semantics.
5. Accessibility + shortcuts hardening.

## 14. Implementation Status

Status legend:
- `done`: implemented and validated in current branch.
- `partial`: present but incomplete or not fully aligned with this spec.
- `todo`: not implemented yet.

### 14.1 Core UX
- 3-pane layout (left/center/right): `done`
- VC list grouped by transition (default): `done`
- Grouped hierarchy Node -> Transition -> VC: `done`
- VC status filters + sorting: `done`
- VC failure counters in groups: `done`
- VC -> source jump and transition focus: `done`
- Scope filter from Program tree selection: `done`
- Clear scope action in Goals header: `done`

### 14.2 Inspector
- `Transition` tab synchronized with selected VC/header: `done`
- `Requires/Ensures` tab synchronized with selected VC: `done`
- `Automata`/product inspection tab set: `done`
- `Abstract Program` tab (read-only): `done`
- `Why VC` tab and auto-focus on failed VC: `done`

### 14.3 Run Feedback
- Global status and progress overview: `done`
- Per-pass timings: `done`
- Live VC updates during prove: `done`
- Cancel current run action: `done`
- Explicit global run state machine (Idle/Parsing/Building/...): `done`

### 14.4 Accessibility and Keyboard
- Keyboard shortcuts for main actions (open/save/build/prove): `done`
- Diagnostic navigation `F8` / `Shift+F8`: `done`
- Command palette `Cmd/Ctrl+K`: `done`
- Full keyboard-only P0 flow validation: `partial`

### 14.5 Advanced Features
- Re-run single VC: `done`
- Artifact diff with previous generation: `done`
- Session restore (layout + selection + files): `done`

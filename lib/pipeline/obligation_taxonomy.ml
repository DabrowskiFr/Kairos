open Ast

type family =
  | FamTransitionRequires
  | FamTransitionEnsures
  | FamCoherencyRequires
  | FamCoherencyEnsuresShifted
  | FamInitialCoherencyGoal
  | FamNoBadRequires
  | FamNoBadEnsures
  | FamMonitorCompatibilityRequires
  | FamStateAwareAssumptionRequires

type summary = { total : int; counts : (family * int) list }

let ordered_families =
  [
    FamTransitionRequires;
    FamTransitionEnsures;
    FamCoherencyRequires;
    FamCoherencyEnsuresShifted;
    FamInitialCoherencyGoal;
    FamNoBadRequires;
    FamNoBadEnsures;
    FamMonitorCompatibilityRequires;
    FamStateAwareAssumptionRequires;
  ]

let family_name = function
  | FamTransitionRequires -> "transition_requires"
  | FamTransitionEnsures -> "transition_ensures"
  | FamCoherencyRequires -> "coherency_requires"
  | FamCoherencyEnsuresShifted -> "coherency_ensures_shifted"
  | FamInitialCoherencyGoal -> "initial_coherency_goal"
  | FamNoBadRequires -> "no_bad_requires"
  | FamNoBadEnsures -> "no_bad_ensures"
  | FamMonitorCompatibilityRequires -> "monitor_compatibility_requires"
  | FamStateAwareAssumptionRequires -> "state_aware_assumption_requires"

let classify_require (f : fo_o) : family =
  match f.origin with
  | Some Coherency -> FamCoherencyRequires
  | Some Instrumentation -> FamNoBadRequires
  | Some Compatibility -> FamMonitorCompatibilityRequires
  | Some AssumeAutomaton -> FamStateAwareAssumptionRequires
  | Some UserContract | Some Internal | None -> FamTransitionRequires

let classify_ensure (f : fo_o) : family =
  match f.origin with
  | Some Coherency -> FamCoherencyEnsuresShifted
  | Some Instrumentation -> FamNoBadEnsures
  | Some UserContract | Some Internal | Some Compatibility | Some AssumeAutomaton | None ->
      FamTransitionEnsures

let summarize_program (p : program) : summary =
  let table = Hashtbl.create 16 in
  let bump family =
    let n = Option.value ~default:0 (Hashtbl.find_opt table family) in
    Hashtbl.replace table family (n + 1)
  in
  List.iter
    (fun (n : node) ->
      List.iter (fun (_ : fo_o) -> bump FamInitialCoherencyGoal) n.attrs.coherency_goals;
      List.iter
        (fun (t : transition) ->
          List.iter (fun r -> bump (classify_require r)) t.requires;
          List.iter (fun e -> bump (classify_ensure e)) t.ensures)
        n.trans)
    p;
  let counts =
    List.filter_map
      (fun fam ->
        let c = Option.value ~default:0 (Hashtbl.find_opt table fam) in
        if c = 0 then None else Some (fam, c))
      ordered_families
  in
  let total = List.fold_left (fun acc (_, c) -> acc + c) 0 counts in
  { total; counts }

let render_summary (s : summary) : string =
  let lines =
    ("total: " ^ string_of_int s.total)
    :: List.map (fun (fam, c) -> Printf.sprintf "- %s: %d" (family_name fam) c) s.counts
  in
  String.concat "\n" lines

let to_stage_meta (s : summary) : (string * string) list =
  ("total", string_of_int s.total)
  :: List.map (fun (fam, c) -> (family_name fam, string_of_int c)) s.counts

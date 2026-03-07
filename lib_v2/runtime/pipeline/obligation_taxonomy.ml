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

type category =
  | CatNoBad
  | CatInitialGoal
  | CatUserInvariant
  | CatAutomatonSupport

type major_class = Safety | Helper

type helper_phase =
  | InitGoal
  | Propagation

type helper_kind =
  | UserInvariant
  | AutomatonSupport

type summary = {
  total : int;
  counts : (family * int) list;
  generated_total : int;
  category_counts : (category * int) list;
  major_counts : (major_class * int) list;
  helper_phase_counts : (helper_phase * int) list;
  helper_kind_counts : (helper_kind * int) list;
}

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

let category_name = function
  | CatNoBad -> "no_bad"
  | CatInitialGoal -> "initial_goal"
  | CatUserInvariant -> "user_invariant"
  | CatAutomatonSupport -> "automaton_support"

let major_class_name = function Safety -> "safety" | Helper -> "helper"
let major_class_of_category = function CatNoBad -> Safety | CatInitialGoal | CatUserInvariant | CatAutomatonSupport -> Helper

let helper_phase_name = function InitGoal -> "init_goal" | Propagation -> "propagation"

let helper_phase_of_category = function
  | CatNoBad -> None
  | CatInitialGoal -> Some InitGoal
  | CatUserInvariant | CatAutomatonSupport -> Some Propagation

let helper_kind_name = function
  | UserInvariant -> "user_invariant"
  | AutomatonSupport -> "automaton_support"

let helper_kind_of_category = function
  | CatNoBad -> None
  | CatInitialGoal -> None
  | CatUserInvariant -> Some UserInvariant
  | CatAutomatonSupport -> Some AutomatonSupport

let category_of_family = function
  | FamNoBadRequires | FamNoBadEnsures -> Some CatNoBad
  | FamInitialCoherencyGoal -> Some CatInitialGoal
  | FamCoherencyRequires | FamCoherencyEnsuresShifted -> Some CatUserInvariant
  | FamMonitorCompatibilityRequires | FamStateAwareAssumptionRequires -> Some CatAutomatonSupport
  | FamTransitionRequires | FamTransitionEnsures -> None

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
  let category_table = Hashtbl.create 8 in
  let major_table = Hashtbl.create 4 in
  let phase_table = Hashtbl.create 4 in
  let kind_table = Hashtbl.create 4 in
  let bump family =
    let n = Option.value ~default:0 (Hashtbl.find_opt table family) in
    Hashtbl.replace table family (n + 1);
    match category_of_family family with
    | None -> ()
    | Some cat ->
        let ncat = Option.value ~default:0 (Hashtbl.find_opt category_table cat) in
        Hashtbl.replace category_table cat (ncat + 1);
        let major = major_class_of_category cat in
        let nmajor = Option.value ~default:0 (Hashtbl.find_opt major_table major) in
        Hashtbl.replace major_table major (nmajor + 1);
        Option.iter
          (fun phase ->
            let nphase = Option.value ~default:0 (Hashtbl.find_opt phase_table phase) in
            Hashtbl.replace phase_table phase (nphase + 1))
          (helper_phase_of_category cat);
        Option.iter
          (fun kind ->
            let nkind = Option.value ~default:0 (Hashtbl.find_opt kind_table kind) in
            Hashtbl.replace kind_table kind (nkind + 1))
          (helper_kind_of_category cat)
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
  let category_counts =
    [ CatNoBad; CatInitialGoal; CatUserInvariant; CatAutomatonSupport ]
    |> List.filter_map (fun cat ->
           let c = Option.value ~default:0 (Hashtbl.find_opt category_table cat) in
           if c = 0 then None else Some (cat, c))
  in
  let generated_total = List.fold_left (fun acc (_, c) -> acc + c) 0 category_counts in
  let major_counts =
    [ Safety; Helper ]
    |> List.filter_map (fun major ->
           let c = Option.value ~default:0 (Hashtbl.find_opt major_table major) in
           if c = 0 then None else Some (major, c))
  in
  let helper_phase_counts =
    [ InitGoal; Propagation ]
    |> List.filter_map (fun phase ->
           let c = Option.value ~default:0 (Hashtbl.find_opt phase_table phase) in
           if c = 0 then None else Some (phase, c))
  in
  let helper_kind_counts =
    [ UserInvariant; AutomatonSupport ]
    |> List.filter_map (fun kind ->
           let c = Option.value ~default:0 (Hashtbl.find_opt kind_table kind) in
           if c = 0 then None else Some (kind, c))
  in
  { total; counts; generated_total; category_counts; major_counts; helper_phase_counts; helper_kind_counts }

let render_summary (s : summary) : string =
  let major_lines =
    List.map
      (fun (major, c) -> Printf.sprintf "- %s: %d" (major_class_name major) c)
      s.major_counts
  in
  let helper_phase_lines =
    List.map
      (fun (phase, c) -> Printf.sprintf "- %s: %d" (helper_phase_name phase) c)
      s.helper_phase_counts
  in
  let helper_kind_lines =
    List.map
      (fun (kind, c) -> Printf.sprintf "- %s: %d" (helper_kind_name kind) c)
      s.helper_kind_counts
  in
  let category_lines =
    ("generated_total: " ^ string_of_int s.generated_total)
    :: List.map
         (fun (cat, c) -> Printf.sprintf "- %s: %d" (category_name cat) c)
         s.category_counts
  in
  let family_lines =
    ("backend_total: " ^ string_of_int s.total)
    :: List.map (fun (fam, c) -> Printf.sprintf "- %s: %d" (family_name fam) c) s.counts
  in
  String.concat "\n"
    ( [ "-- major proof layers --" ]
      @ major_lines
      @ [ ""; "-- helper phases --" ]
      @ helper_phase_lines
      @ [ ""; "-- helper kinds --" ]
      @ helper_kind_lines
      @ [ ""; "-- generated clause families --" ]
      @ category_lines
      @ [ ""; "-- backend families --" ]
      @ family_lines )

let to_stage_meta (s : summary) : (string * string) list =
  [ ("total", string_of_int s.total); ("generated_total", string_of_int s.generated_total) ]
  @ List.map (fun (major, c) -> ("major_" ^ major_class_name major, string_of_int c)) s.major_counts
  @ List.map (fun (phase, c) -> ("helper_phase_" ^ helper_phase_name phase, string_of_int c)) s.helper_phase_counts
  @ List.map (fun (kind, c) -> ("helper_kind_" ^ helper_kind_name kind, string_of_int c)) s.helper_kind_counts
  @ List.map (fun (cat, c) -> ("category_" ^ category_name cat, string_of_int c)) s.category_counts
  @ List.map (fun (fam, c) -> (family_name fam, string_of_int c)) s.counts

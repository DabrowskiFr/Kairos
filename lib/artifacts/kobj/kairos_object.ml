(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

type metadata = {
  format : string;
  format_version : int;
  backend_agnostic : bool;
  source_path : string option;
  source_hash : string option;
  imports : string list;
}
[@@deriving yojson]

type t = {
  metadata : metadata;
  nodes : Proof_kernel_types.exported_node_summary_ir list;
}
[@@deriving yojson]

let current_format = "kairos-kobj"
let current_version = 1

let yojson_of_metadata (metadata : metadata) : Yojson.Safe.t =
  `Assoc
    [
      ("format", `String metadata.format);
      ("format_version", `Int metadata.format_version);
      ("backend_agnostic", `Bool metadata.backend_agnostic);
      ( "source_path",
        match metadata.source_path with Some s -> `String s | None -> `Null );
      ( "source_hash",
        match metadata.source_hash with Some s -> `String s | None -> `Null );
      ("imports", `List (List.map (fun path -> `String path) metadata.imports));
    ]

let metadata_of_yojson = function
  | `Assoc fields ->
      let find name = List.assoc_opt name fields in
      let string_opt = function
        | None | Some `Null -> Ok None
        | Some (`String s) -> Ok (Some s)
        | _ -> Error "expected string or null"
      in
      let string_list = function
        | Some (`List xs) ->
            let rec loop acc = function
              | [] -> Ok (List.rev acc)
              | `String s :: rest -> loop (s :: acc) rest
              | _ -> Error "expected string list"
            in
            loop [] xs
        | None -> Ok []
        | _ -> Error "expected list"
      in
      begin
        match (find "format", find "format_version", find "backend_agnostic", string_opt (find "source_path"),
               string_opt (find "source_hash"), string_list (find "imports"))
        with
        | Some (`String format), Some (`Int format_version), Some (`Bool backend_agnostic), Ok source_path,
          Ok source_hash, Ok imports ->
            Ok { format; format_version; backend_agnostic; source_path; source_hash; imports }
        | _ -> Error "invalid metadata payload"
      end
  | _ -> Error "expected object"

let yojson_of_t (obj : t) : Yojson.Safe.t =
  `Assoc
    [
      ("metadata", yojson_of_metadata obj.metadata);
      ( "nodes",
        `List
          (List.map Proof_kernel_types.exported_node_summary_ir_to_yojson obj.nodes) );
    ]

let t_of_yojson = function
  | `Assoc fields -> (
      match (List.assoc_opt "metadata" fields, List.assoc_opt "nodes" fields) with
      | Some metadata_json, Some (`List nodes_json) -> (
          match metadata_of_yojson metadata_json with
          | Error _ as err -> err
          | Ok metadata ->
              let rec loop acc = function
                | [] -> Ok (List.rev acc)
                | json :: rest -> (
                    match Proof_kernel_types.exported_node_summary_ir_of_yojson json with
                    | Error msg -> Error msg
                    | Ok node -> loop (node :: acc) rest)
              in
              begin match loop [] nodes_json with
              | Error _ as err -> err
              | Ok nodes -> Ok { metadata; nodes }
              end)
      | _ -> Error "expected metadata and nodes")
  | _ -> Error "expected object"

let build ~source_path ~source_hash ~imports ~(program : Ast.program)
    ~(runtime_program : Ast.program) ~(kernel_ir_nodes : Proof_kernel_types.node_ir list) :
    (t, string) result =
  let ir_by_name = Hashtbl.create (List.length kernel_ir_nodes * 2 + 1) in
  let runtime_by_name = Hashtbl.create (List.length runtime_program * 2 + 1) in
  List.iter
    (fun (ir : Proof_kernel_types.node_ir) ->
      Hashtbl.replace ir_by_name ir.reactive_program.node_name ir)
    kernel_ir_nodes;
  List.iter
    (fun (node : Ast.node) -> Hashtbl.replace runtime_by_name node.semantics.sem_nname node)
    runtime_program;
  let pre_k_locals_of_layout (layout : (Ast.hexpr * Temporal_support.pre_k_info) list) : Ast.vdecl list =
    layout
    |> List.concat_map (fun (_, (info : Temporal_support.pre_k_info)) ->
           List.map (fun name -> { Ast.vname = name; vty = info.vty }) info.names)
  in
  let append_missing_locals (locals : Ast.vdecl list) (extra : Ast.vdecl list) : Ast.vdecl list =
    let existing = List.map (fun (v : Ast.vdecl) -> v.vname) locals in
    locals
    @ List.filter (fun (v : Ast.vdecl) -> not (List.mem v.vname existing)) extra
  in
  let node_signature_of_ast (node : Ast.node) : Proof_kernel_types.node_signature_ir =
    let sem = node.semantics in
    {
      node_name = sem.sem_nname;
      inputs = sem.sem_inputs;
      outputs = sem.sem_outputs;
      locals = sem.sem_locals;
      states = sem.sem_states;
      init_state = sem.sem_init_state;
    }
  in
  let rec collect acc = function
    | [] -> Ok (List.rev acc)
    | (node : Ast.node) :: rest -> (
        match Hashtbl.find_opt ir_by_name node.semantics.sem_nname with
        | None ->
            Error
              (Printf.sprintf "Missing normalized IR for local node '%s' while building .kobj"
                 node.semantics.sem_nname)
        | Some normalized_ir ->
            let runtime_node =
              match Hashtbl.find_opt runtime_by_name node.semantics.sem_nname with
              | Some runtime_node -> runtime_node
              | None ->
                  raise
                    (Failure
                       (Printf.sprintf
                          "Missing runtime node '%s' while building .kobj"
                          node.semantics.sem_nname))
            in
            let runtime_signature = node_signature_of_ast runtime_node in
            let exported_runtime_locals = runtime_signature.locals in
            let signature =
              {
                runtime_signature with
                locals =
                  append_missing_locals exported_runtime_locals
                    (pre_k_locals_of_layout normalized_ir.temporal_layout);
              }
            in
            let summary : Proof_kernel_types.exported_node_summary_ir =
              {
                signature;
                normalized_ir;
                user_invariants = [];
                coherency_goals = [];
                temporal_layout = normalized_ir.temporal_layout;
                delay_spec = Pre_k_collect.extract_delay_spec node.specification.spec_guarantees;
                assumes = node.specification.spec_assumes;
                guarantees = node.specification.spec_guarantees;
              }
            in
            collect (summary :: acc) rest)
  in
  match collect [] program with
  | Error _ as err -> err
  | Ok nodes ->
      Ok
        {
          metadata =
            {
              format = current_format;
              format_version = current_version;
              backend_agnostic = true;
              source_path = Some source_path;
              source_hash;
              imports;
            };
          nodes;
        }

let summaries (obj : t) : Proof_kernel_types.exported_node_summary_ir list = obj.nodes

let indent n = String.make (2 * max 0 n) ' '

let string_of_vdecl (v : Ast.vdecl) =
  let ty =
    match v.vty with
    | Ast.TInt -> "int"
    | Ast.TBool -> "bool"
    | Ast.TReal -> "real"
    | Ast.TCustom s -> s
  in
  v.vname ^ ":" ^ ty

let rec string_of_stmt (s : Ast.stmt) =
  match s.stmt with
  | Ast.SAssign (id, e) -> id ^ " := " ^ Logic_pretty.string_of_iexpr e
  | Ast.SSkip -> "skip"
  | Ast.SCall _ -> failwith "calls are not supported outside parser/AST"
  | Ast.SIf (c, _t, _e) -> "if " ^ Logic_pretty.string_of_iexpr c ^ " then ..."
  | Ast.SMatch (e, _branches, _dflt) -> "match " ^ Logic_pretty.string_of_iexpr e ^ " with ..."

let string_of_clause_origin = function
  | Proof_kernel_types.OriginSourceProductSummary -> "SourceProductSummary"
  | Proof_kernel_types.OriginPhaseStepPreSummary -> "PhaseStepPreSummary"
  | Proof_kernel_types.OriginPhaseStepSummary -> "PhaseStepSummary"
  | Proof_kernel_types.OriginSafety -> "Safety"
  | Proof_kernel_types.OriginInitNodeInvariant -> "InitNodeInvariant"
  | Proof_kernel_types.OriginInitAutomatonCoherence -> "InitAutomatonCoherence"
  | Proof_kernel_types.OriginPropagationNodeInvariant -> "PropagationNodeInvariant"
  | Proof_kernel_types.OriginPropagationAutomatonCoherence -> "PropagationAutomatonCoherence"

let string_of_clause_time = function
  | Proof_kernel_types.CurrentTick -> "CUR"
  | Proof_kernel_types.PreviousTick -> "PRE"
  | Proof_kernel_types.StepTickContext -> "STEP"

let string_of_clause_desc = function
  | Proof_kernel_types.FactProgramState st -> "ProgramState = " ^ st
  | Proof_kernel_types.FactGuaranteeState i -> "GuaranteeState = " ^ string_of_int i
  | Proof_kernel_types.FactPhaseFormula f -> "Phase = " ^ Logic_pretty.string_of_fo f
  | Proof_kernel_types.FactFormula f -> Logic_pretty.string_of_fo f
  | Proof_kernel_types.FactFalse -> "false"

let string_of_clause_fact (fact : Proof_kernel_types.clause_fact_ir) =
  string_of_clause_time fact.time ^ " " ^ string_of_clause_desc fact.desc

let simplify_display_fo (f : Fo_formula.t) : Fo_formula.t =
  match Fo_z3_solver.simplify_fo_formula f with Some s -> s | None -> f

let string_of_display_rel_desc = function
  | Proof_kernel_types.RelFactProgramState _ | Proof_kernel_types.RelFactGuaranteeState _ -> None
  | Proof_kernel_types.RelFactPhaseFormula f ->
      let f = simplify_display_fo f in
      Some (Logic_pretty.string_of_fo f)
  | Proof_kernel_types.RelFactFormula f ->
      let f = simplify_display_fo f in
      Some (Logic_pretty.string_of_fo f)
  | Proof_kernel_types.RelFactFalse -> Some "false"

let simplify_formula_list (xs : string list) : string list =
  let xs = List.filter (fun s -> String.trim s <> "" && String.trim s <> "true") xs in
  if List.exists (fun s -> String.trim s = "false") xs then [ "false" ] else xs

let normalize_formula_lines (xs : string list) : string list =
  let xs = simplify_formula_list xs |> List.sort_uniq String.compare in
  match xs with [] -> [ "true" ] | _ -> xs

let formula_of_parts hyps concs =
  let hyps = simplify_formula_list hyps in
  let concs = simplify_formula_list concs in
  match (hyps, concs) with
  | [], [] -> "true"
  | [], xs -> String.concat " /\\ " xs
  | xs, [] -> String.concat " /\\ " xs
  | [ "false" ], _ -> "true"
  | xs, [ "false" ] -> "(" ^ String.concat " /\\ " xs ^ ") -> false"
  | xs, ys -> "(" ^ String.concat " /\\ " xs ^ ") -> (" ^ String.concat " /\\ " ys ^ ")"

let string_of_anchor = function
  | Proof_kernel_types.ClauseAnchorProductState st ->
      Printf.sprintf "state (P=%s,A=%d,G=%d)" st.prog_state st.assume_state_index
        st.guarantee_state_index
  | Proof_kernel_types.ClauseAnchorProductStep step ->
      Printf.sprintf "step (P=%s,A=%d,G=%d) -> (P=%s,A=%d,G=%d)"
        step.src.prog_state step.src.assume_state_index step.src.guarantee_state_index
        step.dst.prog_state step.dst.assume_state_index step.dst.guarantee_state_index

let render_transition_summary indent_level (t : Proof_kernel_types.reactive_transition_ir) =
  let guard =
    match t.guard_iexpr with
    | None -> "true"
    | Some g -> Logic_pretty.string_of_iexpr g
  in
  let render_fo_os label fs =
    match fs with
    | [] -> [ indent indent_level ^ label ^ ": none" ]
    | _ ->
        (indent indent_level ^ label ^ ":")
        :: List.map
             (fun (f : Ir.summary_formula) ->
               indent (indent_level + 1) ^ Logic_pretty.string_of_fo f.logic)
             fs
  in
  let body_lines =
    match t.body_stmts with
    | [] -> [ indent indent_level ^ "body: none" ]
    | xs ->
        (indent indent_level ^ "body:")
        :: List.map (fun s -> indent (indent_level + 1) ^ string_of_stmt s) xs
  in
  [ indent indent_level ^ Printf.sprintf "%s -> %s when %s" t.src_state t.dst_state guard ]
  @ render_fo_os "requires" t.requires
  @ render_fo_os "ensures" t.ensures
  @ body_lines

let render_clause_preview indent_level (clauses : Proof_kernel_types.generated_clause_ir list) =
  let by_origin =
    List.fold_left
      (fun acc (clause : Proof_kernel_types.generated_clause_ir) ->
        let key = string_of_clause_origin clause.origin in
        let prev = List.assoc_opt key acc |> Option.value ~default:[] in
        (key, prev @ [ clause ]) :: List.remove_assoc key acc)
      [] clauses
  in
  by_origin
  |> List.sort (fun (a, _) (b, _) -> String.compare a b)
  |> List.concat_map (fun (origin, xs) ->
         let header = indent indent_level ^ origin ^ ": " ^ string_of_int (List.length xs) in
         match xs with
         | [] -> [ header ]
         | (clause : Proof_kernel_types.generated_clause_ir) :: _ ->
             let hyps =
               clause.hypotheses |> List.map string_of_clause_fact |> String.concat "; "
             in
             let concs =
               clause.conclusions |> List.map string_of_clause_fact |> String.concat "; "
             in
             [
               header;
               indent (indent_level + 1) ^ "anchor: " ^ string_of_anchor clause.anchor;
               indent (indent_level + 1) ^ "hypotheses: " ^ hyps;
               indent (indent_level + 1) ^ "conclusions: " ^ concs;
             ])

let render_all_clauses indent_level (clauses : Proof_kernel_types.generated_clause_ir list) =
  match clauses with
  | [] -> [ indent indent_level ^ "none" ]
  | xs ->
      List.concat_map
        (fun (clause : Proof_kernel_types.generated_clause_ir) ->
          let hyps =
            match clause.hypotheses with
            | [] -> [ indent (indent_level + 2) ^ "none" ]
            | hs -> List.map (fun h -> indent (indent_level + 2) ^ string_of_clause_fact h) hs
          in
          let concs =
            match clause.conclusions with
            | [] -> [ indent (indent_level + 2) ^ "none" ]
            | cs -> List.map (fun c -> indent (indent_level + 2) ^ string_of_clause_fact c) cs
          in
          [
            indent indent_level ^ string_of_clause_origin clause.origin;
            indent (indent_level + 1) ^ "anchor: " ^ string_of_anchor clause.anchor;
            indent (indent_level + 1) ^ "hypotheses:";
          ]
          @ hyps
          @ [ indent (indent_level + 1) ^ "conclusions:" ]
          @ concs
          @ [ "" ])
        xs

let string_of_step_kind = function
  | Proof_kernel_types.StepSafe -> "Safe"
  | Proof_kernel_types.StepBadAssumption -> "BadAssumption"
  | Proof_kernel_types.StepBadGuarantee -> "BadGuarantee"

let string_of_step_origin = function
  | Proof_kernel_types.StepFromExplicitExploration -> "ExplicitExploration"
  | Proof_kernel_types.StepFromFallbackSynthesis -> "FallbackSynthesis"

let render_product_steps indent_level (steps : Proof_kernel_types.product_step_ir list) =
  match steps with
  | [] -> [ indent indent_level ^ "none" ]
  | xs ->
      List.concat_map
        (fun (step : Proof_kernel_types.product_step_ir) ->
          let src =
            Printf.sprintf "(P=%s,A=%d,G=%d)" step.src.prog_state step.src.assume_state_index
              step.src.guarantee_state_index
          in
          let dst =
            Printf.sprintf "(P=%s,A=%d,G=%d)" step.dst.prog_state step.dst.assume_state_index
              step.dst.guarantee_state_index
          in
          [
            indent indent_level ^ (src ^ " -> " ^ dst);
            indent (indent_level + 1) ^ "program transition: "
            ^ fst step.program_transition ^ " -> " ^ snd step.program_transition;
            indent (indent_level + 1) ^ "kind: " ^ string_of_step_kind step.step_kind;
            indent (indent_level + 1) ^ "origin: " ^ string_of_step_origin step.step_origin;
            indent (indent_level + 1) ^ "program guard: " ^ Logic_pretty.string_of_fo step.program_guard;
            indent (indent_level + 1) ^ "assume guard: " ^ Logic_pretty.string_of_fo step.assume_edge.guard;
            indent (indent_level + 1) ^ "guarantee guard: " ^ Logic_pretty.string_of_fo step.guarantee_edge.guard;
            "";
          ])
        xs

let render_node_summary (node : Proof_kernel_types.exported_node_summary_ir) =
  let sig_ = node.signature in
  let ir = node.normalized_ir in
  let header = [ "Node " ^ sig_.node_name ] in
  let signature_lines =
    [
      indent 1 ^ "signature";
      indent 2 ^ "inputs: "
      ^ (match sig_.inputs with [] -> "none" | xs -> String.concat ", " (List.map string_of_vdecl xs));
      indent 2 ^ "outputs: "
      ^ (match sig_.outputs with [] -> "none" | xs -> String.concat ", " (List.map string_of_vdecl xs));
      indent 2 ^ "locals: "
      ^ (match sig_.locals with [] -> "none" | xs -> String.concat ", " (List.map string_of_vdecl xs));
      indent 2 ^ "states: " ^ String.concat ", " sig_.states;
      indent 2 ^ "init: " ^ sig_.init_state;
    ]
  in
  let source_summaries =
    [
      indent 1 ^ "source summaries";
      (if node.assumes = [] then indent 2 ^ "requires: none" else indent 2 ^ "requires:");
    ]
    @ List.map (fun f -> indent 3 ^ Logic_pretty.string_of_ltl f) node.assumes
    @
    [
      (if node.guarantees = [] then indent 2 ^ "ensures: none" else indent 2 ^ "ensures:");
    ]
    @ List.map (fun f -> indent 3 ^ Logic_pretty.string_of_ltl f) node.guarantees
  in
  let transition_lines =
    [ indent 1 ^ "transition summaries" ]
    @ (match ir.reactive_program.transitions with
      | [] -> [ indent 2 ^ "none" ]
      | xs -> List.concat_map (render_transition_summary 2) xs)
  in
  let pre_k_lines =
    [ indent 1 ^ "temporal memory" ]
    @
    (match node.temporal_layout with
    | [] -> [ indent 2 ^ "pre_k: none" ]
    | xs ->
        [ indent 2 ^ "pre_k:" ]
        @ List.map
            (fun (h, info) ->
              indent 3 ^ Logic_pretty.string_of_hexpr h ^ " -> " ^ String.concat ", " info.Temporal_support.names)
            xs)
  in
  let step_counts =
    let safe, bad_a, bad_g =
      List.fold_left
        (fun (s, a, g) step ->
          match step.Proof_kernel_types.step_kind with
          | Proof_kernel_types.StepSafe -> (s + 1, a, g)
          | Proof_kernel_types.StepBadAssumption -> (s, a + 1, g)
          | Proof_kernel_types.StepBadGuarantee -> (s, a, g + 1))
        (0, 0, 0) ir.product_steps
    in
    [ indent 1 ^ "product";
      indent 2 ^ "coverage: "
      ^
      (match ir.product_coverage with
      | Proof_kernel_types.CoverageEmpty -> "empty"
      | Proof_kernel_types.CoverageExplicit -> "explicit"
      | Proof_kernel_types.CoverageFallback -> "fallback");
      indent 2 ^ "states: " ^ string_of_int (List.length ir.product_states);
      indent 2 ^ "steps: " ^ string_of_int (List.length ir.product_steps);
      indent 2 ^ "safe: " ^ string_of_int safe;
      indent 2 ^ "bad assumption: " ^ string_of_int bad_a;
      indent 2 ^ "bad guarantee: " ^ string_of_int bad_g;
    ]
  in
  let clause_lines =
    [ indent 1 ^ "kernel clauses" ]
    @ render_clause_preview 2 ir.historical_generated_clauses
  in
  String.concat "\n"
    (header @ signature_lines @ source_summaries @ transition_lines @ pre_k_lines
   @ step_counts @ clause_lines)

let render_summary (obj : t) : string =
  let metadata_lines =
    [
      "KOBJ Summary";
      indent 1 ^ "source: "
      ^
      (match obj.metadata.source_path with Some s -> s | None -> "<unknown>");
      indent 1
      ^ Printf.sprintf "format: %s v%d" obj.metadata.format obj.metadata.format_version;
      indent 1 ^ "imports: "
      ^
      (match obj.metadata.imports with [] -> "none" | xs -> String.concat ", " xs);
    ]
  in
  String.concat "\n\n" (String.concat "\n" metadata_lines :: List.map render_node_summary obj.nodes)

let render_clauses (obj : t) : string =
  let render_node (node : Proof_kernel_types.exported_node_summary_ir) =
    let header = [ "Node " ^ node.signature.node_name; indent 1 ^ "kernel clauses" ] in
    String.concat "\n" (header @ render_all_clauses 2 node.normalized_ir.historical_generated_clauses)
  in
  String.concat "\n\n" (List.map render_node obj.nodes)

let render_product (obj : t) : string =
  let render_node (node : Proof_kernel_types.exported_node_summary_ir) =
    let ir = node.normalized_ir in
    let header =
      [
        "Node " ^ node.signature.node_name;
        indent 1 ^ "coverage: "
        ^
        (match ir.product_coverage with
        | Proof_kernel_types.CoverageEmpty -> "empty"
        | Proof_kernel_types.CoverageExplicit -> "explicit"
        | Proof_kernel_types.CoverageFallback -> "fallback");
        indent 1 ^ "states: " ^ string_of_int (List.length ir.product_states);
        indent 1 ^ "steps: " ^ string_of_int (List.length ir.product_steps);
        indent 1 ^ "product steps";
      ]
    in
    String.concat "\n" (header @ render_product_steps 2 ir.product_steps)
  in
  String.concat "\n\n" (List.map render_node obj.nodes)

let render_product_summaries (obj : t) : string =
  let string_of_product_state (st : Proof_kernel_types.product_state_ir) =
    Printf.sprintf "(P=%s,A=%d,G=%d)" st.prog_state st.assume_state_index st.guarantee_state_index
  in
  let entry_clause_to_formula (clause : Proof_kernel_types.relational_generated_clause_ir) =
    let select fact =
      match fact.Proof_kernel_types.time with
      | Proof_kernel_types.PreviousTick | Proof_kernel_types.StepTickContext ->
          string_of_display_rel_desc fact.desc
      | Proof_kernel_types.CurrentTick -> None
    in
    formula_of_parts (List.filter_map select clause.hypotheses) (List.filter_map select clause.conclusions)
  in
  let post_clause_to_formula (clause : Proof_kernel_types.relational_generated_clause_ir) =
    let hyp fact =
      match fact.Proof_kernel_types.time with
      | Proof_kernel_types.StepTickContext ->
          string_of_display_rel_desc fact.desc
      | Proof_kernel_types.PreviousTick | Proof_kernel_types.CurrentTick -> None
    in
    let concl fact =
      match fact.Proof_kernel_types.time with
      | Proof_kernel_types.CurrentTick ->
          string_of_display_rel_desc fact.desc
      | Proof_kernel_types.PreviousTick | Proof_kernel_types.StepTickContext -> None
    in
    formula_of_parts (List.filter_map hyp clause.hypotheses) (List.filter_map concl clause.conclusions)
  in
  let render_code indent_level (transition : Proof_kernel_types.reactive_transition_ir) =
    let guard =
      match transition.guard_iexpr with
      | None -> "true"
      | Some g -> Logic_pretty.string_of_iexpr g
    in
    let body_lines =
      match transition.body_stmts with
      | [] -> [ indent (indent_level + 1) ^ "skip" ]
      | xs -> List.map (fun s -> indent (indent_level + 1) ^ string_of_stmt s) xs
    in
    [ indent indent_level ^ ("code:");
      indent (indent_level + 1)
      ^ Printf.sprintf "%s -> %s when %s" transition.src_state transition.dst_state guard;
    ]
    @ body_lines
  in
  let render_summary indent_level
      (transitions_by_id : (string, Proof_kernel_types.reactive_transition_ir) Hashtbl.t)
      (summary : Proof_kernel_types.proof_step_summary_ir) =
    let step =
      match summary.steps with
      | step :: _ -> step
      | [] -> failwith "Malformed proof-step summary: empty grouped steps"
    in
    let transition =
      match Hashtbl.find_opt transitions_by_id step.program_transition_id with
      | Some t -> t
      | None ->
          failwith
            (Printf.sprintf "Missing reactive transition '%s' for proof-step summary"
               step.program_transition_id)
    in
    let pre_formulas =
      match summary.entry_clauses with
      | [] -> [ "true" ]
      | xs -> normalize_formula_lines (List.map entry_clause_to_formula xs)
    in
    let post_formulas =
      match summary.clauses with
      | [] -> [ "true" ]
      | xs -> normalize_formula_lines (List.map post_clause_to_formula xs)
    in
    let grouped_steps =
      match summary.steps with
      | [] | [ _ ] -> []
      | xs ->
          let dsts =
            xs
            |> List.map (fun (step : Proof_kernel_types.product_step_ir) -> string_of_product_state step.dst)
            |> List.sort_uniq String.compare
          in
          [ indent (indent_level + 1) ^ "grouped destinations:";
            indent (indent_level + 2) ^ String.concat ", " dsts ]
    in
    [
      indent indent_level ^ "summary";
      indent (indent_level + 1)
      ^ (string_of_product_state step.src ^ " -> " ^ string_of_product_state step.dst);
      indent (indent_level + 1) ^ "kind: " ^ string_of_step_kind step.step_kind;
      indent (indent_level + 1) ^ "program transition id: " ^ step.program_transition_id;
      indent (indent_level + 1) ^ "{pre}";
    ]
    @ grouped_steps
    @ List.map (fun s -> indent (indent_level + 2) ^ s) pre_formulas
    @ render_code (indent_level + 1) transition
    @ [ indent (indent_level + 1) ^ "{post}" ]
    @ List.map (fun s -> indent (indent_level + 2) ^ s) post_formulas
    @ [ "" ]
  in
  let render_node (node : Proof_kernel_types.exported_node_summary_ir) =
    let ir = node.normalized_ir in
    let transitions_by_id = Hashtbl.create 16 in
    List.iter
      (fun (t : Proof_kernel_types.reactive_transition_ir) ->
        Hashtbl.replace transitions_by_id t.transition_id t)
      ir.reactive_program.transitions;
    let header =
      [
        "Node " ^ node.signature.node_name;
        indent 1 ^ "product automaton";
        indent 2 ^ "coverage: "
        ^
        (match ir.product_coverage with
        | Proof_kernel_types.CoverageEmpty -> "empty"
        | Proof_kernel_types.CoverageExplicit -> "explicit"
        | Proof_kernel_types.CoverageFallback -> "fallback");
        indent 2 ^ "states: " ^ string_of_int (List.length ir.product_states);
        indent 2 ^ "steps: " ^ string_of_int (List.length ir.product_steps);
        indent 2 ^ "product steps";
      ]
    in
    let summaries =
      [ indent 1 ^ "proof step summaries" ]
      @
      (match ir.proof_step_summaries with
      | [] -> [ indent 2 ^ "none" ]
      | xs -> List.concat_map (render_summary 2 transitions_by_id) xs)
    in
    String.concat "\n" (header @ render_product_steps 3 ir.product_steps @ [ "" ] @ summaries)
  in
  String.concat "\n\n" (List.map render_node obj.nodes)

let write_file ~path (obj : t) : (unit, string) result =
  try
    let oc = open_out path in
    Fun.protect
      ~finally:(fun () -> close_out oc)
      (fun () ->
        Yojson.Safe.pretty_to_channel oc (yojson_of_t obj);
        output_char oc '\n');
    Ok ()
  with exn -> Error (Printexc.to_string exn)

let read_file ~path : (t, string) result =
  try
    let json = Yojson.Safe.from_file path in
    match t_of_yojson json with
    | Error msg -> Error (Printf.sprintf "Invalid .kobj '%s': %s" path msg)
    | Ok obj ->
        if obj.metadata.format <> current_format then
          Error
            (Printf.sprintf "Unsupported object format '%s' in %s" obj.metadata.format path)
        else if obj.metadata.format_version <> current_version then
          Error
            (Printf.sprintf
               "Unsupported object version %d in %s (expected %d)"
               obj.metadata.format_version path current_version)
        else Ok obj
  with exn -> Error (Printexc.to_string exn)

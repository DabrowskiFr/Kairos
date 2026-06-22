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

open Core_syntax
open Core_syntax_builders
open Fo_time

module Abs = Ir
module StringSet = Set.Make (String)

type entry = {
  product_state : Abs.product_state;
  entry_fact : Core_syntax.hexpr;
  post_disjuncts : Core_syntax.hexpr list;
}

type t = {
  entries : entry list;
  by_state : (string, entry) Hashtbl.t;
}

let build_cache_limit = 64
let build_cache : (string, t) Hashtbl.t = Hashtbl.create 16

let simplify_fo (f : Core_syntax.hexpr) : Core_syntax.hexpr =
  Core_fo_simplifier.simplify f

let product_state_key (st : Abs.product_state) =
  Printf.sprintf "%s/a%d/g%d" st.prog_state st.assume_state_index
    st.guarantee_state_index

let formula_raw_key (f : Core_syntax.hexpr) : string =
  Core_fo_simplifier.key_of_hexpr f

let guard_expr_key = function
  | None -> "true"
  | Some guard -> guard |> hexpr_of_expr |> formula_raw_key

let transition_key (t : Abs.transition) =
  String.concat "|"
    [ t.src_state; t.dst_state; guard_expr_key t.guard_expr ]

let state_invariant_lookup (node : Abs.node_ir) :
    ident -> Core_syntax.hexpr list =
  let by_state = Hashtbl.create 16 in
  List.iter
    (fun (inv : Abs.state_invariant) ->
      let existing =
        Hashtbl.find_opt by_state inv.state |> Option.value ~default:[]
      in
      Hashtbl.replace by_state inv.state (inv.formula :: existing))
    node.source_info.state_invariants;
  fun state ->
    Hashtbl.find_opt by_state state
    |> Option.value ~default:[]
    |> List.sort_uniq Stdlib.compare

let build_cache_key (node : Abs.node_ir) : string =
  (* The characteristic analysis reads only the node signature, input names,
     invariants, product identity, program guards, and safe/unsafe product
     cases. Generated requires/ensures are deliberately absent so Pre and Post
     can reuse the same characteristics after earlier enrichment passes. *)
  let input_names =
    node.semantics.sem_inputs
    |> List.map (fun (v : vdecl) -> v.vname)
    |> List.sort_uniq String.compare
    |> String.concat ";"
  in
  let state_invariants =
    node.source_info.state_invariants
    |> List.map (fun (inv : Abs.state_invariant) ->
           String.concat ":" [ inv.state; formula_raw_key inv.formula ])
    |> List.sort_uniq String.compare
    |> String.concat ";"
  in
  let case_state_key dst guard =
    product_state_key dst ^ ":" ^ formula_raw_key guard
  in
  let summaries =
    node.summaries
    |> List.map (fun (pc : Abs.product_step_summary) ->
           let safe_cases =
             pc.safe_cases
             |> List.map (fun (case : Abs.safe_product_case) ->
                    case_state_key case.product_dst
                      case.admissible_guard.logic)
             |> List.sort_uniq String.compare
             |> String.concat ","
           in
           let unsafe_cases =
             pc.unsafe_cases
             |> List.map (fun (case : Abs.unsafe_product_case) ->
                    case_state_key case.product_dst
                      case.excluded_guard.logic)
             |> List.sort_uniq String.compare
             |> String.concat ","
           in
           String.concat "#"
             [
               product_state_key pc.identity.product_src;
               transition_key pc.identity.program_step;
               formula_raw_key pc.identity.assume_guard;
               safe_cases;
               unsafe_cases;
             ])
    |> List.sort_uniq String.compare
    |> String.concat "\n"
  in
  String.concat "\n"
    [
      node.semantics.sem_nname;
      node.semantics.sem_init_state;
      input_names;
      state_invariants;
      summaries;
    ]

let is_htrue (f : Core_syntax.hexpr) : bool =
  match (simplify_fo f).hexpr with HLitBool true -> true | _ -> false

let same_product_state (a : Abs.product_state) (b : Abs.product_state) : bool =
  String.equal a.prog_state b.prog_state
  && a.assume_state_index = b.assume_state_index
  && a.guarantee_state_index = b.guarantee_state_index

let formula_key (f : Core_syntax.hexpr) : string =
  Core_fo_simplifier.key_of_hexpr (simplify_fo f)

let same_formula (a : Core_syntax.hexpr) (b : Core_syntax.hexpr) : bool =
  String.equal (formula_key a) (formula_key b)

let flatten_bool (op : binop) (f : Core_syntax.hexpr) : Core_syntax.hexpr list =
  let rec loop acc h =
    match h.hexpr with
    | HBin (op', a, b) when op = op' -> loop (loop acc b) a
    | _ -> h :: acc
  in
  List.rev (loop [] (simplify_fo f))

let key_set_of_conjuncts (f : Core_syntax.hexpr) : StringSet.t =
  flatten_bool And f
  |> List.fold_left
       (fun acc conjunct -> StringSet.add (formula_key conjunct) acc)
       StringSet.empty

let contradictory_context (context : Core_syntax.hexpr list)
    (candidate : Core_syntax.hexpr) : bool =
  Fo_contradiction.contradictory_context context candidate

let dnf_subsumes ~(antecedent : Core_syntax.hexpr)
    ~(consequent : Core_syntax.hexpr) : bool =
  let antecedent_disjuncts = flatten_bool Or antecedent in
  let consequent_disjuncts = flatten_bool Or consequent in
  let consequent_cubes = List.map key_set_of_conjuncts consequent_disjuncts in
  List.for_all
    (fun antecedent_disjunct ->
      let antecedent_cube = key_set_of_conjuncts antecedent_disjunct in
      List.exists
        (fun consequent_cube ->
          StringSet.subset consequent_cube antecedent_cube)
        consequent_cubes)
    antecedent_disjuncts

let dedup_formulas (xs : Core_syntax.hexpr list) : Core_syntax.hexpr list =
  let keyed = List.map (fun f -> (formula_key f, simplify_fo f)) xs in
  keyed
  |> List.sort_uniq (fun (ka, _) (kb, _) -> String.compare ka kb)
  |> List.map snd

let disj_fo (fs : Core_syntax.hexpr list) : Core_syntax.hexpr option =
  match dedup_formulas fs with
  | [] -> None
  | f :: rest -> Some (List.fold_left mk_hor f rest |> simplify_fo)

let infer_initial_product_state (node : Abs.node_ir) : Abs.product_state =
  let candidates =
    node.summaries
    |> List.map (fun (pc : Abs.product_step_summary) -> pc.identity.product_src)
    |> List.filter (fun (st : Abs.product_state) ->
           String.equal st.prog_state node.semantics.sem_init_state)
    |> List.sort_uniq Stdlib.compare
  in
  match
    List.find_opt
      (fun (st : Abs.product_state) ->
        st.assume_state_index = 0 && st.guarantee_state_index = 0)
      candidates
  with
  | Some st -> st
  | None -> (
      match candidates with
      | st :: _ -> st
      | [] ->
          {
            Abs.prog_state = node.semantics.sem_init_state;
            assume_state_index = 0;
            guarantee_state_index = 0;
          })

let input_names (n : Abs.node_ir) : ident list =
  List.map (fun (v : vdecl) -> v.vname) n.semantics.sem_inputs

let is_input_of_node (n : Abs.node_ir) : ident -> bool =
  let names = input_names n in
  fun x -> List.mem x names

let guard_fo_of_transition (t : Abs.transition) : Core_syntax.hexpr =
  match t.guard_expr with
  | None -> mk_hbool true
  | Some guard -> hexpr_of_expr guard |> simplify_fo

let shift_formula_forward_non_inputs ~(is_input : ident -> bool)
    (f : Core_syntax.hexpr) : Core_syntax.hexpr =
  let rec go h =
    match h.hexpr with
    | HLitInt _ | HLitBool _ | HLitEnum _ -> h
    | HVar v -> if is_input v then h else mk_hpre_k v 1
    | HPreK (v, k) -> mk_hpre_k v (k + 1)
    | HPred (id, hs) -> with_hexpr_desc h (HPred (id, List.map go hs))
    | HFunCall (fn, hs) -> with_hexpr_desc h (HFunCall (fn, List.map go hs))
    | HUn (op, inner) -> with_hexpr_desc h (HUn (op, go inner))
    | HBin (op, a, b) -> with_hexpr_desc h (HBin (op, go a, go b))
    | HCmp (op, a, b) -> with_hexpr_desc h (HCmp (op, go a, go b))
  in
  go f

type incoming_entry = {
  dst : Abs.product_state;
  guard_formulas : Core_syntax.hexpr list;
  program_entry_formulas : Core_syntax.hexpr list;
  program_post_formulas : Core_syntax.hexpr list;
  has_noninitial_true_guard : bool;
}

let add_incoming ~src dst ~guard_formula ~program_entry_formula
    ~program_post_formula incoming =
  let noninitial_true_guard =
    is_htrue guard_formula && src.Abs.guarantee_state_index <> 0
  in
  let rec loop acc = function
    | [] ->
        List.rev
          ({
             dst;
             guard_formulas = [ guard_formula ];
             program_entry_formulas = [ program_entry_formula ];
             program_post_formulas = [ program_post_formula ];
             has_noninitial_true_guard = noninitial_true_guard;
           }
            :: acc)
    | entry :: rest when same_product_state dst entry.dst ->
        List.rev_append acc
          ({
             entry with
             guard_formulas = guard_formula :: entry.guard_formulas;
             program_entry_formulas =
               program_entry_formula :: entry.program_entry_formulas;
             program_post_formulas =
               program_post_formula :: entry.program_post_formulas;
             has_noninitial_true_guard =
               entry.has_noninitial_true_guard || noninitial_true_guard;
           }
            :: rest)
    | x :: rest -> loop (x :: acc) rest
  in
  loop [] incoming

let states_with_nontrivial_bad_guarantee_outgoing ~invariants_of_state
    (node : Abs.node_ir) :
    Abs.product_state list =
  node.summaries
  |> List.filter (fun (pc : Abs.product_step_summary) ->
         let state_invariants =
           invariants_of_state pc.identity.product_src.prog_state
         in
         List.exists
           (fun (case : Abs.unsafe_product_case) ->
             not
               (contradictory_context state_invariants
                  case.excluded_guard.logic))
           pc.unsafe_cases)
  |> List.map (fun (pc : Abs.product_step_summary) -> pc.identity.product_src)
  |> List.sort_uniq Stdlib.compare

let needs_program_characteristic
    ~(bad_guarantee_sources : Abs.product_state list)
    (st : Abs.product_state) : bool =
  List.exists (same_product_state st) bad_guarantee_sources

let build_table entries =
  let by_state = Hashtbl.create (List.length entries * 2 + 1) in
  List.iter
    (fun (entry : entry) ->
      Hashtbl.replace by_state (product_state_key entry.product_state) entry)
    entries;
  { entries; by_state }

let build_uncached ~(node : Abs.node_ir) : t =
  let is_input = is_input_of_node node in
  let initial_product_state = infer_initial_product_state node in
  let invariants_of_state = state_invariant_lookup node in
  let bad_guarantee_sources =
    states_with_nontrivial_bad_guarantee_outgoing ~invariants_of_state node
  in
  let incoming =
    List.fold_left
      (fun acc (pc : Abs.product_step_summary) ->
        let program_guard = guard_fo_of_transition pc.identity.program_step in
        List.fold_left
          (fun acc (case : Abs.safe_product_case) ->
            let program_entry_formula =
              mk_hand
                (shift_hexpr_forward_all program_guard)
                (shift_formula_forward_inputs ~is_input
                   case.admissible_guard.logic)
              |> simplify_fo
            in
            let program_post_formula =
              mk_hand
                (shift_formula_forward_non_inputs ~is_input program_guard)
                case.admissible_guard.logic
              |> simplify_fo
            in
            add_incoming ~src:pc.identity.product_src case.product_dst
              ~guard_formula:case.admissible_guard.logic
              ~program_entry_formula ~program_post_formula acc)
          acc pc.safe_cases)
      [] node.summaries
  in
  let entries =
    incoming
    |> List.filter_map (fun entry ->
           let dst = entry.dst in
           if same_product_state dst initial_product_state then None
           else
             let guard_disjuncts = dedup_formulas entry.guard_formulas in
             let use_program_characteristic =
               needs_program_characteristic ~bad_guarantee_sources dst
             in
             if use_program_characteristic then
               let entry_disjuncts = entry.program_entry_formulas in
               match disj_fo entry_disjuncts with
               | None -> None
               | Some entry_fact ->
                   let entry_fact = simplify_fo entry_fact in
                   if is_htrue entry_fact then None
                   else
                     let post_disjuncts =
                       entry.program_post_formulas |> dedup_formulas
                     in
                     Some { product_state = dst; entry_fact; post_disjuncts }
             else
               let post_disjuncts = guard_disjuncts in
               match disj_fo post_disjuncts with
               | None -> None
               | Some post_fact ->
                   let entry_fact =
                     shift_formula_forward_inputs ~is_input post_fact
                     |> simplify_fo
                   in
                   if is_htrue entry_fact then None
                   else Some { product_state = dst; entry_fact; post_disjuncts })
    |> List.sort_uniq Stdlib.compare
  in
  build_table entries

let build ~(node : Abs.node_ir) : t =
  let key = build_cache_key node in
  match Hashtbl.find_opt build_cache key with
  | Some cached -> cached
  | None ->
      let built = build_uncached ~node in
      if Hashtbl.length build_cache >= build_cache_limit then
        Hashtbl.clear build_cache;
      Hashtbl.replace build_cache key built;
      built

let entry_of_product_state (t : t) (st : Abs.product_state) : entry option =
  Hashtbl.find_opt t.by_state (product_state_key st)

let entry_facts_of_product_state (t : t) (st : Abs.product_state) :
    Core_syntax.hexpr list =
  match entry_of_product_state t st with
  | None -> []
  | Some entry -> [ entry.entry_fact ]

let formula_is_post_disjunct (entry : entry) (formula : Core_syntax.hexpr) :
    bool =
  let key = formula_key formula in
  List.exists
    (fun disjunct -> String.equal key (formula_key disjunct))
    entry.post_disjuncts

let preservation_ensures (t : t) ~(is_input : ident -> bool)
    (pc : Abs.product_step_summary) : Core_syntax.hexpr list =
  pc.safe_cases
  |> List.filter_map (fun (case : Abs.safe_product_case) ->
         match entry_of_product_state t case.product_dst with
         | None -> None
         | Some entry ->
             let post_fact = disj_fo entry.post_disjuncts in
             (match post_fact with
             | None -> None
             | Some post_fact ->
             if
               same_formula case.admissible_guard.logic post_fact
               || formula_is_post_disjunct entry case.admissible_guard.logic
               || dnf_subsumes ~antecedent:case.admissible_guard.logic
                    ~consequent:post_fact
             then None
             else
               Some (mk_himp case.admissible_guard.logic post_fact |> simplify_fo))
         )
  |> List.filter (fun f -> not (is_htrue f))
  |> List.sort_uniq Stdlib.compare

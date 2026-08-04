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
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

(** Proof-case decomposition is an optional proof-planning optimization, not part
    of the reference semantics.

    Every generated group is a conjunction of source guarantees, and the groups
    cover every source guarantee. Together with the fact that groups only
    contain source guarantees, this makes the conjunction of all generated
    groups equivalent to the source conjunction.

    [Monolithic] is the literal identity on the core-owned proof-case program.
    [Separate_guarantees] creates one case per source guarantee occurrence.
    [Split_multiple_weak_until] acts only when at least two distinct source
    guarantee occurrences contain weak-until. It creates one case for each such
    occurrence and, when needed, one case containing all remaining guarantees.
    This narrowly targets the product cost of multiple temporal automata without
    duplicating guarantees or inferring proof dependencies from their syntax. *)

type strategy =
  | Monolithic
  | Separate_guarantees
  | Split_multiple_weak_until

let rec ltl_contains_weak_until (formula : Core_syntax.ltl) : bool =
  match formula with
  | Core_syntax.LTrue | Core_syntax.LFalse | Core_syntax.LAtom _ -> false
  | Core_syntax.LNot a | Core_syntax.LX a | Core_syntax.LG a ->
      ltl_contains_weak_until a
  | Core_syntax.LW _ -> true
  | Core_syntax.LAnd (a, b)
  | Core_syntax.LOr (a, b)
  | Core_syntax.LImp (a, b) ->
      ltl_contains_weak_until a || ltl_contains_weak_until b

let guarantee_indices (node : Verification_model.node_model) :
    int list * int list =
  let indexed_guarantees =
    node.guarantees
    |> List.mapi (fun index formula ->
           (index, ltl_contains_weak_until formula))
  in
  List.fold_right
    (fun (index, has_weak_until) (weak_until, other) ->
      if has_weak_until then (index :: weak_until, other)
      else (weak_until, index :: other))
    indexed_guarantees ([], [])

let separate_guarantee_groups (node : Verification_model.node_model) :
    int list list option =
  match node.guarantees with
  | [] | [ _ ] -> None
  | guarantees ->
      Some
        (List.init (List.length guarantees) (fun guarantee_index ->
             [ guarantee_index ]))

let multiple_weak_until_groups (node : Verification_model.node_model) :
    int list list option =
  let weak_until, other = guarantee_indices node in
  match weak_until with
  | _ :: _ :: _ ->
      Some
        (List.map (fun index -> [ index ]) weak_until
        @ match other with [] -> [] | _ -> [ other ])
  | _ -> None

let fresh_proof_case_name used_names base group_index =
  let rec loop suffix =
    let candidate = Printf.sprintf "%s__kairos_g%d" base (group_index + suffix) in
    if Hashtbl.mem used_names candidate then loop (suffix + 1)
    else (
      Hashtbl.replace used_names candidate ();
      candidate)
  in
  loop 0

let identity_spec (node : Verification_model.node_model) :
    Proof_case_program.case_spec =
  {
    source_node_name = node.node_name;
    proof_case_node_name = node.node_name;
    guarantee_indices = List.init (List.length node.guarantees) Fun.id;
  }

let decompose_node
    ~(groups_of_node : Verification_model.node_model -> int list list option)
    ~(used_names : (string, unit) Hashtbl.t)
    (node : Verification_model.node_model) :
    (Proof_case_program.case_spec list, string) result =
  match groups_of_node node with
  | None -> Ok [ identity_spec node ]
  | Some groups ->
      groups
        |> List.mapi (fun idx members ->
               ({
                  Proof_case_program.source_node_name = node.node_name;
                  proof_case_node_name =
                    fresh_proof_case_name used_names node.node_name (idx + 1);
                  guarantee_indices = members;
                }
                 : Proof_case_program.case_spec))
      |> fun specs -> Ok specs

let apply_decomposition
    ~(groups_of_node : Verification_model.node_model -> int list list option)
    (proof_cases : Proof_case_program.t) :
    (Proof_case_program.t, string) result =
  let program = Proof_case_program.source_program proof_cases in
  let used_names = Hashtbl.create (List.length program * 2 + 1) in
  List.iter
    (fun (node : Verification_model.node_model) ->
      Hashtbl.replace used_names node.node_name ())
    program;
  let rec loop specs_acc = function
    | [] ->
        Proof_case_program.rebuild proof_cases (List.rev specs_acc)
    | node :: rest -> (
        match decompose_node ~groups_of_node ~used_names node with
        | Error _ as err -> err
        | Ok specs -> loop (List.rev_append specs specs_acc) rest)
  in
  loop [] program

let apply ~(strategy : strategy) (proof_cases : Proof_case_program.t) :
    (Proof_case_program.t, string) result =
  match strategy with
  | Monolithic -> Ok proof_cases
  | Separate_guarantees ->
      apply_decomposition ~groups_of_node:separate_guarantee_groups proof_cases
  | Split_multiple_weak_until ->
      apply_decomposition ~groups_of_node:multiple_weak_until_groups proof_cases

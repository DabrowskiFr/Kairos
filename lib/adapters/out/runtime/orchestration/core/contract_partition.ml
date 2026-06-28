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

module IntSet = Set.Make (Int)
module StringSet = Set.Make (String)

let ( let* ) = Result.bind

(** Runtime contract partitioning is a proof-structuring pass, not a contract
    rewriting pass.

    Every generated group is a conjunction of source guarantees, and the groups
    must cover every source guarantee. This gives the local semantic check we
    need for relative completeness of generation:

      if P satisfies the source guarantees, then P satisfies every generated
      group.

    When weak-until formulas are present, the reference transformation splits W
    guarantees and keeps internal auxiliary non-W guarantees with each W group.
    This part belongs to the proof-generation structure.

    Public non-W guarantees may be grouped, but not by blindly conjoining the
    whole public contract. The grouping key is structural: same temporal proof
    family and same footprint of variables constrained by the conclusion. This
    keeps the transformation compositional while avoiding a product automaton
    whose edges encode unrelated public guarantees in one large guard. The
    grouping is controlled by [Pipeline_types.proof_optimizations] and can be
    disabled for the Rocq-alignment baseline. *)

type guarantee_ref = {
  gid : int;
  formula : Core_syntax.ltl;
  has_weak_until : bool;
  is_internal_auxiliary : bool;
  public_non_w_family : string option;
}

type proof_group = {
  group_name : string;
  members : int list;
}

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

let rec vars_of_hexpr (acc : StringSet.t) (h : Core_syntax.hexpr) : StringSet.t =
  match h.hexpr with
  | Core_syntax.HLitInt _ | Core_syntax.HLitBool _ | Core_syntax.HLitEnum _ -> acc
  | Core_syntax.HVar name | Core_syntax.HPreK (name, _) -> StringSet.add name acc
  | Core_syntax.HPred (_, args) | Core_syntax.HFunCall (_, args) ->
      List.fold_left vars_of_hexpr acc args
  | Core_syntax.HUn (_, inner) -> vars_of_hexpr acc inner
  | Core_syntax.HBin (_, a, b) | Core_syntax.HCmp (_, a, b) ->
      vars_of_hexpr (vars_of_hexpr acc a) b

let rec vars_of_ltl (acc : StringSet.t) (formula : Core_syntax.ltl) : StringSet.t =
  match formula with
  | Core_syntax.LTrue | Core_syntax.LFalse -> acc
  | Core_syntax.LAtom (a, _, b) -> vars_of_hexpr (vars_of_hexpr acc a) b
  | Core_syntax.LNot a | Core_syntax.LX a | Core_syntax.LG a -> vars_of_ltl acc a
  | Core_syntax.LAnd (a, b)
  | Core_syntax.LOr (a, b)
  | Core_syntax.LImp (a, b)
  | Core_syntax.LW (a, b) ->
      vars_of_ltl (vars_of_ltl acc a) b

let private_vars_of_node (node : Verification_model.node_model) : StringSet.t =
  let public_ghosts = StringSet.of_list node.public_ghosts in
  node.locals @ node.ghosts
  |> List.fold_left
       (fun acc (v : Core_syntax.vdecl) ->
         if StringSet.mem v.vname public_ghosts then acc else StringSet.add v.vname acc)
       StringSet.empty

let mentions_private_var ~(private_vars : StringSet.t) (formula : Core_syntax.ltl) : bool =
  let formula_vars = vars_of_ltl StringSet.empty formula in
  not (StringSet.is_empty (StringSet.inter private_vars formula_vars))

let sorted_vars_key vars =
  match StringSet.elements vars with
  | [] -> "pure"
  | xs -> String.concat "_" xs

let rec strip_leading_x count (formula : Core_syntax.ltl) =
  match formula with
  | Core_syntax.LX inner -> strip_leading_x (count + 1) inner
  | _ -> (count, formula)

let strip_one_leading_x formula =
  match formula with Core_syntax.LX inner -> Some inner | _ -> None

let public_non_w_family_key (formula : Core_syntax.ltl) : string =
  let outer_delay, body = strip_leading_x 0 formula in
  let family, response_delay, focus =
    match body with
    | Core_syntax.LG (Core_syntax.LImp (_trigger, response)) -> begin
        match strip_one_leading_x response with
        | Some delayed_response ->
            ("next_response", outer_delay + 1, delayed_response)
        | None -> ("current_response", outer_delay, response)
      end
    | Core_syntax.LG invariant -> ("invariant", outer_delay, invariant)
    | _ -> ("other", outer_delay, body)
  in
  Printf.sprintf "%s_d%d_%s" family response_delay
    (sorted_vars_key (vars_of_ltl StringSet.empty focus))

let guarantee_refs (node : Verification_model.node_model) : guarantee_ref list =
  let private_vars = private_vars_of_node node in
  node.guarantees
  |> List.mapi (fun gid formula ->
         let has_weak_until = ltl_contains_weak_until formula in
         let is_internal_auxiliary =
           (not has_weak_until) && mentions_private_var ~private_vars formula
         in
         {
           gid;
           formula;
           has_weak_until;
           is_internal_auxiliary;
           public_non_w_family =
             (if (not has_weak_until) && not is_internal_auxiliary then
                Some (public_non_w_family_key formula)
              else None);
         })

let build_groups ~(proof_optimizations : Pipeline_types.proof_optimizations)
    (refs : guarantee_ref list) : proof_group list =
  if not (List.exists (fun g -> g.has_weak_until) refs) then
    match refs with
    | [] -> []
    | _ -> [ { group_name = "all"; members = List.map (fun g -> g.gid) refs } ]
  else
    let auxiliary_members =
      refs
      |> List.filter (fun g -> g.is_internal_auxiliary)
      |> List.map (fun g -> g.gid)
    in
    let auxiliary_group =
      match auxiliary_members with
      | [] -> []
      | members ->
          [
            {
              group_name = "auxiliary";
              members = List.sort_uniq Int.compare members;
            };
          ]
    in
    let w_groups =
      refs
      |> List.filter (fun g -> g.has_weak_until)
      |> List.map (fun g ->
             {
               group_name = Printf.sprintf "g%d" (g.gid + 1);
               members = List.sort_uniq Int.compare (auxiliary_members @ [ g.gid ]);
             })
    in
    let public_non_w_groups =
      if proof_optimizations.group_public_non_w_guarantees then
        let add_ref groups g =
          match g.public_non_w_family with
          | None -> groups
          | Some family ->
              let previous = List.assoc_opt family groups |> Option.value ~default:[] in
              (family, g.gid :: previous) :: List.remove_assoc family groups
        in
        refs
        |> List.filter (fun g -> (not g.has_weak_until) && not g.is_internal_auxiliary)
        |> List.fold_left add_ref []
        |> List.sort (fun (a, _) (b, _) -> String.compare a b)
        |> List.mapi (fun idx (family, members) ->
               {
                 group_name = Printf.sprintf "public_non_w_%02d_%s" (idx + 1) family;
                 members = List.sort_uniq Int.compare members;
               })
      else
        refs
        |> List.filter (fun g -> (not g.has_weak_until) && not g.is_internal_auxiliary)
        |> List.map (fun g ->
               {
                 group_name = Printf.sprintf "g%d" (g.gid + 1);
                 members = [ g.gid ];
               })
    in
    auxiliary_group @ w_groups @ public_non_w_groups

let validate_groups ~(node_name : string) ~(guarantee_count : int) (groups : proof_group list) :
    (unit, string) result =
  let source_ids = List.init guarantee_count (fun i -> i) |> IntSet.of_list in
  let validate_group group =
    match group.members with
    | [] ->
        Error
          (Printf.sprintf "contract partition for node '%s' produced empty group '%s'"
             node_name group.group_name)
    | members ->
        let member_set = IntSet.of_list members in
        if not (IntSet.subset member_set source_ids) then
          Error
            (Printf.sprintf
               "contract partition for node '%s' produced group '%s' with non-source guarantee id"
               node_name group.group_name)
        else Ok ()
  in
  let rec validate_all = function
    | [] -> Ok ()
    | group :: rest -> (
        match validate_group group with
        | Error _ as err -> err
        | Ok () -> validate_all rest)
  in
  match validate_all groups with
  | Error _ as err -> err
  | Ok () ->
      let covered =
        groups
        |> List.fold_left
             (fun acc group -> List.fold_left (fun acc id -> IntSet.add id acc) acc group.members)
             IntSet.empty
      in
      if IntSet.equal covered source_ids then Ok ()
      else
        Error
          (Printf.sprintf
             "contract partition for node '%s' does not cover all source guarantees"
             node_name)

let group_formulas ~(source : Core_syntax.ltl array) (group : proof_group) :
    Core_syntax.ltl list =
  List.map (Array.get source) group.members

let fresh_runtime_name used_names base group_index =
  let rec loop suffix =
    let candidate = Printf.sprintf "%s__kairos_g%d" base (group_index + suffix) in
    if Hashtbl.mem used_names candidate then loop (suffix + 1)
    else (
      Hashtbl.replace used_names candidate ();
      candidate)
  in
  loop 0

let partition_node ~(proof_optimizations : Pipeline_types.proof_optimizations)
    ~(used_names : (string, unit) Hashtbl.t)
    (node : Verification_model.node_model) :
    (Verification_model.node_model list, string) result =
  match node.guarantees with
  | [] | [ _ ] -> Ok [ node ]
  | guarantees ->
      let refs = guarantee_refs node in
      let groups = build_groups ~proof_optimizations refs in
      let guarantee_count = List.length guarantees in
      let* () = validate_groups ~node_name:node.node_name ~guarantee_count groups in
      let source = Array.of_list guarantees in
      if List.length groups = 1 then
        Ok [ node ]
      else
        groups
        |> List.mapi (fun idx group ->
               {
                 node with
                 node_name = fresh_runtime_name used_names node.node_name (idx + 1);
                 guarantees = group_formulas ~source group;
               })
        |> fun nodes -> Ok nodes

let partition_program
    ?(proof_optimizations = Pipeline_types.default_proof_optimizations)
    (program : Verification_model.program_model) :
    (Verification_model.program_model, string) result =
  let used_names = Hashtbl.create (List.length program * 2 + 1) in
  List.iter
    (fun (node : Verification_model.node_model) ->
      Hashtbl.replace used_names node.node_name ())
    program;
  let rec loop acc = function
    | [] -> Ok (List.rev acc)
    | node :: rest -> (
        match partition_node ~proof_optimizations ~used_names node with
        | Error _ as err -> err
        | Ok nodes -> loop (List.rev_append nodes acc) rest)
  in
  loop [] program

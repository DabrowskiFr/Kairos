(*---------------------------------------------------------------------------
 * Tempo - synchronous runtime for OCaml
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

open Ast

let shift_hexpr_forward ~(init_for_var:ident -> iexpr) ~(is_input:ident -> bool)
  (h:hexpr) : hexpr =
  match h with
  | HNow (IVar v) when is_input v ->
      HPreK (IVar v, init_for_var v, 1)
  | HNow _ -> h
  | HPre (IVar v, init_opt) ->
      let init = Option.value init_opt ~default:(init_for_var v) in
      HPreK (IVar v, init, 2)
  | HPre (e, Some init) ->
      HPreK (e, init, 2)
  | HPre (e, None) ->
      HPre (e, None)
  | HPreK (e, init, k) ->
      HPreK (e, init, k + 1)
  | HFold _ -> h

let rec shift_fo_forward_inputs ~(init_for_var:ident -> iexpr)
  ~(is_input:ident -> bool) (f:fo) : fo =
  match f with
  | FTrue | FFalse -> f
  | FNot a -> FNot (shift_fo_forward_inputs ~init_for_var ~is_input a)
  | FAnd (a, b) ->
      FAnd (shift_fo_forward_inputs ~init_for_var ~is_input a,
            shift_fo_forward_inputs ~init_for_var ~is_input b)
  | FOr (a, b) ->
      FOr (shift_fo_forward_inputs ~init_for_var ~is_input a,
           shift_fo_forward_inputs ~init_for_var ~is_input b)
  | FImp (a, b) ->
      FImp (shift_fo_forward_inputs ~init_for_var ~is_input a,
            shift_fo_forward_inputs ~init_for_var ~is_input b)
  | FRel (h1, r, h2) ->
      FRel (shift_hexpr_forward ~init_for_var ~is_input h1, r,
            shift_hexpr_forward ~init_for_var ~is_input h2)
  | FPred (id, hs) ->
      FPred (id, List.map (shift_hexpr_forward ~init_for_var ~is_input) hs)

let[@warning "-32"] rec shift_ltl_forward_inputs ~(init_for_var:ident -> iexpr)
  ~(is_input:ident -> bool) (f:ltl) : ltl =
  match f with
  | LTrue | LFalse -> f
  | LNot a -> LNot (shift_ltl_forward_inputs ~init_for_var ~is_input a)
  | LAnd (a, b) ->
      LAnd (shift_ltl_forward_inputs ~init_for_var ~is_input a,
            shift_ltl_forward_inputs ~init_for_var ~is_input b)
  | LOr (a, b) ->
      LOr (shift_ltl_forward_inputs ~init_for_var ~is_input a,
           shift_ltl_forward_inputs ~init_for_var ~is_input b)
  | LImp (a, b) ->
      LImp (shift_ltl_forward_inputs ~init_for_var ~is_input a,
            shift_ltl_forward_inputs ~init_for_var ~is_input b)
  | LX a -> LX (shift_ltl_forward_inputs ~init_for_var ~is_input a)
  | LG a -> LG (shift_ltl_forward_inputs ~init_for_var ~is_input a)
  | LAtom f -> LAtom (shift_fo_forward_inputs ~init_for_var ~is_input f)

let conj_fo (fs:fo list) : fo option =
  match fs with
  | [] -> None
  | f :: rest -> Some (List.fold_left (fun acc x -> FAnd (acc, x)) f rest)

let add_post_for_next_pre (n:user_node) : internal_node =
  let init_for_var =
    let table =
      List.map (fun v -> (v.vname, v.vty)) (n.inputs @ n.locals @ n.outputs)
    in
    fun v ->
      match List.assoc_opt v table with
      | Some TBool -> ILitBool false
      | Some TInt -> ILitInt 0
      | Some TReal -> ILitInt 0
      | Some (TCustom _) | None -> ILitInt 0
  in
  let succ_requires_by_state : (ident, fo list) Hashtbl.t = Hashtbl.create 16 in
  List.iter
    (fun (t:transition) ->
      List.iter
        (fun f ->
          let existing =
            Hashtbl.find_opt succ_requires_by_state t.src
            |> Option.value ~default:[]
          in
          Hashtbl.replace succ_requires_by_state t.src (f :: existing))
        t.requires)
    n.trans;
  let uniq lst =
    List.sort_uniq compare lst
  in
  let trans =
    List.map
      (fun (t:transition) ->
        let succ_reqs =
          Hashtbl.find_opt succ_requires_by_state t.dst
          |> Option.value ~default:[]
          |> uniq
        in
        let ensures_all = t.ensures in
        let new_lemmas =
          match conj_fo ensures_all with
          | None -> []
          | Some ensures_conj ->
              let is_input v = List.exists (fun vi -> vi.vname = v) n.inputs in
              let ensures_shifted =
                shift_fo_forward_inputs ~init_for_var ~is_input ensures_conj
              in
              let has_lemma f =
                List.exists
                  (fun f' -> f' = f)
                  t.lemmas
              in
              succ_reqs
              |> List.map (fun req -> FImp (ensures_shifted, req))
              |> List.filter (fun f -> not (has_lemma f))
              |> List.map (fun f -> f)
        in
        if new_lemmas = [] then t
        else { t with lemmas = t.lemmas @ new_lemmas })
      n.trans
  in
  { n with trans }

let add_post_for_next_pre_program (p:user_program) : internal_program =
  List.map add_post_for_next_pre p

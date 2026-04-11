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

type temporal_binding = {
  source_hexpr : Core_syntax.hexpr;
  slot_names : Core_syntax.ident list;
}

let temporal_bindings_of_pre_k_map ~(pre_k_map : (hexpr * Temporal_support.pre_k_info) list) :
    temporal_binding list =
  List.map
    (fun (source_hexpr, info) ->
      let slot_names =
        match source_hexpr.hexpr with
        | HPreK (_, k) when k > 0 && k <= List.length info.Temporal_support.names ->
            [ List.nth info.Temporal_support.names (k - 1) ]
        | HPreK _ -> []
        | _ -> info.Temporal_support.names
      in
      { source_hexpr; slot_names })
    pre_k_map

let latest_temporal_slot ~(temporal_bindings : temporal_binding list) (h : hexpr) : ident option =
  temporal_bindings
  |> List.find_map (fun binding ->
         if binding.source_hexpr = h then
           match List.rev binding.slot_names with
           | name :: _ -> Some name
           | [] -> None
         else None)

let rec hexpr_to_expr_with_temporal_bindings ~(inputs : ident list) ~(var_types : (ident * ty) list)
    ~(temporal_bindings : temporal_binding list) (h : hexpr) : expr option =
  let _ = (inputs, var_types) in
  let loc = h.loc in
  match h.hexpr with
  | HLitInt n -> Some { expr = ELitInt n; loc }
  | HLitBool b -> Some { expr = ELitBool b; loc }
  | HVar v -> Some { expr = EVar v; loc }
  | HPreK _ -> begin
      match latest_temporal_slot ~temporal_bindings h with
      | Some name -> Some { expr = EVar name; loc }
      | None -> None
    end
  | HPred _ -> None
  | HUn (op, inner) ->
      Option.map (fun e -> { expr = EUn (op, e); loc })
        (hexpr_to_expr_with_temporal_bindings ~inputs ~var_types ~temporal_bindings inner)
  | HBin (op, a, b) -> begin
      match
        ( hexpr_to_expr_with_temporal_bindings ~inputs ~var_types ~temporal_bindings a,
          hexpr_to_expr_with_temporal_bindings ~inputs ~var_types ~temporal_bindings b )
      with
      | Some a', Some b' -> Some { expr = EBin (op, a', b'); loc }
      | _ -> None
    end
  | HCmp (op, a, b) -> begin
      match
        ( hexpr_to_expr_with_temporal_bindings ~inputs ~var_types ~temporal_bindings a,
          hexpr_to_expr_with_temporal_bindings ~inputs ~var_types ~temporal_bindings b )
      with
      | Some a', Some b' -> Some { expr = ECmp (op, a', b'); loc }
      | _ -> None
    end

let hexpr_to_expr ~(inputs : ident list) ~(var_types : (ident * ty) list)
    ~(pre_k_map : (hexpr * Temporal_support.pre_k_info) list) (h : hexpr) : expr option =
  hexpr_to_expr_with_temporal_bindings ~inputs ~var_types
    ~temporal_bindings:(temporal_bindings_of_pre_k_map ~pre_k_map) h

let rec lower_hexpr_temporal_bindings ~(temporal_bindings : temporal_binding list) (h : hexpr) :
    hexpr option =
  let loc = h.loc in
  match h.hexpr with
  | HLitInt _ | HLitBool _ | HVar _ -> Some h
  | HPreK _ -> begin
      match latest_temporal_slot ~temporal_bindings h with
      | Some name -> Some { hexpr = HVar name; loc }
      | None -> None
    end
  | HPred (id, hs) ->
      let rec lower_args acc = function
        | [] -> Some (List.rev acc)
        | x :: xs -> (
            match lower_hexpr_temporal_bindings ~temporal_bindings x with
            | None -> None
            | Some x' -> lower_args (x' :: acc) xs)
      in
      Option.map (fun hs' -> { hexpr = HPred (id, hs'); loc }) (lower_args [] hs)
  | HUn (op, inner) ->
      Option.map (fun inner' -> { hexpr = HUn (op, inner'); loc })
        (lower_hexpr_temporal_bindings ~temporal_bindings inner)
  | HBin (op, a, b) -> begin
      match
        ( lower_hexpr_temporal_bindings ~temporal_bindings a,
          lower_hexpr_temporal_bindings ~temporal_bindings b )
      with
      | Some a', Some b' -> Some { hexpr = HBin (op, a', b'); loc }
      | _ -> None
    end
  | HCmp (op, a, b) -> begin
      match
        ( lower_hexpr_temporal_bindings ~temporal_bindings a,
          lower_hexpr_temporal_bindings ~temporal_bindings b )
      with
      | Some a', Some b' -> Some { hexpr = HCmp (op, a', b'); loc }
      | _ -> None
    end

let lower_hexpr_pre_k ~(pre_k_map : (hexpr * Temporal_support.pre_k_info) list) (h : hexpr) : hexpr option =
  lower_hexpr_temporal_bindings ~temporal_bindings:(temporal_bindings_of_pre_k_map ~pre_k_map) h

let lower_fo_formula_temporal_bindings ~(temporal_bindings : temporal_binding list)
    (f : Core_syntax.hexpr) : Core_syntax.hexpr option =
  lower_hexpr_temporal_bindings ~temporal_bindings f

let lower_fo_formula_pre_k ~(pre_k_map : (hexpr * Temporal_support.pre_k_info) list)
    (f : Core_syntax.hexpr) : Core_syntax.hexpr option =
  lower_fo_formula_temporal_bindings ~temporal_bindings:(temporal_bindings_of_pre_k_map ~pre_k_map) f

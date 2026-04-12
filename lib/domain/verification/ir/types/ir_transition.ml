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
open Ast

type guard_formula =
  | GTrue
  | GFalse
  | GExpr of expr

let of_ast_transition (t : Ast.transition) : Ir.transition =
  {
    src_state = t.src;
    dst_state = t.dst;
    guard_expr = t.guard;
    body_stmts = t.body;
  }

let guard_formula_of_expr (e : expr) : guard_formula =
  match e.expr with
  | ELitBool true -> GTrue
  | ELitBool false -> GFalse
  | _ -> GExpr e

let guard_formula_of_guard = function
  | None -> GTrue
  | Some g -> guard_formula_of_expr g

let expr_of_formula = function
  | GExpr e -> e
  | GTrue -> Core_syntax_builders.mk_bool true
  | GFalse -> Core_syntax_builders.mk_bool false

let guard_of_formula = function
  | GTrue -> None
  | GFalse -> Some (Core_syntax_builders.mk_bool false)
  | GExpr e -> Some e

let not_formula = function
  | GTrue -> GFalse
  | GFalse -> GTrue
  | GExpr e -> GExpr (Core_syntax_builders.mk_expr (EUn (Not, e)))

let and_formula a b =
  match (a, b) with
  | GFalse, _ | _, GFalse -> GFalse
  | GTrue, x | x, GTrue -> x
  | _ ->
      GExpr
        (Core_syntax_builders.mk_expr
           (EBin (And, expr_of_formula a, expr_of_formula b)))

let or_formula a b =
  match (a, b) with
  | GTrue, _ | _, GTrue -> GTrue
  | GFalse, x | x, GFalse -> x
  | _ ->
      GExpr
        (Core_syntax_builders.mk_expr
           (EBin (Or, expr_of_formula a, expr_of_formula b)))

let prioritized_program_transitions_of_ast (transitions : Ast.transition list) : Ir.transition list =
  let previous_guards_by_src : (ident, guard_formula) Hashtbl.t = Hashtbl.create 16 in
  transitions
  |> List.map (fun (t : Ast.transition) ->
         let original_guard = guard_formula_of_guard t.guard in
         let previous_guard =
           Hashtbl.find_opt previous_guards_by_src t.src |> Option.value ~default:GFalse
         in
         let effective_guard = and_formula original_guard (not_formula previous_guard) in
         let updated_previous_guard = or_formula previous_guard original_guard in
         Hashtbl.replace previous_guards_by_src t.src updated_previous_guard;
         let base = of_ast_transition t in
         ({ base with guard_expr = guard_of_formula effective_guard } : Ir.transition))

let prioritized_program_transitions_of_node (node : Ast.node) : Ir.transition list =
  prioritized_program_transitions_of_ast node.semantics.sem_trans

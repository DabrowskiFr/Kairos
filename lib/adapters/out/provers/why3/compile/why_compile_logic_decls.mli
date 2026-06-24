(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frederic Dabrowski
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

(** Why3 logical declarations and small port conversions. *)

val logic_getter_decl :
  env:Why_compile_expr.env -> Core_syntax.ident -> Core_syntax.ty -> Why3.Ptree.decl

val logic_bool_pred_decl :
  env:Why_compile_expr.env ->
  input_ports:Why_runtime_view.port_view list ->
  name:string ->
  formula:Core_syntax.hexpr ->
  Why3.Ptree.decl

val logic_bool_pred_decl_with_params :
  env:Why_compile_expr.env ->
  params:(Core_syntax.ident * Why3.Ptree.pty) list ->
  name:string ->
  formula:Core_syntax.hexpr ->
  Why3.Ptree.decl

val logic_bool_pred_decl_with_body :
  use_self:bool ->
  params:(Core_syntax.ident * Why3.Ptree.pty) list ->
  name:string ->
  body:Why3.Ptree.term ->
  Why3.Ptree.decl

val port_view_to_vdecl : Why_runtime_view.port_view -> Core_syntax.vdecl

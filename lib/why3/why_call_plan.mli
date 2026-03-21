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

(** Plans helper calls and call-site-specific proof obligations in Why3. *)

type compiled_call_plan = {
  let_bindings : (Why3.Ptree.ident * Why3.Ptree.expr) list;
  pre_asserts : Why3.Ptree.term list;
  output_post_terms : (Why3.Ptree.ident * Why3.Ptree.term list) list;
  any_pattern : Why3.Ptree.pattern;
  any_return_pty : Why3.Ptree.pty option;
  any_post : (Why3.Loc.position * (Why3.Ptree.pattern * Why3.Ptree.term) list) list;
  next_instance_id : Why3.Ptree.ident;
  output_ids : Why3.Ptree.ident list;
  callee_outputs : Why_runtime_view.port_view list;
  callee_output_names : Ast.ident list;
}

val build_call_asserts :
  env:Support.env ->
  caller_runtime:Why_runtime_view.t ->
  (Ast.ident * Ast.ident * Ast.iexpr list * Ast.ident list -> compiled_call_plan option)

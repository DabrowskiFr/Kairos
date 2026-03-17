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

(* {1 Statement Compilation} *)

(* Compile a sequence of statements to a Why3 expression. *)
val compile_seq :
  Support.env ->
  (Ast.ident * Ast.ident * Ast.iexpr list * Ast.ident list ->
  Why_call_plan.compiled_call_plan option) ->
  Why3.Ptree.term list ->
  Why_runtime_view.runtime_action_view list ->
  Why3.Ptree.expr

(* {1 Transition Compilation} *)
(* Compile a branch for a single state (pattern match arm). *)
val compile_state_branch :
  Support.env ->
  (Ast.ident * Ast.ident * Ast.iexpr list * Ast.ident list ->
  Why_call_plan.compiled_call_plan option) ->
  (Ast.ident * Why3.Ptree.term list) list ->
  (Ast.ident * Why3.Ptree.term list) list ->
  Ast.ident ->
  Why_runtime_view.runtime_transition_view list ->
  Why3.Ptree.reg_branch

(* Compile a set of transitions into a Why3 expression. *)
val compile_transitions :
  Support.env ->
  (Ast.ident * Ast.ident * Ast.iexpr list * Ast.ident list ->
  Why_call_plan.compiled_call_plan option) ->
  (Ast.ident * Why3.Ptree.term list) list ->
  (Ast.ident * Why3.Ptree.term list) list ->
  Why_runtime_view.state_branch_view list ->
  Why3.Ptree.expr

(* Compile the runtime view into the body of `step`. *)
val compile_runtime_view :
  Support.env ->
  (Ast.ident * Ast.ident * Ast.iexpr list * Ast.ident list ->
  Why_call_plan.compiled_call_plan option) ->
  (Ast.ident * Why3.Ptree.term list) list ->
  (Ast.ident * Why3.Ptree.term list) list ->
  Why_runtime_view.t ->
  Why3.Ptree.expr
(* {1 Node Compilation} *)

(* Pre/post labels attached to generated specs (for highlighting). *)
type spec_groups = { pre_labels : string list; post_labels : string list }

(* Raw comment payloads used to emit VC/goal comments. *)
type comment_specs =
  Ast.fo_ltl list * Ast.fo_ltl list * Ast.transition list * (string * string * string) list

(* In‑memory Why3 representation of a full program. *)
type program_ast = { mlw : Why3.Ptree.mlw_file; module_info : (string * spec_groups) list }

(* Compile a single node into Why3 declarations. *)
val compile_node :
  prefix_fields:bool ->
  ?comment_specs:comment_specs ->
  ?kernel_ir:Product_kernel_ir.node_ir ->
  external_summaries:Product_kernel_ir.exported_node_summary_ir list ->
  Ast.node list ->
  Ast.node ->
  Why3.Ptree.ident * Why3.Ptree.qualid option * Why3.Ptree.decl list * string * spec_groups

(* Compile a full program to textual Why3. *)
val compile_program :
  ?prefix_fields:bool -> ?comment_map:(Ast.ident * comment_specs) list -> Ast.program -> string

(* Compile a full program to an in‑memory Why3 AST. *)
val compile_program_ast :
  ?prefix_fields:bool ->
  ?comment_map:(Ast.ident * comment_specs) list ->
  ?kernel_ir_map:(Ast.ident * Product_kernel_ir.node_ir) list ->
  ?external_summaries:(Ast.ident * Product_kernel_ir.exported_node_summary_ir) list ->
  Ast.program ->
  program_ast

(* IR path: compile a full list of summaries to a Why3 program AST. *)
val compile_program_ast_from_summaries :
  ?prefix_fields:bool ->
  ?comment_map:(Ast.ident * comment_specs) list ->
  ?kernel_ir_map:(Ast.ident * Product_kernel_ir.node_ir) list ->
  ?external_summaries:Product_kernel_ir.exported_node_summary_ir list ->
  Product_kernel_ir.exported_node_summary_ir list ->
  program_ast

(* Render a Why3 AST to text. *)
val emit_program_ast : program_ast -> string

(* Render a Why3 AST to text and return declaration spans. *)
val emit_program_ast_with_spans : program_ast -> string * (int * (int * int)) list

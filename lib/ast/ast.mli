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

(* {1 AST Overview}

   This module defines the core AST used across all passes. The design is: {ul {- immutable records
   with small, predictable helpers;} {- explicit provenance on FO formulas (requires/ensures);} {-
   node/transition attributes carry uids + invariants + injected stmts;} {- per‑pass metadata is
   kept in [Stage_info], not inside the AST;} {- constructors and provenance helpers live in
   [Ast_builders] / [Ast_provenance];} {- small utilities live in [Ast_utils].} {- a single program
   type (list of nodes) shared by all stages.}}

   Post‑parse modifications: {ul {- FO contracts are wrapped with provenance and ids ([fo_o]);} {-
   attributes are filled/updated by passes (uids, invariants, ghost/monitor).} {- LTL contracts
   (assumes/guarantees) remain plain [fo_ltl] in the pipeline.}}

   Quick map (structural core): {v program -> node -> transition -> stmt \-> assumes/guarantees
   (fo_ltl) \-> requires/ensures (fo_o -> fo) v}

   Conceptual split used by the formalization:
   - a node carries a {i program part} (syntax + transition semantics),
   - and a {i specification part} (assumptions, guarantees, state invariants).
   The concrete AST still stores both on the same record for pipeline convenience,
   but accessors below expose the split explicitly.

   Sections below follow the language structure: expressions, formulas, statements, program
   structure, and utilities. *)

(* {1 Core Types} *)

(* Identifier used for variables, nodes, states, etc. *)
type ident = string [@@deriving yojson]

(* Simple types for variables and expressions. *)
type ty = TInt | TBool | TReal | TCustom of string [@@deriving yojson]

(* Binary operators for expressions. Includes arithmetic, comparisons, and boolean connectives used
   at the expression level. *)
type binop = Add | Sub | Mul | Div | Eq | Neq | Lt | Le | Gt | Ge | And | Or [@@deriving yojson]

(* Unary operators for expressions. *)
type unop = Neg | Not [@@deriving yojson]

(* Source location (1‑based lines/columns). *)
type loc = { line : int; col : int; line_end : int; col_end : int } [@@deriving yojson]

(* {2 Expressions} Immediate expressions (current instant). *)
type iexpr = { iexpr : iexpr_desc; loc : loc option }
[@@deriving yojson]

and iexpr_desc =
  | ILitInt of int
  | ILitBool of bool
  | IVar of ident
  | IBin of binop * iexpr * iexpr
  | IUn of unop * iexpr
  | IPar of iexpr
[@@deriving yojson]

(* {2 Historical expressions} Expressions with temporal operators (pre‑k). *)
type hexpr = HNow of iexpr | HPreK of iexpr * int [@@deriving yojson]

(* Relational operators for FO formulas (over [hexpr]). *)
type relop = REq | RNeq | RLt | RLe | RGt | RGe [@@deriving yojson]

(* {1 Logical Formulas & Provenance} *)
(* First‑order formulas used in requires/ensures and VC generation. *)
type fo =
  | FRel of hexpr * relop * hexpr
  | FPred of ident * hexpr list
[@@deriving yojson]

(* Generic LTL (linear‑time temporal logic) formula over atoms of type ['a]. *)
type 'a ltl =
  | LTrue
  | LFalse
  | LAtom of 'a
  | LNot of 'a ltl
  | LAnd of 'a ltl * 'a ltl
  | LOr of 'a ltl * 'a ltl
  | LImp of 'a ltl * 'a ltl
  | LX of 'a ltl
  | LG of 'a ltl
  | LW of 'a ltl * 'a ltl
[@@deriving yojson]

(* LTL over first‑order formulas. Used for assumes/guarantees. *)
type fo_ltl = fo ltl [@@deriving yojson]

(* {2 Provenance} Provenance categories allow tracing a VC back to its source. *)
type origin =
  | UserContract
  | Instrumentation
  | Coherency
  | Compatibility
  | AssumeAutomaton
  | Internal
[@@deriving yojson]

(* First‑order formula annotated with provenance and optional location. Rationale: this is the
   primary traceability hook in the pipeline. *)
type fo_o = { value : fo ltl; origin : origin option; oid : int; loc : loc option } [@@deriving yojson]

(* {1 Statements & Invariants}
    Rationale: statements are the executable core, while invariants are the
    proof‑oriented facts injected by the monitor/contract passes. *)
(* Executable statements. *)
type stmt = { stmt : stmt_desc; loc : loc option }
[@@deriving yojson]

and stmt_desc =
  | SAssign of ident * iexpr
  | SIf of iexpr * stmt list * stmt list
  | SMatch of iexpr * (ident * stmt list) list * stmt list
  | SSkip
  | SCall of ident * iexpr list * ident list
[@@deriving yojson]

(* User‑level monitor invariants (named expressions). *)
type invariant_user = { inv_id : ident; inv_expr : hexpr } [@@deriving show, yojson]

(* Instrumentation state‑relation invariants. *)
type invariant_state_rel = { is_eq : bool; state : ident; formula : fo ltl } [@@deriving show, yojson]

(* {1 Per‑pass Metadata} Moved to [Stage_info] (kept separate from the AST). *)

(* {1 Program Structure} Rationale: a program is a list of normalized nodes; nodes and transitions
   are the stable backbone that later passes enrich via attributes. *)

(* Atomic LTL proposition (identifier). *)
type atom_ltl = ident ltl

(* Variable declaration (name + type). *)
type vdecl = { vname : ident; vty : ty } [@@deriving yojson]

(* Node‑level attributes and annotations populated by passes. *)
type node_attrs = {
  uid : int option;
  invariants_user : invariant_user list;
  invariants_state_rel : invariant_state_rel list;
  coherency_goals : fo_o list;
}

(* Transition‑level attributes and annotations populated by passes. *)
type transition_attrs = {
  uid : int option;
  ghost : stmt list;
  instrumentation : stmt list;
  warnings : string list;
}

(* Normalized transition (post‑parse, used across passes). *)
type transition = {
  src : ident;
  dst : ident;
  guard : iexpr option;
  requires : fo_o list;
  ensures : fo_o list;
  body : stmt list;
  attrs : transition_attrs;
}

(* Normalized node (post‑parse, used across passes). *)
type node = {
  nname : ident;
  inputs : vdecl list;
  outputs : vdecl list;
  assumes : fo_ltl list;
  guarantees : fo_ltl list;
  instances : (ident * ident) list;
  locals : vdecl list;
  states : ident list;
  init_state : ident;
  trans : transition list;
  attrs : node_attrs;
}

(* Program-only view of a node: syntax and transition semantics. *)
type node_semantics = {
  sem_nname : ident;
  sem_inputs : vdecl list;
  sem_outputs : vdecl list;
  sem_instances : (ident * ident) list;
  sem_locals : vdecl list;
  sem_states : ident list;
  sem_init_state : ident;
  sem_trans : transition list;
}

(* Specification-only view of a node.
   Semantically, these formulas are interpreted on a trace-local context:
   the current tick together with the history made accessible through [HNow]/[HPreK].
   They are therefore not restricted to predicates over the current memory alone.
   The finite encoding through auxiliary [__pre_k...] variables is a later backend step. *)
type node_specification = {
  spec_assumes : fo_ltl list;
  spec_guarantees : fo_ltl list;
  spec_invariants_state_rel : invariant_state_rel list;
}

(* A program is a list of nodes. *)
type program = node list

(* {2 Utilities} Utilities live in [Ast_utils]. *)

val semantics_of_node : node -> node_semantics
val specification_of_node : node -> node_specification

(* Debug string representation of a program (mainly for dumps). *)
val show_program : program -> string

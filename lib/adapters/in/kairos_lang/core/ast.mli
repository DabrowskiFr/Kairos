(** Elaborated Kairos program, immediately before translation to the generic
    verification model.

    All surface-only constructs have been expanded. A node is split explicitly
    between its executable semantics and its logical specification. *)

open Syntax

type invariant_state_rel = {
  state : ident;
  formula : hexpr;
}
[@@deriving yojson]
(** Invariant required whenever the node occupies one control state. *)

type method_param_mode = MPIn | MPInOut [@@deriving yojson]
(** Whether a method parameter is read-only or may also be updated. *)

type method_param = {
  method_param_name : ident;
  method_param_ty : ty;
  method_param_mode : method_param_mode;
}
[@@deriving yojson]
(** Elaborated scalar method parameter. *)

type stmt = {
  stmt : stmt_desc;
  loc : Shared.Syntax.loc option;
}

and stmt_desc =
  | SAssign of ident * expr
  | SAssert of hexpr
  | SIf of expr * stmt list * stmt list
  | SWhile of expr * hexpr list * expr option * stmt list
  | SMatch of expr * (ident * stmt list) list * stmt list
  | SSkip
  | SMethodCall of ident * expr list
[@@deriving yojson]
(** Executable statement after loops over finite domains and surface references
    have been expanded. *)

type method_decl = {
  method_name : ident;
  method_params : method_param list;
  method_requires : hexpr list;
  method_ensures : hexpr list;
  method_body : stmt list;
  method_reads : ident list;
  method_writes : ident list;
}
[@@deriving yojson]
(** Imperative helper method with inferred transitive read and write effects. *)

type transition = {
  src : ident;
  dst : ident;
  guard : expr option;
  body : stmt list;
  ensures : hexpr list;
}
[@@deriving yojson]
(** One control-state transition and its local proof obligations. *)

type node_semantics = {
  sem_nname : ident;
  sem_inputs : vdecl list;
  sem_outputs : vdecl list;
  sem_locals : vdecl list;
  sem_ghosts : vdecl list;
  sem_public_ghosts : ident list;
  sem_methods : method_decl list;
  sem_states : ident list;
  sem_init_state : ident;
  sem_trans : transition list;
}
[@@deriving yojson]
(** Executable state-machine part of a node, including proof-only variables. *)

type node_specification = {
  spec_assumes : ltl list;
  spec_guarantees : ltl list;
  spec_invariants_state_rel : invariant_state_rel list;
}
[@@deriving yojson]
(** Environmental assumptions and properties to prove for a node. *)

type node = {
  semantics : node_semantics;
  specification : node_specification;
}
[@@deriving yojson]
(** Complete elaborated synchronous node. *)

type program = node list [@@deriving yojson]
(** Elaborated nodes from one source file. *)

val semantics_of_node : node -> node_semantics
(** Select the executable part of a node. *)

val specification_of_node : node -> node_specification
(** Select the logical part of a node. *)

(** Complete program structure produced by the parser.

    It combines the expressions and declaration fragments from
    [Kx_surface_syntax] into statements, methods, contracts, transitions and
    nodes. These structures still contain every surface convenience and are the
    direct input of [Kx_elaborate]. *)

include module type of Kx_surface_syntax

type function_decl = {
  function_name : ident;
  function_params : raw_vdecl list;
  function_return : ty;
  function_requires : hexpr list;
  function_ensures : hexpr list;
  function_body : expr;
}
[@@deriving yojson]
(** Global pure function before parameter expansion and logical lowering. *)

type history_alias_decl = {
  alias_name : ident;
  alias_param : ident;
  alias_rhs_param : ident;
  alias_k : int;
}
[@@deriving yojson]
(** Named shorthand for reading a parameter at a fixed past offset. *)

type predicate_decl = {
  predicate_name : ident;
  predicate_params : typed_param list;
  predicate_body : hexpr;
}
[@@deriving yojson]
(** Reusable first-order logical expression expanded during elaboration. *)

type stmt = {
  sstmt : stmt_desc;
  sloc : loc option;
}

and stmt_desc =
  | SSAssign of indexed_ref * expr
  | SSIf of expr * stmt list * stmt list
  | SSWhile of expr * hexpr list * expr option * stmt list
  | SSMatch of expr * (ident * stmt list) list * stmt list option
  | SSSkip
  | SSCall of ident * expr list * ident list
  | SSMethodCall of ident * expr list
  | SSFor of ident * ident * stmt list
  | SSForRange of ident * nat_expr * nat_expr * stmt list
[@@deriving yojson]
(** Executable surface statement. Finite loops and optional match defaults are
    resolved before entering [Kx_core_ast]. *)

type method_decl = {
  method_name : ident;
  method_params : method_param list;
  method_requires : hexpr list;
  method_ensures : hexpr list;
  method_body : stmt list;
}
[@@deriving yojson]
(** Imperative helper method before its effects are inferred. *)

type spec_def_decl = {
  spec_def_name : ident;
  spec_def_params : spec_param list;
  spec_def_body : ltl;
}
[@@deriving yojson]
(** Parameterized temporal specification expanded at each call site. *)

type observer_decl = {
  observer_name : ident;
  observer_ty : ty;
  observer_init : stmt list;
  observer_step : stmt list;
}
[@@deriving yojson]
(** Proof-only value computed once on initialization and then at each instant. *)

type contract_item =
  | SCAssume of ident option * ltl
  | SCGuarantee of ident option * ltl
[@@deriving yojson]
(** Optionally named assumption or guarantee from a node contract. *)

type state_selector =
  | SSelState of ident
  | SSelSet of ident list
  | SSelAll
  | SSelDiff of state_selector * state_selector
[@@deriving yojson]
(** Set expression selecting control states for an invariant. *)

type state_invariant = {
  selector : state_selector;
  formula : hexpr;
}
[@@deriving yojson]
(** Formula required in every state selected by [selector]. *)

type transition = {
  src : ident;
  dst : ident;
  guard : expr option;
  body : stmt list;
  ensures : hexpr list;
}
[@@deriving yojson]
(** Surface control-state transition. *)

type state_decls = {
  states : ident list;
  init_state : ident;
  init_is_hidden : bool;
}
[@@deriving yojson]
(** Declared states and the possibly generated initial state. *)

val visible_states : state_decls -> ident list
(** Return user-visible states, excluding a generated hidden initial state. *)

type node = {
  node_name : ident;
  inputs : raw_vdecl list;
  outputs : raw_vdecl list;
  history_aliases : history_alias_decl list;
  ghosts : raw_vdecl list;
  observers : observer_decl list;
  predicates : predicate_decl list;
  methods : method_decl list;
  contracts : contract_item list;
  instances : (ident * ident) list;
  locals : raw_vdecl list;
  state_decls : state_decls;
  state_invariants : state_invariant list;
  transitions : transition list;
}
[@@deriving yojson]
(** Complete node as written in source, before validation and expansion. *)

type frontend_decl =
  | STypeDecl of enum_decl
  | SFunctionDecl of function_decl
  | SSpecDefDecl of spec_def_decl
[@@deriving yojson]
(** Declaration shared by all nodes in a source file. *)

type import_decl = string * loc option [@@deriving yojson]
(** Imported source path and its optional location. *)

type source = {
  imports : import_decl list;
  frontend_decls : frontend_decl list;
  nodes : node list;
}
[@@deriving yojson]
(** Complete parsed source file. *)

type program = node list [@@deriving yojson]
(** Surface nodes without their surrounding global declarations. *)

val mk_stmt : ?loc:loc -> stmt_desc -> stmt
(** Build a surface statement with an optional location. *)

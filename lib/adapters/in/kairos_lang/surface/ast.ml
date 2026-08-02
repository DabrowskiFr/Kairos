(** Program structure produced by the Kairos parser. *)

include Syntax

type function_decl = {
  function_name : ident;
  function_params : raw_vdecl list;
  function_return : ty;
  function_requires : hexpr list;
  function_ensures : hexpr list;
  function_body : expr;
}
[@@deriving yojson]

type history_alias_decl = {
  alias_name : ident;
  alias_param : ident;
  alias_rhs_param : ident;
  alias_k : int;
}
[@@deriving yojson]

type predicate_decl = {
  predicate_name : ident;
  predicate_params : typed_param list;
  predicate_body : hexpr;
}
[@@deriving yojson]

type stmt = { sstmt : stmt_desc; sloc : loc option }

and stmt_desc =
  | SSAssign of indexed_ref * expr
  | SSIf of expr * stmt list * stmt list
  | SSWhile of expr * hexpr list * expr option * stmt list
  | SSMatch of expr * (ident * stmt list) list * stmt list option
  | SSSkip
  | SSMethodCall of ident * expr list
  | SSFor of ident * ident * stmt list
  | SSForRange of ident * nat_expr * nat_expr * stmt list
[@@deriving yojson]

type method_decl = {
  method_name : ident;
  method_params : method_param list;
  method_requires : hexpr list;
  method_ensures : hexpr list;
  method_body : stmt list;
}
[@@deriving yojson]

type spec_def_decl = {
  spec_def_name : ident;
  spec_def_params : spec_param list;
  spec_def_body : ltl;
}
[@@deriving yojson]

type observer_decl = {
  observer_name : ident;
  observer_ty : ty;
  observer_init : stmt list;
  observer_step : stmt list;
}
[@@deriving yojson]

type contract_item =
  | SCAssume of ident option * ltl
  | SCGuarantee of ident option * ltl
[@@deriving yojson]

type state_selector =
  | SSelState of ident
  | SSelSet of ident list
  | SSelAll
  | SSelDiff of state_selector * state_selector
[@@deriving yojson]

type state_invariant = {
  selector : state_selector;
  formula : hexpr;
}
[@@deriving yojson]

type transition = {
  src : ident;
  dst : ident;
  guard : expr option;
  body : stmt list;
  ensures : hexpr list;
}
[@@deriving yojson]

type state_decls = {
  states : ident list;
  init_state : ident;
  init_is_hidden : bool;
}
[@@deriving yojson]

let visible_states decls =
  if decls.init_is_hidden then
    List.filter (fun state -> not (String.equal state decls.init_state)) decls.states
  else decls.states

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
  locals : raw_vdecl list;
  state_decls : state_decls;
  state_invariants : state_invariant list;
  transitions : transition list;
}
[@@deriving yojson]

type frontend_decl =
  | STypeDecl of enum_decl
  | SFunctionDecl of function_decl
  | SSpecDefDecl of spec_def_decl
[@@deriving yojson]

type source = {
  frontend_decls : frontend_decl list;
  nodes : node list;
}
[@@deriving yojson]

type program = node list [@@deriving yojson]

let mk_stmt ?loc sstmt = { sstmt; sloc = loc }

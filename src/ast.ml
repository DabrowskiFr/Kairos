
type ident = string [@@deriving show]

type ty =
  | TInt | TBool | TReal | TCustom of string
[@@deriving show]

type binop = Add | Sub | Mul | Div | Eq | Neq | Lt | Le | Gt | Ge | And | Or
[@@deriving show]
type unop = Neg | Not [@@deriving show]
type op = OMin | OMax | OAdd | OMul | OAnd | OOr | OFirst [@@deriving show]

type iexpr =
  | ILitInt of int
  | ILitBool of bool
  | IVar of ident
  | IBin of binop * iexpr * iexpr
  | IUn of unop * iexpr
  | IPar of iexpr
[@@deriving show]

type hexpr =
  | HNow of iexpr
  | HPre of iexpr * iexpr option          (* pre(e) or pre(e, init) *)
  | HPreK of iexpr * iexpr * int          (* pre_k(e, init, k) *)
  | HFold of op * iexpr * iexpr           (* fold(op, init, x) *)
[@@deriving show]

type relop = REq | RNeq | RLt | RLe | RGt | RGe [@@deriving show]

type fo =
  | FTrue
  | FFalse
  | FRel of hexpr * relop * hexpr
  | FPred of ident * hexpr list
  | FNot of fo
  | FAnd of fo * fo
  | FOr of fo * fo
  | FImp of fo * fo
[@@deriving show]

type ltl =
  | LTrue
  | LFalse
  | LAtom of fo
  | LNot of ltl
  | LAnd of ltl * ltl
  | LOr of ltl * ltl
  | LImp of ltl * ltl
  | LX of ltl                       (* Next *)
  | LG of ltl                       (* Globally *)
[@@deriving show]

type vdecl = { vname: ident; vty: ty } [@@deriving show]

type stmt =
  | SAssign of ident * iexpr
  | SIf of iexpr * stmt list * stmt list
  | SMatch of iexpr * (ident * stmt list) list * stmt list
  | SSkip
  | SCall of ident * iexpr list * ident list
[@@deriving show]

type invariant_mon =
  | Invariant of ident * hexpr
  | InvariantStateRel of bool * ident * fo
[@@deriving show]

type transition = {
  src: ident;
  dst: ident;
  guard: iexpr option;
  requires: fo list;
  ensures: fo list;
  lemmas: fo list;
  body: stmt list;
} [@@deriving show]

type node = {
  nname: ident;
  inputs: vdecl list;
  outputs: vdecl list;
  assumes: ltl list;
  guarantees: ltl list;
  invariants_mon: invariant_mon list;
  instances: (ident * ident) list;
  locals: vdecl list;
  states: ident list;
  init_state: ident;
  trans: transition list;
} [@@deriving show]

type program = node list [@@deriving show]

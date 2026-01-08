
type ident = string [@@deriving show]

type ty =
  | TInt | TBool | TReal | TCustom of string
[@@deriving show]

type binop = Add | Sub | Mul | Div | Eq | Neq | Lt | Le | Gt | Ge | And | Or
[@@deriving show]
type unop = Neg | Not [@@deriving show]
type op = OMin | OMax | OAdd | OMul | OAnd | OOr [@@deriving show]
type wop = WMin | WMax | WSum | WCount [@@deriving show]

type iexpr =
  | ILitInt of int
  | ILitBool of bool
  | IVar of ident
  | IScan1 of op * iexpr
  | IScan of op * iexpr * iexpr
  | IBin of binop * iexpr * iexpr
  | IUn of unop * iexpr
  | IPar of iexpr
[@@deriving show]

type hexpr =
  | HNow of iexpr
  | HPre of iexpr * iexpr option          (* pre(e) or pre(e, init) *)
  | HScan1 of op * iexpr                  (* scan1(op, x) *)
  | HScan of op * iexpr * iexpr           (* scan(op, init, x) *)
  | HWindow of int * wop * iexpr          (* window(k, wop, x) *)
  | HLet of ident * hexpr * hexpr
[@@deriving show]

type relop = REq | RNeq | RLt | RLe | RGt | RGe [@@deriving show]

type atom =
  | ARel of hexpr * relop * hexpr
  | APred of ident * hexpr list
[@@deriving show]

type ltl =
  | LTrue
  | LFalse
  | LAtom of atom
  | LNot of ltl
  | LAnd of ltl * ltl
  | LOr of ltl * ltl
  | LImp of ltl * ltl
  | LX of ltl                       (* Next *)
  | LG of ltl                       (* Globally *)
  | LF of ltl * iexpr option        (* Finally with optional variant bound *)
  | LU of ltl * ltl                 (* Until *)
[@@deriving show]

type vdecl = { vname: ident; vty: ty } [@@deriving show]

type stmt =
  | SAssign of ident * iexpr
  | SIf of iexpr * stmt list * stmt list
  | SSkip
  | SAssert of ltl
[@@deriving show]

type transition = {
  src: ident;
  dst: ident;
  guard: iexpr option;
  body: stmt list;
} [@@deriving show]

type contract =
  | Requires of ltl
  | Ensures of ltl
  | Assume of ltl
  | Guarantee of ltl
[@@deriving show]

type node = {
  nname: ident;
  inputs: vdecl list;
  outputs: vdecl list;
  contracts: contract list;
  locals: vdecl list;
  states: ident list;
  init_state: ident;
  trans: transition list;
} [@@deriving show]

type program = node list [@@deriving show]

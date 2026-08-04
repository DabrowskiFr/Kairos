(** Constructors for the elaborated [Ast] representation. *)

open Kr_lang_shared.Kr_lang_shared_syntax
module Kx_core_ast = Kr_lang_core_ast
open Kx_core_ast
module Kx_core_syntax = Kr_lang_core_syntax
open Kx_core_syntax

val mk_stmt : ?loc:Kr_lang_shared.Kr_lang_shared_syntax.loc -> stmt_desc -> stmt
(** Build a statement with an optional source location. *)

val stmt_desc : stmt -> stmt_desc
(** Select a statement's description. *)

val with_stmt_desc : stmt -> stmt_desc -> stmt
(** Replace a statement's description while preserving location. *)

val mk_transition :
  src:ident ->
  dst:ident ->
  guard:expr option ->
  body:stmt list ->
  ?ensures:hexpr list ->
  unit ->
  transition
(** Build a transition; local postconditions default to the empty list. *)

val mk_node :
  nname:ident ->
  inputs:vdecl list ->
  outputs:vdecl list ->
  assumes:ltl list ->
  guarantees:ltl list ->
  locals:vdecl list ->
  ghosts:vdecl list ->
  public_ghosts:ident list ->
  methods:method_decl list ->
  states:ident list ->
  init_state:ident ->
  trans:transition list ->
  node
(** Assemble the semantic and specification halves of an elaborated node. State
    invariants are attached later in elaboration. *)

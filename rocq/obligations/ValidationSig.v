Require Import obligations.OracleSig.

Set Implicit Arguments.

(* Preferred facade for validation-oriented naming.

   This file exists only to offer a readable entry point. The underlying
   implementation remains in [OracleSig.v] for compatibility with the existing
   development. *)

Module Type VALIDATION_SIG := OracleSig.VALIDATION_SIG.
Module Type ORACLE_SIG := OracleSig.ORACLE_SIG.

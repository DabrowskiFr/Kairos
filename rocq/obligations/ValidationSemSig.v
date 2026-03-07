Require Import obligations.OracleSemSig.

Set Implicit Arguments.

(* Preferred facade for validation-semantics naming.

   This file exists only to offer a readable entry point. The underlying
   implementation remains in [OracleSemSig.v] for compatibility with the
   existing development. *)

Module Type VALIDATION_SEM_SIG := OracleSemSig.VALIDATION_SEM_SIG.
Module Type ORACLE_SEM_SIG := OracleSemSig.ORACLE_SEM_SIG.

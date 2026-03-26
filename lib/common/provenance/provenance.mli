(** Provenance graph primitives used to link generated proof obligations back to
    source-level formulas. *)

(** Unique identifier used to link derived formulas to their sources. *)
type id = int

(** Reset the provenance graph, mainly between runs and tests. *)
val reset : unit -> unit

(** Allocate a fresh identifier. *)
val fresh_id : unit -> id

(** Register an identifier without parent links. *)
val register : id -> unit

(** Record parent links for a derived identifier. *)
val add_parents : child:id -> parents:id list -> unit

(** Direct parents of an identifier, one derivation step away. *)
val parents : id -> id list

(** Transitive closure of parent links. *)
val ancestors : id -> id list

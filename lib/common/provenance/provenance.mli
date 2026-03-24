(** Provenance graph primitives used to link generated proof obligations back to
    source-level formulas. *)

(* Unique identifier used to link derived formulas to their sources. *)
type id = int

(* Reset the provenance graph (used between runs/tests). *)
val reset : unit -> unit

(* Allocate a fresh identifier. *)
val fresh_id : unit -> id

(* Register an id without parent links (for externally created nodes). *)
val register : id -> unit

(* Record parent links for a derived id. *)
val add_parents : child:id -> parents:id list -> unit

(* Direct parents of an id (one derivation step). *)
val parents : id -> id list

(* Transitive closure of parents. *)
val ancestors : id -> id list

type id = int

val reset : unit -> unit
val fresh_id : unit -> id
val register : id -> unit
val add_parents : child:id -> parents:id list -> unit
val parents : id -> id list
val ancestors : id -> id list

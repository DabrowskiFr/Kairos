(** UI-oriented metadata for stages, including labels, descriptions, and stats
    keys. *)

(* Short UI label for a stage. *)
val stage_label : Stage_names.stage_id -> string

(* Longer description for tooltips/help. *)
val stage_description : Stage_names.stage_id -> string

(* Ordered list of item keys shown in the stage‑meta panel. *)
val stage_items : Stage_names.stage_id -> string list

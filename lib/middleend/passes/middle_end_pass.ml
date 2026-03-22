(** Generic signature for a middle-end pass with stage artifacts and info. *)
module type S = sig
  type ast_in
  type ast_out
  type stage_in
  type stage_out
  type info

  val run : ast_in -> stage_in -> ast_out * stage_out
  val run_with_info : ast_in -> stage_in -> ast_out * stage_out * info
end

module type S = sig
  type obs_stream
  type ltl_formula

  val sat : obs_stream -> ltl_formula -> bool
end

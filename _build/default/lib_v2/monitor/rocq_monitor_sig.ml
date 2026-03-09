module type S = sig
  type obs
  type monitor_state

  val init : monitor_state
  val next : monitor_state -> obs -> monitor_state
  val is_bad : monitor_state -> bool
end

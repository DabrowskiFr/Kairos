type role =
  | ObjectiveNoBad
  | SupportAutomaton
  | SupportUserInvariant

module type S = sig
  type obligation

  val role_of : obligation -> role
end

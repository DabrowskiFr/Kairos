module type CORE = sig
  type input
  type output
  type mem
  type ctrl
  type step_ctx
end

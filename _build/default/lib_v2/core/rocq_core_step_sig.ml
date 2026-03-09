module type S = sig
  type input
  type output
  type mem
  type ctrl
  type ctx
  type cfg = ctrl * mem

  val init_cfg : cfg
  val step : ctx -> cfg -> cfg * output
end

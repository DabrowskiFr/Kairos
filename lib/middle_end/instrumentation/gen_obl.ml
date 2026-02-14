open Ast

module Abs = Abstract_model

type hooks = {
  add_not_bad_state_ensures :
    ?log:(Abs.transition -> fo -> unit) option ->
    bad_state_fo_opt:fo option ->
    Abs.transition list ->
    Abs.transition list;
}

let apply ~(bad_state_fo_opt : fo option) ~(trans : Abs.transition list)
    ~(log_contract : reason:string -> t:Abs.transition -> fo -> unit) ~(hooks : hooks) :
    Abs.transition list =
  hooks.add_not_bad_state_ensures
    ~log:(Some (fun t f -> log_contract ~reason:"GenObl/no_bad_state" ~t f))
    ~bad_state_fo_opt trans

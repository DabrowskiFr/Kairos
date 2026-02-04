type summary = {
  total : int;
  valid : int;
  invalid : int;
  unknown : int;
  timeout : int;
  failure : int;
}

type result = {
  status : int;
  summary : summary;
}

val prove_text : ?timeout:int -> prover:string -> text:string -> unit -> result

val dump_why3_tasks : text:string -> string list

val dump_smt2_tasks : prover:string -> text:string -> string list

val prove_text_detailed :
  ?timeout:int ->
  prover:string ->
  text:string ->
  unit ->
  summary * (string * string * float) list

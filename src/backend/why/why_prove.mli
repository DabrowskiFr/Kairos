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

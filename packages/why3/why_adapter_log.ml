let progress_handler = ref (fun (_ : string) -> ())
let warning_handler = ref (fun (_ : string) -> ())

let set_handlers ~progress ~warning =
  progress_handler := progress;
  warning_handler := warning

let progress message = !progress_handler message
let warning message = !warning_handler message

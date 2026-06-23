(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

let section_payload (sections : Lsp_outline.outline_sections) :
    Lsp_protocol.outline_sections =
  {
    nodes = sections.nodes;
    transitions = sections.transitions;
    contracts = sections.contracts;
  }

let yojson_of_texts (texts : Lsp_outline_texts.t) =
  let source_sections =
    Lsp_outline.outline_sections_of_text texts.source_text
  in
  let abstract_sections =
    Lsp_outline.outline_sections_of_text texts.abstract_text
  in
  Lsp_protocol.yojson_of_outline_payload
    {
      source = section_payload source_sections;
      abstract_program = section_payload abstract_sections;
    }

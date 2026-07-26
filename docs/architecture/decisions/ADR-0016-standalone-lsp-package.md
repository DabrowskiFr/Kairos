# ADR-0016 Standalone LSP Package

## Status

Accepted

## Context

The main `kairos` package delivered both the verification engine and the LSP
server. It consequently depended on `lsp` and `jsonrpc` even for CLI-only or
embedded-engine installations. The LSP implementation also imported
application records, the concrete composition root, and frontend AST modules
directly.

The LSP is a delivery adapter. It does not own the meaning of programs,
products, obligations, or backend encodings. Separating it must therefore not
introduce a process boundary or duplicate the internal verification model.

## Decision

Create two installation boundaries:

- `kairos` provides the CLI and the wrapped `kairos.engine` in-process facade;
- `kairos-lsp` provides the protocol libraries and the `kairos-lsp`
  executable.

`kairos.engine` owns:

- construction of supported pipeline configurations;
- calls to the concretely wired application use-cases;
- stable application result types;
- neutral source diagnostics and semantic-symbol projections needed by
  editor clients.

LSP sources may depend on `kairos.engine`, `kairos-lsp.protocol`, generic
transport libraries, and external tool contracts. They must not import domain,
backend, runtime-orchestration, concrete composition, or Kairos frontend AST
modules.

The adapter remains linked in process. No IPC or runtime serialization layer is
introduced.

Implementation libraries required to install `kairos.engine` have installation
names below `kairos.internal.*`. Those names satisfy Dune's installed-library
closure; they are not supported client APIs. `kairos.engine` is the supported
embedding boundary.

## Consequences

- installing `kairos` no longer requires `lsp` or `jsonrpc`;
- installing `kairos-lsp` explicitly brings those dependencies and the engine;
- the CLI and proof pipeline are unchanged;
- editor parsing no longer exposes `Kx_ast` across the LSP boundary;
- the architecture fitness checks reject direct LSP imports that bypass
  `kairos.engine`;
- package separation does not claim semantic independence of the LSP from the
  Kairos engine.

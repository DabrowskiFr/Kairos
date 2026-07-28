# OCaml Formatting Policy

Date: 2026-07-02

Kairos uses OCamlFormat, but the migration is intentionally opt-in to avoid a
large mechanical rewrite mixed with semantic work.

## Configuration

- The repository-level configuration is `.ocamlformat`.
- The pinned formatter version is `0.29.0`.
- Formatting is disabled by default at the repository root.
- `.ocamlformat-enable` lists the files or subtrees that have been explicitly
  migrated.

## Migration Rule

Formatting a file is a deliberate refactoring step:

1. Add the file or subtree to `.ocamlformat-enable`.
2. Run OCamlFormat on exactly that scope.
3. Keep semantic edits separate from broad mechanical formatting whenever the
   diff would otherwise become hard to review.
4. Run the usual validation for the subsystem that was touched.

New OCaml modules should either be formatted immediately and added to the
enabled set, or be covered by a documented reason if they are introduced inside
an unmigrated subtree.

Dune files are formatter-managed globally by `dune build @fmt`; changes to
them should keep that alias clean.

## Current Migrated Scope

- `lib/adapters/out/codegen/c/c_codegen*.ml`
- `lib/adapters/out/codegen/c/c_codegen*.mli`
- `lib/domain/core/core_fo_simplifier*.ml`
- `lib/domain/core/core_fo_simplifier*.mli`

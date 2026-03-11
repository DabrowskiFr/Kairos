# Install Kairos

This file explains how to install:

- the Kairos CLI and LSP server;
- the optional native GTK IDE;
- the Kairos VS Code extension.

The commands below assume:

- macOS or Linux;
- `opam`, `git`, `node`, `npm`, and VS Code are already installed.

## 1. Clone the repository

```bash
git clone <YOUR-KAIROS-REMOTE> kairos-dev
cd kairos-dev
```

## 2. Prepare the opam switch

If you already have a suitable switch, activate it. Otherwise create one:

```bash
opam switch create kairos-5.2.1 ocaml-base-compiler.5.2.1
eval "$(opam env)"
```

Install the basic OCaml build toolchain if needed:

```bash
opam install dune odoc
```

## 3. Pin and install Kairos

From the repository root:

```bash
opam pin add kairos . --working-dir
opam install kairos
```

This installs the package from the current checkout and exposes the binaries in
the active opam switch.

## 4. Install proof dependencies

Kairos proof workflows rely on Why3 and an SMT solver. A practical default is:

```bash
opam install why3
brew install z3 graphviz
```

If you are not on macOS, install `z3` and `graphviz` with your system package
manager instead.

Then detect Why3 provers:

```bash
why3 config detect
```

## 5. Verify the installation

Check that the main binaries are available:

```bash
which kairos
which kairos-lsp
which kairos-ide
```

You can also verify the local build directly from the repository:

```bash
opam exec -- dune build bin/cli/main.exe --display=short
opam exec -- dune build bin/lsp/kairos_lsp.exe --display=short
opam exec -- dune build bin/ide/obcwhy3_ide.exe --display=short
```

Minimal CLI smoke test:

```bash
kairos --dump-proof-traces-json - tests/ok/inputs/delay_int.kairos
```

If `kairos` is not found, re-run:

```bash
eval "$(opam env)"
```

## 6. Install the VS Code extension

The extension source lives in:

`extensions/kairos-vscode`

Install its Node dependencies and build it:

```bash
cd extensions/kairos-vscode
npm install
npm run compile
```

Package the extension as a `.vsix`:

```bash
npx @vscode/vsce package
```

This generates a file like:

`extensions/kairos-vscode/kairos-vscode-0.1.2.vsix`

Install it in VS Code with either:

1. `Extensions` panel -> `...` menu -> `Install from VSIX...`
2. or:

```bash
code --install-extension extensions/kairos-vscode/kairos-vscode-0.1.2.vsix
```

## 7. Configure the extension

### Recommended setup when `kairos-lsp` is installed in the active shell

No special setting is required if `kairos-lsp` is visible in the VS Code
environment `PATH`.

### Recommended setup during development from the repository

If VS Code does not inherit the opam environment cleanly, configure the
extension to launch the server through `dune`.

Open VS Code settings JSON and add:

```json
{
  "kairos.lsp.serverPath": "dune",
  "kairos.lsp.serverArgs": ["exec", "--", "kairos-lsp"]
}
```

If Graphviz is not in `PATH`, also set:

```json
{
  "kairos.graphviz.dotPath": "/absolute/path/to/dot"
}
```

## 8. Verify the VS Code extension

1. Open the repository in VS Code.
2. Open a `.kairos` file, for example:
   `tests/ok/inputs/delay_int.kairos`
3. Run `Kairos: Prove`.
4. Open:
   - `Proof Dashboard`
   - `Explain Failure`
   - `Automata Studio`

If the extension starts correctly, you should see Kairos commands, proof runs,
and generated artifacts.

## 9. Optional: run from source without installing globally

You can use Kairos directly from the checkout:

```bash
opam exec -- dune exec -- kairos --dump-proof-traces-json - tests/ok/inputs/delay_int.kairos
opam exec -- dune exec -- kairos-lsp
opam exec -- dune exec -- bin/ide/obcwhy3_ide.exe
```

This is useful for development when you do not want to reinstall after every
change.

## 10. Common problems

### `kairos-lsp` not found in VS Code

Use the `dune`-based configuration shown above, or launch VS Code from a shell
where `eval "$(opam env)"` has been run.

### Why3 says no prover matches `z3`

Run:

```bash
why3 config detect
```

Then verify:

```bash
why3 config list-provers
```

### Graph export fails

Check:

```bash
dot --version
```

and configure `kairos.graphviz.dotPath` if necessary.

### The extension builds but VS Code shows nothing

Check:

- the `Kairos` output channel;
- `kairos.lsp.serverPath`;
- `kairos.lsp.serverArgs`;
- that `kairos-lsp` or `dune` is reachable from VS Code.

# OBC LSP Server (Stub)

This is a minimal Language Server Protocol stub for OBC. It only provides
basic diagnostics.

## Build

```
npm install
npm run compile
```

## Run

The server is a Node.js executable. Point the client to:

```
<vscode-obc>/server/dist/server.js
```

Example VSCode setting:

```
obc.lsp.path
```

You can also pass arguments via `obc.lsp.args`.

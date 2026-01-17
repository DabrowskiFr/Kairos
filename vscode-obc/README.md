# OBC VSCode Extension

Cette extension fournit la coloration syntaxique pour les fichiers `.obc` et
un client LSP minimal.

## Compilation

1. Ouvrir `vscode-obc` dans VSCode.
2. Installer les dependances :
   ```
   npm install
   ```
3. Compiler :
   ```
   npm run compile
   ```

## Debug (Extension Development Host)

Si la configuration de debug n'est pas presente, creer :
```
.vscode/launch.json
```
avec :
```
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Run Extension",
      "type": "extensionHost",
      "request": "launch",
      "args": ["--extensionDevelopmentPath=${workspaceFolder}"],
      "outFiles": ["${workspaceFolder}/dist/**/*.js"]
    }
  ]
}
```

Ensuite :
1. `npm run compile`
2. Lancer **Run Extension** (F5) pour ouvrir l'Extension Development Host.

## Installation "reelle" (hors debug)

### Option A - VSIX (recommande)

1. S'assurer d'avoir Node 20+ (ex : via nvm).
2. Compiler :
   ```
   npm run compile
   ```
3. Packager :
   ```
   npx @vscode/vsce package
   ```
4. Installer le fichier `.vsix` :
   - Palette de commandes : **Extensions: Install from VSIX...**
   - ou CLI :
     ```
     code --install-extension /chemin/vers/obc-syntax-0.1.0.vsix
     ```

### Option B - Installation depuis le dossier

1. Compiler :
   ```
   npm run compile
   ```
2. Palette de commandes : **Developer: Install Extension from Location...**
3. Choisir le dossier `vscode-obc`, puis redemarrer VSCode.

## LSP Setup

Configurer le chemin vers l'executable du serveur LSP :
```
obc.lsp.path
```

Arguments optionnels :
```
obc.lsp.args
```

Utiliser la commande **OBC: Restart LSP** apres un changement de config.

## LSP Server Stub

Un serveur minimal est disponible dans `vscode-obc/server`.
Pour le compiler :
```
cd vscode-obc/server
npm install
npm run compile
```

Puis configurer :
```
obc.lsp.path = <repo>/vscode-obc/server/dist/server.js
```

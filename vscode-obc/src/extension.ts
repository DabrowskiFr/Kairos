import * as vscode from 'vscode';
import { LanguageClient, LanguageClientOptions, ServerOptions } from 'vscode-languageclient/node';

let client: LanguageClient | undefined;

function getLspConfig() {
  const config = vscode.workspace.getConfiguration('obc');
  const path = config.get<string>('lsp.path', '');
  const args = config.get<string[]>('lsp.args', []);
  return { path, args };
}

async function startClient(context: vscode.ExtensionContext): Promise<void> {
  const { path, args } = getLspConfig();
  if (!path) {
    vscode.window.showInformationMessage('OBC LSP: set obc.lsp.path to enable the language server.');
    return;
  }

  const serverOptions: ServerOptions = {
    command: path,
    args
  };

  const clientOptions: LanguageClientOptions = {
    documentSelector: [{ language: 'obc' }],
    synchronize: {
      fileEvents: vscode.workspace.createFileSystemWatcher('**/*.obc')
    }
  };

  client = new LanguageClient('obcLsp', 'OBC LSP', serverOptions, clientOptions);
  await client.start();
  context.subscriptions.push(client);
}

export async function activate(context: vscode.ExtensionContext) {
  await startClient(context);

  context.subscriptions.push(
    vscode.commands.registerCommand('obc.restartLsp', async () => {
      if (client) {
        await client.stop();
        client = undefined;
      }
      await startClient(context);
    })
  );
}

export async function deactivate() {
  if (client) {
    await client.stop();
    client = undefined;
  }
}

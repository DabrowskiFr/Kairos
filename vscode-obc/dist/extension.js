"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.activate = activate;
exports.deactivate = deactivate;
const vscode = __importStar(require("vscode"));
const node_1 = require("vscode-languageclient/node");
let client;
function getLspConfig() {
    const config = vscode.workspace.getConfiguration('obc');
    const path = config.get('lsp.path', '');
    const args = config.get('lsp.args', []);
    return { path, args };
}
async function startClient(context) {
    const { path, args } = getLspConfig();
    if (!path) {
        vscode.window.showInformationMessage('OBC LSP: set obc.lsp.path to enable the language server.');
        return;
    }
    const serverOptions = {
        command: path,
        args
    };
    const clientOptions = {
        documentSelector: [{ language: 'obc' }],
        synchronize: {
            fileEvents: vscode.workspace.createFileSystemWatcher('**/*.obc')
        }
    };
    client = new node_1.LanguageClient('obcLsp', 'OBC LSP', serverOptions, clientOptions);
    await client.start();
    context.subscriptions.push(client);
}
async function activate(context) {
    await startClient(context);
    context.subscriptions.push(vscode.commands.registerCommand('obc.restartLsp', async () => {
        if (client) {
            await client.stop();
            client = undefined;
        }
        await startClient(context);
    }));
}
async function deactivate() {
    if (client) {
        await client.stop();
        client = undefined;
    }
}
//# sourceMappingURL=extension.js.map
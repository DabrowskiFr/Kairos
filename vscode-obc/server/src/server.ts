import {
  createConnection,
  TextDocuments,
  ProposedFeatures,
  InitializeParams,
  InitializeResult,
  TextDocumentSyncKind,
  Diagnostic,
  DiagnosticSeverity
} from 'vscode-languageserver/node';
import { TextDocument } from 'vscode-languageserver-textdocument';

const connection = createConnection(ProposedFeatures.all);
const documents: TextDocuments<TextDocument> = new TextDocuments(TextDocument);

connection.onInitialize((_params: InitializeParams): InitializeResult => {
  return {
    capabilities: {
      textDocumentSync: TextDocumentSyncKind.Incremental
    }
  };
});

function validateTextDocument(doc: TextDocument): Diagnostic[] {
  const text = doc.getText();
  const diagnostics: Diagnostic[] = [];

  // Simple stub rule: warn if file does not contain a node declaration.
  if (!/\bnode\b/.test(text)) {
    diagnostics.push({
      severity: DiagnosticSeverity.Warning,
      range: {
        start: doc.positionAt(0),
        end: doc.positionAt(Math.min(1, text.length))
      },
      message: 'No node declaration found.'
    });
  }

  return diagnostics;
}

documents.onDidOpen((e) => {
  const diagnostics = validateTextDocument(e.document);
  connection.sendDiagnostics({ uri: e.document.uri, diagnostics });
});

documents.onDidChangeContent((change) => {
  const diagnostics = validateTextDocument(change.document);
  connection.sendDiagnostics({ uri: change.document.uri, diagnostics });
});

documents.onDidClose((e) => {
  connection.sendDiagnostics({ uri: e.document.uri, diagnostics: [] });
});

documents.listen(connection);
connection.listen();

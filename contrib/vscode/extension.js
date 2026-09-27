// Metis LLP — LSP client: hands .llp buffers to the metis toolchain
// (metis/lang/lsp.py). The server command is configurable
// (llp.server.command); diagnostics are the REAL compiler findings.
// With no command configured, auto-detect: find metis/lang/lsp.py up
// from the workspace folders, run it with the theia venv python
// ($THEIA_ROOT, else the metis checkout's ../theia sibling, else python3).
const fs = require("fs");
const path = require("path");
const { workspace } = require("vscode");
const { LanguageClient } = require("vscode-languageclient/node");

let client;

function findUp(start, rel) {
  for (let dir = start; ; dir = path.dirname(dir)) {
    const p = path.join(dir, rel);
    if (fs.existsSync(p)) return p;
    if (dir === path.dirname(dir)) return null;
  }
}

function autoCommand() {
  const roots = (workspace.workspaceFolders || []).map(f => f.uri.fsPath);
  let lsp = null;
  for (const root of roots) {
    lsp = findUp(root, path.join("metis", "lang", "lsp.py"));
    if (lsp) break;
  }
  if (!lsp) return null;
  const metisRoot = path.dirname(path.dirname(path.dirname(lsp)));
  for (const base of [process.env.THEIA_ROOT,
                      path.join(metisRoot, "..", "theia")]) {
    if (!base) continue;
    const py = path.join(base, ".venv", "bin", "python");
    if (fs.existsSync(py)) return [py, lsp];
  }
  return ["python3", lsp];
}

function activate() {
  const cfg = workspace.getConfiguration("llp").get("server.command");
  const cmd = (cfg && cfg.length) ? cfg : autoCommand();
  if (!cmd) return;   // no .llp toolchain in sight; stay quiet
  client = new LanguageClient(
    "metis-llp", "Metis LLP",
    { command: cmd[0], args: cmd.slice(1) },
    { documentSelector: [{ scheme: "file", language: "llp" }] });
  client.start();
}

function deactivate() {
  return client ? client.stop() : undefined;
}

module.exports = { activate, deactivate };

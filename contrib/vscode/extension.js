// SPDX-License-Identifier: Apache-2.0
// Metis LLP — LSP client + REPL integration for .llp buffers.
//
// Language server: metis/lang/lsp.py, auto-detected (llp.server.command
// overrides) — real compiler diagnostics, hover, completion, outline.
//
// Two run gestures, following the Python/Julia extension conventions:
//   shift+enter      "Send Line/Selection to REPL" — sends the selection
//                    (or current line, advancing the cursor) to a `metis`
//                    terminal REPL serving THIS file, auto-starting it on
//                    first send. One REPL instance per catalog file: a
//                    file from another package gets its own fresh
//                    instance. '#'-directive lines apply to the live
//                    session; after editing rules, save and send `reload`.
//   ctrl+alt+enter   "Run Embedded Case in REPL" — save the file, open
//                    its REPL, send `trace`: replays the whole embedded
//                    '#'-directive case (= metisc --run) fresh from
//                    #init, leaving the interactive session untouched.
//                    (The output-channel variant via the language server
//                    stays in the palette as "Send to Interpreter".)
const fs = require("fs");
const path = require("path");
const { commands, window, workspace } = require("vscode");
const { LanguageClient } = require("vscode-languageclient/node");

let client;
let channel;
const repls = new Map();   // fsPath -> Terminal

function findUp(start, rel) {
  for (let dir = start; ; dir = path.dirname(dir)) {
    const p = path.join(dir, rel);
    if (fs.existsSync(p)) return p;
    if (dir === path.dirname(dir)) return null;
  }
}

// locate the toolchain: {lsp, py, pkgRoot} or null. lsp.py found up
// from the workspace folders (also inside a metispy/ or metis/
// checkout sitting in the workspace); python from the nearest venv —
// the checkout's own or its parent's .venv (the dedicated repo env,
// where metispy is pip-installed), else the theia venv ($THEIA_ROOT,
// else the checkout's ../theia sibling), else python3 — the server,
// kernel and REPL are stdlib-only. The REPL terminal's "shell" IS
// the metis process (the `metis` command when found, see findMetis),
// so the environment must be right at launch: there is no bash in
// that terminal to `source` an activate into.
function findServer() {
  const roots = (workspace.workspaceFolders || []).map(f => f.uri.fsPath);
  const rel = path.join("metis", "lang", "lsp.py");
  let lsp = null;
  for (const root of roots) {
    for (const sub of ["metispy", "metis", "."]) {
      const p = path.join(root, sub, rel);
      if (fs.existsSync(p)) { lsp = p; break; }
    }
    if (!lsp) lsp = findUp(root, rel);
    if (lsp) break;
  }
  if (!lsp) return null;
  const pkgRoot = path.dirname(path.dirname(path.dirname(lsp)));
  let py = "python3";
  for (const base of [pkgRoot,
                      path.join(pkgRoot, ".."),
                      process.env.THEIA_ROOT,
                      path.join(pkgRoot, "..", "theia")]) {
    if (!base) continue;
    const p = path.join(base, ".venv", "bin", "python");
    if (fs.existsSync(p)) { py = p; break; }
  }
  return { lsp, py, pkgRoot, metis: findMetis(py) };
}

// the `metis` shell command for the REPL terminal: from PATH first (an
// environment activated before VS Code started), else the console
// script beside the chosen python; null falls back to `python -m`.
function findMetis(py) {
  const dirs = (process.env.PATH || "").split(path.delimiter);
  if (path.isAbsolute(py)) dirs.push(path.dirname(py));
  for (const dir of dirs) {
    if (!dir) continue;
    const p = path.join(dir, "metis");
    try { fs.accessSync(p, fs.constants.X_OK); return p; } catch {}
  }
  return null;
}

// -- the REPL terminal (one per catalog file) ---------------------------

function replFor(file) {
  const live = repls.get(file);
  if (live && live.exitStatus === undefined) return live;
  const srv = findServer();
  if (!srv) return null;
  // A metis terminal, not a Python one: launched as the `metis`
  // command, and hideFromUser — the flag both Python extensions honor
  // to skip their `source .../activate` injection. show() still
  // reveals it, so the terminal is visible as before.
  const t = window.createTerminal({
    name: `metis: ${path.basename(file)}`,
    shellPath: srv.metis || srv.py,
    shellArgs: srv.metis ? [file] : ["-m", "metis.lang.repl", file],
    cwd: srv.pkgRoot,
    hideFromUser: true,
  });
  repls.set(file, t);
  return t;
}

function activeLlpEditor() {
  const ed = window.activeTextEditor;
  if (!ed || ed.document.languageId !== "llp") {
    window.showInformationMessage("LLP: focus an .llp editor first.");
    return null;
  }
  return ed;
}

function openRepl() {
  const ed = activeLlpEditor();
  if (!ed) return;
  const t = replFor(ed.document.uri.fsPath);
  if (!t) {
    window.showWarningMessage(
      "LLP: metis toolchain not found (metis/lang/ in or above the " +
      "workspace); set llp.server.command.");
    return;
  }
  t.show(true);                       // reveal, keep editor focus
  return t;
}

// sendText straight after createTerminal races the shell spawn (the
// line echoes before the banner); processId is a thenable that
// resolves once the metis process is up — send async behind it.
function sendWhenUp(t, text) {
  Promise.resolve(t.processId).then(() => t.sendText(text, true));
}

function sendToRepl() {
  const ed = activeLlpEditor();
  if (!ed) return;
  const t = openRepl();
  if (!t) return;
  const sel = ed.selection;
  const text = sel.isEmpty
    ? ed.document.lineAt(sel.active.line).text
    : ed.document.getText(sel);
  if (text.trim()) sendWhenUp(t, text);
  if (sel.isEmpty)                    // advance, like a notebook cell
    commands.executeCommand("cursorDown");
}

async function runCaseInRepl() {
  const ed = activeLlpEditor();
  if (!ed) return;
  if (ed.document.isDirty) await ed.document.save();
  const t = openRepl();
  if (t) sendWhenUp(t, "trace");
}

// -- run the whole embedded case through the language server ------------

async function sendToInterpreter() {
  const ed = activeLlpEditor();
  if (!ed) return;
  if (!client) {
    window.showWarningMessage(
      "LLP: no language server (metis/lang/lsp.py not found; " +
      "set llp.server.command).");
    return;
  }
  const res = await client.sendRequest("workspace/executeCommand", {
    command: "llp.trace",
    arguments: [ed.document.uri.toString()],
  });
  if (!channel) channel = window.createOutputChannel("LLP Interpreter");
  channel.appendLine(res && res.text ? res.text : "(no output)");
  channel.appendLine("");
  channel.show(true);
}

function activate(context) {
  const cfg = workspace.getConfiguration("llp").get("server.command");
  const cmd = (cfg && cfg.length) ? cfg
    : (s => s && [s.py, s.lsp])(findServer());
  if (cmd) {
    client = new LanguageClient(
      "metis-llp", "Metis LLP",
      { command: cmd[0], args: cmd.slice(1) },
      { documentSelector: [{ scheme: "file", language: "llp" }] });
    client.start();
  }
  context.subscriptions.push(
    commands.registerCommand("llp.sendToRepl", sendToRepl),
    commands.registerCommand("llp.openRepl", openRepl),
    commands.registerCommand("llp.runCaseInRepl", runCaseInRepl),
    commands.registerCommand("llp.sendToInterpreter", sendToInterpreter),
    window.onDidCloseTerminal(term => {
      for (const [k, v] of repls) if (v === term) repls.delete(k);
    }));
}

function deactivate() {
  return client ? client.stop() : undefined;
}

module.exports = { activate, deactivate };

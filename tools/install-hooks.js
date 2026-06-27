#!/usr/bin/env node
"use strict";
/*
 * Idempotently wire CodePet into Claude Code's hooks so the pet reflects the
 * live agent state. Pass "install" or "uninstall" plus the absolute repo dir.
 *
 *   node install-hooks.js install   /abs/path/to/codepet
 *   node install-hooks.js uninstall /abs/path/to/codepet
 *
 * Transport:
 *   • SessionStart → a command hook (node codepet-hook.js). Fires once per
 *     session and captures terminal identity (TERM_PROGRAM / ITERM_SESSION_ID)
 *     from its process env so the app can focus the right terminal on click.
 *   • Everything else → HTTP hooks POSTed straight to the running app's loopback
 *     server (127.0.0.1:<port>/codepet/hook). No node process per tool call, and
 *     transcript parsing happens in the app — off Claude Code's critical path.
 *     If the app isn't running the POST fails fast (non-blocking) and is ignored.
 */
const fs = require("fs");
const os = require("os");
const path = require("path");
const crypto = require("crypto");

const mode = process.argv[2] || "install";
const repo = process.argv[3] || path.resolve(__dirname, "..");
const settingsPath = path.join(os.homedir(), ".claude", "settings.json");
const codepetDir = path.join(os.homedir(), ".codepet");
const hookCfgPath = path.join(codepetDir, "hook.json");

const hookCmd = `node ${path.join(repo, "tools", "codepet-hook.js")}`;
const CMD_MARK = "codepet-hook.js";        // identifies our command hook
const HTTP_MARK = "/codepet/hook";         // identifies our http hook (url path)

// SessionStart needs the command hook (terminal identity). Everything else is
// high-frequency and goes over HTTP.
const CMD_EVENTS = ["SessionStart"];
const HTTP_EVENTS = [
  "UserPromptSubmit", "PreToolUse", "PostToolUse",
  "Notification", "Stop", "SubagentStop",
];

function load() {
  let raw;
  try {
    raw = fs.readFileSync(settingsPath, "utf8");
  } catch (e) {
    if (e && e.code === "ENOENT") return {}; // no settings yet → start fresh
    // Unreadable (permissions, etc.) — refuse to clobber what we can't read.
    console.error(`✗ Could not read ${settingsPath}: ${e.message}`);
    process.exit(1);
  }
  try {
    return JSON.parse(raw);
  } catch (e) {
    // The file exists but isn't valid JSON. Overwriting it would wipe the
    // user's other Claude Code settings — refuse and let them fix it.
    console.error(`✗ ${settingsPath} isn't valid JSON (${e.message}).`);
    console.error("  Refusing to overwrite it so your settings aren't lost — fix the JSON and re-run.");
    process.exit(1);
  }
}

function save(obj) {
  fs.mkdirSync(path.dirname(settingsPath), { recursive: true });
  // Write atomically so an interrupted run can never leave a half-written
  // (corrupt) settings.json behind.
  const tmp = settingsPath + "." + process.pid + ".tmp";
  fs.writeFileSync(tmp, JSON.stringify(obj, null, 2) + "\n");
  fs.renameSync(tmp, settingsPath);
}

// Stable port + token shared with the app (HookConfig in HookServer.swift).
function ensureHookConfig() {
  fs.mkdirSync(codepetDir, { recursive: true });
  let cfg = {};
  try { cfg = JSON.parse(fs.readFileSync(hookCfgPath, "utf8")); } catch {}
  if (!Number.isInteger(cfg.port)) cfg.port = 51763;
  if (typeof cfg.token !== "string" || !cfg.token) {
    cfg.token = crypto.randomBytes(16).toString("hex");
  }
  fs.writeFileSync(hookCfgPath, JSON.stringify(cfg, null, 2) + "\n");
  return cfg;
}

// Drop any matcher-group that references our hooks (command OR http), leaving
// other hooks intact. Always run first → idempotent + migrates older installs.
function stripOurs(settings) {
  const hooks = settings.hooks || {};
  for (const ev of Object.keys(hooks)) {
    if (!Array.isArray(hooks[ev])) continue;
    hooks[ev] = hooks[ev].filter((group) => {
      const list = (group && group.hooks) || [];
      return !list.some((h) =>
        (typeof h.command === "string" && h.command.includes(CMD_MARK)) ||
        (typeof h.url === "string" && h.url.includes(HTTP_MARK))
      );
    });
    if (hooks[ev].length === 0) delete hooks[ev];
  }
  if (Object.keys(hooks).length === 0) delete settings.hooks;
  else settings.hooks = hooks;
}

function main() {
  const settings = load();
  stripOurs(settings); // always clean first → idempotent

  if (mode === "uninstall") {
    save(settings);
    console.log("✓ Removed CodePet hooks from " + settingsPath);
    return;
  }

  const cfg = ensureHookConfig();
  const httpHook = {
    type: "http",
    url: `http://127.0.0.1:${cfg.port}${HTTP_MARK}`,
    headers: { "X-CodePet-Token": cfg.token },
    timeout: 5,
  };
  const cmdHook = { type: "command", command: hookCmd, timeout: 5 };

  settings.hooks = settings.hooks || {};
  for (const ev of CMD_EVENTS) {
    settings.hooks[ev] = settings.hooks[ev] || [];
    settings.hooks[ev].push({ matcher: "", hooks: [cmdHook] });
  }
  for (const ev of HTTP_EVENTS) {
    settings.hooks[ev] = settings.hooks[ev] || [];
    settings.hooks[ev].push({ matcher: "", hooks: [httpHook] });
  }

  save(settings);
  console.log("✓ Installed CodePet hooks into " + settingsPath);
  console.log("  command (terminal identity): " + CMD_EVENTS.join(", "));
  console.log(`  http → 127.0.0.1:${cfg.port}: ` + HTTP_EVENTS.join(", "));
}

main();

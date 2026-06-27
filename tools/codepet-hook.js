#!/usr/bin/env node
"use strict";
/*
 * codepet hook bridge — multi-session aware.
 *
 * Claude Code invokes this for several hook events, passing the event JSON on
 * stdin. Each Claude Code session is tracked independently:
 *
 *   ~/.codepet/sessions/<session_id>.json   ← one record per live session
 *   ~/.codepet/state.json                   ← latest event (back-compat)
 *
 * A per-session record accumulates progress across events so the app can show
 * a real summary (current task, state, current action, tool count + trail,
 * elapsed time) for every session at once — not just the most recent write.
 *
 * Usage (configured by install.sh):
 *   node codepet-hook.js <state-or-auto>
 * If the first arg is one of idle|running|waiting|ready we use it directly;
 * otherwise we infer the state from the hook_event_name on stdin.
 */
const fs = require("fs");
const os = require("os");
const path = require("path");

const dir = path.join(os.homedir(), ".codepet");
const sessionsDir = path.join(dir, "sessions");
const stateFile = path.join(dir, "state.json");

const RECENT_TOOLS_MAX = 8;
const PROMPT_MAX = 500;

function readStdin() {
  try {
    return fs.readFileSync(0, "utf8");
  } catch {
    return "";
  }
}

function looksLikeError(payload) {
  const r = payload.tool_response || payload.tool_result;
  if (r && typeof r === "object") {
    if (r.is_error === true || r.error) return true;
    if (typeof r.stderr === "string" && /error|fail|exception/i.test(r.stderr)) return true;
  }
  const nt = (payload.notification_type || "") + " " + (payload.message || "");
  return /error|fail|denied|exception/i.test(nt) && !/permission/i.test(nt);
}

function inferState(event, payload) {
  switch (event) {
    case "UserPromptSubmit":
    case "PreToolUse":
    case "SubagentStop":
      return "running";
    case "PostToolUse":
      return looksLikeError(payload) ? "failed" : "running";
    case "Notification":
      return looksLikeError(payload) ? "failed" : "waiting";
    case "Stop":
      return "ready";
    case "SessionStart":
      return "idle";
    default:
      return null;
  }
}

function detailFor(event, payload) {
  switch (event) {
    case "PreToolUse":
    case "PostToolUse":
      return payload.tool_name ? `${payload.tool_name}` : undefined;
    case "Notification":
      return payload.message || payload.notification_type || "waiting for input";
    case "UserPromptSubmit":
      return "thinking…";
    case "Stop":
      return "done";
    case "SessionStart":
      return "session started";
    default:
      return undefined;
  }
}

function atomicWrite(file, obj) {
  const tmp = file + "." + process.pid + ".tmp";
  fs.writeFileSync(tmp, JSON.stringify(obj));
  fs.renameSync(tmp, file); // atomic replace
}

function safeName(id) {
  // Session ids are uuids, but be defensive about path traversal.
  return String(id).replace(/[^A-Za-z0-9._-]/g, "_");
}

function readSession(file) {
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch {
    return null;
  }
}

// A terminal tab runs only one Claude Code session at a time. When a new session
// starts in a tab, any previous session sharing that tab's identity is dead — so
// drop its record instead of letting it linger as a duplicate/ghost card until
// it ages out. Only matches an exact term_session, and never the new session.
function pruneSupersededSessions(currentId, termSession) {
  if (!termSession) return; // no terminal identity → can't tell tabs apart
  let files;
  try {
    files = fs.readdirSync(sessionsDir);
  } catch {
    return;
  }
  for (const f of files) {
    if (!f.endsWith(".json")) continue;
    const full = path.join(sessionsDir, f);
    const rec = readSession(full);
    if (!rec || rec.session_id === currentId) continue;
    if (rec.term_session && rec.term_session === termSession) {
      try { fs.unlinkSync(full); } catch {}
    }
  }
}

// --- Transcript parsing: derive a task title + a current summary. ----------

function blockText(content) {
  if (typeof content === "string") return content;
  if (Array.isArray(content)) {
    return content
      .filter((b) => b && b.type === "text" && typeof b.text === "string")
      .map((b) => b.text)
      .join(" ");
  }
  return "";
}

function isToolResult(content) {
  return Array.isArray(content) && content.some((b) => b && b.type === "tool_result");
}

function clean(s, n) {
  return String(s).replace(/\s+/g, " ").trim().slice(0, n);
}

/// Read the head (for the first user message) and tail (for the latest
/// assistant message) of the transcript without loading huge files whole.
function readTranscriptChunks(path) {
  try {
    const stat = fs.statSync(path);
    if (!stat.size) return null;
    const fd = fs.openSync(path, "r");
    try {
      const headLen = Math.min(stat.size, 64 * 1024);
      const head = Buffer.alloc(headLen);
      fs.readSync(fd, head, 0, headLen, 0);
      const tailLen = Math.min(stat.size, 256 * 1024);
      const tail = Buffer.alloc(tailLen);
      fs.readSync(fd, tail, 0, tailLen, stat.size - tailLen);
      return { head: head.toString("utf8"), tail: tail.toString("utf8") };
    } finally {
      fs.closeSync(fd);
    }
  } catch {
    return null;
  }
}

function entryRole(o) {
  return (o.message && o.message.role) || o.role || o.type;
}
function entryContent(o) {
  return o.message ? o.message.content : o.content;
}

// A slash-command turn embeds the command + args in tags — turn it into a
// readable title like "codex-goal:pursue-agent <goal>".
function extractCommand(t) {
  const name = (t.match(/<command-name>\s*\/?([^<]+?)\s*<\/command-name>/) || [])[1];
  const args = (t.match(/<command-args>([\s\S]*?)<\/command-args>/) || [])[1];
  if (name) {
    const a = (args || "").trim();
    return (name.trim() + (a ? " " + a : "")).trim();
  }
  return null;
}

// Scaffolding injected around real user input that shouldn't become a title.
const SCAFFOLD = /^(Base directory for this skill:|Caveat:|\[Request interrupted|<system-reminder>|<local-command)/;

// Most recent real user message (scan from the end) — the current task.
function lastUserText(lines) {
  for (let i = lines.length - 1; i >= 0; i--) {
    const line = lines[i];
    if (!line.trim()) continue;
    let o;
    try { o = JSON.parse(line); } catch { continue; }
    if (entryRole(o) !== "user") continue;
    const c = entryContent(o);
    if (isToolResult(c)) continue;          // skip tool outputs
    const raw = blockText(c).trim();
    if (!raw) continue;
    const cmd = extractCommand(raw);         // slash command → readable title
    if (cmd) return cmd;
    if (raw.startsWith("<")) continue;       // other tag-wrapped meta
    if (SCAFFOLD.test(raw)) continue;        // skill/system scaffolding
    return raw;
  }
  return null;
}

function lastAssistantText(lines) {
  for (let i = lines.length - 1; i >= 0; i--) {
    const line = lines[i];
    if (!line.trim()) continue;
    let o;
    try { o = JSON.parse(line); } catch { continue; }
    if (entryRole(o) !== "assistant") continue;
    const t = blockText(entryContent(o)).trim();
    if (t) return t;
  }
  return null;
}

/// Returns { title, summary } gleaned from the transcript — both the latest
/// task (most recent user message) and the latest progress (most recent
/// assistant text), read from the tail so the card reflects what's current.
function transcriptInfo(path) {
  const chunks = readTranscriptChunks(path);
  if (!chunks) return {};
  const out = {};
  const lines = chunks.tail.split("\n");
  const t = lastUserText(lines);
  if (t) out.title = clean(t, 100);
  const s = lastAssistantText(lines);
  if (s) out.summary = clean(s, 200);
  return out;
}

function main() {
  const arg = process.argv[2];
  const raw = readStdin();
  let payload = {};
  try {
    payload = raw ? JSON.parse(raw) : {};
  } catch {
    payload = {};
  }

  const event = payload.hook_event_name || "";
  let state;
  if (["idle", "running", "waiting", "ready"].includes(arg)) {
    state = arg;
  } else {
    state = inferState(event, payload);
  }
  if (!state) process.exit(0); // nothing to do for this event

  const now = Date.now() / 1000;
  const detail = detailFor(event, payload);
  const sessionId = payload.session_id || null;

  // --- Back-compat: single latest-event state file the old app watched. ---
  fs.mkdirSync(dir, { recursive: true });
  atomicWrite(stateFile, {
    state,
    detail,
    session_id: sessionId,
    updated_at: now,
  });

  // --- Per-session record (the multi-session model). ---
  if (sessionId) {
    fs.mkdirSync(sessionsDir, { recursive: true });
    const file = path.join(sessionsDir, safeName(sessionId) + ".json");
    const prev = readSession(file) || {};

    const rec = {
      session_id: sessionId,
      state,
      detail: detail !== undefined ? detail : prev.detail,
      cwd: payload.cwd || prev.cwd || null,
      prompt: prev.prompt || null,
      title: prev.title || null,
      summary: prev.summary || null,
      last_tool: prev.last_tool || null,
      recent_tools: Array.isArray(prev.recent_tools) ? prev.recent_tools.slice() : [],
      tool_count: typeof prev.tool_count === "number" ? prev.tool_count : 0,
      started_at: prev.started_at || now,
      updated_at: now,
      transcript_path: payload.transcript_path || prev.transcript_path || null,
      // Terminal identity — lets the app bring the right terminal forward on
      // click. Set by every terminal emulator in the session's environment.
      term_program: process.env.TERM_PROGRAM || prev.term_program || null,
      term_session: process.env.ITERM_SESSION_ID || process.env.TERM_SESSION_ID
                    || prev.term_session || null,
    };

    // Capture the latest user prompt.
    if (event === "UserPromptSubmit" && typeof payload.prompt === "string") {
      rec.prompt = payload.prompt.trim().slice(0, PROMPT_MAX);
      if (!rec.title) rec.title = clean(payload.prompt, 100);  // fallback title
    }

    // Enrich title (first user message) + summary (latest assistant text) from
    // the transcript so the card shows a real task title and what's happening.
    const tpath = payload.transcript_path || rec.transcript_path;
    if (tpath) {
      const info = transcriptInfo(tpath);
      if (info.title) rec.title = info.title;
      if (info.summary) rec.summary = info.summary;
    }

    // Track tool usage as progress.
    if (event === "PreToolUse" && payload.tool_name) {
      rec.tool_count = (rec.tool_count || 0) + 1;
      rec.last_tool = payload.tool_name;
      rec.recent_tools.push(payload.tool_name);
      if (rec.recent_tools.length > RECENT_TOOLS_MAX) {
        rec.recent_tools = rec.recent_tools.slice(-RECENT_TOOLS_MAX);
      }
    }

    atomicWrite(file, rec);

    // A fresh session in this terminal supersedes any earlier one there.
    if (event === "SessionStart") {
      pruneSupersededSessions(sessionId, rec.term_session);
    }
  }

  process.exit(0);
}

main();

#!/usr/bin/env bun
// Source and preview for the `claude-sessions` channel.
//
//   claude-sessions.ts list            the current project's resumable sessions, newest
//                                      first: this git repo, or the cwd outside one
//   claude-sessions.ts preview <id>    metadata and the tail of the conversation
//   claude-sessions.ts cwd <id>        the directory the session was started in
//
// Sessions come from the Agent SDK's listSessions(), the documented way to list
// what `claude --resume` can open; the transcript JSONL format is internal and
// changes between releases. The version is pinned in the specifier so bun
// auto-installs it into its global cache: there is no node_modules to maintain,
// and that only holds while no directory above this script has one.
import {
  getSessionInfo,
  getSessionMessages,
  listSessions,
  type SDKSessionInfo,
} from "@anthropic-ai/claude-agent-sdk@0.3.300";
import { homedir } from "node:os";

const [cmd, arg] = process.argv.slice(2);

const dim = (s: string) => `\x1b[2m${s}\x1b[0m`;
const bold = (s: string) => `\x1b[1m${s}\x1b[0m`;
const cyan = (s: string) => `\x1b[36m${s}\x1b[0m`;
const yellow = (s: string) => `\x1b[33m${s}\x1b[0m`;
const magenta = (s: string) => `\x1b[35m${s}\x1b[0m`;

const home = homedir();
const tilde = (p: string) => (p.startsWith(home) ? "~" + p.slice(home.length) : p);
const oneLine = (s: string) => s.replace(/\s+/g, " ").trim();
const clip = (s: string, n: number) => (s.length > n ? s.slice(0, n - 1) + "…" : s);

function ago(ms: number): string {
  const s = Math.max(0, (Date.now() - ms) / 1000);
  if (s < 60) return "now";
  if (s < 3600) return `${Math.floor(s / 60)}m`;
  if (s < 86400) return `${Math.floor(s / 3600)}h`;
  if (s < 86400 * 30) return `${Math.floor(s / 86400)}d`;
  return `${Math.floor(s / (86400 * 30))}mo`;
}

const stamp = (ms?: number) =>
  ms ? new Date(ms).toLocaleString("sv-SE").slice(0, 16) : "?";

const branch = (s: SDKSessionInfo) =>
  s.gitBranch && !["main", "master"].includes(s.gitBranch) ? s.gitBranch : "";

// Sessions are filed under the directory claude started in, which is usually
// the repo root, so a picker opened deeper in the repo should still find them.
// listSessions() folds in the repo's worktrees on its own.
function projectRoot(): string {
  const git = Bun.spawnSync(["git", "rev-parse", "--show-toplevel"], { stderr: "ignore" });
  return git.success ? git.stdout.toString().trim() : process.cwd();
}

async function list() {
  const sessions = await listSessions({ dir: projectRoot() });
  sessions.sort((a, b) => b.lastModified - a.lastModified);
  const width = 80;
  for (const s of sessions) {
    // The id trails, padded into a column, so the channel can split it off the
    // end (see `output` in the toml) and a narrow window cuts it rather than
    // the title. Every row is the same project, so only a branch other than
    // main/master is worth showing.
    const title = clip(oneLine(s.summary), width);
    const tag = branch(s) ? clip(branch(s), width - title.length - 1) : "";
    const label = tag ? `${title} ${magenta(tag)}` : title;
    const pad = " ".repeat(Math.max(0, width - title.length - (tag ? tag.length + 1 : 0)));
    console.log([yellow(ago(s.lastModified).padStart(3)), label + pad, dim(s.sessionId)].join(" "));
  }
}

type Block = { type: string; text?: string; name?: string; input?: Record<string, unknown> };

function render(content: unknown): string[] {
  if (typeof content === "string") return [content];
  if (!Array.isArray(content)) return [];
  const out: string[] = [];
  for (const b of content as Block[]) {
    if (b.type === "text" && b.text) out.push(b.text);
    else if (b.type === "tool_use") {
      const hint = b.input?.description ?? b.input?.file_path ?? b.input?.command ?? "";
      out.push(dim(`→ ${b.name} ${oneLine(String(hint)).slice(0, 100)}`));
    }
  }
  return out;
}

// A user turn that only carries tool results, or a harness-injected wrapper,
// is not something the person typed.
const isNoise = (text: string) => /^<(system-reminder|local-command|command-|task-notification)/.test(text.trimStart());

async function preview(id: string) {
  if (!/^[0-9a-f-]{36}$/.test(id ?? "")) {
    console.log("No sessions for this project");
    return;
  }
  const info = await getSessionInfo(id);
  if (!info) {
    console.log(`Session ${id} not found`);
    return;
  }
  console.log(bold(oneLine(info.summary)));
  console.log(`${dim("dir    ")} ${tilde(info.cwd ?? "?")}${info.gitBranch ? dim(" on ") + info.gitBranch : ""}`);
  console.log(`${dim("started")} ${stamp(info.createdAt)}   ${dim("last")} ${stamp(info.lastModified)} (${ago(info.lastModified) === "now" ? "just now" : ago(info.lastModified) + " ago"})`);
  if (info.tag) console.log(`${dim("tag    ")} ${info.tag}`);
  console.log(`${dim("id     ")} ${dim(id.slice(0, 8))}`);

  const turns: string[] = [];
  for (const m of await getSessionMessages(id)) {
    const msg = m.message as { role?: string; content?: unknown };
    const lines = render(msg?.content).filter((t) => t.trim() && !isNoise(t));
    if (!lines.length || m.parent_tool_use_id) continue;
    const who = m.type === "user" ? magenta("❯ you") : cyan("● claude");
    turns.push(`${who}\n${lines.join("\n")}`);
  }

  // The tail is what you need to pick up where you left off; the first prompt
  // says what the session was for.
  const keep = 12;
  console.log();
  if (turns.length > keep + 1) {
    console.log(turns[0]);
    console.log(dim(`\n… ${turns.length - keep - 1} earlier turns …\n`));
    console.log(turns.slice(-keep).join("\n\n"));
  } else {
    console.log(turns.join("\n\n"));
  }
}

// `claude --resume` only finds a session from the directory it ran in, so the
// channel's actions cd here first. They exec claude themselves rather than
// have this script spawn it, which would keep bun alive as its parent.
async function cwd(id: string) {
  const info = await getSessionInfo(id);
  if (!info) {
    console.error(`Session ${id} not found`);
    process.exit(1);
  }
  console.log(info.cwd ?? process.cwd());
}

switch (cmd) {
  case "list":
    await list();
    break;
  case "preview":
    await preview(arg);
    break;
  case "cwd":
    await cwd(arg);
    break;
  default:
    console.error("usage: claude-sessions.ts list | preview <id> | cwd <id>");
    process.exit(2);
}

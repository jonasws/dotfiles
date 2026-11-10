#!/usr/bin/env bun
// agent-sessions adapter for Claude Code. See ../README.md for the contract.
//
//   claude-code.ts list            every session, every project, as NDJSON records
//   claude-code.ts info <id>       one record
//   claude-code.ts messages <id>   the conversation as NDJSON turns
//
// Sessions come from the Agent SDK rather than parsing ~/.claude/projects/*.jsonl,
// whose format is internal to Claude Code. The version is pinned in the
// specifier so bun auto-installs it into its global cache: no node_modules to
// maintain, which only holds while no directory above this script has one.
import {
  getSessionInfo,
  getSessionMessages,
  listSessions,
  type SDKSessionInfo,
} from "@anthropic-ai/claude-agent-sdk@0.3.300";
import { homedir } from "node:os";
import { existsSync } from "node:fs";

const [cmd, arg] = process.argv.slice(2);
const projects = `${homedir()}/.claude/projects`;
const oneLine = (s: string) => s.replace(/\s+/g, " ").trim();

// Claude Code files a session under its start directory with every
// non-alphanumeric character turned into a hyphen. Long paths are hashed
// instead, so fall back to looking for the id in every project directory.
function transcript(s: SDKSessionInfo): string {
  if (s.cwd) {
    const guess = `${projects}/${s.cwd.replace(/[^a-zA-Z0-9]/g, "-")}/${s.sessionId}.jsonl`;
    if (existsSync(guess)) return guess;
  }
  const hit = new Bun.Glob(`*/${s.sessionId}.jsonl`).scanSync({ cwd: projects }).next();
  return hit.done ? "" : `${projects}/${hit.value}`;
}

function record(s: SDKSessionInfo) {
  return {
    harness: "claude-code",
    id: s.sessionId,
    title: oneLine(s.summary ?? ""),
    first_prompt: oneLine(s.firstPrompt ?? ""),
    cwd: s.cwd ?? "",
    branch: s.gitBranch ?? "",
    created: s.createdAt ?? null,
    updated: s.lastModified,
    size: s.fileSize ?? null,
    transcript: transcript(s),
    resume: ["claude", "--resume", s.sessionId],
    fork: ["claude", "--resume", s.sessionId, "--fork-session"],
  };
}

type Block = { type: string; text?: string; name?: string; input?: Record<string, unknown> };

// A user turn that only carries tool results, or a harness-injected wrapper,
// is not something the person typed.
const isNoise = (text: string) =>
  /^<(system-reminder|local-command|command-|task-notification|agent-message)/.test(text.trimStart());

function toolHint(b: Block): string {
  const i = b.input ?? {};
  const hint = i.description ?? i.file_path ?? i.command ?? i.pattern ?? i.query ?? i.url ?? i.prompt ?? "";
  return oneLine(String(hint)).slice(0, 120);
}

async function messages(id: string) {
  for (const m of await getSessionMessages(id)) {
    if (m.parent_tool_use_id) continue;
    const msg = m.message as { role?: string; content?: unknown };
    const content = msg?.content;
    const texts: string[] = [];
    const tools: { name: string; hint: string; file?: string }[] = [];
    if (typeof content === "string") texts.push(content);
    else if (Array.isArray(content)) {
      for (const b of content as Block[]) {
        if (b.type === "text" && b.text) texts.push(b.text);
        else if (b.type === "tool_use") {
          const file = typeof b.input?.file_path === "string" ? (b.input.file_path as string) : undefined;
          tools.push({ name: b.name ?? "?", hint: toolHint(b), ...(file ? { file } : {}) });
        }
      }
    }
    const text = texts.filter((t) => t.trim() && !isNoise(t)).join("\n");
    if (!text && !tools.length) continue;
    const at = (m as { timestamp?: string }).timestamp;
    console.log(JSON.stringify({ role: m.type === "user" ? "user" : "assistant", text, tools, ...(at ? { at } : {}) }));
  }
}

switch (cmd) {
  case "list":
    for (const s of await listSessions()) console.log(JSON.stringify(record(s)));
    break;
  case "info": {
    const s = await getSessionInfo(arg);
    if (!s) {
      console.error(`claude-code: no session ${arg}`);
      process.exit(1);
    }
    console.log(JSON.stringify(record(s)));
    break;
  }
  case "messages":
    await messages(arg);
    break;
  default:
    console.error("usage: claude-code.ts list | info <id> | messages <id>");
    process.exit(2);
}

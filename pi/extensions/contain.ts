/**
 * The permission rules of claude/settings.json, for pi.
 *
 * This is not the boundary. The pi-agent nono profile is: it makes the denied
 * commands unrunnable, the protected paths unwritable and herdr reachable only
 * through pi-herdr, whatever the command line looks like. Matching a shell
 * string is easy to evade (`h=gh; $h`), so these rules exist to fail early
 * with a reason the model can act on instead of a bare EPERM, and to ask the
 * user before the destructive-but-allowed git and docker commands that Claude
 * Code asks about too. In print mode (`pi -p` children) there is nobody to
 * ask, so asking means blocking.
 */

import { existsSync, realpathSync } from "node:fs";
import { homedir } from "node:os";
import { basename, dirname, isAbsolute, resolve } from "node:path";
import { isToolCallEventType } from "@earendil-works/pi-coding-agent";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

type Verdict = { action: "block" | "ask"; reason: string } | undefined;

const HOME = homedir();

const DENIED: Record<string, string> = {
	gh: "gh is not available: it has no credential in the sandbox. Use the github MCP tools (read-only, public repos), or tell the user the gh command to run.",
	op: "1Password is not reachable from the sandbox.",
	fnox: "fnox secrets are not reachable from the sandbox.",
	twg: "twg is not available to agents.",
};

// Mirrors the session allowlist in nono/profiles/pi-agent.jsonc.
const HERDR_READS = new Set([
	"--version",
	"--help",
	"status",
	"api snapshot",
	"api schema",
	"notification show",
	"pane list",
	"pane current",
	"pane get",
	"pane layout",
	"pane process-info",
	"pane neighbor",
	"pane edges",
	"pane read",
	"pane wait-output",
	"pane focus",
	"pane zoom",
	"tab list",
	"tab get",
	"tab focus",
	"workspace list",
	"workspace get",
	"workspace focus",
	"worktree list",
	"agent list",
	"agent get",
	"agent read",
	"agent wait",
	"agent explain",
	"agent focus",
]);

const HERDR_REASON =
	"herdr commands that change layout or drive agents run outside the sandbox. Use pi-herdr spawn|prompt|interrupt|stop for pi children; herdr reads (agent read/wait/list, pane read) work directly.";

const WRAPPERS = new Set(["command", "exec", "env", "nohup", "time", "sudo", "builtin"]);
const SOCKET_CLIENTS = new Set(["nc", "ncat", "socat", "curl", "python", "python3", "node", "perl", "ruby"]);

/** Split a shell command into simple commands, as word lists without env assignments or wrappers. */
function simpleCommands(command: string): string[][] {
	return command
		.split(/\|\||&&|[;&|\n()`]|\$\(/)
		.map((part) => part.trim().split(/\s+/).filter(Boolean))
		.map((words) => {
			let i = 0;
			while (i < words.length && (/^[A-Za-z_][A-Za-z0-9_]*=/.test(words[i]) || WRAPPERS.has(words[i]))) i++;
			const rest = words.slice(i).map((w) => w.replace(/^['"]|['"]$/g, ""));
			if (rest[0]) rest[0] = basename(rest[0]);
			return rest;
		})
		.filter((words) => words.length > 0);
}

function gitVerdict(words: string[]): Verdict {
	// Skip global options: -C <dir> and -c <key=value> take a value.
	let i = 1;
	while (i < words.length && words[i].startsWith("-")) i += words[i] === "-C" || words[i] === "-c" ? 2 : 1;
	const sub = words[i];
	const args = words.slice(i + 1);
	const has = (test: (arg: string) => boolean) => args.some(test);
	if (sub === "push" && has((a) => a.startsWith("--force") || a === "-f" || a === "--delete" || a === "-d")) {
		return { action: "ask", reason: "force push or remote branch delete" };
	}
	if (sub === "reset" && has((a) => a === "--hard")) return { action: "ask", reason: "git reset --hard" };
	if (sub === "clean" && has((a) => a === "--force" || /^-[a-zA-Z]*f/.test(a))) {
		return { action: "ask", reason: "git clean -f" };
	}
	if (sub === "rebase") return { action: "ask", reason: "git rebase" };
	return undefined;
}

function dockerVerdict(words: string[]): Verdict {
	const args = words.slice(1);
	const risky = args.some(
		(a, i) =>
			a === "--privileged" ||
			/^--(pid|network|net|userns)=host$/.test(a) ||
			(/^--(pid|network|net|userns)$/.test(a) && args[i + 1] === "host") ||
			/^--(cap-add|security-opt|device)/.test(a) ||
			a.includes("docker.sock"),
	);
	return risky ? { action: "ask", reason: "docker with host-level access" } : undefined;
}

function bashVerdict(command: string): Verdict {
	for (const words of simpleCommands(command)) {
		const name = words[0];
		if (DENIED[name]) return { action: "block", reason: DENIED[name] };
		if (name === "herdr") {
			if (words.includes("--") || words.some((w) => w.startsWith("--machine"))) {
				return { action: "block", reason: HERDR_REASON };
			}
			const sub = words.slice(1, 3).join(" ");
			const one = words[1] ?? "";
			if (!HERDR_READS.has(sub) && !HERDR_READS.has(one)) return { action: "block", reason: HERDR_REASON };
		}
		if (SOCKET_CLIENTS.has(name) && words.some((w) => /(herdr|docker)\.sock/.test(w))) {
			return {
				action: "block",
				reason: "Talk to herdr and docker through their CLIs, not their sockets.",
			};
		}
		if (name === "git") {
			const verdict = gitVerdict(words);
			if (verdict) return verdict;
		}
		if (name === "docker") {
			const verdict = dockerVerdict(words);
			if (verdict) return verdict;
		}
	}
	return undefined;
}

/** Resolve through symlinks, as the sandbox does: linked config resolves into ~/dotfiles. */
function realTarget(path: string, cwd: string): string {
	const absolute = resolve(cwd, path.startsWith("~/") ? `${HOME}/${path.slice(2)}` : path);
	let probe = absolute;
	while (!existsSync(probe) && dirname(probe) !== probe) probe = dirname(probe);
	try {
		return realpathSync(probe) + absolute.slice(probe.length);
	} catch {
		return absolute;
	}
}

const PROTECTED = [
	...["claude", "fish", "fnox", "herdr", "nono", "pi", "git", "mise-global", "mise.toml"].map((p) => `${HOME}/dotfiles/${p}`),
	...["extensions", "prompts", "skills", "themes", "npm", "git", "SYSTEM.md", "APPEND_SYSTEM.md", "models.json", "auth.json", "keybindings.json"].map(
		(p) => `${HOME}/.pi/agent/${p}`,
	),
	`${HOME}/.config`,
	`${HOME}/.local/bin`,
	`${HOME}/.local/share/mise`,
	`${HOME}/Library/LaunchAgents`,
];

const ENV_FILE = /(\.env|\.env\.[^/]*|-env)$/;

function pathVerdict(tool: string, path: string, cwd: string): Verdict {
	const target = realTarget(path, cwd);
	if (ENV_FILE.test(target)) return { action: "block", reason: `${path}: env files are not readable in the sandbox` };
	if (tool === "read") return undefined;
	if (PROTECTED.some((p) => target === p || target.startsWith(`${p}/`)) || /\/\.git\/(hooks(\/|$)|config$)/.test(target)) {
		return {
			action: "block",
			reason: `${path} is part of the agent's own containment or runs in the user's shell; the sandbox makes it read-only. Describe the change for the user instead.`,
		};
	}
	if (/(^|\/)(\.?mise(\.local)?\.toml|\.tool-versions|\.envrc|\.?mise\/config\.toml)$/.test(target)) {
		return { action: "ask", reason: `${path} configures the shell of anyone who enters this directory` };
	}
	return undefined;
}

async function enforce(verdict: Verdict, detail: string, ctx: ExtensionContext) {
	if (!verdict) return undefined;
	if (verdict.action === "ask" && ctx.hasUI) {
		if (await ctx.ui.confirm(`Allow: ${verdict.reason}?`, detail)) return undefined;
		return { block: true, reason: `The user declined: ${verdict.reason}` };
	}
	const why = verdict.action === "ask" ? `${verdict.reason} needs the user's approval, and no one can approve here` : verdict.reason;
	return { block: true, reason: why };
}

export default function (pi: ExtensionAPI) {
	pi.on("session_start", async (_event, ctx) => {
		if (process.env.AGENT_SANDBOX !== "nono" && ctx.hasUI) {
			ctx.ui.notify("pi is running outside the pi-agent nono sandbox: nothing contains it", "warning");
		}
	});

	pi.on("tool_call", async (event, ctx) => {
		if (isToolCallEventType("bash", event)) {
			return enforce(bashVerdict(event.input.command), event.input.command, ctx);
		}
		if (isToolCallEventType("read", event) || isToolCallEventType("write", event) || isToolCallEventType("edit", event)) {
			const path = event.input.path;
			return enforce(pathVerdict(event.toolName, path, isAbsolute(path) ? "/" : ctx.cwd), path, ctx);
		}
		return undefined;
	});
}

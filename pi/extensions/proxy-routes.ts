/**
 * Points pi at the credential routes of the pi-agent nono profile.
 *
 * nono's proxy listens on a fresh port per sandbox and exports one base URL
 * per route (ANTHROPIC_BASE_URL, EXA_BASE_URL, GITHUB_MCP_BASE_URL) next to a
 * phantom token in the route's env_var. pi ignores ANTHROPIC_BASE_URL (its
 * built-in models carry their own baseUrl), models.json cannot interpolate a
 * baseUrl, and mcp.json cannot interpolate a url, so the routes are wired up
 * here at load time instead. Headers keep `${NAME}` references, which pi
 * resolves itself, so no token value passes through this file.
 *
 * Outside the pi-agent sandbox this does nothing, whatever the environment
 * says.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function (pi: ExtensionAPI) {
	const env = process.env;
	if (env.AGENT_SANDBOX !== "nono") return;

	if (env.ANTHROPIC_BASE_URL) {
		// Only the URL changes; the built-in catalog and API stay.
		pi.registerProvider("anthropic", { baseUrl: env.ANTHROPIC_BASE_URL });
	}

	if (env.EXA_BASE_URL && env.EXA_API_KEY) {
		pi.registerMcpServer("exa", {
			url: `${env.EXA_BASE_URL}/mcp`,
			headers: { "x-api-key": "${EXA_API_KEY}" },
			description: "Exa web search and page fetching",
			// Two tools, used often: not worth a search step.
			exposure: "direct",
		});
	}

	if (env.GITHUB_MCP_BASE_URL && env.GITHUB_MCP_TOKEN) {
		pi.registerMcpServer("github", {
			url: `${env.GITHUB_MCP_BASE_URL}/mcp/`,
			headers: {
				Authorization: "Bearer ${GITHUB_MCP_TOKEN}",
				// The token can read public repositories and nothing else; the
				// header also keeps write tools from being registered at all.
				"X-MCP-Readonly": "true",
			},
			description: "GitHub, read-only and public repositories only",
			exposure: "deferred",
		});
	}
}

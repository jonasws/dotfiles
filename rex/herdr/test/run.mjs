// End-to-end test of the herdr socket: the real bridge.mjs and server.lua,
// with server.lua running in harness.lua's scripted Rex under Lua 5.1, talked
// to over the real socket the way herdr clients talk to herdr.
//
//   node rex/herdr/test/run.mjs          needs node, lua5.1, nc and jq
//   node rex/herdr/test/run.mjs --keep   leaves the socket up for a minute
import { spawn } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync, existsSync, rmSync } from 'node:fs';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const TEST = path.dirname(fileURLToPath(import.meta.url));
const REX = path.dirname(TEST);
const REPO = path.resolve(REX, '..', '..');
const HERE = mkdtempSync(path.join(os.tmpdir(), 'rex-herdr-test-'));
const SOCKET = path.join(HERE, 'herdr.sock');
const CONFIG = path.join(HERE, 'config');
rmSync(CONFIG, { recursive: true, force: true });
mkdirSync(path.join(CONFIG, 'herdr'), { recursive: true });
// A herdr plugin as `herdr plugin install` records it.
mkdirSync(path.join(HERE, 'plugin'), { recursive: true });
writeFileSync(path.join(CONFIG, 'herdr', 'plugins.json'), JSON.stringify([{
  plugin_id: 'test.echo', name: 'Echo', version: '1', min_herdr_version: '0.9.0', manifest_path: path.join(HERE, 'plugin', 'herdr-plugin.toml'),
  plugin_root: path.join(HERE, 'plugin'), enabled: true, build: [], startup: [], events: [], link_handlers: [], warnings: [], source: { kind: 'local' },
  actions: [{ id: 'say', title: 'Say', contexts: [], command: ['sh', '-c', 'env | grep ^HERDR_ | sort > "$HERDR_PLUGIN_STATE_DIR/env.txt"'] }],
  panes: [{ id: 'board', title: 'Board', placement: 'overlay', command: ['sh', '-c', 'echo board'] }],
}]));

const env = { ...process.env, XDG_CONFIG_HOME: CONFIG, XDG_STATE_HOME: path.join(HERE, 'state') };
const bridge = spawn('node', [path.join(REX, 'bridge.mjs'), SOCKET], { env });
const lua = spawn('lua5.1', [path.join(TEST, 'harness.lua'), path.join(REX, 'server.lua'), SOCKET], { env });
bridge.stdout.pipe(lua.stdin, { end: false });
lua.stdout.pipe(bridge.stdin);
let errors = '';
lua.stderr.on('data', d => { errors += d; });
bridge.stderr.on('data', d => { errors += d; });
const tick = setInterval(() => lua.stdin.write('T\n'), 20);
const inject = (name, ctx, ev) => lua.stdin.write(`X ${name} ${JSON.stringify({ ctx, ev })}\n`);
const mutate = edit => lua.stdin.write(`M ${JSON.stringify(edit)}\n`);
const sleep = ms => new Promise(r => setTimeout(r, ms));

function call(method, params = {}) {
  return new Promise((resolve, reject) => {
    const s = net.createConnection(SOCKET);
    let b = '';
    s.setEncoding('utf8');
    s.setTimeout(8000, () => { s.destroy(); reject(new Error(`${method} timed out`)); });
    s.on('connect', () => s.write(JSON.stringify({ id: `t:${method}`, method, params }) + '\n'));
    s.on('data', d => { b += d; });
    s.on('end', () => { try { resolve(JSON.parse(b)); } catch (e) { reject(new Error(`${method}: ${b}`)); } });
    s.on('error', reject);
  });
}

function subscribe(subscriptions) {
  const s = net.createConnection(SOCKET);
  const lines = [];
  let b = '';
  s.setEncoding('utf8');
  s.on('connect', () => s.write(JSON.stringify({ id: 'sub', method: 'events.subscribe', params: { subscriptions } }) + '\n'));
  s.on('data', d => { b += d; let i; while ((i = b.indexOf('\n')) >= 0) { lines.push(JSON.parse(b.slice(0, i))); b = b.slice(i + 1); } });
  return { lines, close: () => s.destroy() };
}

let failures = 0;
const check = (name, ok, detail = '') => { console.log(`${ok ? 'ok  ' : 'FAIL'} ${name}${detail ? ` — ${detail}` : ''}`); if (!ok) failures++; };

for (let i = 0; i < 100 && !existsSync(SOCKET); i++) await sleep(50);
await sleep(200);

const S1 = 'session:00000000-0000-7000-8000-0000aaaa1111';
const B = n => `block:00000000-0000-7000-8000-${n.toString(16).padStart(12, '0')}`;

const pong = await call('ping');
check('ping', pong.result?.type === 'pong' && pong.result.protocol === 22 && /\+rex$/.test(pong.result.version), JSON.stringify(pong.result));

const snap = (await call('session.snapshot')).result.snapshot;
check('snapshot shape', snap.workspaces.length === 2 && snap.tabs.length === 3 && snap.panes.length === 4 && snap.agents.length === 2 && snap.layouts.length === 3,
  `ws ${snap.workspaces.length} tabs ${snap.tabs.length} panes ${snap.panes.length} agents ${snap.agents.length}`);
const p1 = snap.panes[0], p2 = snap.panes[1];
check('pane ids herdr-shaped', snap.panes.every(p => /^w[0-9a-f]{12}:p[0-9a-f]{12}$/.test(p.pane_id)), p1.pane_id);
check('agent mapping', p1.agent === 'claude' && p1.display_agent === 'claude-code' && p1.agent_status === 'working' && p1.state_labels?.working === 'Refactoring the parser');
check('error/blocked mapping', snap.panes[3].agent_status === 'blocked' && snap.agents.some(a => a.agent === 'codex'));
check('shell title like herdr', p2.terminal_title_stripped === '/Users/me/dotfiles' && !p2.agent, p2.terminal_title_stripped);
check('nvim title', snap.panes[2].terminal_title_stripped === 'nvim /Users/me/dotfiles/rex', snap.panes[2].terminal_title_stripped);
check('focused', snap.focused_pane_id === p1.pane_id && snap.workspaces[0].focused && snap.panes[0].focused);
check('workspace rollup', snap.workspaces[0].agent_status === 'working' && snap.workspaces[1].agent_status === 'blocked');
const lay = snap.layouts[0];
check('layout rects', lay.panes.length === 2 && lay.panes[0].rect.width === 500 && lay.panes[1].rect.x === 500, JSON.stringify(lay.panes.map(p => p.rect)));

const nb = (await call('pane.neighbor', { pane_id: p1.pane_id, direction: 'right' })).result.neighbor;
check('pane.neighbor', nb.neighbor_pane_id === p2.pane_id);
const edges = (await call('pane.edges', { pane_id: p1.pane_id })).result.edges;
check('pane.edges', edges.left && !edges.right && edges.up && edges.down);
const read = (await call('pane.read', { pane_id: p1.pane_id, source: 'visible', format: 'text' })).result.read;
check('pane.read visible', read.text === 'hello from claude\n> doing work\n' && read.pane_id === p1.pane_id, JSON.stringify(read.text));
const read1 = (await call('pane.read', { pane_id: p1.pane_id, source: 'recent', lines: 1 })).result.read;
check('pane.read lines', read1.text === '> doing work\n' && read1.truncated);
const cur = (await call('pane.current', { caller_pane_id: p2.pane_id })).result;
check('pane.current', cur.type === 'pane_current' && cur.pane.pane_id === p2.pane_id);
const proc = (await call('pane.process_info', { pane_id: p2.pane_id })).result.process_info;
check('pane.process_info', proc.foreground_processes[0].name === 'fish' && proc.shell_pid === 50);

await call('pane.send_text', { pane_id: p2.pane_id, text: 'echo hi' });
await call('pane.send_keys', { pane_id: p2.pane_id, keys: ['Enter', 'ctrl+c', 'C-d', 'Up', 'alt+b'] });
const typed = (await call('pane.read', { pane_id: p2.pane_id, source: 'recent' })).result.read.text;
check('send_text + send_keys', typed.includes('echo hi\r\x03\x04\x1b[A\x1bb'), JSON.stringify(typed.slice(-20)));

// Events: lifecycle plus a per-pane status subscription.
const sub = subscribe([{ type: 'pane.created' }, { type: 'pane.closed' }, { type: 'tab.renamed' }, { type: 'pane.agent_status_changed', pane_id: p1.pane_id }]);
await sleep(150);
check('subscription_started', sub.lines[0]?.result?.type === 'subscription_started');

const split = (await call('pane.split', { target_pane_id: p2.pane_id, direction: 'down', focus: true })).result;
await sleep(150);
check('pane.split', split.type === 'pane_info' && /:p/.test(split.pane.pane_id) && split.pane.cwd === '/Users/me', split.pane.pane_id);
const created = sub.lines.find(l => l.event === 'pane_created');
check('pane_created event', created?.data?.type === 'pane_created' && created.data.pane.pane_id === split.pane.pane_id);

const zoom = (await call('pane.zoom', { pane_id: split.pane.pane_id, mode: 'toggle' })).result.zoom;
check('pane.zoom', zoom.zoomed && zoom.changed);
const renamed = (await call('pane.rename', { pane_id: split.pane.pane_id, label: 'logs' })).result.pane;
check('pane.rename', renamed.label === 'logs');
const focus = (await call('pane.focus', { pane_id: p1.pane_id })).result;
check('pane.focus', focus.type === 'pane_info' && focus.pane.focused, JSON.stringify(focus.pane?.focused));
await call('pane.close', { pane_id: split.pane.pane_id });
await sleep(150);
check('pane_closed event', sub.lines.some(l => l.event === 'pane_closed' && l.data.pane_id === split.pane.pane_id));

// Program status change → per-pane event and the lifecycle rollup.
const waiting = call('events.wait', { match_event: { event: 'pane_agent_status_changed', pane_id: p1.pane_id, agent_status: 'done' }, timeout_ms: 3000 });
const agentWait = call('agent.wait', { target: p1.pane_id, until: ['done'], timeout_ms: 3000 });
await sleep(100);
mutate({ block_id: B(1), set: { records: [{ id: '', state: 'done', app: 'claude-code', msg: 'All tests pass' }] } });
inject('terminal.program_status_changed', { session_id: S1, block_id: B(1) }, { id: '', record: { state: 'done' } });
const waited = await waiting;
check('events.wait', waited.result?.type === 'wait_matched' && waited.result.event.data.agent_status === 'done', JSON.stringify(waited).slice(0, 120));
const aw = await agentWait;
check('agent.wait', aw.result?.agent?.agent_status === 'done');
await sleep(100);
const perPane = sub.lines.find(l => l.event === 'pane.agent_status_changed');
check('per-pane status event', perPane && perPane.data.agent_status === 'done' && perPane.data.type === undefined && perPane.data.state_labels?.done === 'All tests pass', JSON.stringify(perPane));
const timeout = await call('events.wait', { match_event: { event: 'pane_closed', pane_id: 'w0:p0' }, timeout_ms: 200 });
check('events.wait timeout', timeout.error?.code === 'timeout');

// Output waits are polled.
const outWait = call('pane.wait_for_output', { pane_id: p2.pane_id, source: 'recent', match: { type: 'substring', value: 'BUILD OK' }, timeout_ms: 3000 });
await sleep(200);
mutate({ block_id: B(2), set: { screen: '$ make\nBUILD OK\n' } });
const ow = await outWait;
check('pane.wait_for_output', ow.result?.type === 'output_matched' && ow.result.matched_line === 'BUILD OK');

// Workspaces and tabs.
const ws = (await call('workspace.create', { label: 'scratch', focus: true })).result;
check('workspace.create', ws.type === 'workspace_created' && ws.workspace.label === 'scratch' && ws.root_pane.pane_id.startsWith(ws.workspace.workspace_id + ':p'));
const wr = (await call('workspace.rename', { workspace_id: ws.workspace.workspace_id, label: 'scratch2' })).result;
check('workspace.rename', wr.workspace?.label === 'scratch2');
const tab = (await call('tab.create', { workspace_id: snap.workspaces[0].workspace_id, label: 'build' })).result;
check('tab.create', tab.type === 'tab_created' && tab.tab.label === 'build' && tab.root_pane.tab_id === tab.tab.tab_id);
const tr = (await call('tab.rename', { tab_id: tab.tab.tab_id, label: 'build2' })).result;
await sleep(100);
check('tab.rename + event', tr.tab.label === 'build2' && sub.lines.some(l => l.event === 'tab_renamed' && l.data.label === 'build2'));
const tabs = (await call('tab.list', { workspace_id: snap.workspaces[0].workspace_id })).result.tabs;
check('tab.list', tabs.length === 3);

// Agents.
const al = (await call('agent.list')).result.agents;
check('agent.list', al.length === 2);
const ag = (await call('agent.get', { target: 'codex' })).result;
check('agent.get by kind', ag?.agent?.agent === 'codex');
await call('agent.prompt', { target: 'codex', text: 'yes' });
check('agent.prompt', (await call('pane.read', { pane_id: snap.panes[3].pane_id, source: 'recent' })).result.read.text.includes('yes\r'));
await call('pane.report_agent', { pane_id: p2.pane_id, source: 'crush', agent: 'crush', state: 'working', message: 'thinking', seq: 5 });
await call('pane.report_agent', { pane_id: p2.pane_id, source: 'crush', agent: 'crush', state: 'idle', seq: 4 });
const reported = (await call('pane.get', { pane_id: p2.pane_id })).result.pane;
check('pane.report_agent (+ stale seq ignored)', reported.agent === 'crush' && reported.agent_status === 'working', `${reported.agent} ${reported.agent_status}`);

// Errors, as herdr answers them.
check('unknown method', (await call('pane.fly')).error?.code === 'invalid_request');
check('unsupported method', (await call('layout.apply')).error?.code === 'unsupported');
check('missing pane', (await call('pane.get', { pane_id: 'w000000000000:p000000000000' })).error?.code === 'pane_not_found');

// Plugins from herdr's registry.
const pl = (await call('plugin.list')).result.plugins;
check('plugin.list', pl.length === 1 && pl[0].plugin_id === 'test.echo');
const inv = (await call('plugin.action.invoke', { action_id: 'test.echo.say' })).result;
check('plugin.action.invoke', inv?.type === 'plugin_action_invoked' && inv.context.focused_pane_id);
await sleep(500);
const envFile = path.join(HERE, 'state', 'herdr', 'plugins', 'test.echo', 'env.txt');
const envText = existsSync(envFile) ? readFileSync(envFile, 'utf8') : '';
check('plugin env', /HERDR_PLUGIN_ACTION_ID=say/.test(envText) && envText.includes(`HERDR_SOCKET_PATH=${SOCKET}`) && /HERDR_PANE_ID=w/.test(envText), envText.split('\n').join(' ').slice(0, 160));
const po = (await call('plugin.pane.open', { plugin_id: 'test.echo', entrypoint: 'board' })).result;
check('plugin.pane.open', po?.type === 'plugin_pane_opened' && po.plugin_pane.pane.pane_id);
check('popup.close', (await call('popup.close')).result?.type === 'ok');

// Your herdr-focus.sh, over nc as it does.
// Async: this process pipes the bridge to the server, so it must not block.
const hf = await new Promise(resolve => {
  const child = spawn('bash', [path.join(REPO, 'television', 'scripts', 'herdr-focus.sh'), snap.panes[3].pane_id], { env: { ...process.env, HERDR_SOCKET_PATH: SOCKET, HERDR_ENV: '1' } });
  let err = '';
  child.stderr.on('data', d => { err += d; });
  child.on('exit', code => resolve({ code, err }));
});
check('herdr-focus.sh', hf.code === 0, hf.err.trim());

sub.close();
console.log(failures ? `${failures} FAILED` : 'all passed');
if (process.argv.includes('--keep')) { console.log('socket kept at', SOCKET); await sleep(Number(process.argv.at(-1)) || 60000); }
clearInterval(tick);
lua.stdin.end();
await sleep(300);
const noise = /client.queue|exec.start|server loaded|answering/;
const stderr = errors.split('\n').filter(l => l.trim() && !noise.test(l)).join('\n');
if (stderr) console.log('--- stderr ---\n' + stderr.slice(0, 3000));
bridge.kill(); lua.kill();
rmSync(HERE, { recursive: true, force: true });
process.exit(failures ? 1 : 0);

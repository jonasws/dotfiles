#!/usr/bin/env node
// Starts, stops and talks to herdr/server.lua, Rex's herdr socket.
//
//   ctl.mjs ensure              start it unless it answers; print the socket path
//   ctl.mjs path                print the socket path
//   ctl.mjs status              exit 0 when it answers
//   ctl.mjs stop                stop it
//   ctl.mjs call METHOD [JSON]  send one request and print the answer
//   ctl.mjs dashboard           herdr-f1: its herdr plugin when installed, else
//                               the herdr-f1 CLI pointed at this socket
//   ctl.mjs dashboard-stop      stop herdr-f1
//
// The socket is $TMPDIR/rex-herdr-<uid>.sock unless REX_HERDR_SOCKET says
// otherwise; fish/conf.d/45-rex-herdr.fish computes the same path.
import { spawn, spawnSync } from 'node:child_process';
import { closeSync, openSync, readFileSync } from 'node:fs';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const SOCKET = process.env.REX_HERDR_SOCKET || path.join(os.tmpdir(), `rex-herdr-${os.userInfo().uid}.sock`);
const REX = process.env.REX_BIN || 'rex';
const LOG = `${SOCKET}.log`;
const F1_ACTION = 'dev.minung.herdr-f1.open';

export function call(method, params = {}) {
  return new Promise((resolve, reject) => {
    const socket = net.createConnection(SOCKET);
    let buffer = '';
    socket.setEncoding('utf8');
    socket.setTimeout(10000, () => socket.destroy(new Error(`${method} timed out`)));
    socket.on('connect', () => socket.write(JSON.stringify({ id: `ctl:${method}`, method, params }) + '\n'));
    socket.on('data', data => {
      buffer += data;
      const nl = buffer.indexOf('\n');
      if (nl >= 0) { socket.destroy(); resolve(JSON.parse(buffer.slice(0, nl))); }
    });
    socket.on('error', reject);
  });
}

async function alive() {
  try { return Boolean((await call('ping')).result); } catch { return false; }
}

async function ensure() {
  if (await alive()) return SOCKET;
  const log = openSync(LOG, 'a');
  const child = spawn(REX, ['do', path.join(HERE, 'server.lua'), '--all', `socket=${SOCKET}`, `dir=${HERE}`], {
    detached: true, stdio: ['ignore', log, log],
  });
  child.on('error', err => { console.error(`cannot run ${REX}: ${err.message}`); process.exit(1); });
  child.unref();
  closeSync(log);
  for (let i = 0; i < 100; i++) {
    await new Promise(r => setTimeout(r, 100));
    if (await alive()) return SOCKET;
  }
  console.error(`the herdr socket did not come up; see ${LOG}`);
  process.exit(1);
}

function stop() {
  try { process.kill(Number(readFileSync(`${SOCKET}.pid`, 'utf8')), 'SIGTERM'); } catch {}
}

function herdrF1(...args) {
  const which = spawnSync('sh', ['-c', 'command -v herdr-f1'], { encoding: 'utf8' });
  return which.status === 0 ? [which.stdout.trim(), args] : ['npx', ['--yes', 'herdr-f1', ...args]];
}

const [command = 'ensure', ...rest] = process.argv.slice(2);
switch (command) {
  case 'ensure': console.log(await ensure()); break;
  case 'path': console.log(SOCKET); break;
  case 'status': process.exit((await alive()) ? 0 : 1); break;
  case 'stop': stop(); break;
  case 'call': {
    await ensure();
    const answer = await call(rest[0], rest[1] ? JSON.parse(rest[1]) : {});
    console.log(JSON.stringify(answer));
    process.exit(answer.error ? 1 : 0);
    break;
  }
  case 'dashboard': {
    await ensure();
    const answer = await call('plugin.action.invoke', { action_id: F1_ACTION });
    if (answer.result) break;
    const [bin, argv] = herdrF1('start', '--socket', SOCKET, '--open');
    process.exit(spawnSync(bin, argv, { stdio: 'inherit' }).status ?? 1);
    break;
  }
  case 'dashboard-stop': {
    const [bin, argv] = herdrF1('stop', '--socket', SOCKET);
    spawnSync(bin, argv, { stdio: 'inherit', timeout: 10000 });
    break;
  }
  default:
    console.error('usage: ctl.mjs ensure | path | status | stop | call METHOD [JSON] | dashboard | dashboard-stop');
    process.exit(2);
}

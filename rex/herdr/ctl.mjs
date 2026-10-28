#!/usr/bin/env node
// Talks to herdr/server.lua, Rex's herdr socket.
//
//   ctl.mjs path                print the socket path
//   ctl.mjs status              exit 0 when it answers
//   ctl.mjs restart             ask launchd to restart it
//   ctl.mjs call METHOD [JSON]  send one request and print the answer
//   ctl.mjs dashboard           herdr-f1: its herdr plugin when installed, else
//                               the herdr-f1 CLI pointed at this socket
//   ctl.mjs dashboard-stop      stop herdr-f1
//
// The server is the com.jonasws.rex-herdr LaunchAgent (herdr/serve). Its socket
// is $XDG_STATE_HOME/rex/herdr.sock unless REX_HERDR_SOCKET says otherwise;
// fish/conf.d/45-rex-herdr.fish computes the same path.
import { spawnSync } from 'node:child_process';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';

const STATE = process.env.XDG_STATE_HOME || path.join(os.homedir(), '.local', 'state');
const SOCKET = process.env.REX_HERDR_SOCKET || path.join(STATE, 'rex', 'herdr.sock');
const LABEL = 'com.jonasws.rex-herdr';
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

async function up() {
  if (await alive()) return SOCKET;
  console.error(`the herdr socket does not answer at ${SOCKET}; see ${STATE}/rex/herdr.log`);
  process.exit(1);
}

function herdrF1(...args) {
  const which = spawnSync('sh', ['-c', 'command -v herdr-f1'], { encoding: 'utf8' });
  return which.status === 0 ? [which.stdout.trim(), args] : ['npx', ['--yes', 'herdr-f1', ...args]];
}

const [command = 'path', ...rest] = process.argv.slice(2);
switch (command) {
  case 'path': console.log(SOCKET); break;
  case 'status': process.exit((await alive()) ? 0 : 1); break;
  case 'restart': process.exit(spawnSync('launchctl', ['kickstart', '-k', `gui/${os.userInfo().uid}/${LABEL}`], { stdio: 'inherit' }).status ?? 1);
  case 'call': {
    await up();
    const answer = await call(rest[0], rest[1] ? JSON.parse(rest[1]) : {});
    console.log(JSON.stringify(answer));
    process.exit(answer.error ? 1 : 0);
    break;
  }
  case 'dashboard': {
    await up();
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
    console.error('usage: ctl.mjs path | status | restart | call METHOD [JSON] | dashboard | dashboard-stop');
    process.exit(2);
}

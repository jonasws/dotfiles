#!/usr/bin/env node
// The socket half of herdr/server.lua, which can't open sockets itself: Lua
// in Rex has no sockets, and io.popen and os.execute are disabled. It knows
// nothing about herdr. Every line a client sends goes to stdout tagged with
// its connection, and every line from stdin goes back to that connection:
//
//   stdout   R <conn> <line>   a client sent a line
//            G <conn>          the client went away
//   stdin    S <conn> <line>   send the line, keep the connection open
//            E <conn> <line>   send the line, then close
//
// It exits, removing the socket, when stdin closes (server.lua is gone) or
// when told to stop, and refuses to start while another server answers.
import { chmodSync, existsSync, unlinkSync, writeFileSync } from 'node:fs';
import net from 'node:net';

const socketPath = process.argv[2];
if (!socketPath) {
  console.error('usage: bridge.mjs <socket>');
  process.exit(2);
}

const connections = new Map();
let next = 1;

function alive() {
  return new Promise(resolve => {
    const probe = net.createConnection(socketPath);
    probe.once('connect', () => { probe.destroy(); resolve(true); });
    probe.once('error', () => resolve(false));
  });
}

if (existsSync(socketPath)) {
  if (await alive()) {
    console.error(`${socketPath} is already answering`);
    process.exit(3);
  }
  unlinkSync(socketPath);
}

const server = net.createServer(socket => {
  const conn = String(next++);
  connections.set(conn, socket);
  socket.setEncoding('utf8');
  socket.on('error', () => {});
  let buffer = '';
  socket.on('data', data => {
    buffer += data;
    let nl;
    while ((nl = buffer.indexOf('\n')) >= 0) {
      const line = buffer.slice(0, nl).replace(/\r$/, '');
      buffer = buffer.slice(nl + 1);
      if (line.trim()) process.stdout.write(`R ${conn} ${line}\n`);
    }
  });
  socket.on('close', () => {
    connections.delete(conn);
    process.stdout.write(`G ${conn}\n`);
  });
});

server.listen(socketPath, () => {
  chmodSync(socketPath, 0o600);
  writeFileSync(`${socketPath}.pid`, String(process.pid));
});

let input = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', data => {
  input += data;
  let nl;
  while ((nl = input.indexOf('\n')) >= 0) {
    const line = input.slice(0, nl);
    input = input.slice(nl + 1);
    const m = /^([SE]) (\d+) (.*)$/.exec(line);
    if (!m) continue;
    const socket = connections.get(m[2]);
    if (!socket) continue;
    if (m[1] === 'E') socket.end(`${m[3]}\n`);
    else socket.write(`${m[3]}\n`);
  }
});

function shutdown() {
  server.close();
  for (const socket of connections.values()) socket.destroy();
  for (const file of [socketPath, `${socketPath}.pid`]) try { unlinkSync(file); } catch {}
  process.exit(0);
}
process.stdin.on('end', shutdown);
for (const signal of ['SIGINT', 'SIGTERM', 'SIGHUP']) process.on(signal, shutdown);

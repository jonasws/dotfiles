// Cars from a running herdr, over its socket API: the same transport herdr-f1
// uses. session.snapshot and pane.focus get one answer per connection; a
// second, long-lived connection holds events.subscribe. Events only say that
// something changed, and each one triggers a fresh snapshot, as herdr's docs
// recommend: https://herdr.dev/docs/socket-api/ (Event subscriptions).
import { existsSync } from 'node:fs';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import { clean } from './sources.mjs';

export function herdrSocketPath() {
  return process.env.HERDR_SOCKET_PATH || path.join(os.homedir(), '.config', 'herdr', 'herdr.sock');
}

export function herdrAvailable() {
  return existsSync(herdrSocketPath());
}

const LIFECYCLE = [
  'workspace.created', 'workspace.updated', 'workspace.renamed', 'workspace.moved',
  'workspace.reordered', 'workspace.closed',
  'tab.created', 'tab.closed', 'tab.renamed', 'tab.moved',
  'pane.created', 'pane.closed', 'pane.moved', 'pane.exited', 'pane.agent_detected',
];

// herdr's `unknown` means an agent it can't classify, so it waits in the pits.
const STATES = { working: 'working', idle: 'idle', done: 'done', blocked: 'blocked', unknown: 'idle' };
const FLOOR_MS = 30000;

/** One request, one answer, then the connection closes. */
function request(socketPath, method, params = {}) {
  return new Promise((resolve, reject) => {
    const socket = net.createConnection(socketPath);
    let buffer = '';
    socket.setEncoding('utf8');
    socket.setTimeout(5000, () => socket.destroy(new Error(`${method} timed out`)));
    socket.on('connect', () => socket.write(JSON.stringify({ id: `f1-${method}`, method, params }) + '\n'));
    socket.on('data', data => {
      buffer += data;
      const nl = buffer.indexOf('\n');
      if (nl < 0) return;
      socket.destroy();
      try {
        const envelope = JSON.parse(buffer.slice(0, nl));
        if (envelope.error) reject(new Error(`${envelope.error.code}: ${envelope.error.message}`));
        else resolve(envelope.result);
      } catch (err) {
        reject(err);
      }
    });
    socket.on('error', reject);
    socket.on('close', () => reject(new Error(`herdr closed the connection during ${method}`)));
  });
}

/** A herdr session snapshot → race entries. Workspaces are teams, agents are
 *  cars, named after their tab the way herdr-f1 names them. */
export function entriesFromHerdr(snapshot) {
  const workspaces = new Map((snapshot.workspaces || []).map(w => [w.workspace_id, w]));
  const tabs = new Map((snapshot.tabs || []).map(t => [t.tab_id, t]));
  const order = [...workspaces.keys()];
  return (snapshot.agents || [])
    .filter(a => STATES[a.agent_status])
    .sort((a, b) => order.indexOf(a.workspace_id) - order.indexOf(b.workspace_id))
    .map(a => {
      const workspace = workspaces.get(a.workspace_id);
      const tab = tabs.get(a.tab_id);
      const app = clean(a.display_agent) || clean(a.agent) || clean(a.name) || 'agent';
      return {
        key: a.terminal_id || a.pane_id,
        sessionId: a.workspace_id,
        blockId: a.pane_id,
        teamId: a.workspace_id,
        teamLabel: clean(workspace?.label) || a.workspace_id,
        driver: clean(tab?.label) || clean(a.title) || clean(a.terminal_title_stripped) || app,
        app,
        state: STATES[a.agent_status],
        kind: null,
        // herdr's nearest thing to an OSC 7501 message: a reported label for
        // the current state, or a summary token.
        msg: clean(a.state_labels?.[a.agent_status]) || clean(a.tokens?.summary) || '',
        progress: null,
      };
    });
}

/** Entries on every change, connection state and errors, like demoFeed.
 *  Returns a stop function with a `focus(car)` method for jumping to a car. */
export function herdrFeed({ onEntries, onConnection = () => {}, onError = () => {}, socketPath = herdrSocketPath() }) {
  let stopped = false;
  let events = null;
  let panes = '';
  let refreshing = null;
  let again = false;
  let delay = 1000;

  // Snapshots run one at a time; an event during one queues exactly one more.
  async function refresh() {
    if (refreshing) { again = true; return refreshing; }
    refreshing = (async () => {
      do {
        again = false;
        const result = await request(socketPath, 'session.snapshot');
        const snapshot = result.snapshot || {};
        onEntries(entriesFromHerdr(snapshot));
        const next = (snapshot.panes || snapshot.agents || []).map(p => p.pane_id).sort().join();
        // Agent status is subscribed per pane, so a new pane set needs a new
        // subscription.
        if (next !== panes) { panes = next; subscribe(snapshot); }
      } while (again && !stopped);
    })().finally(() => { refreshing = null; });
    return refreshing;
  }

  function subscribe(snapshot) {
    events?.destroy();
    if (stopped) return;
    const subscriptions = LIFECYCLE.map(type => ({ type }));
    for (const pane of snapshot.panes || snapshot.agents || []) {
      subscriptions.push({ type: 'pane.agent_status_changed', pane_id: pane.pane_id });
    }
    const socket = net.createConnection(socketPath);
    events = socket;
    let buffer = '';
    socket.setEncoding('utf8');
    socket.on('connect', () => socket.write(JSON.stringify({ id: 'f1-subscribe', method: 'events.subscribe', params: { subscriptions } }) + '\n'));
    socket.on('data', data => {
      buffer += data;
      let nl;
      while ((nl = buffer.indexOf('\n')) >= 0) {
        const line = buffer.slice(0, nl);
        buffer = buffer.slice(nl + 1);
        let envelope;
        try { envelope = JSON.parse(line); } catch { continue; }
        if (envelope.result?.type === 'subscription_started') { delay = 1000; onConnection('live'); continue; }
        // events_lost, or a pane that vanished before we subscribed: start
        // over from a snapshot.
        if (envelope.error) { panes = ''; socket.destroy(); continue; }
        if (envelope.event) refresh().catch(fail);
      }
    });
    socket.on('error', () => {});
    socket.on('close', () => {
      if (events !== socket || stopped) return;
      events = null;
      panes = '';
      retry();
    });
  }

  function fail(err) {
    if (stopped) return;
    onError(`herdr: ${err.message}`);
    onConnection('offline');
    retry();
  }

  let retrying = null;
  function retry() {
    if (retrying || stopped) return;
    retrying = setTimeout(() => {
      retrying = null;
      refresh().catch(fail);
    }, delay);
    delay = Math.min(delay * 2, 15000);
  }

  refresh().catch(fail);
  // A missed event can't strand the race for long.
  const floor = setInterval(() => refresh().catch(fail), FLOOR_MS);

  const stop = () => {
    stopped = true;
    clearInterval(floor);
    clearTimeout(retrying);
    events?.destroy();
  };
  // pane.focus moves the attached client's view, which agent.focus doesn't
  // (herdr-f1, src/server/herdr/client.ts).
  stop.focus = car => request(socketPath, 'pane.focus', { pane_id: car.blockId });
  return stop;
}

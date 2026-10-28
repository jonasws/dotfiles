#!/usr/bin/env node
// Rex F1: a Grand Prix for the agents in your Rex sessions, or in herdr,
// rendered in 3D and shown with Kitty graphics. See ../README.md for how it
// is wired up.
//
//   f1.mjs                 live: Rex inside Rex, herdr inside herdr, else
//                          whichever is reachable (--source rex|herdr|demo)
//   f1.mjs --demo          fake agents, same as --source demo
//   f1.mjs --demo --snapshot out.png [--seconds 40] [--camera tv] [--size 960x540]
import { spawnSync } from 'node:child_process';
import { existsSync, writeFileSync } from 'node:fs';
import { parseArgs } from 'node:util';
import { fileURLToPath } from 'node:url';
import { Broadcast, CAMERAS } from './broadcast.mjs';
import { RULES, Race } from './race.mjs';
import { Renderer } from './raster.mjs';
import { Circuit } from './scene.mjs';
import { KittyFrames, halfBlocks, png } from './output.mjs';
import { herdrAvailable, herdrFeed } from './herdr.mjs';
import { demoFeed } from './sources.mjs';

const { values: args } = parseArgs({
  options: {
    demo: { type: 'boolean', default: false },
    source: { type: 'string', default: process.env.F1_SOURCE || 'auto' },
    snapshot: { type: 'string' },
    seconds: { type: 'string', default: '40' },
    camera: { type: 'string', default: process.env.F1_CAMERA || 'tv' },
    size: { type: 'string', default: '960x540' },
    fps: { type: 'string', default: process.env.F1_FPS || '10' },
    graphics: { type: 'string', default: process.env.F1_GRAPHICS || 'auto' },
  },
});

const circuit = new Circuit();
const broadcast = new Broadcast(circuit);
const race = new Race();
let camera = CAMERAS.includes(args.camera) ? args.camera : 'tv';
const source = args.demo ? 'demo' : args.source === 'auto' ? detectSource() : args.source;
const SOURCE_NAME = { rex: 'REX', herdr: 'HERDR', demo: 'DEMO' }[source] || source.toUpperCase();

/** The multiplexer the dashboard runs inside, else the one that is reachable. */
function detectSource() {
  if (process.env.REX_SESSION) return 'rex';
  if (process.env.HERDR_ENV || process.env.HERDR_PANE_ID) return 'herdr';
  if (process.env.REX_BIN) return 'rex';
  const onPath = (process.env.PATH || '').split(':').some(dir => dir && existsSync(`${dir}/rex`));
  if (!onPath && herdrAvailable()) return 'herdr';
  return 'rex';
}

if (args.snapshot) snapshot();
else tui();

// ── Headless: simulate a while, then write one PNG ──────────────────────────

function snapshot() {
  const feed = demoFeed({ onEntries: entries => race.apply(entries) });
  feed();
  const [w, h] = args.size.split('x').map(Number);
  const renderer = new Renderer(w, h);
  const seconds = Number(args.seconds);
  const dt = 0.1;
  for (let t = 0; t < seconds; t += dt) {
    race.step(dt);
    if (Math.abs(t - Math.round(t)) < dt / 2) feed.advance(1);
    // Only the last few seconds are drawn: enough for the camera to settle.
    if (t > seconds - 4) broadcast.render(renderer, race, { selected: race.standings()[1]?.key, camera, dt });
  }
  writeFileSync(args.snapshot, png(renderer.color, w, h));
  const counts = {};
  for (const car of race.standings()) counts[car.state] = (counts[car.state] || 0) + 1;
  console.log(`${args.snapshot}: ${w}x${h}, ${race.cars.size} cars, lap ${race.leaderLap()}, ${JSON.stringify(counts)}`);
}

// ── Interactive ─────────────────────────────────────────────────────────────

function tui() {
  const out = process.stdout;
  const input = process.stdin;
  if (!out.isTTY || !input.isTTY) {
    console.error('rex-f1 needs a terminal. For a still image, use --demo --snapshot out.png');
    process.exit(2);
  }

  const kitty = new KittyFrames();
  let graphics = args.graphics === 'blocks' ? 'blocks' : null;
  let cell = { w: 9, h: 18 };
  let status = { text: '', until: 0 };
  let cache = new Map();
  let renderer = null;
  let layout = { imageRows: 0, tableTop: 0, cols: 0 };
  let tableCars = [];
  let lastClick = { key: null, at: 0 };

  // What the viewer is looking at. The selected car is the one the TV and
  // onboard cameras follow, the pit wall line describes, and Enter jumps to.
  // With nothing selected, the cameras follow the leader.
  let selected = null;
  let scope = 'all';
  let scopeTeam = null;
  let autopilot = false;
  let help = false;

  const flash = text => { status = { text, until: Date.now() + 4000 }; };

  // Rex is read through its herdr socket (../herdr/server.lua), started
  // here if it isn't up yet.
  const rexFeed = options => {
    const ctl = fileURLToPath(new URL('../herdr/ctl.mjs', import.meta.url));
    const ensure = spawnSync(process.execPath, [ctl, 'ensure'], { encoding: 'utf8' });
    if (ensure.status !== 0) {
      options.onError(`herdr socket: ${(ensure.stderr || ensure.stdout).trim()}`);
      options.onConnection('offline');
      return Object.assign(() => {}, { focus: () => Promise.reject(new Error('no herdr socket')) });
    }
    return herdrFeed({ ...options, socketPath: ensure.stdout.trim() });
  };
  const feeds = { demo: demoFeed, rex: rexFeed, herdr: herdrFeed };
  if (!feeds[source]) {
    console.error(`unknown --source ${source}: use rex, herdr or demo`);
    process.exit(2);
  }
  const stop = feeds[source]({
    onEntries: entries => race.apply(entries),
    onConnection: state => race.setConnection(state),
    onError: flash,
  });

  out.write('\x1b[?1049h\x1b[?25l\x1b[?1000h\x1b[?1006h\x1b[2J');
  input.setRawMode(true);
  input.setEncoding('utf8');

  let detected = false;
  const detect = setTimeout(() => finishDetect(false), 800);
  function finishDetect(kittyOk) {
    if (detected) return;
    detected = true;
    clearTimeout(detect);
    if (!graphics) graphics = args.graphics === 'kitty' || kittyOk ? 'kitty' : 'blocks';
    if (graphics === 'blocks' && args.graphics === 'auto') flash('No Kitty graphics reply: using half blocks');
  }
  // Cell size, a Kitty graphics query, then primary device attributes: if DA1
  // answers before the Kitty query, there is no Kitty graphics support.
  out.write('\x1b[16t\x1b_Gi=31,s=1,v=1,a=q,t=d,f=24;AAAA\x1b\\\x1b[c');

  const ARROWS = { A: 'up', B: 'down', C: 'right', D: 'left' };
  const NAMED = { '\t': 'tab', '\r': 'enter', '\n': 'enter', '\x1b': 'esc', '\x03': 'ctrl+c', ' ': 'space' };
  const TOKENS = /\x1b\[<(\d+);(\d+);(\d+)([Mm])|\x1b\[6;(\d+);(\d+)t|\x1b_G([^\x1b]*)\x1b\\|\x1b\[\?[\d;]*c|\x1b\[Z|\x1b[[O]([A-D])|[\s\S]/g;
  input.on('data', data => {
    for (const m of data.matchAll(TOKENS)) {
      const [token] = m;
      if (m[1] !== undefined) mouse(Number(m[1]), Number(m[2]), Number(m[3]), m[4] === 'M');
      else if (m[5] !== undefined) { cell = { h: Number(m[5]), w: Number(m[6]) }; cache = new Map(); }
      else if (m[7] !== undefined) { if (/^i=31;OK/.test(m[7])) finishDetect(true); }
      else if (token.startsWith('\x1b[?')) finishDetect(false);
      else if (token === '\x1b[Z') key('shift+tab');
      else if (m[8]) key(ARROWS[m[8]]);
      else key(NAMED[token] || token);
    }
  });

  // ── Groups of cars ──────────────────────────────────────────────────────
  // After the herdr-sessions tv channel: an attention queue, and scopes that
  // narrow the standings the way its Tab-cycled sources narrow the picker.

  const NEEDS_YOU = { blocked: 0, error: 1, done: 2 };
  const SCOPES = [
    { id: 'all', label: 'all', test: () => true },
    { id: 'needs', label: 'needs you', test: car => car.state in NEEDS_YOU },
    { id: 'racing', label: 'racing', test: car => car.state === 'working' },
    { id: 'pits', label: 'in the pits', test: car => car.state === 'idle' },
    { id: 'team', label: 'team', test: car => car.teamId === scopeTeam },
  ];
  const scopeOf = id => SCOPES.find(x => x.id === id);
  const scopeLabel = () => scope === 'team' ? `team ${race.teams.get(scopeTeam)?.label ?? ''}` : scopeOf(scope).label;

  /** Cars in the current scope, in race order. */
  function inScope() {
    const test = scopeOf(scope).test;
    return race.standings().filter(test);
  }

  /** Cars waiting on you, most urgent first: stopped, then failed, then
   *  finished and unseen, and the longest waiting first within each. */
  function attentionQueue() {
    return race.standings()
      .filter(car => car.state in NEEDS_YOU)
      .sort((a, b) => NEEDS_YOU[a.state] - NEEDS_YOU[b.state] || a.changedAt - b.changedAt);
  }

  /** Teams with a car in scope, in the order they joined. */
  function teamsInScope() {
    const cars = inScope();
    return [...race.teams.values()]
      .sort((a, b) => a.order - b.order)
      .filter(team => cars.some(car => car.teamId === team.id));
  }

  function select(key, { manual = true } = {}) {
    if (manual && autopilot) { autopilot = false; flash('Autopilot off'); }
    selected = key;
  }

  function step(list, by, empty = `Nobody in ${scopeLabel()}`) {
    if (!list.length) { flash(empty); return; }
    const index = list.findIndex(car => car.key === selected);
    const next = index < 0 ? (by > 0 ? 0 : list.length - 1) : (index + by + list.length) % list.length;
    select(list[next].key);
  }

  function stepTeam(by) {
    const teams = teamsInScope();
    if (!teams.length) return;
    const current = race.cars.get(selected)?.teamId;
    const index = teams.findIndex(team => team.id === current);
    const team = teams[index < 0 ? 0 : (index + by + teams.length) % teams.length];
    // A team is entered at its best-placed car in scope.
    select(inScope().find(car => car.teamId === team.id).key);
  }

  function setScope(id) {
    if (id === 'team') {
      const car = race.cars.get(selected) || race.standings()[0];
      if (!car) return;
      scopeTeam = car.teamId;
    }
    scope = id;
    const cars = inScope();
    if (selected && !cars.some(car => car.key === selected)) selected = null;
    flash(`Scope: ${scopeLabel()} (${cars.length})`);
  }

  function cycleScope(by) {
    const index = SCOPES.findIndex(x => x.id === scope);
    setScope(SCOPES[(index + by + SCOPES.length) % SCOPES.length].id);
  }

  // ── Keymap ──────────────────────────────────────────────────────────────
  // One table drives both the keys and the `?` overlay.

  const KEYMAP = [
    ['cars', ['j', 'down'], 'j/↓', 'next car in scope', () => step(inScope(), 1)],
    ['cars', ['k', 'up'], 'k/↑', 'previous car in scope', () => step(inScope(), -1)],
    ['cars', ['g'], 'g', 'leader', () => inScope()[0] && select(inScope()[0].key)],
    ['cars', ['G'], 'G', 'last car', () => inScope().length && select(inScope().at(-1).key)],
    ['cars', ['1', '2', '3', '4', '5', '6', '7', '8', '9'], '1–9', 'Nth car in scope', k => inScope()[Number(k) - 1] && select(inScope()[Number(k) - 1].key)],
    ['cars', ['tab'], 'tab', 'next car that needs you', () => step(attentionQueue(), 1, 'Nobody needs you')],
    ['cars', ['shift+tab'], 'S-tab', 'previous car that needs you', () => step(attentionQueue(), -1, 'Nobody needs you')],
    ['teams', ['l', 'right'], 'l/→', 'next team', () => stepTeam(1)],
    ['teams', ['h', 'left'], 'h/←', 'previous team', () => stepTeam(-1)],
    ['scope', ['s'], 's', 'next scope', () => cycleScope(1)],
    ['scope', ['S'], 'S', 'previous scope', () => cycleScope(-1)],
    ['scope', ['!'], '!', 'needs you', () => setScope('needs')],
    ['scope', ['t'], 't', "selected car's team", () => setScope('team')],
    ['scope', ['*'], '*', 'all', () => setScope('all')],
    ['act', ['enter'], '⏎', 'jump to the pane (or double-click)', () => jump(race.cars.get(selected))],
    ['act', ['a'], 'a', 'autopilot: follow whoever needs you most recently', () => { autopilot = !autopilot; flash(`Autopilot ${autopilot ? 'on' : 'off'}`); }],
    ['act', ['esc'], 'esc', 'clear selection, then scope', () => { if (help) help = false; else if (selected || autopilot) { selected = null; autopilot = false; } else if (scope !== 'all') setScope('all'); }],
    ['camera', ['c'], 'c', 'next camera', () => { camera = CAMERAS[(CAMERAS.indexOf(camera) + 1) % CAMERAS.length]; }],
    ['camera', ['C'], 'C', 'previous camera', () => { camera = CAMERAS[(CAMERAS.indexOf(camera) - 1 + CAMERAS.length) % CAMERAS.length]; }],
    ['camera', ['b'], 'b', "bird's eye on/off", () => { camera = camera === 'birdseye' ? 'tv' : 'birdseye'; }],
    ['other', ['?'], '?', 'these keys', () => { help = !help; cache = new Map(); }],
    ['other', ['q', 'ctrl+c'], 'q', 'quit', () => quit()],
  ];
  const BINDINGS = new Map(KEYMAP.flatMap(([, keys, , , run]) => keys.map(k => [k, run])));

  function key(k) {
    const run = BINDINGS.get(k);
    if (run) run(k);
  }

  function mouse(button, col, row, press) {
    if (!press) return;
    if (button === 64) return step(inScope(), -1);
    if (button === 65) return step(inScope(), 1);
    if (button !== 0) return;
    let car = null;
    if (row >= 2 && row < 2 + layout.imageRows && renderer) {
      // A click on the picture: the car whose tag or body is nearest.
      const x = (col - 0.5) / layout.cols * renderer.w;
      const y = (row - 2 + 0.5) / layout.imageRows * renderer.h;
      car = race.cars.get(broadcast.carAt(x, y, renderer)) || null;
    } else {
      car = tableCars[row - layout.tableTop] || null;
    }
    if (!car) return;
    const now = Date.now();
    if (lastClick.key === car.key && now - lastClick.at < 400) jump(car);
    select(car.key);
    lastClick = { key: car.key, at: now };
  }

  function jump(car) {
    if (!car) { flash('Select a car first: j/k, tab, or click one'); return; }
    const done = err => flash(err ? `jump failed: ${err.message.trim().split('\n').pop()}` : `→ ${car.driver} (${car.teamLabel})`);
    if (source === 'demo') { flash(`demo: would focus ${car.driver} in ${car.teamLabel}`); return; }
    // pane.focus, on herdr or on Rex's herdr socket, which also shows the
    // pane's session.
    stop.focus(car).then(() => done(), done);
  }

  let quitting = false;
  function quit() {
    if (quitting) return;
    quitting = true;
    stop();
    out.write(kitty.clear() + '\x1b[?1000l\x1b[?1006l\x1b[0m\x1b[?25h\x1b[?1049l');
    process.exit(0);
  }
  for (const signal of ['SIGINT', 'SIGTERM', 'SIGHUP']) process.on(signal, quit);
  out.on('resize', () => { cache = new Map(); out.write('\x1b[2J'); });

  let last = performance.now();
  const fps = Math.max(1, Math.min(30, Number(args.fps) || 10));
  setInterval(() => {
    const now = performance.now();
    const dt = (now - last) / 1000;
    last = now;
    race.step(dt);
    if (!detected || out.writableNeedDrain) return;
    frame(dt);
  }, 1000 / fps);

  function frame(dt) {
    const cols = out.columns, rows = out.rows;
    if (selected && !race.cars.has(selected)) selected = null;
    if (scope === 'team' && !race.teams.has(scopeTeam)) scope = 'all';
    if (autopilot) {
      // The newest arrival in the queue is the one you haven't seen yet.
      const newest = attentionQueue().sort((a, b) => b.changedAt - a.changedAt)[0];
      select(newest?.key ?? null, { manual: false });
    }
    const cars = inScope();

    const radioRows = rows >= 34 ? 4 : rows >= 24 ? 2 : 1;
    const tableRows = Math.min(Math.max(cars.length, 1), Math.max(3, Math.floor(rows * 0.3)));
    const imageRows = Math.max(4, rows - 3 - tableRows - radioRows);

    let width, height;
    if (graphics === 'kitty') {
      const maxW = Number(process.env.F1_MAX_WIDTH) || 800;
      const pw = cols * cell.w, ph = imageRows * cell.h;
      const scale = Math.min(1, maxW / pw, (maxW * 0.75) / ph);
      width = Math.max(32, Math.round(pw * scale));
      height = Math.max(24, Math.round(ph * scale));
    } else {
      width = cols;
      height = imageRows * 2;
    }
    if (!renderer || renderer.w !== width || renderer.h !== height) renderer = new Renderer(width, height);
    const scopeKeys = scope === 'all' ? null : new Set(cars.map(car => car.key));
    broadcast.render(renderer, race, { selected, camera, dt, scope: scopeKeys });

    const tableTop = 2 + imageRows + 2;
    let s = '\x1b[?2026h';
    if (imageRows !== layout.imageRows || cols !== layout.cols) {
      // The table moved: drop the old rows rather than leave them behind.
      s += '\x1b[2J';
      cache = new Map();
    }
    layout = { imageRows, tableTop, cols };
    s += line(1, header(cols));
    s += graphics === 'kitty'
      ? `\x1b[2;1H${kitty.frame(renderer.color, width, height, cols, imageRows)}`
      : halfBlocks(renderer.color, width, height, 2, 1);

    s += line(tableTop - 2, pitWall(cols));
    if (help) {
      const lines = helpLines(cols);
      tableCars = [];
      for (let i = 0; i < tableRows + radioRows + 1; i++) s += line(tableTop - 1 + i, lines[i] ?? '');
    } else {
      s += line(tableTop - 1, tableHeader(cols));
      tableCars = scrolled(cars, tableRows);
      const leader = race.standings()[0];
      for (let i = 0; i < tableRows; i++) s += line(tableTop + i, tableCars[i] ? row(tableCars[i], leader, cols) : i === 0 ? emptyGrid(cols) : '');
      const radio = race.radio.slice(-radioRows);
      for (let i = 0; i < radioRows; i++) s += line(tableTop + tableRows + i, radioLine(radio[i], cols));
    }
    s += '\x1b[?2026l';
    out.write(s);
  }

  /** The standings window, scrolled so the selected car stays visible. */
  function scrolled(order, n) {
    const index = Math.max(0, order.findIndex(c => c.key === selected));
    const start = Math.max(0, Math.min(order.length - n, index - Math.floor(n / 2)));
    return order.slice(start, start + n);
  }

  function line(r, content) {
    if (cache.get(r) === content) return '';
    cache.set(r, content);
    return `\x1b[${r};1H\x1b[0m${content}\x1b[0m\x1b[K`;
  }

  function header(cols) {
    let flag;
    if (race.connection === 'offline') flag = `${fg('#ff5f5f')}● OFFLINE, reconnecting`;
    else if (race.connection === 'waiting') flag = `${fg('#9399b2')}● WAITING FOR ${SOURCE_NAME}`;
    else if (race.phase === 'podium') flag = `${fg('#e8c547')}▲ PODIUM`;
    else if (race.yellow) flag = `${fg('#ffb000')}● SAFETY CAR`;
    else flag = `${fg('#36d66b')}● GREEN`;
    const mode = `cam ${camera}${scope === 'all' ? '' : ` · ${scopeLabel()}`}${autopilot ? ` · ${fg('#f9e2af')}AUTO` : ''}`;
    const left = `${bold()}${fg('#cba6f7')} ${SOURCE_NAME} GRAND PRIX ${reset()}${fg('#cdd6f4')} GP ${race.gp}  LAP ${race.leaderLap()}/${RULES.totalLaps}  ${flag}${reset()}${fg('#9399b2')}  ${mode}`;
    const right = Date.now() < status.until ? status.text : 'tab needs you  ⏎ jump  s scope  ? keys';
    const leftWidth = visible(left);
    return left + ' '.repeat(Math.max(1, cols - leftWidth - [...right].length - 1)) + fg('#7f849c') + fit(right, Math.max(0, cols - leftWidth - 2));
  }

  /** One line about the selected car, or about the field when none is. */
  function pitWall(cols) {
    const car = race.cars.get(selected);
    if (!car) {
      const waiting = attentionQueue().length;
      const field = `${fg('#9399b2')} ▸ ${camera === 'birdseye' ? 'Whole circuit' : 'Following the leader'}  ·  ${scopeLabel()} (${inScope().length})  ·  `;
      const queue = waiting ? `${fg('#ffb000')}${waiting} need${waiting === 1 ? 's' : ''} you, tab to cycle` : `${fg('#36d66b')}nobody needs you`;
      const text = field + queue;
      return visible(text) <= cols ? text : fg('#9399b2') + fit(text.replace(/\x1b\[[\d;]*m/g, ''), cols);
    }
    const [label, colour] = badge(car);
    const position = race.standings().indexOf(car) + 1;
    const queue = attentionQueue();
    const place = queue.indexOf(car);
    const head =
      `${fg(car.livery)}${bold()} ▸ #${car.number} ${reset()}${fg('#cdd6f4')}${car.driver}${fg('#7f849c')} · ${car.teamLabel} · ${car.app} · P${position} · ` +
      `${fg(colour)}${label} ${ago(car.changedAt)}${place >= 0 ? `${fg('#7f849c')} · ${place + 1}/${queue.length} in queue` : ''}${fg('#7f849c')} · `;
    const message = car.state === 'blocked' && car.kind ? `[${car.kind}] ${car.msg}` : car.msg || '—';
    return head + fg('#cdd6f4') + fit(message, Math.max(0, cols - visible(head)));
  }

  function helpLines(cols) {
    const groups = [...new Set(KEYMAP.map(([group]) => group))];
    const lines = [`${bold()}${fg('#cba6f7')} KEYS${reset()}${fg('#7f849c')}  ? or esc closes. Mouse: click a car or a row to select, double-click to jump, wheel to step.`];
    for (const group of groups) {
      let current = `${fg('#cba6f7')} ${group.toUpperCase().padEnd(7)}`;
      for (const [g, , keys, label] of KEYMAP) {
        if (g !== group) continue;
        const item = `${fg('#f5e0dc')}${keys} ${fg('#a6adc8')}${label}   `;
        if (visible(current + item) > cols) { lines.push(current); current = ' '.repeat(8); }
        current += item;
      }
      lines.push(current);
    }
    return lines;
  }

  function tableHeader(cols) {
    return fg('#7f849c') + fit(' POS  NO  TEAM            DRIVER              STATUS     LAP   GAP       MESSAGE', cols);
  }

  function row(car, leader, cols) {
    const pos = race.standings().indexOf(car) + 1;
    const [label, colour] = badge(car);
    const lap = Math.min(RULES.totalLaps, Math.floor(car.distance) + 1);
    const message = car.state === 'blocked' && car.kind ? `[${car.kind}] ${car.msg}` : car.msg;
    const isSelected = car.key === selected;
    const bg = isSelected ? '\x1b[48;2;49;50;68m' : '';
    const cells =
      `${bg}${fg('#cdd6f4')} ${fit(`P${pos}`, 4)} ` +
      `${fg(car.livery)}${bold()}${fit(String(car.number).padStart(2), 3)}${reset()}${bg} ` +
      `${fg(car.livery)}▌${fg('#cdd6f4')}${fit(car.teamLabel, 14)} ` +
      `${fit(car.driver, 19)} ` +
      `${fg(colour)}${fit(label, 10)} ` +
      `${fg('#cdd6f4')}${fit(String(lap), 5)} ` +
      `${fit(race.gapText(car, leader), 9)} ` +
      `${fg('#a6adc8')}`;
    return cells + fit(message || car.app, Math.max(0, cols - visible(cells)));
  }

  function badge(car) {
    switch (car.state) {
      case 'working': return [car.progress !== null ? `RACING ${car.progress}%` : 'RACING', '#36d66b'];
      case 'blocked': return ['STOPPED', '#ffb000'];
      case 'error': return ['DNF', '#ff5f5f'];
      case 'done': return [race.placement(car).kind === 'track' ? 'COOL-DOWN' : 'FINISHED', '#89b4fa'];
      default: return ['IN PIT', '#9399b2'];
    }
  }

  function emptyGrid(cols) {
    if (race.cars.size) return fg('#9399b2') + fit(` Nobody in ${scopeLabel()}. s cycles scope, * shows all.`, cols);
    const how = source === 'herdr'
      ? 'Agents herdr detects in any workspace join automatically.'
      : 'Programs that report their status (OSC 7501) in any Rex session join automatically.';
    return fg('#9399b2') + fit(` No cars on the grid. ${how}`, cols);
  }

  function radioLine(message, cols) {
    if (!message) return '';
    const head = `${fg('#7f849c')} ${message.time} ${fg(message.livery)}${message.number ? '▌' : '◆'} `;
    return head + fg('#cdd6f4') + fit(message.text, Math.max(0, cols - visible(head)));
  }
}

// ── Text helpers ────────────────────────────────────────────────────────────

function fg(hexColour) {
  const n = parseInt(hexColour.slice(1), 16);
  return `\x1b[38;2;${n >> 16 & 255};${n >> 8 & 255};${n & 255}m`;
}
function bold() { return '\x1b[1m'; }
function reset() { return '\x1b[0m'; }

function ago(ms) {
  const s = Math.max(0, Math.round((Date.now() - ms) / 1000));
  return s < 60 ? `${s}s` : s < 3600 ? `${Math.floor(s / 60)}m${String(s % 60).padStart(2, '0')}s` : `${Math.floor(s / 3600)}h${String(Math.floor(s / 60) % 60).padStart(2, '0')}m`;
}

function visible(str) {
  return [...str.replace(/\x1b\[[\d;]*m/g, '')].length;
}

/** Pads or cuts to exactly n columns, with an ellipsis when cut. */
function fit(str, n) {
  const chars = [...String(str ?? '')];
  if (chars.length <= n) return chars.join('') + ' '.repeat(n - chars.length);
  return n > 0 ? chars.slice(0, n - 1).join('') + '…' : '';
}

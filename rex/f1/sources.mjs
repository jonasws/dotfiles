// Where cars come from besides herdr's socket (herdr.mjs): a demo of fake
// agents. Also the text cleaning both use.

/** Printable single-line text, with control and bidi characters removed. */
export function clean(value) {
  if (typeof value !== 'string') return '';
  return value.replace(/[\u0000-\u001f\u007f-\u009f\u200e\u200f\u202a-\u202e\u2066-\u2069]/g, '').trim();
}

// ── Demo ────────────────────────────────────────────────────────────────────

const DEMO = [
  ['dotfiles', ['claude-code', 'rex-f1'], ['codex', 'nvim config']],
  ['api-gateway', ['claude-code', 'auth refactor'], ['claude-code', 'flaky tests'], ['opencode', 'openapi diff']],
  ['infra', ['claude-code', 'cdk synth'], ['codex', 'terraform plan']],
  ['blog', ['pi', 'draft post']],
];

const MESSAGES = {
  working: ['Reading the codebase', 'Running the test suite', 'Editing 4 files', 'Planning the change', 'Searching for usages', 'Running cdk diff'],
  blocked: ['Allow Bash(git push)?', 'Approve the apply: 3 to add, 1 to change?', 'Which region should this deploy to?', 'Token expired, log in again'],
  done: ['Opened PR #212', 'All 148 tests pass', 'Refactor complete', 'Plan ready to review'],
  error: ['Tests failed: 3 errors', 'Build failed'],
  idle: [''],
};

const KINDS = { blocked: ['permission', 'question', 'permission', 'auth'] };

/** Fake agents in a few fake sessions, changing state every few seconds. */
export function demoFeed({ onEntries, seed = 1 }) {
  let s = seed;
  const random = () => { s = (Math.imul(s, 1103515245) + 12345) >>> 0; return s / 4294967296; };
  const pick = list => list[Math.floor(random() * list.length)];
  const cars = [];
  DEMO.forEach(([session, ...blocks], i) => blocks.forEach(([app, label], j) => cars.push({
    key: `session:demo-${i}/block:demo-${i}-${j}`, sessionId: `session:demo-${i}`, blockId: `block:demo-${i}-${j}`,
    teamId: `session:demo-${i}`, teamLabel: session, driver: label, app,
    state: random() < 0.75 ? 'working' : 'idle', kind: null, msg: '', progress: null, next: 2 + random() * 10,
  })));
  for (const car of cars) car.msg = pick(MESSAGES[car.state]);

  const advance = dt => {
    for (const car of cars) {
      car.next -= dt;
      if (car.next > 0) continue;
      const r = random();
      const state =
        car.state === 'blocked' || car.state === 'error' ? (r < 0.7 ? 'working' : 'idle')
          : r < 0.55 ? 'working' : r < 0.7 ? 'idle' : r < 0.82 ? 'blocked' : r < 0.97 ? 'done' : 'error';
      car.state = state;
      car.msg = pick(MESSAGES[state]);
      car.kind = KINDS[state] ? pick(KINDS[state]) : null;
      car.next = state === 'working' ? 8 + random() * 20 : 4 + random() * 8;
    }
    onEntries(cars.map(({ next, ...entry }) => entry));
  };
  advance(0);
  const timer = setInterval(() => advance(1), 1000);
  return Object.assign(() => clearInterval(timer), { advance });
}

// The Grand Prix. Rex sessions are teams and terminals reporting a program
// status (OSC 7501) are cars. Laps, gaps and positions are race fiction for
// spectating, in the spirit of herdr-f1; only the states are real.
//
//   working  racing at a pace that varies lap to lap
//   idle     parked in its pit box
//   done     a slow cool-down lap, then the pits
//   blocked  stopped on track; the safety car comes out and the field slows
//   error    retired at the side of the track, smoking

export const RULES = {
  totalLaps: 58,
  lapSeconds: 18,
  paceMin: 0.75,
  paceMax: 1.25,
  cooldownFactor: 0.25,
  safetyCarFactor: 0.4,
  podiumSeconds: 12,
  newEntrantDeficit: 0.15,
  maxStep: 1,
  radioLimit: 40,
  goneGrace: 6,
};

// Eleven liveries in max-contrast order, then they repeat with a stripe.
export const LIVERIES = [
  '#e8002d', '#27f4d2', '#ff8000', '#3671c6', '#52e252', '#ff87bc',
  '#ffd700', '#9b59ff', '#64c4ff', '#b6babd', '#229971',
];

export function hash(str) {
  let h = 0x811c9dc5;
  for (let i = 0; i < str.length; i++) {
    h ^= str.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return h >>> 0;
}

function pace(gp, key, lap) {
  let h = hash(`${gp}|${key}|${lap}`);
  h ^= h >>> 16; h = Math.imul(h, 0x45d9f3b); h ^= h >>> 16;
  return RULES.paceMin + (h % 10000) / 9999 * (RULES.paceMax - RULES.paceMin);
}

export class Race {
  constructor(clock = () => new Date()) {
    this.clock = clock;
    this.cars = new Map();
    this.teams = new Map();
    this.gp = 1;
    this.phase = 'live';
    this.podiumLeft = 0;
    this.podium = [];
    this.radio = [];
    this.time = 0;
    this.connection = 'waiting';
    this.safetyCar = null;
    this.nextPitSlot = 0;
    this.radioId = 1;
  }

  /** Reconciles the cars with one complete snapshot from the feed. */
  apply(entries) {
    this.connection = 'live';
    const present = new Set();
    for (const e of entries) {
      present.add(e.key);
      this.team(e.teamId, e.teamLabel);
      let car = this.cars.get(e.key);
      if (!car) {
        car = this.enter(e);
      } else if (car.gone !== null) {
        car.gone = null;
      }
      car.driver = e.driver;
      car.app = e.app;
      car.kind = e.kind;
      car.progress = e.progress;
      car.teamLabel = this.teams.get(e.teamId).label;
      if (e.state !== car.state) this.transition(car, e.state, e.msg);
      car.msg = e.msg;
    }
    for (const car of this.cars.values()) {
      if (!present.has(car.key) && car.gone === null) {
        car.gone = this.time;
        this.say(car, 'retired', `#${car.number} ${car.driver} is out of the session. Thanks, mate.`);
      }
    }
  }

  setConnection(state) {
    this.connection = state;
  }

  team(id, label) {
    let team = this.teams.get(id);
    if (!team) {
      const used = new Set([...this.teams.values()].map(t => t.slot));
      let slot = hash(id) % LIVERIES.length;
      for (let k = 0; k < LIVERIES.length && used.has(slot); k++) slot = (slot + 1) % LIVERIES.length;
      team = { id, label, slot, livery: LIVERIES[slot], order: this.teams.size };
      this.teams.set(id, team);
    }
    team.label = label;
    return team;
  }

  enter(e) {
    const used = new Set([...this.cars.values()].map(c => c.number));
    let number = hash(e.key) % 99 + 1;
    for (let k = 0; k < 99 && used.has(number); k++) number = number % 99 + 1;
    const distances = [...this.cars.values()].map(c => c.distance);
    const last = distances.length ? Math.min(...distances) : 0;
    const live = distances.length > 0;
    const team = this.teams.get(e.teamId);
    const car = {
      key: e.key, sessionId: e.sessionId, blockId: e.blockId, teamId: e.teamId, teamLabel: team.label,
      livery: team.livery, number, driver: e.driver, app: e.app, kind: e.kind, msg: e.msg,
      state: e.state, since: this.time, changedAt: this.clock().getTime(), progress: e.progress,
      distance: live ? Math.max(0, last - RULES.newEntrantDeficit) : 0,
      pace: 1, paceLap: -1, lane: number % 3 - 1, pitSlot: this.nextPitSlot++, gone: null,
    };
    this.cars.set(e.key, car);
    this.say(car, 'join', `#${number} ${car.driver} joins the grid for ${team.label}.`);
    return car;
  }

  transition(car, state, msg) {
    const from = car.state;
    car.state = state;
    car.since = this.time;
    // Wall clock, for "waiting 2m": race time stops while the feed is down.
    car.changedAt = this.clock().getTime();
    const who = `#${car.number} ${car.driver}`;
    const why = msg ? `: ${msg}` : '';
    if (state === 'blocked') this.say(car, 'incident', `${who} has stopped on track${why || '. Needs you.'}`);
    else if (from === 'blocked') this.say(car, 'recovered', `${who} is moving again. Good recovery.`);
    else if (state === 'working') this.say(car, 'green', `${who} out of the pits, push now${why}`);
    else if (state === 'idle') this.say(car, 'box', `${who}: box, box. Waiting for instructions.`);
    else if (state === 'done') this.say(car, 'chequered', `${who} takes the flag${why || '. Result ready to look at.'}`);
    else if (state === 'error') this.say(car, 'dnf', `${who} DNF${why || '. Retired with a failure.'}`);
  }

  say(car, kind, text) {
    const now = this.clock();
    this.radio.push({
      id: this.radioId++, kind, key: car.key, number: car.number, livery: car.livery,
      time: now.toTimeString().slice(0, 8), text,
    });
    if (this.radio.length > RULES.radioLimit) this.radio.shift();
  }

  get yellow() {
    return [...this.cars.values()].some(c => c.state === 'blocked' && c.gone === null);
  }

  step(dt) {
    dt = Math.min(Math.max(0, dt), RULES.maxStep);
    this.time += dt;

    for (const car of [...this.cars.values()]) {
      if (car.gone !== null && this.time - car.gone > RULES.goneGrace) this.cars.delete(car.key);
    }

    if (this.phase === 'podium') {
      this.podiumLeft -= dt;
      if (this.podiumLeft <= 0) {
        this.phase = 'live';
        this.gp += 1;
        for (const car of this.cars.values()) { car.distance = 0; car.paceLap = -1; }
        this.radio.push({ id: this.radioId++, kind: 'gp', key: null, number: 0, livery: '#ffffff', time: this.clock().toTimeString().slice(0, 8), text: `Lights out for Grand Prix ${this.gp}!` });
      }
      return;
    }
    if (this.connection !== 'live') return;

    const yellow = this.yellow;
    const base = 1 / RULES.lapSeconds;
    for (const car of this.cars.values()) {
      if (car.gone !== null) continue;
      const lap = Math.floor(car.distance);
      if (car.paceLap !== lap) { car.pace = pace(this.gp, car.key, lap); car.paceLap = lap; }
      let speed = 0;
      if (car.state === 'working') speed = base * car.pace * (yellow ? RULES.safetyCarFactor : 1);
      else if (car.state === 'done' && this.time - car.since < RULES.lapSeconds / RULES.cooldownFactor) speed = base * RULES.cooldownFactor;
      car.speed = speed;
      car.distance = Math.min(RULES.totalLaps, car.distance + speed * dt);
    }

    // The safety car runs just ahead of the leader while the yellow is out.
    const order = this.standings();
    if (yellow && order.length) {
      const target = (order[0].distance + 0.025) % 1;
      if (!this.safetyCar) this.safetyCar = { progress: target };
      this.safetyCar.progress = target;
    } else {
      this.safetyCar = null;
    }

    const leader = order[0];
    if (leader && leader.distance >= RULES.totalLaps) {
      this.phase = 'podium';
      this.podiumLeft = RULES.podiumSeconds;
      this.podium = order.slice(0, 3).map(c => c.key);
      this.say(leader, 'win', `#${leader.number} ${leader.driver} wins Grand Prix ${this.gp} for ${leader.teamLabel}!`);
    }
  }

  /** Cars in race order. Ties break on car number so the order is stable. */
  standings() {
    return [...this.cars.values()]
      .filter(c => c.gone === null)
      .sort((a, b) => b.distance - a.distance || a.number - b.number);
  }

  leaderLap() {
    const leader = this.standings()[0];
    return leader ? Math.min(RULES.totalLaps, Math.floor(leader.distance) + 1) : 1;
  }

  gapText(car, leader) {
    if (car === leader) return 'LEADER';
    const gap = leader.distance - car.distance;
    if (gap < 1) return `+${(gap * RULES.lapSeconds).toFixed(1)}s`;
    const laps = Math.floor(gap);
    return `+${laps} LAP${laps === 1 ? '' : 'S'}`;
  }

  /** Where the car sits: on track, in the pits, stopped, or off the circuit. */
  placement(car) {
    if (this.phase === 'podium') {
      const rank = this.podium.indexOf(car.key);
      return rank >= 0 ? { kind: 'podium', rank } : { kind: 'pit' };
    }
    switch (car.state) {
      case 'working': return { kind: 'track' };
      case 'blocked': return { kind: 'stopped' };
      case 'error': return { kind: 'retired' };
      case 'done': return this.time - car.since < RULES.lapSeconds / RULES.cooldownFactor ? { kind: 'track' } : { kind: 'pit' };
      default: return { kind: 'pit' };
    }
  }
}

/** Collapses a terminal's status records into the one that decides the car. */
const RANK = { blocked: 5, error: 4, working: 3, done: 2, idle: 1 };
export function dominant(records) {
  let best = null;
  for (const r of records) {
    if (!RANK[r.state]) continue;
    if (!best || RANK[r.state] > RANK[best.state] || (RANK[r.state] === RANK[best.state] && !r.id && best.id)) best = r;
  }
  return best;
}

// The 3D world: the circuit, its scenery, and the car models. Everything is
// built from triangles once; cars are re-posed every frame.
import { MAT, hex, tri, textWidth } from './raster.mjs';

// ── Circuit ────────────────────────────────────────────────────────────────

// Control points on the ground plane (x, z), driven in this order. The first
// point is the start/finish line, halfway down the main straight.
const RING = [
  [-60, 120], [100, 120], [200, 110], [255, 55], [240, -5], [185, -32], [120, -22],
  [62, -62], [72, -132], [22, -184], [-82, -172], [-140, -110], [-205, -122],
  [-268, -60], [-275, 42], [-230, 118],
];

export const HALF_WIDTH = 14;
const KERB = 3.2;
const PIT_OFFSET = 36;
const PIT_HALF = 9;
export const PIT_SPACING = 16;
const CAR_SCALE = 2.6;

function catmull(p0, p1, p2, p3, t) {
  const t2 = t * t, t3 = t2 * t;
  return [0, 1].map(k => 0.5 * (
    2 * p1[k] + (-p0[k] + p2[k]) * t + (2 * p0[k] - 5 * p1[k] + 4 * p2[k] - p3[k]) * t2 +
    (-p0[k] + 3 * p1[k] - 3 * p2[k] + p3[k]) * t3));
}

export class Circuit {
  constructor(points = RING, samples = 720) {
    const raw = [];
    const n = points.length;
    for (let i = 0; i < samples; i++) {
      const f = i / samples * n;
      const seg = Math.floor(f);
      raw.push(catmull(points[(seg - 1 + n) % n], points[seg], points[(seg + 1) % n], points[(seg + 2) % n], f - seg));
    }
    this.points = raw;
    this.cumulative = [0];
    for (let i = 1; i <= raw.length; i++) {
      const a = raw[i - 1], b = raw[i % raw.length];
      this.cumulative.push(this.cumulative[i - 1] + Math.hypot(b[0] - a[0], b[1] - a[1]));
    }
    this.length = this.cumulative[raw.length];
    const xs = raw.map(p => p[0]), zs = raw.map(p => p[1]);
    this.center = [(Math.min(...xs) + Math.max(...xs)) / 2, (Math.min(...zs) + Math.max(...zs)) / 2];
    this.radius = Math.max(Math.max(...xs) - Math.min(...xs), Math.max(...zs) - Math.min(...zs)) / 2;

    // Which lateral side is the infield: pit lane and pit building go there,
    // grandstands go on the other side.
    const start = this.pose(0, 0);
    const toCenter = [this.center[0] - start.x, this.center[1] - start.z];
    this.inside = Math.sign(toCenter[0] * start.nx + toCenter[1] * start.nz) || 1;
  }

  /** Pose at `s` metres along the lap, `lateral` metres to the left. */
  pose(s, lateral = 0) {
    const L = this.length;
    s = ((s % L) + L) % L;
    let lo = 0, hi = this.points.length;
    while (hi - lo > 1) {
      const mid = (lo + hi) >> 1;
      if (this.cumulative[mid] <= s) lo = mid; else hi = mid;
    }
    const a = this.points[lo], b = this.points[(lo + 1) % this.points.length];
    const span = this.cumulative[lo + 1] - this.cumulative[lo] || 1;
    const t = (s - this.cumulative[lo]) / span;
    const dx = b[0] - a[0], dz = b[1] - a[1];
    const len = Math.hypot(dx, dz) || 1;
    const tx = dx / len, tz = dz / len;
    const nx = -tz, nz = tx;
    return {
      x: a[0] + dx * t + nx * lateral,
      z: a[1] + dz * t + nz * lateral,
      heading: Math.atan2(tz, tx),
      tx, tz, nx, nz,
    };
  }

  /** Pose at a fraction of the lap. */
  at(progress, lateral = 0) {
    return this.pose(progress * this.length, lateral);
  }

  /** A parked pose in pit box `slot`, along the pit lane beside the main straight. */
  pitBox(slot) {
    const along = -110 + (slot % 14) * PIT_SPACING;
    const row = Math.floor(slot / 14);
    const p = this.pose(along, this.inside * (PIT_OFFSET + 4 + row * 6));
    return { ...p, heading: p.heading + this.inside * 0.5 };
  }

  pitLane(along) {
    return this.pose(along, this.inside * (PIT_OFFSET - 3));
  }
}

// ── Mesh helpers ────────────────────────────────────────────────────────────

function quad(a, b, c, d, color, m = MAT.FLAT, uv = null) {
  const p1 = [...a, ...b, ...c], p2 = [...a, ...c, ...d];
  if (!uv) return [tri(p1, color, m), tri(p2, color, m)];
  return [
    tri(p1, color, m, [...uv[0], ...uv[1], ...uv[2]]),
    tri(p2, color, m, [...uv[0], ...uv[2], ...uv[3]]),
  ];
}

/** Axis-aligned box centred at (x, y, z) with size (sx, sy, sz), in local space. */
function box(x, y, z, sx, sy, sz, color) {
  const X = [x - sx / 2, x + sx / 2], Y = [y - sy / 2, y + sy / 2], Z = [z - sz / 2, z + sz / 2];
  const v = (i, j, k) => [X[i], Y[j], Z[k]];
  return [
    ...quad(v(0, 0, 0), v(1, 0, 0), v(1, 1, 0), v(0, 1, 0), color),
    ...quad(v(0, 0, 1), v(1, 0, 1), v(1, 1, 1), v(0, 1, 1), color),
    ...quad(v(0, 0, 0), v(0, 0, 1), v(0, 1, 1), v(0, 1, 0), color),
    ...quad(v(1, 0, 0), v(1, 0, 1), v(1, 1, 1), v(1, 1, 0), color),
    ...quad(v(0, 1, 0), v(1, 1, 0), v(1, 1, 1), v(0, 1, 1), color),
    ...quad(v(0, 0, 0), v(1, 0, 0), v(1, 0, 1), v(0, 0, 1), color),
  ];
}

/** A wheel: an octagonal cylinder along z. */
function wheel(x, y, z, radius, width, color) {
  const out = [];
  const sides = 8;
  const ring = k => [x + Math.cos(k / sides * Math.PI * 2) * radius, y + Math.sin(k / sides * Math.PI * 2) * radius];
  for (let k = 0; k < sides; k++) {
    const [ax, ay] = ring(k), [bx, by] = ring(k + 1);
    out.push(...quad([ax, ay, z - width / 2], [bx, by, z - width / 2], [bx, by, z + width / 2], [ax, ay, z + width / 2], color));
    for (const side of [-1, 1]) out.push(tri([x, y, z + side * width / 2, ax, ay, z + side * width / 2, bx, by, z + side * width / 2], RIM));
  }
  return out;
}

/** An n-sided cone (tree canopy, marker). Apex up when height > 0. */
function cone(x, y, z, radius, height, color, sides = 6, m = MAT.FLAT) {
  const out = [];
  for (let k = 0; k < sides; k++) {
    const a = k / sides * Math.PI * 2, b = (k + 1) / sides * Math.PI * 2;
    out.push(tri([x + Math.cos(a) * radius, y, z + Math.sin(a) * radius, x + Math.cos(b) * radius, y, z + Math.sin(b) * radius, x, y + height, z], color, m));
  }
  return out;
}

function shade(color, k) {
  return color.map(c => Math.min(1, c * k));
}

const RIM = hex('#9aa0a6');
const TYRE = hex('#1b1c1f');
const CARBON = hex('#24262b');
const HELMET = hex('#f7d046');

// ── Cars ────────────────────────────────────────────────────────────────────

/** An F1 car in local metres: x forward, y up, z across. */
export function carModel(livery) {
  const body = hex(livery);
  const trim = shade(body, 0.55);
  const wing = shade(body, 0.8);
  return [
    ...box(0, 0.12, 0, 3.6, 0.06, 1.4, CARBON),
    ...box(0.35, 0.38, 0, 2.2, 0.38, 0.62, body),
    ...box(1.95, 0.3, 0, 1.4, 0.2, 0.32, body),
    ...box(2.72, 0.24, 0, 0.3, 0.14, 0.22, trim),
    ...box(2.65, 0.1, 0, 0.45, 0.05, 1.9, wing),
    ...box(2.65, 0.17, 0.95, 0.5, 0.18, 0.04, trim),
    ...box(2.65, 0.17, -0.95, 0.5, 0.18, 0.04, trim),
    ...box(-0.25, 0.32, 0.5, 1.5, 0.36, 0.42, body),
    ...box(-0.25, 0.32, -0.5, 1.5, 0.36, 0.42, body),
    ...box(-0.7, 0.58, 0, 1.6, 0.3, 0.42, body),
    ...box(0.05, 0.8, 0, 0.35, 0.25, 0.25, trim),
    ...box(0.45, 0.66, 0, 0.28, 0.24, 0.24, HELMET),
    ...box(0.75, 0.74, 0, 0.55, 0.05, 0.4, CARBON),
    ...box(1.0, 0.66, 0, 0.06, 0.16, 0.06, CARBON),
    ...box(-2.0, 0.85, 0, 0.4, 0.06, 1.3, wing),
    ...box(-2.1, 0.98, 0, 0.3, 0.05, 1.3, body),
    ...box(-2.05, 0.78, 0.66, 0.6, 0.5, 0.04, trim),
    ...box(-2.05, 0.78, -0.66, 0.6, 0.5, 0.04, trim),
    ...box(-1.85, 0.55, 0, 0.12, 0.4, 0.08, CARBON),
    ...box(-2.0, 0.18, 0, 0.4, 0.15, 1.1, CARBON),
    ...wheel(1.75, 0.36, 0.82, 0.36, 0.36, TYRE),
    ...wheel(1.75, 0.36, -0.82, 0.36, 0.36, TYRE),
    ...wheel(-1.55, 0.38, 0.8, 0.38, 0.44, TYRE),
    ...wheel(-1.55, 0.38, -0.8, 0.38, 0.44, TYRE),
  ];
}

export function safetyCarModel(lightsOn) {
  const silver = hex('#c9ccd1');
  return [
    ...box(0, 0.45, 0, 4.4, 0.55, 1.8, silver),
    ...box(-0.3, 0.95, 0, 2.0, 0.45, 1.5, hex('#2a2f3a')),
    ...box(-0.3, 1.24, 0, 0.5, 0.12, 1.2, lightsOn ? hex('#ffb000') : hex('#6b4c00')).map(t => ({ ...t, m: lightsOn ? MAT.GLOW : MAT.FLAT })),
    ...wheel(1.4, 0.34, 0.85, 0.34, 0.3, TYRE),
    ...wheel(1.4, 0.34, -0.85, 0.34, 0.3, TYRE),
    ...wheel(-1.4, 0.34, 0.85, 0.34, 0.3, TYRE),
    ...wheel(-1.4, 0.34, -0.85, 0.34, 0.3, TYRE),
  ];
}

/** Places local-space triangles at a pose: scale, yaw, then translate. */
export function place(model, x, y, z, heading, scale = CAR_SCALE) {
  const c = Math.cos(heading), s = Math.sin(heading);
  return model.map(t => {
    const p = t.p, q = new Array(9);
    for (let i = 0; i < 9; i += 3) {
      const lx = p[i] * scale, ly = p[i + 1] * scale, lz = p[i + 2] * scale;
      // Local x is forward along the heading, local z is to its left.
      q[i] = x + lx * c - lz * s;
      q[i + 1] = y + ly;
      q[i + 2] = z + lx * s + lz * c;
    }
    return { ...t, p: q };
  });
}

export function shadowFor(x, z, heading, scale = CAR_SCALE) {
  const c = Math.cos(heading), s = Math.sin(heading);
  const corner = (lx, lz) => [x + (lx * c - lz * s) * scale, 0, z + (lx * s + lz * c) * scale];
  return quad(corner(3, 1.05), corner(-2.3, 1.05), corner(-2.3, -1.05), corner(3, -1.05), [0, 0, 0], MAT.SHADOW);
}

// ── Static scenery ──────────────────────────────────────────────────────────

function rng(seed) {
  let s = seed >>> 0;
  return () => {
    s = (s + 0x6d2b79f5) >>> 0;
    let t = s;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const CROWD = ['#e8002d', '#3671c6', '#ff8000', '#f2f2f2', '#27f4d2', '#ffd700', '#ff87bc', '#52e252'].map(hex);

export function buildWorld(circuit) {
  const flat = [];
  const solid = [];
  const [cx, cz] = circuit.center;
  const G = 2400;
  flat.push(...quad(
    [cx - G, 0, cz - G], [cx + G, 0, cz - G], [cx + G, 0, cz + G], [cx - G, 0, cz + G], [0, 0, 0], MAT.GRASS,
    [[cx - G, cz - G], [cx + G, cz - G], [cx + G, cz + G], [cx - G, cz + G]]));

  // Pit lane, with ramps back onto the circuit at both ends.
  const pitFrom = -135, pitTo = 125;
  const lane = [];
  for (let s = pitFrom; s < pitTo; s += 10) {
    const a = circuit.pose(s, circuit.inside * (PIT_OFFSET - PIT_HALF));
    const b = circuit.pose(s, circuit.inside * (PIT_OFFSET + PIT_HALF + 10));
    const c = circuit.pose(s + 10, circuit.inside * (PIT_OFFSET + PIT_HALF + 10));
    const d = circuit.pose(s + 10, circuit.inside * (PIT_OFFSET - PIT_HALF));
    // v runs from the fast lane (-1, track side) to the pit boxes (+1).
    lane.push(...quad([a.x, 0, a.z], [b.x, 0, b.z], [c.x, 0, c.z], [d.x, 0, d.z], [0, 0, 0], MAT.PITLANE,
      [[s, -1], [s, 1], [s + 10, 1], [s + 10, -1]]));
  }
  for (const [from, to] of [[pitFrom - 50, pitFrom], [pitTo, pitTo + 50]]) {
    const entry = from < pitFrom;
    const a = circuit.pose(from, circuit.inside * (entry ? HALF_WIDTH - 6 : PIT_OFFSET - PIT_HALF));
    const b = circuit.pose(from, circuit.inside * (entry ? HALF_WIDTH + 2 : PIT_OFFSET + PIT_HALF));
    const c = circuit.pose(to, circuit.inside * (entry ? PIT_OFFSET + PIT_HALF : HALF_WIDTH + 2));
    const d = circuit.pose(to, circuit.inside * (entry ? PIT_OFFSET - PIT_HALF : HALF_WIDTH - 6));
    lane.push(...quad([a.x, 0, a.z], [b.x, 0, b.z], [c.x, 0, c.z], [d.x, 0, d.z], [0, 0, 0], MAT.PITLANE,
      [[from, 0], [from, 0], [to, 0], [to, 0]]));
  }
  flat.push(...lane);

  // Track ribbon and kerbs. Kerbs only sit where the track bends.
  const step = circuit.length / circuit.points.length;
  for (let i = 0; i < circuit.points.length; i++) {
    const s0 = i * step, s1 = (i + 1) * step;
    const l0 = circuit.pose(s0, HALF_WIDTH), r0 = circuit.pose(s0, -HALF_WIDTH);
    const l1 = circuit.pose(s1, HALF_WIDTH), r1 = circuit.pose(s1, -HALF_WIDTH);
    flat.push(...quad([l0.x, 0, l0.z], [r0.x, 0, r0.z], [r1.x, 0, r1.z], [l1.x, 0, l1.z], [0, 0, 0], MAT.ASPHALT,
      [[s0, 1], [s0, -1], [s1, -1], [s1, 1]]));
    const bend = Math.abs(angleDelta(circuit.pose(s0 - 20).heading, circuit.pose(s0 + 20).heading));
    if (bend > 0.12) {
      for (const side of [1, -1]) {
        const a = circuit.pose(s0, side * HALF_WIDTH), b = circuit.pose(s0, side * (HALF_WIDTH + KERB));
        const c = circuit.pose(s1, side * (HALF_WIDTH + KERB)), d = circuit.pose(s1, side * HALF_WIDTH);
        flat.push(...quad([a.x, 0, a.z], [b.x, 0, b.z], [c.x, 0, c.z], [d.x, 0, d.z], [0, 0, 0], MAT.KERB,
          [[s0, 0], [s0, 0], [s1, 0], [s1, 0]]));
      }
    }
  }

  // Start gantry over the line. Its lights are re-coloured per frame.
  const g = circuit.pose(0);
  const post = side => {
    const p = circuit.pose(0, side * (HALF_WIDTH + 5));
    return box(0, 0, 0, 1.6, 1, 1.6, hex('#30343c')).map(t => ({ ...t, p: t.p.map((v, k) => k % 3 === 0 ? v + p.x : k % 3 === 1 ? v * 18 + 9 : v + p.z) }));
  };
  solid.push(...post(1), ...post(-1));
  solid.push(...place(box(0, 0, 0, 1.2, 1.4, (HALF_WIDTH + 6) * 2, hex('#30343c')), g.x, 18, g.z, g.heading, 1));

  // Pit building and garages behind the pit boxes.
  const garage = [];
  for (let s = -125; s < 115; s += 30) {
    const p = circuit.pose(s + 15, circuit.inside * (PIT_OFFSET + PIT_HALF + 22));
    garage.push(...place(box(0, 7, 0, 29.5, 14, 22, hex('#d9dce1')), p.x, 0, p.z, p.heading, 1));
    garage.push(...place(box(0, 14.6, 0, 30, 1.2, 23, hex('#3a3f4b')), p.x, 0, p.z, p.heading, 1));
    const door = circuit.pose(s + 15, circuit.inside * (PIT_OFFSET + PIT_HALF + 10.9));
    garage.push(...place(box(0, 4.5, 0, 22, 8, 0.4, hex('#5a6170')), door.x, 0, door.z, door.heading, 1));
  }
  solid.push(...garage);

  // Grandstands on the outside of the main straight, tiers full of crowd.
  const random = rng(7);
  for (const center of [-110, -30, 50]) {
    for (let tier = 0; tier < 5; tier++) {
      const lateral = -circuit.inside * (HALF_WIDTH + 16 + tier * 4.5);
      for (let k = -30; k < 30; k += 6) {
        const p = circuit.pose(center + k + 3, lateral);
        const colour = CROWD[Math.floor(random() * CROWD.length)];
        solid.push(...place(box(0, 1.5 + tier * 2.6, 0, 6, 3 + tier * 5.2, 4.5, shade(colour, 0.85)), p.x, 0, p.z, p.heading, 1));
      }
    }
    const roof = circuit.pose(center, -circuit.inside * (HALF_WIDTH + 25));
    solid.push(...place(box(0, 19, 0, 62, 0.8, 26, hex('#e4e6ea')), roof.x, 0, roof.z, roof.heading, 1));
  }

  // Trees, kept clear of the circuit, pits and stands.
  const near = circuit.points.filter((_, i) => i % 6 === 0);
  for (let s = -180; s <= 160; s += 20) {
    for (const lateral of [circuit.inside * 60, -circuit.inside * 30]) {
      const p = circuit.pose(s, lateral);
      near.push([p.x, p.z]);
    }
  }
  const podium = circuit.pose(0, circuit.inside * (PIT_OFFSET + PIT_HALF + 75));
  near.push([podium.x, podium.z]);
  let placed = 0;
  for (let attempt = 0; attempt < 600 && placed < 110; attempt++) {
    const angle = random() * Math.PI * 2;
    const r = circuit.radius * (0.1 + random() * 1.6);
    const x = cx + Math.cos(angle) * r, z = cz + Math.sin(angle) * r;
    if (near.some(p => Math.hypot(p[0] - x, p[1] - z) < 75)) continue;
    const size = 0.8 + random() * 0.7;
    const green = hex(random() < 0.5 ? '#2e6b34' : '#356f2a');
    solid.push(...box(x, 3 * size, z, 1.6 * size, 6 * size, 1.6 * size, hex('#5b3a1f')));
    solid.push(...cone(x, 4 * size, z, 7 * size, 14 * size, green));
    solid.push(...cone(x, 10 * size, z, 5 * size, 10 * size, shade(green, 1.15)));
    placed++;
  }

  // Podium, in the infield behind the pits.
  const podiumAt = (place2, lift) => {
    const offset = [0, -1, 1][place2] * 22;
    return { x: podium.x + podium.tx * offset, z: podium.z + podium.tz * offset, y: lift, heading: podium.heading + circuit.inside * Math.PI / 2 };
  };
  const steps = [6, 4, 2.4];
  for (let k = 0; k < 3; k++) {
    const at = podiumAt(k, 0);
    solid.push(...place(box(0, steps[k] / 2, 0, 20, steps[k], 20, k === 0 ? hex('#e8c547') : k === 1 ? hex('#c0c4ca') : hex('#c98a4b')), at.x, 0, at.z, podium.heading, 1));
  }

  return {
    flat, solid,
    gantry: g,
    podium: { x: podium.x, z: podium.z, slot: k => podiumAt(k, steps[k]) },
  };
}

export function gantryLights(gantry, colour) {
  const out = [];
  for (let k = -2; k <= 2; k++) {
    out.push(...place(box(0.8, 0, k * 3, 0.6, 1.4, 1.8, hex(colour)).map(t => ({ ...t, m: MAT.GLOW })), gantry.x, 16.4, gantry.z, gantry.heading, 1));
  }
  return out;
}

export function markerAbove(x, y, z, colour, t) {
  const bob = Math.sin(t * 4) * 0.8;
  return cone(x, y + 9.5 + bob, z, 2.4, -4, hex(colour), 4, MAT.GLOW);
}

export function beacon(x, y, z, on) {
  return box(x, y, z, 1.6, 1.6, 1.6, on ? hex('#ffb000') : hex('#8a5a00')).map(t => ({ ...t, m: on ? MAT.GLOW : MAT.FLAT }));
}

export function smoke(x, z, t, seed) {
  const out = [];
  for (let k = 0; k < 5; k++) {
    const phase = ((t * 0.6 + k / 5 + seed) % 1);
    const size = 2 + phase * 5;
    const grey = 0.75 - phase * 0.3;
    out.push(...box(x + Math.sin(k * 2.1 + seed) * 2, 3 + phase * 22, z + Math.cos(k * 1.7) * 2 + phase * 6, size, size, size, [grey, grey, grey]));
  }
  return out;
}

export function angleDelta(a, b) {
  let d = b - a;
  while (d > Math.PI) d -= Math.PI * 2;
  while (d < -Math.PI) d += Math.PI * 2;
  return d;
}

/** Draws a number tag above a projected point. */
export function tag(renderer, screen, label, background, foreground, outlined) {
  const scale = renderer.h >= 300 ? 2 : 1;
  const width = textWidth(label, scale) + 4 * scale;
  const height = 5 * scale + 4 * scale;
  const x = Math.round(screen[0] - width / 2), y = Math.round(screen[1] - height);
  if (outlined) renderer.rect(x - scale, y - scale, x + width + scale, y + height + scale, [255, 255, 255]);
  renderer.rect(x, y, x + width, y + height, background);
  renderer.text(label, x + 2 * scale, y + 2 * scale, scale, foreground);
}

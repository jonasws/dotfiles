// Turns race state into a rendered frame: car poses, cameras, effects, tags.
import { hex } from './raster.mjs';
import {
  HALF_WIDTH, angleDelta, beacon, buildWorld, carModel, gantryLights, markerAbove,
  place, safetyCarModel, shadowFor, smoke, tag,
} from './scene.mjs';

export const CAMERAS = ['tv', 'heli', 'chase', 'birdseye'];
const BLEND_SECONDS = 1.6;

export class Broadcast {
  constructor(circuit) {
    this.circuit = circuit;
    this.world = buildWorld(circuit);
    this.models = new Map();
    this.poses = new Map();
    this.eye = null;
    this.target = null;
    this.t = 0;
    this.still = null;
    // Everything the bird's-eye view has to fit: the circuit plus the pits,
    // stands and podium beside it.
    const xs = circuit.points.map(p => p[0]), zs = circuit.points.map(p => p[1]);
    const margin = 70;
    this.extent = {
      x: (Math.max(...xs) - Math.min(...xs)) / 2 + margin,
      z: (Math.max(...zs) - Math.min(...zs)) / 2 + margin,
    };
  }

  model(livery) {
    if (!this.models.has(livery)) this.models.set(livery, carModel(livery));
    return this.models.get(livery);
  }

  /** Where a car should be right now, before blending. */
  targetPose(race, car) {
    const c = this.circuit;
    const where = race.placement(car);
    const progress = car.distance % 1;
    switch (where.kind) {
      case 'track': {
        const p = c.at(progress, car.lane * HALF_WIDTH * 0.45);
        return { kind: 'track', x: p.x, z: p.z, y: 0, heading: p.heading };
      }
      case 'stopped': {
        const p = c.at(progress, car.lane * HALF_WIDTH * 0.45);
        return { kind: 'stopped', x: p.x, z: p.z, y: 0, heading: p.heading + 0.7 };
      }
      case 'retired': {
        const p = c.at(progress, -c.inside * (HALF_WIDTH + 12));
        return { kind: 'retired', x: p.x, z: p.z, y: 0, heading: p.heading + 1.3 };
      }
      case 'podium': {
        const p = this.world.podium.slot(where.rank);
        return { kind: 'podium', x: p.x, z: p.z, y: p.y, heading: p.heading };
      }
      default: {
        const p = c.pitBox(car.pitSlot);
        return { kind: 'pit', x: p.x, z: p.z, y: 0, heading: p.heading };
      }
    }
  }

  /** Eases a car between placements so it drives into the pits rather than
   *  teleporting there. Moving along the track needs no easing. */
  pose(race, car, dt) {
    const want = this.targetPose(race, car);
    let state = this.poses.get(car.key);
    if (!state) {
      state = { kind: want.kind, from: null, t: 1, current: want };
      this.poses.set(car.key, state);
    }
    if (want.kind !== state.kind) {
      state.from = state.current;
      state.kind = want.kind;
      state.t = 0;
    }
    if (state.t < 1) {
      state.t = Math.min(1, state.t + dt / BLEND_SECONDS);
      const e = state.t * state.t * (3 - 2 * state.t);
      const f = state.from;
      state.current = {
        kind: want.kind,
        x: f.x + (want.x - f.x) * e,
        z: f.z + (want.z - f.z) * e,
        y: f.y + (want.y - f.y) * e,
        heading: f.heading + angleDelta(f.heading, want.heading) * e,
      };
    } else {
      state.current = want;
    }
    return state.current;
  }

  /** `scope`, when given, is the set of car keys the viewer has narrowed to:
   *  cars outside it still race, with grey tags. */
  render(renderer, race, { selected, camera, dt, scope = null }) {
    this.t += dt;
    const t = this.t;
    renderer.trackLength = this.circuit.length;

    const order = race.standings();
    const live = [];
    for (const car of order) live.push({ car, pose: this.pose(race, car, dt) });
    for (const key of this.poses.keys()) if (!race.cars.has(key)) this.poses.delete(key);

    this.moveCamera(renderer, race, live, selected, camera, dt);
    this.drawStill(renderer);

    const shadows = [];
    const solid = [];
    const lights = race.phase === 'podium' ? '#e8c547' : race.yellow ? (Math.floor(t * 2) % 2 ? '#ffb000' : '#3a2b00') : '#36d66b';
    solid.push(...gantryLights(this.world.gantry, lights));

    for (const { car, pose } of live) {
      shadows.push(...shadowFor(pose.x, pose.z, pose.heading));
      solid.push(...place(this.model(car.livery), pose.x, pose.y, pose.z, pose.heading));
      if (pose.kind === 'stopped') solid.push(...beacon(pose.x, pose.y + 4.6, pose.z, Math.floor(t * 3) % 2 === 0));
      if (pose.kind === 'retired') solid.push(...smoke(pose.x, pose.z, t, car.number / 7));
      if (car.key === selected) solid.push(...markerAbove(pose.x, pose.y, pose.z, car.livery, t));
    }
    if (race.safetyCar) {
      const p = this.circuit.at(race.safetyCar.progress, 0);
      shadows.push(...shadowFor(p.x, p.z, p.heading));
      solid.push(...place(safetyCarModel(Math.floor(t * 4) % 2 === 0), p.x, 0, p.z, p.heading));
    }

    renderer.drawSolid(shadows);
    renderer.drawSolid(solid);

    // Number tags, furthest first so near ones stay on top. Each car's tag
    // and body positions are kept so a mouse click can find it.
    const tags = [];
    this.hits = [];
    for (const { car, pose } of live) {
      const screen = renderer.project([pose.x, pose.y + 14, pose.z]);
      const body = renderer.project([pose.x, pose.y + 1, pose.z]);
      if (body) this.hits.push({ key: car.key, x: body[0], y: body[1] });
      if (screen && screen[0] > -40 && screen[0] < renderer.w + 40 && screen[1] > 0) {
        tags.push({ car, screen });
        this.hits.push({ key: car.key, x: screen[0], y: screen[1] - 6 });
      }
    }
    tags.sort((a, b) => b.screen[2] - a.screen[2]);
    for (const { car, screen } of tags) {
      const inScope = !scope || scope.has(car.key);
      const bg = inScope ? hex(car.livery).map(c => c * 255) : [92, 96, 110];
      const light = bg[0] * 0.299 + bg[1] * 0.587 + bg[2] * 0.114 > 150;
      const ink = !inScope ? [190, 194, 205] : light ? [10, 10, 12] : [255, 255, 255];
      tag(renderer, screen, String(car.number), bg, ink, car.key === selected);
    }
    if (race.safetyCar) {
      const p = this.circuit.at(race.safetyCar.progress, 0);
      const screen = renderer.project([p.x, 9, p.z]);
      if (screen) tag(renderer, screen, 'SC', [255, 176, 0], [10, 10, 12], false);
    }
  }

  /** The car nearest to a point in image pixels, if one is close enough. */
  carAt(x, y, renderer) {
    const reach = Math.max(14, renderer.w * 0.035);
    let best = null, bestDistance = reach;
    for (const hit of this.hits || []) {
      const d = Math.hypot(hit.x - x, hit.y - y);
      if (d < bestDistance) { best = hit.key; bestDistance = d; }
    }
    return best;
  }

  /** The sky, ground, track and scenery. While the camera holds still, as
   *  it does in the bird's-eye view, they are drawn once and copied after. */
  drawStill(renderer) {
    const key = [renderer.w, renderer.h, ...this.eye, ...this.target, this.fov, renderer.fogStart].join();
    const still = this.still;
    if (still && still.renderer === renderer && still.key === key) {
      renderer.color.set(still.color);
      renderer.depth.set(still.depth);
      return;
    }
    renderer.clear(hex('#5b8fd6'), hex('#c9dcf0'));
    renderer.drawFlat(this.world.flat);
    renderer.drawSolid(this.world.solid);
    this.still = { renderer, key, color: renderer.color.slice(), depth: renderer.depth.slice() };
  }

  /** A fixed view from above that fits the whole circuit. The long side of
   *  the circuit goes along the long side of the pane. */
  birdseye(renderer, fov) {
    const [cx, cz] = this.circuit.center;
    const tilt = 0.32;
    const v = Math.tan(fov * Math.PI / 360);
    const h = v * renderer.w / renderer.h;
    const fit = (across, along) => Math.max(across / h, along * Math.cos(tilt) / v) * 1.06;
    const wide = fit(this.extent.x, this.extent.z), tall = fit(this.extent.z, this.extent.x);
    const d = Math.min(wide, tall);
    // Tilted back along z when x runs across the screen, along x otherwise.
    const back = wide <= tall ? [0, -1] : [-1, 0];
    return {
      eye: [cx + back[0] * Math.sin(tilt) * d, Math.cos(tilt) * d, cz + back[1] * Math.sin(tilt) * d],
      target: [cx, 0, cz],
      distance: d,
    };
  }

  moveCamera(renderer, race, live, selected, camera, dt) {
    const c = this.circuit;
    const [cx, cz] = c.center;
    const t = this.t;
    let eye, target, fov = 50;
    const focus = live.find(l => l.car.key === selected) || live[0];

    renderer.fogStart = 260;
    renderer.fogEnd = 1500;
    if (camera === 'birdseye') {
      // Frozen: it stays put through the podium too.
      const view = this.birdseye(renderer, fov);
      eye = view.eye;
      target = view.target;
      renderer.fogStart = view.distance * 1.6;
      renderer.fogEnd = renderer.fogStart + 1500;
    } else if (race.phase === 'podium') {
      const p = this.world.podium;
      const a = t * 0.25;
      eye = [p.x + Math.cos(a) * 70, 32, p.z + Math.sin(a) * 70];
      target = [p.x, 6, p.z];
    } else if (camera === 'heli' || !focus) {
      const a = t * 0.04;
      const r = c.radius * 1.15;
      eye = [cx + Math.cos(a) * r, c.radius * 0.75, cz + Math.sin(a) * r];
      target = [cx, 0, cz];
    } else if (camera === 'chase') {
      const p = focus.pose;
      const fx = Math.cos(p.heading), fz = Math.sin(p.heading);
      eye = [p.x - fx * 34, p.y + 12, p.z - fz * 34];
      target = [p.x + fx * 30, p.y + 2, p.z + fz * 30];
      fov = 60;
    } else {
      // TV: a trackside camera orbiting the car it follows.
      const p = focus.pose;
      const a = t * 0.12;
      eye = [p.x + Math.cos(a) * 70, p.y + 30, p.z + Math.sin(a) * 70];
      target = [p.x, p.y + 2, p.z];
      fov = 45;
    }

    if (!this.eye || dt <= 0) {
      this.eye = eye;
      this.target = target;
    } else {
      const k = 1 - Math.exp(-dt * 3);
      this.eye = this.eye.map((v, i) => v + (eye[i] - v) * k);
      this.target = this.target.map((v, i) => v + (target[i] - v) * k);
      // Snap once close, so a camera that has arrived is exactly still.
      const off = Math.max(...this.eye.map((v, i) => Math.abs(v - eye[i])), ...this.target.map((v, i) => Math.abs(v - target[i])));
      if (off < 0.05) {
        this.eye = eye;
        this.target = target;
      }
    }
    this.fov = fov;
    renderer.setCamera(this.eye, this.target, fov);
  }
}

// A small software rasterizer: flat-shaded triangles, a z-buffer, near-plane
// clipping and perspective-correct uv for the procedural ground and track
// materials. Output is a packed RGB buffer, ready for Kitty graphics (f=24).

export const MAT = {
  FLAT: 0,    // lit by the sun, colour per triangle
  GRASS: 1,   // uv = world x/z: mowing stripes
  ASPHALT: 2, // uv = (metres along the lap, lateral -1..1): edge lines, grid
  KERB: 3,    // uv = (metres along the lap, -): red and white blocks
  SHADOW: 4,  // darkens what is already drawn, writes nothing
  GLOW: 5,    // unlit, for lights and markers
  PITLANE: 6, // uv = (metres along the lane, lateral -1..1)
};

const NEAR = 0.5;
const SUN = normalize([-0.45, 0.8, -0.35]);

export function normalize(v) {
  const l = Math.hypot(v[0], v[1], v[2]) || 1;
  return [v[0] / l, v[1] / l, v[2] / l];
}

export function hex(color) {
  const n = parseInt(color.slice(1), 16);
  return [(n >> 16 & 255) / 255, (n >> 8 & 255) / 255, (n & 255) / 255];
}

/** A triangle in world space. `uv` is only read by the procedural materials. */
export function tri(p, c, m = MAT.FLAT, uv = null) {
  return { p, c, m, uv };
}

export class Renderer {
  constructor(width, height) {
    this.resize(width, height);
    this.fog = [0.62, 0.72, 0.86];
    this.fogStart = 260;
    this.fogEnd = 1500;
    this.trackLength = 1;
  }

  resize(width, height) {
    this.w = width;
    this.h = height;
    this.color = new Uint8Array(width * height * 3);
    this.depth = new Float32Array(width * height);
    this.sky = null;
  }

  setCamera(eye, target, fovDegrees = 50) {
    const fwd = normalize([target[0] - eye[0], target[1] - eye[1], target[2] - eye[2]]);
    // fwd × world up, then right × fwd: a level camera with +y up on screen.
    let right = [-fwd[2], 0, fwd[0]];
    if (Math.hypot(right[0], right[2]) < 1e-6) right = [1, 0, 0];
    right = normalize(right);
    const up = [
      right[1] * fwd[2] - right[2] * fwd[1],
      right[2] * fwd[0] - right[0] * fwd[2],
      right[0] * fwd[1] - right[1] * fwd[0],
    ];
    this.eye = eye;
    this.basis = { fwd, right, up };
    this.focal = (this.h / 2) / Math.tan((fovDegrees * Math.PI / 180) / 2);
  }

  /** World → screen, or null behind the camera. */
  project(p) {
    const v = this.toView(p);
    if (v[2] < NEAR) return null;
    return [this.w / 2 + v[0] * this.focal / v[2], this.h / 2 - v[1] * this.focal / v[2], v[2]];
  }

  toView(p) {
    const { fwd, right, up } = this.basis;
    const dx = p[0] - this.eye[0], dy = p[1] - this.eye[1], dz = p[2] - this.eye[2];
    return [
      dx * right[0] + dy * right[1] + dz * right[2],
      dx * up[0] + dy * up[1] + dz * up[2],
      dx * fwd[0] + dy * fwd[1] + dz * fwd[2],
    ];
  }

  clear(top, bottom) {
    if (!this.sky || this.sky.top !== top || this.sky.bottom !== bottom) {
      const row = new Uint8Array(this.w * this.h * 3);
      for (let y = 0; y < this.h; y++) {
        const t = y / Math.max(1, this.h - 1);
        const r = (top[0] + (bottom[0] - top[0]) * t) * 255;
        const g = (top[1] + (bottom[1] - top[1]) * t) * 255;
        const b = (top[2] + (bottom[2] - top[2]) * t) * 255;
        for (let x = 0; x < this.w; x++) {
          const i = (y * this.w + x) * 3;
          row[i] = r; row[i + 1] = g; row[i + 2] = b;
        }
      }
      this.sky = { top, bottom, pixels: row };
      this.fog = bottom;
    }
    this.color.set(this.sky.pixels);
    this.depth.fill(0);
  }

  /** Flat layers (ground, track, shadows) are painted in order with no depth
   *  test; solids are z-buffered on top of them. Everything on the ground is
   *  coplanar, so this sidesteps z-fighting entirely. */
  drawFlat(tris) {
    for (const t of tris) this.drawTri(t, false);
  }

  drawSolid(tris) {
    for (const t of tris) this.drawTri(t, true);
  }

  drawTri(t, depthTest) {
    const p = t.p;
    const a = this.toView([p[0], p[1], p[2]]);
    const b = this.toView([p[3], p[4], p[5]]);
    const c = this.toView([p[6], p[7], p[8]]);
    if (a[2] < NEAR && b[2] < NEAR && c[2] < NEAR) return;
    const far = this.fogEnd * 1.2;
    if (a[2] > far && b[2] > far && c[2] > far) return;

    let shade = t.c;
    if (t.m === MAT.FLAT) {
      // Two-sided lighting: turn the normal towards the camera, so winding
      // order never matters.
      const e1 = [p[3] - p[0], p[4] - p[1], p[5] - p[2]];
      const e2 = [p[6] - p[0], p[7] - p[1], p[8] - p[2]];
      let n = normalize([
        e1[1] * e2[2] - e1[2] * e2[1],
        e1[2] * e2[0] - e1[0] * e2[2],
        e1[0] * e2[1] - e1[1] * e2[0],
      ]);
      const toEye = [this.eye[0] - p[0], this.eye[1] - p[1], this.eye[2] - p[2]];
      if (n[0] * toEye[0] + n[1] * toEye[1] + n[2] * toEye[2] < 0) n = [-n[0], -n[1], -n[2]];
      const lambert = Math.max(0, n[0] * SUN[0] + n[1] * SUN[1] + n[2] * SUN[2]);
      const sky = 0.5 + 0.5 * n[1];
      const k = 0.32 + 0.16 * sky + 0.62 * lambert;
      shade = [t.c[0] * k, t.c[1] * k, t.c[2] * k];
    }

    const uv = t.uv || ZERO_UV;
    let poly = [
      [a[0], a[1], a[2], uv[0], uv[1]],
      [b[0], b[1], b[2], uv[2], uv[3]],
      [c[0], c[1], c[2], uv[4], uv[5]],
    ];
    if (a[2] < NEAR || b[2] < NEAR || c[2] < NEAR) poly = clipNear(poly);
    if (poly.length < 3) return;

    const s = poly.map(v => {
      const iz = 1 / v[2];
      return [this.w / 2 + v[0] * this.focal * iz, this.h / 2 - v[1] * this.focal * iz, iz, v[3] * iz, v[4] * iz];
    });
    for (let i = 1; i + 1 < s.length; i++) this.raster(s[0], s[i], s[i + 1], t.m, shade, depthTest);
  }

  raster(v0, v1, v2, mat, shade, depthTest) {
    const area = (v1[0] - v0[0]) * (v2[1] - v0[1]) - (v2[0] - v0[0]) * (v1[1] - v0[1]);
    if (Math.abs(area) < 1e-9) return;
    const minX = Math.max(0, Math.floor(Math.min(v0[0], v1[0], v2[0])));
    const maxX = Math.min(this.w - 1, Math.ceil(Math.max(v0[0], v1[0], v2[0])));
    const minY = Math.max(0, Math.floor(Math.min(v0[1], v1[1], v2[1])));
    const maxY = Math.min(this.h - 1, Math.ceil(Math.max(v0[1], v1[1], v2[1])));
    if (minX > maxX || minY > maxY) return;

    const inv = 1 / area;
    // Barycentric weights as linear functions of the pixel centre.
    const a0 = (v1[1] - v2[1]) * inv, b0 = (v2[0] - v1[0]) * inv, c0 = (v1[0] * v2[1] - v2[0] * v1[1]) * inv;
    const a1 = (v2[1] - v0[1]) * inv, b1 = (v0[0] - v2[0]) * inv, c1 = (v2[0] * v0[1] - v0[0] * v2[1]) * inv;

    const { color, depth, w } = this;
    const fog = this.fog;
    const fogStart = this.fogStart, fogSpan = this.fogEnd - this.fogStart;
    const sr = shade[0] * 255, sg = shade[1] * 255, sb = shade[2] * 255;
    const procedural = mat !== MAT.FLAT && mat !== MAT.GLOW;

    const a2 = -(a0 + a1);
    for (let y = minY; y <= maxY; y++) {
      const py = y + 0.5;
      // Each weight is linear in x along the row, so the covered span can be
      // solved for directly instead of testing every pixel of the bounding box.
      const k0 = b0 * py + c0, k1 = b1 * py + c1, k2 = 1 - k0 - k1;
      let lo = minX + 0.5, hi = maxX + 0.5;
      [lo, hi] = span(a0, k0, lo, hi);
      [lo, hi] = span(a1, k1, lo, hi);
      [lo, hi] = span(a2, k2, lo, hi);
      if (lo > hi) continue;
      const xStart = Math.max(minX, Math.ceil(lo - 0.5)), xEnd = Math.min(maxX, Math.floor(hi - 0.5));
      for (let x = xStart; x <= xEnd; x++) {
        const px = x + 0.5;
        const w0 = Math.max(0, a0 * px + k0);
        const w1 = Math.max(0, a1 * px + k1);
        const w2 = Math.max(0, 1 - w0 - w1);
        const iz = w0 * v0[2] + w1 * v1[2] + w2 * v2[2];
        const i = y * w + x;
        if (depthTest) {
          if (iz <= depth[i]) continue;
          if (mat !== MAT.SHADOW) depth[i] = iz;
        }
        const z = 1 / iz;
        const o = i * 3;
        if (mat === MAT.SHADOW) {
          color[o] *= 0.55; color[o + 1] *= 0.55; color[o + 2] *= 0.58;
          continue;
        }
        let r = sr, g = sg, b = sb;
        if (procedural) {
          const u = (w0 * v0[3] + w1 * v1[3] + w2 * v2[3]) * z;
          const v = (w0 * v0[4] + w1 * v1[4] + w2 * v2[4]) * z;
          const c = this.material(mat, u, v);
          r = c[0]; g = c[1]; b = c[2];
        }
        let f = (z - fogStart) / fogSpan;
        if (f > 0) {
          if (f > 1) f = 1;
          f *= 0.85;
          r += (fog[0] * 255 - r) * f;
          g += (fog[1] * 255 - g) * f;
          b += (fog[2] * 255 - b) * f;
        }
        color[o] = r; color[o + 1] = g; color[o + 2] = b;
      }
    }
  }

  material(mat, u, v) {
    switch (mat) {
      case MAT.GRASS: {
        const stripe = (Math.floor((u + v * 0.35) / 22) & 1) === 0;
        return stripe ? GRASS_A : GRASS_B;
      }
      case MAT.ASPHALT: {
        const edge = Math.abs(v);
        if (edge > 0.93 && edge < 0.98) return LINE;
        let s = u % this.trackLength;
        if (s < 0) s += this.trackLength;
        if (s < 4 || s > this.trackLength - 4) {
          // Chequered start/finish line.
          const cell = (Math.floor(s * 0.75) + Math.floor((v + 1) * 6)) & 1;
          return cell ? LINE : INK;
        }
        // Grid boxes behind the line.
        const back = this.trackLength - s;
        if (back > 10 && back < 130 && (Math.floor((back - 10) / 12) & 1) === 0 && Math.abs(Math.abs(v) - 0.42) < 0.2) {
          const inBox = ((back - 10) % 12) < 0.9;
          if (inBox) return LINE;
        }
        return Math.abs(v) < 0.5 ? ASPHALT_RACING : ASPHALT;
      }
      case MAT.KERB:
        return (Math.floor(u / 4) & 1) === 0 ? KERB_RED : LINE;
      case MAT.PITLANE: {
        if (Math.abs(v) > 0.9) return LINE;
        const box = ((u % 16) + 16) % 16;
        if (v > -0.15 && box < 0.6) return PIT_LINE;
        return v < -0.15 ? PIT_FAST : PIT_BOX;
      }
      default:
        return [255, 0, 255];
    }
  }

  /** A filled screen-space rectangle. */
  rect(x0, y0, x1, y1, rgb) {
    x0 = Math.max(0, Math.round(x0)); y0 = Math.max(0, Math.round(y0));
    x1 = Math.min(this.w, Math.round(x1)); y1 = Math.min(this.h, Math.round(y1));
    for (let y = y0; y < y1; y++) {
      for (let x = x0; x < x1; x++) {
        const o = (y * this.w + x) * 3;
        this.color[o] = rgb[0]; this.color[o + 1] = rgb[1]; this.color[o + 2] = rgb[2];
      }
    }
  }

  /** Bitmap text for car numbers and flags, 3×5 glyphs scaled by `scale`. */
  text(str, x, y, scale, rgb) {
    for (const ch of str) {
      const glyph = GLYPHS[ch];
      if (glyph) {
        for (let gy = 0; gy < 5; gy++) {
          for (let gx = 0; gx < 3; gx++) {
            if (glyph[gy] >> (2 - gx) & 1) this.rect(x + gx * scale, y + gy * scale, x + (gx + 1) * scale, y + (gy + 1) * scale, rgb);
          }
        }
      }
      x += 4 * scale;
    }
  }
}

export function textWidth(str, scale) {
  return [...str].length * 4 * scale - scale;
}

/** Narrows [lo, hi] to where a * x + k >= 0 (with a hair of slack, so shared
 *  edges leave no cracks). */
function span(a, k, lo, hi) {
  const EPS = 1e-6;
  if (Math.abs(a) < 1e-12) return k >= -EPS ? [lo, hi] : [1, 0];
  const x = (-EPS - k) / a;
  return a > 0 ? [Math.max(lo, x), hi] : [lo, Math.min(hi, x)];
}

function clipNear(poly) {
  const out = [];
  for (let i = 0; i < poly.length; i++) {
    const a = poly[i], b = poly[(i + 1) % poly.length];
    const aIn = a[2] >= NEAR, bIn = b[2] >= NEAR;
    if (aIn) out.push(a);
    if (aIn !== bIn) {
      const t = (NEAR - a[2]) / (b[2] - a[2]);
      out.push(a.map((value, k) => value + (b[k] - value) * t));
    }
  }
  return out;
}

const ZERO_UV = [0, 0, 0, 0, 0, 0];
const rgb255 = h => hex(h).map(c => c * 255);
const GRASS_A = rgb255('#3f8f3a');
const GRASS_B = rgb255('#47a040');
const ASPHALT = rgb255('#4a4e57');
const ASPHALT_RACING = rgb255('#41454d');
const LINE = rgb255('#f2f2f2');
const INK = rgb255('#16181d');
const KERB_RED = rgb255('#d7263d');
const PIT_FAST = rgb255('#55595f');
const PIT_BOX = rgb255('#5d6168');
const PIT_LINE = rgb255('#e8c547');

const GLYPHS = {
  0: [7, 5, 5, 5, 7], 1: [2, 6, 2, 2, 7], 2: [7, 1, 7, 4, 7], 3: [7, 1, 7, 1, 7],
  4: [5, 5, 7, 1, 1], 5: [7, 4, 7, 1, 7], 6: [7, 4, 7, 5, 7], 7: [7, 1, 2, 2, 2],
  8: [7, 5, 7, 5, 7], 9: [7, 5, 7, 1, 7],
  P: [6, 5, 6, 4, 4], S: [7, 4, 7, 1, 7], C: [7, 4, 4, 4, 7], '!': [2, 2, 2, 0, 2],
  D: [6, 5, 5, 5, 6], N: [5, 7, 7, 5, 5], F: [7, 4, 6, 4, 4], '#': [5, 7, 5, 7, 5],
};

// Getting pixels out: Kitty graphics for Rex, half blocks for terminals
// without it, and PNG for --snapshot.
import { deflateSync } from 'node:zlib';

const CHUNK = 4096;

/** One frame as a Kitty graphics transmit-and-display, zlib-compressed RGB.
 *  Frames alternate between two image ids: the new one is placed before the
 *  old one is deleted, so there is never a gap to flicker through. */
export class KittyFrames {
  constructor() {
    this.current = null;
  }

  frame(rgb, width, height, cols, rows) {
    const id = this.current === 1701 ? 1702 : 1701;
    const data = deflateSync(rgb, { level: 1 }).toString('base64');
    let out = '';
    for (let i = 0; i < data.length; i += CHUNK) {
      const more = i + CHUNK < data.length ? 1 : 0;
      const head = i === 0
        ? `a=T,f=24,o=z,s=${width},v=${height},i=${id},p=1,c=${cols},r=${rows},C=1,q=2,m=${more}`
        : `m=${more}`;
      out += `\x1b_G${head};${data.slice(i, i + CHUNK)}\x1b\\`;
    }
    if (this.current !== null) out += `\x1b_Ga=d,d=I,i=${this.current},q=2\x1b\\`;
    this.current = id;
    return out;
  }

  clear() {
    this.current = null;
    return '\x1b_Ga=d,d=A,q=2\x1b\\';
  }
}

/** Upper half blocks: two pixels per cell, for terminals without graphics. */
export function halfBlocks(rgb, width, height, row, col) {
  let out = '';
  for (let y = 0; y + 1 < height; y += 2) {
    out += `\x1b[${row + y / 2};${col}H`;
    let last = '';
    for (let x = 0; x < width; x++) {
      const a = (y * width + x) * 3, b = ((y + 1) * width + x) * 3;
      const sgr = `\x1b[38;2;${rgb[a]};${rgb[a + 1]};${rgb[a + 2]};48;2;${rgb[b]};${rgb[b + 1]};${rgb[b + 2]}m`;
      out += (sgr === last ? '' : sgr) + '▀';
      last = sgr;
    }
    out += '\x1b[0m';
  }
  return out;
}

const CRC = new Uint32Array(256).map((_, n) => {
  let c = n;
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  return c >>> 0;
});

function crc32(buf) {
  let c = 0xffffffff;
  for (const byte of buf) c = CRC[(c ^ byte) & 255] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const head = Buffer.alloc(8);
  head.writeUInt32BE(data.length, 0);
  head.write(type, 4, 'ascii');
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(Buffer.concat([head.subarray(4), data])), 0);
  return Buffer.concat([head, data, crc]);
}

export function png(rgb, width, height) {
  const raw = Buffer.alloc((width * 3 + 1) * height);
  for (let y = 0; y < height; y++) {
    raw[y * (width * 3 + 1)] = 0;
    Buffer.from(rgb.buffer, rgb.byteOffset + y * width * 3, width * 3).copy(raw, y * (width * 3 + 1) + 1);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; ihdr[9] = 2;
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', deflateSync(raw)),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

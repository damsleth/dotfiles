// Generates icon.ico — a dark-purple pill on transparent background.
// Pure Node.js, no npm deps needed.
const fs = require('fs');

function isPill(x, y, w, h) {
  const r = h / 2;
  const cx0 = r;
  const cx1 = w - r;
  const cy  = r;
  if (x >= cx0 && x <= cx1) return (y - cy) ** 2 <= r * r;
  if (x < cx0)  return (x - cx0) ** 2 + (y - cy) ** 2 <= r * r;
  if (x > cx1)  return (x - cx1) ** 2 + (y - cy) ** 2 <= r * r;
  return false;
}

function makePixels(size) {
  const buf = Buffer.alloc(size * size * 4);

  const pw = Math.round(size * 0.84);
  const ph = Math.round(size * 0.42);
  const ox = Math.round((size - pw) / 2);
  const oy = Math.round((size - ph) / 2);

  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const i = (y * size + x) * 4;
      const lx = x - ox, ly = y - oy;

      if (lx >= 0 && lx < pw && ly >= 0 && ly < ph && isPill(lx, ly, pw, ph)) {
        const t = ph > 0 ? ly / ph : 0; // 0 = top, 1 = bottom
        const r = Math.round(60  + t * -30);   // 60 → 30
        const g = Math.round(0);
        const b = Math.round(110 + t * -50);   // 110 → 60

        // Thin highlight stripe along the top quarter
        const highlight = t < 0.18;
        buf[i]   = highlight ? Math.min(255, r + 80) : r;
        buf[i+1] = g;
        buf[i+2] = highlight ? Math.min(255, b + 80) : b;
        buf[i+3] = 255;
      }
      // else: transparent (zero-filled by alloc)
    }
  }
  return buf;
}

function bmpInIco(size, rgba) {
  const maskRowBytes = Math.ceil(size / 32) * 4;
  const hdr = Buffer.alloc(40);
  hdr.writeUInt32LE(40,         0);
  hdr.writeInt32LE (size,       4);
  hdr.writeInt32LE (size * 2,   8);  // doubled for ICO
  hdr.writeUInt16LE(1,         12);
  hdr.writeUInt16LE(32,        14);
  hdr.writeUInt32LE(size*size*4,20);

  // BGRA, bottom-up
  const px = Buffer.alloc(size * size * 4);
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const si = (y * size + x) * 4;
      const di = ((size - 1 - y) * size + x) * 4;
      px[di]   = rgba[si+2];
      px[di+1] = rgba[si+1];
      px[di+2] = rgba[si];
      px[di+3] = rgba[si+3];
    }
  }

  // AND mask: 1 = transparent, 0 = opaque
  const mask = Buffer.alloc(maskRowBytes * size, 0);
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      if (rgba[(y * size + x) * 4 + 3] === 0) {
        const my = size - 1 - y;
        mask[my * maskRowBytes + (x >> 3)] |= (0x80 >> (x & 7));
      }
    }
  }

  return Buffer.concat([hdr, px, mask]);
}

function makeIco(sizes) {
  const count = sizes.length;
  const dir   = Buffer.alloc(6);
  dir.writeUInt16LE(0,     0);
  dir.writeUInt16LE(1,     2);
  dir.writeUInt16LE(count, 4);

  const entries = [];
  const images  = [];
  let offset = 6 + count * 16;

  for (const sz of sizes) {
    const bmp   = bmpInIco(sz, makePixels(sz));
    const entry = Buffer.alloc(16);
    entry.writeUInt8   (sz >= 256 ? 0 : sz, 0);
    entry.writeUInt8   (sz >= 256 ? 0 : sz, 1);
    entry.writeUInt8   (0,  2);
    entry.writeUInt8   (0,  3);
    entry.writeUInt16LE(1,  4);
    entry.writeUInt16LE(32, 6);
    entry.writeUInt32LE(bmp.length, 8);
    entry.writeUInt32LE(offset,    12);
    entries.push(entry);
    images.push(bmp);
    offset += bmp.length;
  }

  return Buffer.concat([dir, ...entries, ...images]);
}

const ico = makeIco([16, 24, 32, 48, 64, 128, 256]);
fs.writeFileSync('icon.ico', ico);
console.log(`icon.ico written (${ico.length} bytes)`);

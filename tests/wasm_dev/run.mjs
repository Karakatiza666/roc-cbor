// The host of scripts/wasm_dev.sh: node run.mjs app.wasm expected.txt
// expected.txt: one line for each case, "name seed checksum". Each case runs in a new instance.
// A case fails on a trap or a wrong checksum. When the module exports __stack_low and __stack_high,
// the stack use of each case is measured (the stack is filled with a mark first), and the stack for each
// nesting level (case "deep" against case "rr1") must be at most WASM_DEV_LEVEL_BUDGET bytes.
import { readFileSync } from 'node:fs';

const [file, expectedFile] = process.argv.slice(2);
const budget = Number(process.env.WASM_DEV_LEVEL_BUDGET || 30000);
const mod = new WebAssembly.Module(readFileSync(file));
const cases = readFileSync(expectedFile, 'utf8').split('\n').filter((l) => l.trim() && !l.startsWith('#')).map((l) => l.trim().split(/\s+/));
const used = {};
let failed = 0;

for (const [name, seed, want] of cases) {
  let mem;
  let next = 0;
  const u8 = () => new Uint8Array(mem.buffer);
  const dv = () => new DataView(mem.buffer);
  // A bump allocator above the initial memory. The 4 bytes before each block hold its length (for realloc).
  const alloc = (len, align) => {
    const pre = Math.max(align, 8);
    if (next === 0) next = mem.buffer.byteLength;
    const at = Math.ceil(next / pre) * pre + pre;
    next = at + len;
    if (next > mem.buffer.byteLength) mem.grow(Math.ceil((next - mem.buffer.byteLength) / 65536));
    dv().setUint32(at - 4, len, true);
    return at;
  };
  const env = {
    roc_alloc: alloc,
    roc_dealloc: () => {},
    roc_realloc: (p, len, align) => {
      const q = alloc(len, align);
      u8().copyWithin(q, p, p + Math.min(dv().getUint32(p - 4, true), len));
      return q;
    },
    roc_crashed: (p, len) => {
      throw new Error(`roc crashed: ${new TextDecoder().decode(u8().slice(p, p + len))}`);
    },
  };
  const x = new WebAssembly.Instance(mod, { env }).exports;
  mem = x.memory;
  const lo = x.__stack_low ? x.__stack_low.value : 0;
  const hi = x.__stack_high ? x.__stack_high.value : 0;
  u8().fill(0xa5, lo, hi);
  let got;
  try {
    got = String(x.roc_main(BigInt(seed)));
  } catch (e) {
    got = `trap (${e.message})`;
  }
  let low = lo;
  while (low < hi && u8()[low] === 0xa5) low++;
  used[name] = hi - low;
  const ok = got === want;
  if (!ok) failed++;
  console.log(`${ok ? 'PASS' : 'FAIL'} ${name}: ${got}${ok ? '' : `, want ${want}`}${hi ? `, stack ${hi - low} of ${hi - lo}` : ''}`);
}

if (used.deep !== undefined && used.rr1 !== undefined && used.deep > 0) {
  // rr1 has 3 levels, deep has 6.
  const level = Math.round((used.deep - used.rr1) / 3);
  const ok = level <= budget;
  if (!ok) failed++;
  console.log(`${ok ? 'PASS' : 'FAIL'} stack for each level: ${level} bytes (budget ${budget})`);
} else {
  console.log('SKIP stack for each level: the module has no __stack_low and __stack_high (an older nightly)');
}
process.exitCode = failed ? 1 : 0;

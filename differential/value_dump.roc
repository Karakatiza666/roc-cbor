app [] { pkg: "../src/main.roc" }

# P24: the Roc side of the differential test. Each arg is the hex of one input. For each input, one line:
# "ok <dump>" when Cbor.parse_with (IndefiniteLength) reads it as a Cbor.Value, else "err". differential.py writes the same dump
# from cbor2. The dump format:
#
# | Item | Dump |
# | --- | --- |
# | Integer | `i<decimal>` |
# | Float | `f<16 hex digits of the f64 bits>`, `fnan` for each NaN |
# | Byte string, text | `b<hex>`, `t<hex of the UTF-8 bytes>` |
# | Array, map | `[a,b]`, `{k:v,k:v}` in the order of the bytes |
# | Tag | `c<number>(<item>)` |
# | Simple | `false`, `true`, `null`, `undef`, `s<number>` |

import pkg.Cbor

digit : U8 -> U8
digit = |n| if (n < 10) n + 48 else n + 87

hex : List(U8) -> Str
hex = |bytes| Str.from_utf8(bytes.join_map(|b| [digit(b // 16), digit(b % 16)])) ?? "?"

hex64 : U64 -> Str
hex64 = |n| hex((0.U64).until(8).fold(([], n), |(acc, m), _| (acc.prepend((m % 256).to_u8_wrap()), m // 256)).0)

nibble : U8 -> Try(U8, [BadHex])
nibble = |c|
	if c >= 48 and c <= 57 {
		Ok(c - 48)
	} else if c >= 97 and c <= 102 {
		Ok(c - 87)
	} else {
		Err(BadHex)
	}

unhex : Str -> Try(List(U8), [BadHex])
unhex = |s| {
	chars = s.to_utf8()
	var $out = List.with_capacity(chars.len() // 2)
	for i in (0.U64).until(chars.len() // 2) {
		hi = nibble(chars.get(2 * i) ?? 0)?
		lo = nibble(chars.get(2 * i + 1) ?? 0)?
		$out = $out.append(hi * 16 + lo)
	}
	Ok($out)
}

dump : Cbor.Value -> Str
dump = |v|
	match v {
		Int(i) => "i${i.to_i128().to_str()}"
		Float(f) => if (f.is_nan()) "fnan" else "f${hex64(f.to_bits())}"
		Bytes(b) => "b${hex(b)}"
		Text(s) => "t${hex(s.to_utf8())}"
		Array(items) => "[${Str.join_with(items.map(dump), ",")}]"
		Map(pairs) => "{${Str.join_with(pairs.to_list().map(|(k, x)| "${dump(k)}:${dump(x)}"), ",")}}"
		Tag(n, x) => "c${n.to_str()}(${dump(x)})"
		Bool(b) => if (b) "true" else "false"
		Null => "null"
		Undefined => "undef"
		Simple(n) => "s${n.to_u8().to_str()}"
	}

main! = |args| {
	for arg in args {
		line =
			match unhex(arg) {
				Ok(bytes) => {
					r : Try(Cbor.Value, _)
					# IndefiniteLength: cbor2 reads indefinite lengths, so they are compared too.
					r = Cbor.parse_with(bytes, { allow: [IndefiniteLength] })
					match r {
						Ok(v) => "ok ${dump(v)}"
						Err(_) => "err"
					}
				}
				Err(_) => "badhex"
			}
		echo!("${line}\n")
	}
	Ok({})
}

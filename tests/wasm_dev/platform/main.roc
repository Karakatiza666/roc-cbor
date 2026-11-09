## The platform of scripts/wasm_dev.sh: no host code. The wasm module imports roc_alloc, roc_realloc, roc_dealloc and
## roc_crashed, and tests/wasm_dev/run.mjs gives them. The script writes an empty host object to targets/wasm32/host.wasm.
platform ""
	requires {
		main! : U64 => U64
	}
	exposes []
	packages {}
	provides { "roc_main": main_for_host! }
	targets: {
		inputs_dir: "targets/",
		wasm32: {
			inputs: ["host.wasm", app],
			output: Shared,
			exports: ["roc_main"],
		},
	}

main_for_host! : U64 => U64
main_for_host! = |seed| main!(seed)

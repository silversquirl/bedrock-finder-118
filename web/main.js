(function () {
	'use strict';

	const form = document.getElementById("params");
	const status = document.getElementById("status");
	const result_list = document.getElementById("results");

	// Less-than operation for search results
	const resultsInOrder = (a, b) => {
		const a_d2 = a.x*a.x + a.y*a.y + a.z*a.z;
		const b_d2 = b.x*b.x + b.y*b.y + b.z*b.z;
		if (a_d2 !== b_d2) {
			return a_d2 < b_d2;
		}

		// Break ties
		if (a.x !== b.x) {
			return a.x < b.x;
		}
		if (a.z !== b.z) {
			return a.z < b.z;
		}
		return a.y < b.y;
	};

	let results = [];
	const reportResult = (res) => {
		// Insert the result preserving sortedness
		var i = results.length;
		while (i > 0 && resultsInOrder(res, results[i-1])) i--;
		results.splice(i, 0, res);

		// Insert a DOM element at the same position
		const elem = document.createElement("li");
		elem.innerText = `(${res.x}, ${res.y}, ${res.z})`;
		if (i === result_list.length) {
			result_list.appendChild(elem);
		} else {
			result_list.insertBefore(elem, result_list.children[i]);
		}
	}

	let wasm;
	const wasm_promise = WebAssembly.instantiateStreaming(fetch("bedrock-finder.wasm"), {bedrock: {
		consoleLog(ptr, len) { // For debugging purposes
			const buf = new Uint8Array(wasm.memory.buffer, ptr, len);
			const str = new TextDecoder('utf-8').decode(buf);
			console.log(str);
		},

		resultCallback(x, y, z) {
			reportResult({
				x: x,
				y: y,
				z: z,
			});
		},
	}}).then(result => {
		wasm = result.instance.exports;
	});

	// Yield to the event loop
	const tickEventLoop = () => {
		return new Promise(resolve => {
			const chan = new MessageChannel();
			chan.port1.onmessage = resolve;
			chan.port2.postMessage(undefined);
		});
	};

	const submitSearch = async config => {
		await wasm_promise;

		const searcher = wasm.searchInit(
			config.seed, 0 /* overworld_floor */,
			config.x0, config.y0, config.z0,
			config.x1, config.y1, config.z1,
		);
		if (searcher == 0) {
			console.error("error initializing search");
			return;
		}

		while (wasm.searchStep(searcher)) {
			const percent = 100 * wasm.searchProgress(searcher);
			status.innerText = `Searching... (${percent.toFixed(2)}%)`;
			await tickEventLoop();
		}
		status.innerText = 'Done';
		wasm.searchDeinit(searcher);
	};

	form.addEventListener("submit", async ev => {
		ev.preventDefault();

		const seed = BigInt(form.elements.seed.value);
		const range = form.elements.range.value | 0;

		submitSearch({
			seed: seed,

			x0: -range,
			x1: range,
			y0: -60,
			y1: -60,
			z0: -range,
			z1: range,
		});
	});
})();

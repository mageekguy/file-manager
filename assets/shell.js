/* jshint esversion: 6 */

const $shell = $("#shell")
const $close = $("#shell-close")

if ($shell.length > 0) {
	const ws = new WebSocket(
		"ws" +
		(window.location.protocol === "https:" ? "s" : "") +
		"://" +
		window.location.host +
		"/websocket?path=" +
		encodeURIComponent($shell.data("path"))
	)

	const term = new Terminal()
	const attachAddon = new AttachAddon.AttachAddon(ws, { bidirectional: true })
	term.loadAddon(attachAddon)
	const fitAddon = new FitAddon.FitAddon()
	term.loadAddon(fitAddon)
	term.open($shell[0])

	ws.addEventListener("open", () => {
		// resize
		term.onResize(({ cols, rows }) => {
			console.debug(cols, rows)
			const buf = Uint16Array.of(0, cols, rows)
			ws.send(buf)
		})
		$(window).on("resize", () => {
			fitAddon.fit()
		})
		fitAddon.fit()

		// close
		let closeTimeout = null
		$close.on("click", (e) => {
			e.preventDefault()
			if (ws.readyState !== 1) {
				window.location.pathname = window.location.pathname.replace(
					"@shell",
					""
				)
			} else {
				ws.close()
			}
		})
		ws.addEventListener("close", () => {
			term.write("\r\n\r\nclosing shell in 2 seconds...")
			closeTimeout = setTimeout(() => {
				window.location.pathname = window.location.pathname.replace(
					"@shell",
					""
				)
			}, 2000)
		})
		term.onData(() => {
			if (closeTimeout != null) {
				clearTimeout(closeTimeout)
				term.write("\r\nkeyboard input detected. timeout canceled")
				closeTimeout = null
			}
		})
	})
}

let runInShellTerm = null
let ws = null

const setRunInShellTerm = (runInShellBtn) => {
	let btn = $(runInShellBtn.currentTarget)

	ws = new WebSocket(
		(window.location.protocol === "http:" ? "ws" : "wss") + "://" +
		window.location.host +
		"/websocket?path=" +
		encodeURIComponent(btn.data("dir"))
	)

	runInShellTerm = new Terminal({
		cols: 123
	})

	ws.addEventListener("open", () => {
		runInShellTerm.loadAddon(new AttachAddon.AttachAddon(ws, { bidirectional: true }))
		runInShellTerm.open(document.getElementById('run-in-shell-term'))
		ws.send(btn.data('cmd') + ' ' + btn.data("file"))
	})
}

$('#run-in-shell').on('shown.bs.modal', function () {
	$('#run-in-shell').trigger('focus')
})

$('#run-in-shell').on('hidden.bs.modal', () => {
	if (runInShellTerm) {
		runInShellTerm.dispose()
		runInShellTerm = null
		ws.close()
		ws = null
	}
})

$(".run-in-shell").on("click", setRunInShellTerm)

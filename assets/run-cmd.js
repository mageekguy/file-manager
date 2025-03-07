/* jshint esversion: 6 */

let $runCmd = $(".run-cmd")

const updateRunCmdModal = (runBtn) => {
	let btn = $(runBtn.currentTarget)
	$('#cmd-cmd').val(btn.data('cmd') + ' ' + btn.data("select"))
}

$runCmd.on("click", updateRunCmdModal)

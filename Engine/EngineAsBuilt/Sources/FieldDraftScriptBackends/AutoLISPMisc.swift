// MARK: - Misc Functions

func prompt(_ msg: any LispValue) -> Call { Call("prompt", msg) }
func prin1(_ expr: any LispValue, _ desc: (any LispValue)? = nil) -> Call { desc.map { Call("prin1", expr, $0) } ?? Call("prin1", expr) }
func print_(_ expr: any LispValue, _ desc: (any LispValue)? = nil) -> Call { desc.map { Call("print", expr, $0) } ?? Call("print", expr) }
func terpri() -> Call { Call("terpri") }
func alert(_ str: any LispValue) -> Call { Call("alert", str) }
func commandS(_ args: any LispValue...) -> Call { Call(name: "command-s", args: args.map { $0.toLispNode() }) }
func initcommandversion(_ version: (any LispValue)? = nil) -> Call { version.map { Call("initcommandversion", $0) } ?? Call("initcommandversion") }
func initdia(_ flag: (any LispValue)? = nil) -> Call { flag.map { Call("initdia", $0) } ?? Call("initdia") }
func help(_ helpfile: (any LispValue)? = nil, _ topic: (any LispValue)? = nil, _ flag: (any LispValue)? = nil) -> Call {
    var args: [any LispValue] = []
    if let h = helpfile { args.append(h); if let t = topic { args.append(t); if let f = flag { args.append(f) } } }
    return Call(name: "help", args: args.map { $0.toLispNode() })
}
func setfunhelp(_ cmd: any LispValue, _ helpfile: any LispValue, _ topic: any LispValue) -> Call { Call("setfunhelp", cmd, helpfile, topic) }
func acadColordlg(_ color: any LispValue, _ flag: (any LispValue)? = nil) -> Call { flag.map { Call("acad_colordlg", color, $0) } ?? Call("acad_colordlg", color) }
func acadHelpdlg(_ helpfile: any LispValue, _ topic: any LispValue) -> Call { Call("acad_helpdlg", helpfile, topic) }
func acadTruecolordlg(_ color: any LispValue, _ allowbylayer: (any LispValue)? = nil, _ currentlayercolor: (any LispValue)? = nil) -> Call {
    var args: [any LispValue] = [color]
    if let a = allowbylayer { args.append(a); if let c = currentlayercolor { args.append(c) } }
    return Call(name: "acad_truecolordlg", args: args.map { $0.toLispNode() })
}
func acadTruecolorcli(_ color: any LispValue) -> Call { Call("acad_truecolorcli", color) }
func acadPopDbmod() -> Call { Call("acad-pop-dbmod") }
func acadPushDbmod() -> Call { Call("acad-push-dbmod") }
func acdimenableupdate(_ status: any LispValue) -> Call { Call("acdimenableupdate", status) }
func acetLayerpMark(_ status: (any LispValue)? = nil) -> Call { status.map { Call("acet-layerp-mark", $0) } ?? Call("acet-layerp-mark") }
func acetLayerpMode(_ status: (any LispValue)? = nil) -> Call { status.map { Call("acet-layerp-mode", $0) } ?? Call("acet-layerp-mode") }
func acetLaytrans(_ drawing: any LispValue, _ settings: any LispValue) -> Call { Call("acet-laytrans", drawing, settings) }
func acetMsToPs(_ value: any LispValue) -> Call { Call("acet-ms-to-ps", value) }
func acetPsToMs(_ value: any LispValue) -> Call { Call("acet-ps-to-ms", value) }
func trans(_ pt: any LispValue, _ from: any LispValue, _ to: any LispValue, _ disp: (any LispValue)? = nil) -> Call { disp.map { Call("trans", pt, from, to, $0) } ?? Call("trans", pt, from, to) }
func cvunit(_ value: any LispValue, _ from: any LispValue, _ to: any LispValue) -> Call { Call("cvunit", value, from, to) }
func osnap(_ pt: any LispValue, _ mode: any LispValue) -> Call { Call("osnap", pt, mode) }
func vports() -> Call { Call("vports") }
func showhtmlmodalwindow(_ url: any LispValue, _ options: (any LispValue)? = nil) -> Call { options.map { Call("showhtmlmodalwindow", url, $0) } ?? Call("showhtmlmodalwindow", url) }
func popErrorMode() -> Call { Call("*pop-error-mode*") }
func pushErrorUsingCommand() -> Call { Call("*push-error-using-command*") }
func pushErrorUsingStack() -> Call { Call("*push-error-using-stack*") }
func defunQ(_ name: any LispValue, _ args: any LispValue, _ locals: any LispValue, _ expr: any LispValue) -> Call { Call("defun-q", name, args, locals, expr) }
func defunQListRef(_ function: any LispValue) -> Call { Call("defun-q-list-ref", function) }
func defunQListSet(_ sym: any LispValue, _ listVal: any LispValue) -> Call { Call("defun-q-list-set", sym, listVal) }

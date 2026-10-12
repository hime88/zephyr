// MARK: - File I/O

func fileOpen(_ filename: any LispValue, _ mode: any LispValue) -> Call { Call("open", filename, mode) }
func fileClose(_ desc: any LispValue) -> Call { Call("close", desc) }
func readLine(_ desc: (any LispValue)? = nil) -> Call { desc.map { Call("read-line", $0) } ?? Call("read-line") }
func readChar(_ desc: (any LispValue)? = nil) -> Call { desc.map { Call("read-char", $0) } ?? Call("read-char") }
func writeLine(_ str: any LispValue, _ desc: (any LispValue)? = nil) -> Call { desc.map { Call("write-line", str, $0) } ?? Call("write-line", str) }
func writeChar(_ char: any LispValue, _ desc: (any LispValue)? = nil) -> Call { desc.map { Call("write-char", char, $0) } ?? Call("write-char", char) }
func findfile(_ filename: any LispValue) -> Call { Call("findfile", filename) }
func findtrustedfile(_ filename: any LispValue) -> Call { Call("findtrustedfile", filename) }
func load(_ filename: any LispValue, _ onFailure: (any LispValue)? = nil) -> Call { onFailure.map { Call("load", filename, $0) } ?? Call("load", filename) }
func vlFileCopy(_ src: any LispValue, _ dest: any LispValue, _ append: (any LispValue)? = nil) -> Call { append.map { Call("vl-file-copy", src, dest, $0) } ?? Call("vl-file-copy", src, dest) }
func vlFileDelete(_ filename: any LispValue) -> Call { Call("vl-file-delete", filename) }
func vlFileDirectoryP(_ filename: any LispValue) -> Call { Call("vl-file-directory-p", filename) }
func vlFileRename(_ old: any LispValue, _ new: any LispValue) -> Call { Call("vl-file-rename", old, new) }
func vlFileSize(_ filename: any LispValue) -> Call { Call("vl-file-size", filename) }
func vlFileSystime(_ filename: any LispValue) -> Call { Call("vl-file-systime", filename) }
func vlFilenameBase(_ filename: any LispValue) -> Call { Call("vl-filename-base", filename) }
func vlFilenameDirectory(_ filename: any LispValue) -> Call { Call("vl-filename-directory", filename) }
func vlFilenameExtension(_ filename: any LispValue) -> Call { Call("vl-filename-extension", filename) }
func vlFilenameMktemp(_ pattern: (any LispValue)? = nil, _ dir: (any LispValue)? = nil, _ ext: (any LispValue)? = nil) -> Call {
    var args: [any LispValue] = []
    if let p = pattern { args.append(p); if let d = dir { args.append(d); if let e = ext { args.append(e) } } }
    return Call(name: "vl-filename-mktemp", args: args.map { $0.toLispNode() })
}
func vlMkdir(_ dir: any LispValue) -> Call { Call("vl-mkdir", dir) }
func vlDirectoryFiles(_ path: (any LispValue)? = nil, _ pattern: (any LispValue)? = nil, _ dirs: (any LispValue)? = nil) -> Call {
    var args: [any LispValue] = []
    if let p = path { args.append(p); if let pat = pattern { args.append(pat); if let d = dirs { args.append(d) } } }
    return Call(name: "vl-directory-files", args: args.map { $0.toLispNode() })
}

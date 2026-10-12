// StubBuiltins: the 17 Tier-2-only inventory entries (ARX/VLX/VBA
// loading, menus, tablet, modal HTML, text page, layer translate).
// Each dispatches and throws LispError.unsupportedStub with the
// platform message — no silent nil, no crash.
enum StubBuiltins {
    static let table: [String: LispBuiltin] = {
        var table: [String: LispBuiltin] = [:]
        for name in [
            "ACET-LAYTRANS",
            "ARX",
            "ARXLOAD",
            "ARXUNLOAD",
            "AUTOARXLOAD",
            "MENUCMD",
            "MENUGROUP",
            "SHOWHTMLMODALWINDOW",
            "TABLET",
            "TEXTPAGE",
            "VL-ARX-IMPORT",
            "VL-LIST-LOADED-VLX",
            "VL-LOAD-ALL",
            "VL-UNLOAD-VLX",
            "VL-VBALOAD",
            "VL-VBARUN",
            "VL-VLX-LOADED-P",
        ] {
            table[name] = { _, args, _, _ in
                _ = args
                throw LispError.unsupportedStub(name)
            }
        }
        return table
    }()
}

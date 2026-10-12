// MARK: - Table & Dictionary

func tblnext(_ table: any LispValue, _ rewind: (any LispValue)? = nil) -> Call { rewind.map { Call("tblnext", table, $0) } ?? Call("tblnext", table) }
func tblsearch(_ table: any LispValue, _ entry: any LispValue, _ setnext: (any LispValue)? = nil) -> Call { setnext.map { Call("tblsearch", table, entry, $0) } ?? Call("tblsearch", table, entry) }
func tblobjname(_ table: any LispValue, _ entry: any LispValue) -> Call { Call("tblobjname", table, entry) }
func namedobjdict() -> Call { Call("namedobjdict") }
func dictadd(_ dict: any LispValue, _ symbol: any LispValue, _ obj: any LispValue) -> Call { Call("dictadd", dict, symbol, obj) }
func dictnext(_ dict: any LispValue, _ rewind: (any LispValue)? = nil) -> Call { rewind.map { Call("dictnext", dict, $0) } ?? Call("dictnext", dict) }
func dictremove(_ dict: any LispValue, _ symbol: any LispValue) -> Call { Call("dictremove", dict, symbol) }
func dictrename(_ dict: any LispValue, _ old: any LispValue, _ new: any LispValue) -> Call { Call("dictrename", dict, old, new) }
func dictsearch(_ dict: any LispValue, _ symbol: any LispValue, _ setnext: (any LispValue)? = nil) -> Call { setnext.map { Call("dictsearch", dict, symbol, $0) } ?? Call("dictsearch", dict, symbol) }

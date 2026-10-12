// MARK: - Operator Overloads

prefix func -(value: any LispValue) -> Call { Call("-", value) }
func +(lhs: any LispValue, rhs: any LispValue) -> Call { Call("+", lhs, rhs) }
func -(lhs: any LispValue, rhs: any LispValue) -> Call { Call("-", lhs, rhs) }
func *(lhs: any LispValue, rhs: any LispValue) -> Call { Call("*", lhs, rhs) }
func /(lhs: any LispValue, rhs: any LispValue) -> Call { Call("/", lhs, rhs) }
func >(lhs: any LispValue, rhs: any LispValue) -> Call { Call(">", lhs, rhs) }
func <(lhs: any LispValue, rhs: any LispValue) -> Call { Call("<", lhs, rhs) }
func >=(lhs: any LispValue, rhs: any LispValue) -> Call { Call(">=", lhs, rhs) }
func <=(lhs: any LispValue, rhs: any LispValue) -> Call { Call("<=", lhs, rhs) }

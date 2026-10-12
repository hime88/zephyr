// MARK: - Dict / Hash Helpers

func dictSet(_ tag: any LispValue, _ key: any LispValue, _ value: any LispValue) -> Call {
    Call("set", Call("read", Call("strcat", tag, key)), value)
}
func dictHas(_ tag: any LispValue, _ key: any LispValue) -> Call {
    Call("boundp", Call("read", Call("strcat", tag, key)))
}
func dictGet(_ tag: any LispValue, _ key: any LispValue) -> Call {
    Call("eval", Call("read", Call("strcat", tag, key)))
}

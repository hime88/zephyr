# AutoLISP examples

Runnable compatibility examples for Zephyr's AutoLISP engine. Each script
defines one `c:` command. In the app, run `LOAD`, pick the file in the
picker, then type the command name.

| File | Command | What it exercises |
|---|---|---|
| `shapes.lsp` | `SHAPES` | `entmake` for LINE, CIRCLE, ARC, POINT, TEXT, and a closed LWPOLYLINE |
| `selection.lsp` | `SELCOUNT` | `ssget "_X"` with no filter, `(0 . type)`, and `(62 . color)` filters; `sslength` |
| `modify.lsp` | `REDCIRCLES` | `entget` / `entmod` / `subst` / `assoc` round-trip; colors all circles red |
| `input.lsp` | `INPUTDEMO` | `getpoint` (pick + base-point forms), `getstring`, `getint`, `repeat`, `strcat` |

Related builtins worth probing next: `ssget` window/crossing/fence/polygon
modes with corner points, `ssname`/`ssadd`/`ssdel` set editing, `entdel`,
`getdist`/`getangle`/`getorient`, `getkword` with `initget`, `tblsearch`
layer/block queries, and `(command …)` scripted calls.

Every example is executed headless by `LispExamplesTests` (real evaluator +
CAD host, broker-fed input), so a script that stops working fails the build.

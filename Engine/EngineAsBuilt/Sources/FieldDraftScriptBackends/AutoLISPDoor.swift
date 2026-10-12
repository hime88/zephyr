// MARK: - Door Helpers

func drawDoorPanel(
    hingePt: any LispPointType,
    dEndPt: any LispPointType,
    p3: any LispPointType,
    p4: any LispPointType
) -> LispNode {
    command("_.PLINE", "_non", hingePt, "_non", dEndPt, "_non", p3, "_non", p4, "_C")
}

func drawDoorArc(
    diff: any LispNumberType,
    hingePt: any LispPointType,
    latchPt: any LispPointType,
    dEndPt: any LispPointType
) -> LispNode {
    ifElse(diff > 0.0) {
        command("_.ARC", "_C", "_non", hingePt, "_non", latchPt, "_non", dEndPt)
    } else: {
        command("_.ARC", "_C", "_non", hingePt, "_non", dEndPt, "_non", latchPt)
    }
}

func withDoorPoints(_ body: LispNode) -> LispNode {
    let hingePt = pointVar("hingePt")
    return LispBlock(nodes: [
        setvar("OSMODE", 512).comment("Snap to Nearest"),
        ifLet("hingePt", Prompt.point("Click first line for Hinge Point: ")) {
            setvar("OSMODE", 128).comment("Snap to Perpendicular")
            ifLet("latchPt", Prompt.point("Click second line for Latch Point: ", basePoint: hingePt)) {
                setvar("OSMODE", 0).comment("Disable snaps")
                ifLet("swingPt", Prompt.point("Click anywhere on the side the door should swing towards: ", basePoint: hingePt)) {
                    body
                } else: {
                    princ("\\nError: No swing direction provided.")
                }
            } else: {
                princ("\\nError: Invalid latch point.")
            }
        } else: {
            princ("\\nError: Invalid hinge point.")
        }
    ])
}

func withDoorPoints(@AutoLISPBuilder body: () -> LispNode) -> LispNode {
    withDoorPoints(body())
}

struct DynamicSetq: LispNode {
    let pairs: [(String, LispNode)]

    func render(environment: LispEnvironment) -> String {
        for pair in pairs { environment.localVariables.insert(pair.0) }
        guard let first = pairs.first else { return "(setq)" }
        if pairs.count == 1 {
            return "(setq \(first.0) \(first.1.render(environment: environment)))"
        }
        let rest = pairs.dropFirst().map {
            "      \($0.0) \($0.1.render(environment: environment))"
        }.joined(separator: "\n")
        return "(setq \(first.0) \(first.1.render(environment: environment))\n\(rest))"
    }
}

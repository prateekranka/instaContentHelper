from .support import Finding, bodies, contains, scoped

HISTORY = [
    ("8daa6b1", ["tests/pocket-plan.e2e.ts"]),
    ("8ce636a^", ["tests/pocket-support.ts"]),
]
RECONSTRUCTED = "Step 6 loop artifacts: inclusive target top replaced by the two-point swipe inset"


def check(repository):
    findings = []
    for file, source in repository.sources.items():
        if not file.startswith("tests/"):
            continue
        for stream, i, scope in scoped(source):
            token = stream[i]
            if token.value == "scrollUntilVisible" and i > 0 and stream[i - 1].value == ".":
                supported = file == "tests/pocket-support.ts" and "function:scrollToControl" in scope and i > 1 and stream[i - 2].value == "scrollView"
                if not supported:
                    findings.append(Finding(file, token.line, "Use scrollToControl(screen, locator, direction) or tapVisibleControl from tests/pocket-support.ts; raw scrollUntilVisible can put a control under a pinned dock."))
    file = "tests/pocket-support.ts"
    implementations = list(bodies(repository.sources.get(file, ""), "function", "scrollToControl"))
    dock_edge = ["visibleBottom", "=", "Math", ".", "min", "(", "visibleBottom", ",", "box", ".", "y", "-", "8", ")"]
    target_edge = ["inScrollView", "?", "visibleBottom", ":", "viewportBottom"]
    if not implementations or not all(contains(body, dock_edge) and contains(body, target_edge) for body in implementations):
        findings.append(Finding(file, implementations[0][0].line if implementations else 1, "Use the dock-aware scrollToControl implementation: exclude pinned controls from visibleBottom and use targetBottom for content hit targets."))
    target_top = ["const", "targetTop", "=", "Math", ".", "max", "(", "8", ",", "scrollBox", ".", "y", "-", "0", ".", "5", ")"]
    top_check = ["box", ".", "y", ">", "=", "targetTop"]
    top_assertion = ["expect", "(", "box", ".", "y", ")", ".", "toBeGreaterThanOrEqual", "(", "targetTop", ")"]
    outer_scroll_view = ["filter", "(", "{", "has", ":", "locator", "}", ")", ".", "first", "(", ")"]
    for body in implementations:
        if not all(contains(body, sequence) for sequence in [target_top, top_check, top_assertion, outer_scroll_view]):
            findings.append(Finding(file, body[0].line, "Use scrollToControl's outer containing scroll view and inclusive targetTop with rounding tolerance; keep visibleTop's swipe inset separate and retain the dock-aware bottom edge."))
    return findings


def reconstruct(root):
    file = root / "tests/pocket-support.ts"
    source = file.read_text()
    old = "const targetTop = Math.max(8, scrollBox.y - 0.5);"
    new = "const targetTop = Math.max(8, scrollBox.y + 2);"
    if source.count(old) != 1:
        raise RuntimeError("Cannot reconstruct the Step 6 top-edge mistake.")
    file.write_text(source.replace(old, new))

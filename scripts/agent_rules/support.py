import re
import subprocess
from collections import Counter
from dataclasses import dataclass
from functools import cached_property
from pathlib import Path

BASELINE = "8ce636ab3b380bca1db500b18f8ce1dbe4506521"
REPO = Path(__file__).resolve().parents[2]


def rules():
    names = sorted(p.stem for p in Path(__file__).parent.glob("*.py") if p.stem != "support")
    if not names:
        raise RuntimeError("No rule modules found; restore scripts/agent_rules/*.py.")
    return names


@dataclass(frozen=True)
class Finding:
    file: str
    line: int
    message: str


@dataclass(frozen=True)
class Token:
    value: str
    line: int
    kind: str = "code"


def quoted(source, start):
    delimiter = '"""' if source.startswith('"""', start) else source[start]
    i = start + len(delimiter)
    expressions = []
    while i < len(source):
        if delimiter.startswith('"') and source.startswith("\\(", i):
            expression = i + 2
            i = expression
            depth = 1
            while i < len(source) and depth:
                if source[i] in "\"'`":
                    i, nested = quoted(source, i)
                elif source[i] == "(":
                    depth += 1
                    i += 1
                elif source[i] == ")":
                    depth -= 1
                    i += 1
                else:
                    i += 1
            expressions.append((expression, i - 1))
        elif source[i] == "\\":
            i += 2
        elif source.startswith(delimiter, i):
            return i + len(delimiter), expressions
        else:
            i += 1
    return i, expressions


def tokens(source):
    result = []
    i = 0
    line = 1
    while i < len(source):
        start = i
        if source.startswith("//", i):
            end = source.find("\n", i)
            i = len(source) if end < 0 else end
        elif source.startswith("/*", i):
            depth = 1
            i += 2
            while i < len(source) and depth:
                if source.startswith("/*", i):
                    depth += 1
                    i += 2
                elif source.startswith("*/", i):
                    depth -= 1
                    i += 2
                else:
                    i += 1
        elif source[i].isspace():
            i += 1
        elif source[i] in "\"'`" and not (source[i] == "'" and source[max(0, i - 1):i] == "\\"):
            i, expressions = quoted(source, i)
            result.append(Token(source[start:i], line, "string"))
            for begin, end in expressions:
                offset = line - 1 + source[start:begin].count("\n")
                result.extend(Token(t.value, t.line + offset, t.kind) for t in tokens(source[begin:end]))
        else:
            match = re.match(r"[A-Za-z_$][\w$]*|[0-9]+", source[i:])
            i += len(match[0]) if match else 1
            result.append(Token(source[start:i], line))
        line += source[start:i].count("\n")
    return result


def scoped(source):
    stream = tokens(source)
    stack = []
    pending = None
    for i, token in enumerate(stream):
        if token.value in {"class", "struct", "enum", "actor", "extension", "protocol", "func", "function", "var", "let"}:
            if i + 1 < len(stream) and re.fullmatch(r"[\w$]+", stream[i + 1].value):
                pending = (stream[i + 1].value, token.line, token.value)
        elif token.value in {"init", "subscript"}:
            pending = (token.value, token.line, token.value)
        if token.value == "{":
            stack.append(f"{pending[2]}:{pending[0]}" if pending else "")
            pending = None
        elif token.value == "}":
            if stack:
                stack.pop()
            pending = None
        elif pending and pending[2] in {"var", "let"} and token.line > pending[1] and token.value not in {"=", ":", ",", ".", "?"}:
            pending = None
        scope = tuple(part for part in stack if part)
        yield stream, i, scope


def bodies(source, kind, name):
    stream = tokens(source)
    for i in range(len(stream) - 1):
        if [stream[i].value, stream[i + 1].value] != [kind, name]:
            continue
        start = i + 2
        while start < len(stream) and stream[start].value != "{":
            if stream[start].value in {"func", "var", "class", "struct", "extension", "protocol", "}"}:
                break
            start += 1
        if start == len(stream) or stream[start].value != "{":
            continue
        depth = 1
        end = start + 1
        while end < len(stream) and depth:
            if stream[end].value == "{":
                depth += 1
            elif stream[end].value == "}":
                depth -= 1
            end += 1
        yield stream[start + 1:end - 1]


def contains(stream, sequence):
    values = [token.value for token in stream]
    return any(values[i:i + len(sequence)] == sequence for i in range(len(values)))


def git_source(ref, file):
    result = subprocess.run(["git", "show", f"{ref}:{file}"], cwd=REPO, capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(f"Cannot read {ref}:{file}; fetch repository history including {BASELINE} before checking.")
    return result.stdout


class Repository:
    def __init__(self, root):
        self.root = root.resolve()
        if not (self.root / "CreatorContentOS").is_dir() or not (self.root / "tests").is_dir():
            raise RuntimeError(f"{self.root} is not a ContentHelper source root.")

    @cached_property
    def sources(self):
        return {
            str(p.relative_to(self.root)): p.read_text()
            for directory, pattern in [("CreatorContentOS", "*.swift"), ("tests", "*.ts")]
            for p in sorted((self.root / directory).rglob(pattern))
        }

    @cached_property
    def baseline(self):
        result = subprocess.run(["git", "ls-tree", "-r", "--name-only", BASELINE, "CreatorContentOS", "tests"], cwd=REPO, capture_output=True, text=True)
        if result.returncode:
            raise RuntimeError(f"Missing rule baseline {BASELINE}; use a checkout with full Git history.")
        return {file: git_source(BASELINE, file) for file in result.stdout.splitlines() if file.endswith((".swift", ".ts"))}

    def added(self, occurrences, message):
        baseline = Counter(key for file, source in self.baseline.items() for key, line in occurrences(file, source))
        findings = []
        seen = Counter()
        for file, source in self.sources.items():
            for key, line in occurrences(file, source):
                seen[key] += 1
                if seen[key] > baseline[key]:
                    findings.append(Finding(file, line, message))
        return findings

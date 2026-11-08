#!/usr/bin/env python3
"""Structural Lua/Luau sanity checker for the pizza-tycoon project.

Strips strings and comments, then verifies that:
- block keywords balance (function/for/while/repeat/if-statement/do
  open, end/until close),
- brackets/parens/braces balance.

It deliberately does NOT attempt a full parse, so expression-level
errors (wrong property name, misplaced paren inside an expression)
can slip through: always re-read new code carefully as well.
"""
import re
import sys
import pathlib

TOKEN = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")

VALID_CLOSERS = {
    "end": ("function", "if", "for", "while", "do"),
    "until": ("repeat",),
}

# an `if` whose previous non-space character is one of these (or whose
# previous word is `return`) is the Luau if-expression, not a statement
EXPR_IF_PREV_CHARS = ("=", "(", ",", "{", "[")


def strip(src: str) -> str:
    # Strings and comments become placeholder tokens so that constructs
    # like `if` following a line that ends in a string literal are still
    # recognized as statements (the placeholder's last char is a letter).
    out = []
    i, n = 0, len(src)
    while i < n:
        if src[i:i + 4] == "--[[":
            j = src.find("]]", i + 4)
            out.append(" ")
            i = n if j == -1 else j + 2
            continue
        if src[i:i + 2] == "--":
            j = src.find("\n", i)
            out.append(" ")
            i = n if j == -1 else j
            continue
        c = src[i]
        if c in "\"'":
            j = i + 1
            while j < n:
                if src[j] == "\\":
                    j += 2
                    continue
                if src[j] == c:
                    break
                j += 1
            out.append("S")
            i = j + 1
            continue
        if src[i:i + 2] == "[[":
            j = src.find("]]", i + 2)
            out.append("S")
            i = n if j == -1 else j + 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


def line_of(src: str, pos: int) -> int:
    return src.count("\n", 0, pos) + 1


def check(path: pathlib.Path) -> list:
    src = strip(path.read_text(encoding="utf-8"))
    errors = []
    stack = []  # [kind, pos, needs_do]
    prev_word = ""
    for m in TOKEN.finditer(src):
        word = m.group(0)
        before = src[:m.start()].rstrip()
        prev_char = before[-1] if before else ""

        if word in ("end", "until"):
            if not stack:
                errors.append(f"{path}:{line_of(src, m.start())}: '{word}' with empty block stack")
            elif stack[-1][0] not in VALID_CLOSERS[word]:
                errors.append(f"{path}:{line_of(src, m.start())}: '{word}' closes '{stack[-1][0]}' opened at line {line_of(src, stack[-1][1])}")
                stack.pop()
            else:
                stack.pop()
        elif word == "if":
            if not (prev_char in EXPR_IF_PREV_CHARS or prev_word == "return"):
                stack.append(["if", m.start(), False])
        elif word in ("function", "repeat"):
            stack.append([word, m.start(), False])
        elif word in ("for", "while"):
            stack.append([word, m.start(), True])
        elif word == "do":
            if stack and stack[-1][0] in ("for", "while") and stack[-1][2]:
                stack[-1][2] = False
            else:
                stack.append(["do", m.start(), False])
        if word.isalpha():
            prev_word = word
        else:
            prev_word = prev_word  # tokens are always words here

    for kind, pos, _ in stack:
        errors.append(f"{path}:{line_of(src, pos)}: unclosed '{kind}'")

    for a, b in (("(", ")"), ("[", "]"), ("{", "}")):
        ca, cb = src.count(a), src.count(b)
        if ca != cb:
            errors.append(f"{path}: unbalanced {a}{b} ({ca} vs {cb})")
    return errors


def main():
    root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    files = sorted(p for p in root.rglob("*.luau") if "tools" not in p.parts)
    bad = 0
    for f in files:
        errors = check(f)
        if errors:
            bad += 1
            for e in errors:
                print(e)
    print(f"{len(files) - bad}/{len(files)} files OK")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()

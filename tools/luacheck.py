#!/usr/bin/env python3
"""Structural Luau block-balance checker (strings/comments stripped).

Usage: python3 tools/luacheck.py <project-root>
Checks every .luau under the root for balanced blocks
(function/for/while/repeat/if/do vs end/until) and balanced brackets.
"""
import re, sys, os

def strip(code: str) -> str:
    out = []
    i, n = 0, len(code)
    while i < n:
        c = code[i]
        if c == '-' and i + 1 < n and code[i+1] == '-':
            m = re.match(r'\[(=*)\[', code[i+2:])
            if m:
                closer = ']' + m.group(1) + ']'
                k = code.find(closer, i + 2 + m.end())
                i = (k + len(closer)) if k != -1 else n
            else:
                k = code.find('\n', i)
                i = k if k != -1 else n
        elif c in ('"', "'"):
            out.append(' @ ')
            q = c; i += 1
            while i < n:
                if code[i] == '\\': i += 2; continue
                if code[i] == q: i += 1; break
                if code[i] == '\n': out.append('\n'); i += 1; continue
                i += 1
        elif c == '[':
            m = re.match(r'\[(=*)\[', code[i:])
            if m:
                closer = ']' + m.group(1) + ']'
                k = code.find(closer, i + m.end())
                body = code[i:(k + len(closer)) if k != -1 else n]
                out.append(' @ ' + ('\n' * body.count('\n')))
                i = (k + len(closer)) if k != -1 else n
            else:
                out.append(c); i += 1
        else:
            out.append(c); i += 1
    return ''.join(out)

KEYWORDS = {'function','if','for','while','repeat','do','end','until','then','else','elseif','return','local'}
EXPR_PREFIX = {'=', '(', ',', '{', '[', 'return'}

def check(path: str):
    code = strip(open(path, encoding='utf-8').read())
    depth = 0; expect_do = False; prev_word = ''
    line = 1; stack_line = []; errors = []
    i = 0; n = len(code)
    while i < n:
        c = code[i]
        if c == '\n': line += 1; i += 1; continue
        if c.isspace(): i += 1; continue
        m = re.match(r'[A-Za-z_][A-Za-z0-9_]*', code[i:])
        if m:
            word = m.group(0); i += len(word)
            if word in KEYWORDS:
                if word in ('function','for','while','repeat'):
                    depth += 1; stack_line.append(line)
                    if word in ('for','while'): expect_do = True
                elif word == 'do':
                    if expect_do: expect_do = False
                    else: depth += 1; stack_line.append(line)
                elif word == 'if':
                    if prev_word not in EXPR_PREFIX:
                        depth += 1; stack_line.append(line)
                elif word in ('end','until'):
                    depth -= 1
                    if stack_line: stack_line.pop()
                    if depth < 0:
                        errors.append(f"line {line}: '{word}' closes too much")
                prev_word = word
            else:
                prev_word = word
            continue
        prev_word = c
        i += 1
    if depth != 0:
        where = stack_line[-1] if stack_line else '?'
        errors.append(f"unbalanced: depth {depth} at EOF (last open block near line {where})")
    depthb = {'(':0,'[':0,'{':0}
    closer = {')':'(', ']':'[', '}':'{'}
    for ch in code:
        if ch in depthb: depthb[ch] += 1
        elif ch in closer: depthb[closer[ch]] -= 1
    for k, v in depthb.items():
        if v != 0: errors.append(f"unbalanced '{k}': {v}")
    return errors

def main():
    root = sys.argv[1] if len(sys.argv) > 1 else '.'
    failures = 0
    for dirpath, _, files in os.walk(root):
        for fn in sorted(files):
            if fn.endswith('.luau'):
                p = os.path.join(dirpath, fn)
                errs = check(p)
                rel = os.path.relpath(p, root)
                if errs:
                    failures += 1
                    print(f"FAIL {rel}")
                    for e in errs: print(f"   {e}")
                else:
                    print(f"ok   {rel}")
    sys.exit(1 if failures else 0)

if __name__ == '__main__':
    main()

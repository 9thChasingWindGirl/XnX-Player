"""Rough bracket balance check for Dart sources.

No Dart SDK is available in this environment, so CI is the only real analyzer.
This catches the one thing that would waste a full CI round trip: a file that
does not even parse because a brace or paren is missing.
"""

import sys


def scan(src: str) -> list[tuple[str, int]]:
    """Yields (char, line) for brackets outside strings and comments."""
    out: list[tuple[str, int]] = []
    i = 0
    n = len(src)
    line = 1
    while i < n:
        c = src[i]
        if c == '\n':
            line += 1
            i += 1
            continue
        # line comment
        if src.startswith('//', i):
            j = src.find('\n', i)
            i = n if j < 0 else j
            continue
        # block comment (nesting allowed in Dart)
        if src.startswith('/*', i):
            depth = 1
            i += 2
            while i < n and depth:
                if src.startswith('/*', i):
                    depth += 1
                    i += 2
                elif src.startswith('*/', i):
                    depth -= 1
                    i += 2
                else:
                    if src[i] == '\n':
                        line += 1
                    i += 1
            continue
        # raw strings
        raw = False
        start = i
        if c in 'rR' and i + 1 < n and src[i + 1] in '\'"':
            raw = True
            i += 1
            c = src[i]
        if c in '\'"':
            quote = c
            triple = src.startswith(quote * 3, i)
            if triple:
                i += 3
                end = quote * 3
            else:
                i += 1
                end = quote
            while i < n:
                if not raw and src[i] == '\\':
                    if src[i] == '\n':
                        line += 1
                    i += 2
                    continue
                if src.startswith(end, i):
                    i += len(end)
                    break
                if src[i] == '\n':
                    line += 1
                    if not triple:
                        # Unterminated single-line string.
                        return out
                i += 1
            del start, raw
            continue
        if c in '(){}[]':
            out.append((c, line))
        i += 1
    return out


PAIRS = {')': '(', '}': '{', ']': '['}


def check(path: str) -> int:
    with open(path, encoding='utf-8') as handle:
        src = handle.read()
    stack: list[tuple[str, int]] = []
    for char, line in scan(src):
        if char in '({[':
            stack.append((char, line))
        else:
            if not stack:
                print(f'{path}:{line}: unexpected {char}')
                return 1
            open_char, open_line = stack.pop()
            if open_char != PAIRS[char]:
                print(f'{path}:{line}: {char} closes {open_char} opened at {open_line}')
                return 1
    if stack:
        open_char, open_line = stack[-1]
        print(f'{path}:{open_line}: {open_char} never closed')
        return 1
    return 0


if __name__ == '__main__':
    failed = 0
    for name in sys.argv[1:]:
        failed |= check(name)
    print('balance ok' if failed == 0 else 'balance FAILED')
    sys.exit(failed)

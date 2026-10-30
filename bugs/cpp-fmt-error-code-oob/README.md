# {fmt}: `formatter<std::error_code>` reads one byte past the format string

| | |
|---|---|
| upstream fix | [fmtlib/fmt#4934](https://github.com/fmtlib/fmt/pull/4934), commit [`8a7aea0`](https://github.com/fmtlib/fmt/commit/8a7aea04222d6680aae2c69fe8d514ffc2f9808d) (no separate issue; the PR describes the bug) |
| reproduced on | parent commit [`7071103`](https://github.com/fmtlib/fmt/commit/7071103ceadf5791d3edc47149969b42e8abc883) (master after 12.2.0), GCC 15.3.0, `-O0 -fsanitize=address,undefined` |
| class | missing bounds check (off-by-one read at `end`) |
| license of the patch | MIT ({fmt}) |

## Symptom

Formatting a `std::error_code` with a format string that ends right after an
alignment character, for example `"{:>"` or `"{:*^"`, dereferences the end
pointer of the string. Format strings are often not NUL-terminated
(`fmt::runtime`, `string_view` into a larger buffer), so this reads whatever
follows. Under AddressSanitizer:

```
ERROR: AddressSanitizer: heap-buffer-overflow ...
READ of size 1 ... in fmt::v12::formatter<std::error_code, char, void>::parse(...) include/fmt/std.h:553
... is located 0 bytes after 3-byte region
```

Full output: [`results/cpp-fmt-error-code-oob/`](../../results/cpp-fmt-error-code-oob/).

## Root cause

`formatter<std::error_code>::parse` before the fix:

```cpp
it = detail::parse_align(it, end, specs_);   // may consume the rest
char c = *it;                                 // reads *end if it == end
if (it != end && ((c >= '1' && c <= '9') || c == '{'))
  it = detail::parse_width(it, end, specs_, width_ref_, ctx);
```

The bounds check is there, but after the read: `*it` is evaluated first and
`it != end` only decides whether the value is used. For `"{:>"`,
`parse_align` consumes `>` and returns `end`, so `*it` reads one byte past
the buffer. The other parsers in the same function check `it != end` before
`*it`; this line had the order backwards.

The bug is easy to miss in two ways, both seen here:

- Without ASan the stray byte is usually harmless, and the following code
  still throws the correct `format_error`.
- With ASan at `-O1`, the same test passed without a report in our runs,
  because the byte read is only used when `it != end` and the compiler may
  drop or move the load. The reproduction compiles at `-O0` so the load
  stays where the source puts it.

## Fix

Return as soon as `parse_align` reaches the end, and drop the now redundant
check before the width parse:

```cpp
it = detail::parse_align(it, end, specs_);
if (it == end) return it;
char c = *it;
if ((c >= '1' && c <= '9') || c == '{') ...
```

See [`fix.patch`](fix.patch).

## Regression test

[`error_code_test.cc`](error_code_test.cc): every format string is copied into
a heap buffer of exactly its length, with no terminating NUL, so a read at
`end` lands in ASan's redzone. Three valid specs must format as expected
(`"{:>12}"` → `"  generic:42"`) and two truncated ones (`"{:>"`, `"{:*^"`)
must throw `fmt::format_error`. Before the fix ASan aborts on the first
truncated spec; after, all five checks pass.

## In one minute

A parser checked `it != end` after dereferencing `it` instead of before. The
read is one byte past the end, so it rarely crashes and the result looked
correct. Finding it needs a buffer with no slack after the string and a
sanitizer, and here also `-O0`, because the optimizer could drop the
offending load.

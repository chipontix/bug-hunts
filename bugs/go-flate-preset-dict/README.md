# Go `compress/flate`: a preset dictionary leaks into the output

| | |
|---|---|
| upstream issue | [golang/go#80538](https://github.com/golang/go/issues/80538), backport [golang/go#81233](https://github.com/golang/go/issues/81233) |
| upstream fix | [`d16d95c`](https://github.com/golang/go/commit/d16d95ce1d92efbe2102d3754d4d64c2c7e4d4c1) on release-branch.go1.27 ([CL 829764](https://go-review.googlesource.com/c/go/+/829764)), cherry-pick of [`655a713`](https://github.com/golang/go/commit/655a713cda939618d56b179ed44d1257858b775c) |
| reproduced on | `golang:1.27.1-bookworm` (pinned by digest); first fixed release: go1.27.2 |
| class | wrong boundary in a shared buffer: silent data corruption |
| license of the patch | BSD-3-Clause (Go) |

## Symptom

`flate.NewWriterDict(w, level, dict)` followed by `flate.NewReaderDict(r, dict)`
returns `dict + data` instead of `data`, with no error. Through `zlib`, which
carries an Adler-32 of the payload, the same stream fails with
`zlib: invalid checksum`. It only happens when the input does not compress
(random bytes, already-compressed data), and on 1.27.1 only at levels 7–9.

```
=== RUN   TestFlateRoundTripWithPresetDict/size=763/level=7
    flate_dict_test.go:46: got 798 bytes, want 763; dictionary leaked into output: true
=== RUN   TestZlibRoundTripWithPresetDict
    flate_dict_test.go:71: decompress: zlib: invalid checksum (dictionary leaked into output)
```

Full output: [`results/go-flate-preset-dict/`](../../results/go-flate-preset-dict/).

## Root cause

The level 7–9 compressor keeps one byte array, `d.window`, that holds both the
look-back history and the bytes of the block it is about to emit. A preset
dictionary is loaded by `fillWindow`, which copies it into `window[0:len(dict)]`
and hashes it so that later input can reference it. The dictionary is history,
never output.

When a block is flushed, the encoder chooses the cheapest of three encodings.
Two of them (dynamic and fixed Huffman over LZ77 tokens) are built from the
tokens, and the tokens only describe the new input, so they are correct. The
third, a *stored* block, is the raw bytes `window[blockStart:index]`. The
encoder picks it when tokens would be larger than the raw data, which is
exactly the case for incompressible input.

`blockStart` marks where the current block's bytes begin. `fillWindow` moved
`windowEnd` past the dictionary but left `blockStart` at 0, so the first
stored block started at the beginning of the dictionary. The decoder has no
way to know: a stored block is just "copy these bytes", so it outputs them.

Levels 1–6 on 1.27 use a different encoder (`deflateFast`) whose dictionary
path does not put the dictionary into the window, so they are not affected on
this version; the original report was on 1.26, where levels 2–9 were.

## Fix

One line in `fillWindow`: after loading the dictionary, set
`d.blockStart = d.windowEnd`, so the first block starts after the dictionary.
See [`fix.patch`](fix.patch).

## Regression test

[`flate_dict_test.go`](flate_dict_test.go): round trips 100, 763 and 4096
bytes of seeded pseudo-random data through every compression level with a
dictionary, plus one zlib round trip at `BestCompression` to show the checksum
error. Before the fix: 6 of 36 subtests and the zlib test fail. After: all pass.

## How the reproduction works

The Go toolchain builds the standard library from `$GOROOT/src` on demand, so
the "after" run patches `/usr/local/go/src/compress/flate/deflate.go` inside
the 1.27.1 container and `go test` recompiles it. Both runs use the same
toolchain; only the one line differs.

## In one minute

A compressor reuses one buffer for history and pending output. Loading a
preset dictionary advanced the end of the buffer but not the start of the
pending block, so whenever the encoder decided raw bytes were cheaper than
compressed ones, it emitted the dictionary too. It only shows on
incompressible input, which is why ordinary tests with text never caught it.

# nlohmann/json: `update()` and `merge_patch()` with an argument inside `*this`

| | |
|---|---|
| upstream issue | [nlohmann/json#5641](https://github.com/nlohmann/json/issues/5641) |
| upstream fix | [nlohmann/json#5678](https://github.com/nlohmann/json/pull/5678), commit [`a32f61e`](https://github.com/nlohmann/json/commit/a32f61eb98a27cbf2b9186780d46da2f996054eb) |
| reproduced on | parent commit [`1d675cd`](https://github.com/nlohmann/json/commit/1d675cdb46973038f0087c24c0f399722e823281) (develop after v3.12.0; the issue reports the same behaviour on v3.12.0), GCC 15.3.0, `-O0 -fsanitize=address,undefined` |
| class | aliasing: iterator invalidation / use after free |
| license of the patch | MIT (nlohmann/json) |

## Symptom

Natural one-liners such as "hoist the members of `j["a"]` into `j`" or
"apply `j["a"]` as a merge patch to `j`" either throw a confusing exception
or read freed memory:

```
FAIL update(j["a"]): threw [json.exception.invalid_iterator.214] cannot get value
ERROR: AddressSanitizer: heap-use-after-free ... in iter_impl<...>::operator++()
```

Full output: [`results/cpp-json-update-self-alias/`](../../results/cpp-json-update-self-alias/).

## Root cause

Both functions iterate their argument and write into `*this` in the same loop:

```cpp
// update(j): for each member of j
m_data.m_value.object->operator[](it.key()) = it.value();

// merge_patch(patch): for each member of patch
if (it.value().is_null()) erase(it.key());
else operator[](it.key()).merge_patch(it.value());
```

That is only safe if the argument and `*this` do not share storage. When the
argument is `*this` or a value nested inside it, the writes destroy or move
the thing being iterated:

| call | what the write does to the argument |
|---|---|
| `j.update(j["a"])` with `j = {"a": {"a": 1, "b": 2}}` | `j["a"] = 1` replaces the object being iterated with a number; the next `++it` works on an iterator into a destroyed object (here it threw `invalid_iterator.214`; it is undefined behaviour) |
| `j.merge_patch(j["a"])` with `j = {"a": {"a": null, "b": 2}}` | the null member means "erase key `a`", which frees the patch object mid-loop: heap-use-after-free |
| `j.merge_patch(j)` with `j = {"a": null, "b": 1}` | erasing `a` frees the map node the loop's iterator points to |
| `ordered_json` `j.update(j["a"])` | `ordered_json` stores members in a `std::vector`; inserting a new key into `j` can reallocate it, which moves `j["a"]` while iterators into it are live |

It is the same class of bug as `v.push_back(v[0])` on a `std::vector`: the
callee takes a reference to something it is about to modify.

## Fix

Copy the argument first, then iterate the copy and move values out of it:
`basic_json source = j; update_from(source, ...)` and
`basic_json patch = apply_patch; apply_merge_patch(patch, 0)`. The loops now
take mutable iterators so they can `std::move` each value instead of copying
it twice, so the extra cost is one copy of the argument. Type checks happen
before the copy, so error messages still name the caller's value. See
[`fix.patch`](fix.patch) (the `include/` hunks of the PR; the amalgamated
`single_include/` copy, docs and tests are left out).

## Regression test

[`self_alias_test.cc`](self_alias_test.cc): the four calls above, each
compared with the result expected when the argument is copied first (the
expected values match the upstream tests). Output is unbuffered so the
checks that ran before an ASan abort are still in the log. Before the fix the
first check fails and the second aborts with heap-use-after-free; after, all
four pass under ASan and UBSan.

## In one minute

`update()` and `merge_patch()` read from their argument while writing into
`*this`. Pass a piece of `*this` and the writes free or move what the loop is
reading. Library functions that take a `const&` should either document that
it must not alias or survive it; the usual fix, used here, is to copy the
input first, then move from the copy so it costs little extra.

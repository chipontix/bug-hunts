// update() and merge_patch() read their argument while they write *this.
// When the argument is *this or lives inside it, the writes free or move the
// value being iterated. Each case below must produce the same result as if
// the argument had been copied first.
#include <nlohmann/json.hpp>

#include <cstdio>
#include <exception>
#include <functional>
#include <string>

using nlohmann::json;
using nlohmann::ordered_json;

static int failures = 0;

template <typename J>
static void check(const char* name, J j, const std::function<void(J&)>& op,
                  const J& want) {
  try {
    op(j);
  } catch (const std::exception& e) {
    std::printf("FAIL %s: threw %s\n", name, e.what());
    ++failures;
    return;
  }
  if (j != want) {
    std::printf("FAIL %s: got %s, want %s\n", name, j.dump().c_str(),
                want.dump().c_str());
    ++failures;
    return;
  }
  std::printf("ok   %s: %s\n", name, j.dump().c_str());
}

int main() {
  std::setvbuf(stdout, nullptr, _IONBF, 0);  // keep output if ASan aborts
  // Hoisting a nested object's members into its parent.
  // Assigning j["a"] = 1 destroys the object j["a"] that is being iterated.
  check<json>("update(j[\"a\"])",
              json::parse(R"({"a": {"a": 1, "b": 2}})"),
              [](json& j) { j.update(j["a"]); },
              json::parse(R"({"a": 1, "b": 2})"));

  // RFC 7396: a null member deletes the key. Erasing "a" from j frees the
  // patch object j["a"] in the middle of the loop over it.
  check<json>("merge_patch(j[\"a\"])",
              json::parse(R"({"a": {"a": null, "b": 2}})"),
              [](json& j) { j.merge_patch(j["a"]); },
              json::parse(R"({"b": 2})"));

  // Patching a value with itself: erasing "a" destroys the map node the
  // loop's iterator points to.
  check<json>("merge_patch(j)",
              json::parse(R"({"a": null, "b": 1})"),
              [](json& j) { j.merge_patch(j); },
              json::parse(R"({"b": 1})"));

  // ordered_json keeps members in a vector: inserting "x" into j may
  // reallocate it and move j["a"] while its iterators are live.
  check<ordered_json>("ordered_json update(j[\"a\"])",
                      ordered_json::parse(R"({"a": {"x": 1, "y": 2, "z": 3}})"),
                      [](ordered_json& j) { j.update(j["a"]); },
                      ordered_json::parse(R"({"a": {"x": 1, "y": 2, "z": 3}, "x": 1, "y": 2, "z": 3})"));

  std::printf("%d failure(s)\n", failures);
  return failures ? 1 : 0;
}

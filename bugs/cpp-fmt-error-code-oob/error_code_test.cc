// formatter<std::error_code>::parse must not read past the end of the format
// string. Each spec is copied into a heap buffer of exactly its length (no
// terminating NUL), so a read of one byte past the end lands in ASan's
// redzone instead of on some harmless byte that happens to follow.
#include <fmt/format.h>
#include <fmt/std.h>

#include <cstdio>
#include <cstring>
#include <memory>
#include <string>
#include <system_error>

static int failures = 0;

// Formats ec with a format string that is exactly `spec`, nothing after it.
static std::string format_exact(const char* spec, const std::error_code& ec,
                                bool* threw) {
  size_t n = std::strlen(spec);
  std::unique_ptr<char[]> buf(new char[n]);
  std::memcpy(buf.get(), spec, n);
  *threw = false;
  try {
    return fmt::vformat(fmt::string_view(buf.get(), n),
                        fmt::make_format_args(ec));
  } catch (const fmt::format_error&) {
    *threw = true;
    return {};
  }
}

static void expect_error(const char* spec, const std::error_code& ec) {
  bool threw;
  std::string out = format_exact(spec, ec, &threw);
  if (!threw) {
    std::printf("FAIL %s: expected format_error, got \"%s\"\n", spec, out.c_str());
    ++failures;
  } else {
    std::printf("ok   %s: format_error\n", spec);
  }
}

static void expect_output(const char* spec, const std::error_code& ec,
                          const char* want) {
  bool threw;
  std::string out = format_exact(spec, ec, &threw);
  if (threw || out != want) {
    std::printf("FAIL %s: want \"%s\", got \"%s\"%s\n", spec, want, out.c_str(),
                threw ? " (threw)" : "");
    ++failures;
  } else {
    std::printf("ok   %s: \"%s\"\n", spec, out.c_str());
  }
}

int main() {
  std::setvbuf(stdout, nullptr, _IONBF, 0);  // keep output if ASan aborts
  auto ec = std::error_code(42, std::generic_category());

  // Valid specs keep working, before and after the fix.
  expect_output("{}", ec, "generic:42");
  expect_output("{:>12}", ec, "  generic:42");
  expect_output("{:*<12}", ec, "generic:42**");

  // Truncated after the alignment: the parser stops at end and must report an
  // unterminated replacement field instead of looking at the next byte.
  expect_error("{:>", ec);
  expect_error("{:*^", ec);

  std::printf("%d failure(s)\n", failures);
  return failures ? 1 : 0;
}

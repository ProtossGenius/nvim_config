#include "demo/app.h"

#include "demo/worker.h"

#include <algorithm>
#include <chrono>
#include <iostream>
#include <string>
#include <utility>

namespace demo {

int App::run(const std::string& tag, int wait_ms) const {
  const int loops = wait_ms > 0 ? std::max(wait_ms / 200, 1) : 1;
  const int result = accumulate_steps(loops, 200);
  std::cout << "[cpp_dap_demo] tag=" << tag << " result=" << result << std::endl;
  return result >= 0 ? 0 : 1;
}

std::pair<std::string, int> App::parse_args(int argc, char** argv) {
  std::string tag = "launch";
  int wait_ms = 1200;

  for (int i = 1; i < argc; ++i) {
    const std::string arg = argv[i];
    if (arg == "--tag" && i + 1 < argc) {
      tag = argv[++i];
      continue;
    }
    if (arg == "--attach-wait-ms" && i + 1 < argc) {
      wait_ms = std::stoi(argv[++i]);
      continue;
    }
  }

  return {tag, wait_ms};
}

}  // namespace demo

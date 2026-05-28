#pragma once

#include <string>
#include <utility>

namespace demo {

class App {
 public:
  int run(const std::string& tag, int wait_ms) const;
  static std::pair<std::string, int> parse_args(int argc, char** argv);
};

}  // namespace demo

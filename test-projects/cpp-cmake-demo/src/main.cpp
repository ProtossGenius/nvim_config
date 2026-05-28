#include "demo/app.h"

#include <iostream>
#include <string>
#include <unistd.h>
#include <utility>

int main(int argc, char** argv) {
  const auto [tag, wait_ms] = demo::App::parse_args(argc, argv);
  std::cout << "[cpp_dap_demo] pid=" << getpid() << " tag=" << tag << " wait_ms=" << wait_ms << std::endl;
  const demo::App app;
  return app.run(tag, wait_ms);
}

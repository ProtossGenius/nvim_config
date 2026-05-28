#include "demo/worker.h"

#include <chrono>
#include <thread>

namespace demo {

int accumulate_steps(int loops, int delay_ms) {
  int total = 0;
  for (int i = 0; i < loops; ++i) {
    total += i;
    std::this_thread::sleep_for(std::chrono::milliseconds(delay_ms));
  }
  return total;
}

}  // namespace demo

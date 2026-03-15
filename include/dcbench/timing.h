#pragma once

#include <chrono>
#include <cstdint>
#include <thread>

namespace dcbench {

inline uint64_t now_ns() {
    auto tp = std::chrono::steady_clock::now();
    return std::chrono::duration_cast<std::chrono::nanoseconds>(
        tp.time_since_epoch()).count();
}

inline double ns_to_us(uint64_t ns) {
    return static_cast<double>(ns) / 1000.0;
}

inline double ns_to_ms(uint64_t ns) {
    return static_cast<double>(ns) / 1'000'000.0;
}

inline void precise_sleep_until(std::chrono::steady_clock::time_point target) {
    auto remaining = target - std::chrono::steady_clock::now();
    if (remaining > std::chrono::microseconds(100)) {
        std::this_thread::sleep_for(remaining - std::chrono::microseconds(50));
    }
    while (std::chrono::steady_clock::now() < target) {}
}

class Stopwatch {
public:
    Stopwatch() : start_(now_ns()) {}
    void reset() { start_ = now_ns(); }
    uint64_t elapsed_ns() const { return now_ns() - start_; }
    double elapsed_us() const { return ns_to_us(elapsed_ns()); }
    double elapsed_ms() const { return ns_to_ms(elapsed_ns()); }

private:
    uint64_t start_;
};

}

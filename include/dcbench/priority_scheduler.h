#pragma once

#include <cstdint>
#include <string>
#include <atomic>
#include <random>

namespace dcbench {

enum class SchedulingPolicy { ROUND_ROBIN, SIZE_AWARE, RANDOM };

SchedulingPolicy parse_scheduling_policy(const std::string& name);

class PriorityScheduler {
public:
    PriorityScheduler(SchedulingPolicy policy, uint32_t pool_size);

    uint32_t select(uint32_t message_size);

private:
    SchedulingPolicy policy_;
    uint32_t pool_size_;
    std::atomic<uint32_t> rr_counter_{0};

    uint32_t round_robin();
    uint32_t size_aware(uint32_t message_size);
    uint32_t random_select();
};

}

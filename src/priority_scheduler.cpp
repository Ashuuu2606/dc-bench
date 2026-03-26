#include "dcbench/priority_scheduler.h"

#include <stdexcept>
#include <algorithm>
#include <random>

namespace dcbench {

SchedulingPolicy parse_scheduling_policy(const std::string& name) {
    if (name == "round_robin") return SchedulingPolicy::ROUND_ROBIN;
    if (name == "size_aware") return SchedulingPolicy::SIZE_AWARE;
    if (name == "random") return SchedulingPolicy::RANDOM;
    throw std::runtime_error("Unknown scheduling policy: " + name);
}

PriorityScheduler::PriorityScheduler(SchedulingPolicy policy, uint32_t pool_size)
    : policy_(policy), pool_size_(pool_size) {}

uint32_t PriorityScheduler::select(uint32_t message_size) {
    switch (policy_) {
    case SchedulingPolicy::ROUND_ROBIN: return round_robin();
    case SchedulingPolicy::SIZE_AWARE:  return size_aware(message_size);
    case SchedulingPolicy::RANDOM:      return random_select();
    }
    return round_robin();
}

uint32_t PriorityScheduler::round_robin() {
    return rr_counter_.fetch_add(1, std::memory_order_relaxed) % pool_size_;
}

uint32_t PriorityScheduler::size_aware(uint32_t message_size) {
    uint32_t large_pool = std::max(1u, pool_size_ / 4);
    uint32_t small_pool = pool_size_ - large_pool;

    if (message_size > 65536) {
        return small_pool + (rr_counter_.fetch_add(1, std::memory_order_relaxed) % large_pool);
    }
    return rr_counter_.fetch_add(1, std::memory_order_relaxed) % small_pool;
}

uint32_t PriorityScheduler::random_select() {
    thread_local std::mt19937 local_rng(std::random_device{}());
    std::uniform_int_distribution<uint32_t> dist(0, pool_size_ - 1);
    return dist(local_rng);
}

}

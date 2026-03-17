#pragma once

#include <string>
#include <vector>
#include <thread>
#include <queue>
#include <mutex>
#include <condition_variable>
#include <atomic>

#include "dcbench/statistics.h"
#include "dcbench/workload.h"
#include "dcbench/connection_pool.h"
#include "dcbench/priority_scheduler.h"

namespace dcbench {

struct PendingRequest {
    uint64_t id;
    uint32_t size;
    uint8_t priority;
    bool warmup;
};

template <typename T>
class BoundedQueue {
public:
    void push(T item) {
        std::lock_guard<std::mutex> lk(mu_);
        q_.push(std::move(item));
        cv_.notify_one();
    }

    bool pop(T& item, int timeout_ms) {
        std::unique_lock<std::mutex> lk(mu_);
        if (!cv_.wait_for(lk, std::chrono::milliseconds(timeout_ms),
                          [this] { return !q_.empty(); })) {
            return false;
        }
        item = std::move(q_.front());
        q_.pop();
        return true;
    }

    size_t size() const {
        std::lock_guard<std::mutex> lk(mu_);
        return q_.size();
    }

private:
    mutable std::mutex mu_;
    std::condition_variable cv_;
    std::queue<T> q_;
};

struct BenchmarkResult {
    LatencyHistogram latency;
    uint64_t total_requests = 0;
    uint64_t total_bytes = 0;
    double duration_seconds = 0;
    double throughput_rps = 0;
    double goodput_mbps = 0;
};

class TcpClient {
public:
    TcpClient(const PoolConfig& pool_cfg, SchedulingPolicy sched_policy);

    BenchmarkResult run_closed_loop(const WorkloadConfig& cfg);
    BenchmarkResult run_open_loop(const WorkloadConfig& cfg);

private:
    ConnectionPool pool_;
    PriorityScheduler scheduler_;
    std::atomic<uint64_t> total_bytes_{0};

    void closed_loop_worker(int conn_idx, const WorkloadConfig& cfg,
                            uint32_t num_requests,
                            std::vector<uint64_t>& samples);

    void open_loop_worker(int conn_idx,
                          BoundedQueue<PendingRequest>& queue,
                          std::vector<uint64_t>& samples,
                          std::atomic<bool>& running);

    uint64_t do_request(int fd, uint64_t id, uint32_t size, uint8_t priority);

    static bool recv_exact(int fd, void* buf, size_t len);
    static bool send_exact(int fd, const void* buf, size_t len);
};

}

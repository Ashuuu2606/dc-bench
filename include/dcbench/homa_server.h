#pragma once

#include <cstdint>
#include <vector>
#include <thread>
#include <atomic>
#include "dcbench/homa_api.h"
#include "dcbench/statistics.h"

namespace dcbench {

class HomaServer {
public:
    HomaServer(uint16_t port, uint32_t num_threads);
    ~HomaServer();

    void start();
    void stop();
    bool running() const;

    const LatencyHistogram& processing_latency() const;
    uint64_t total_requests() const;
    uint64_t total_bytes() const;

private:
    uint16_t port_;
    uint32_t num_threads_;
    HomaSocket socket_;
    std::atomic<bool> running_{false};
    std::vector<std::thread> workers_;
    LatencyHistogram processing_latency_;
    std::atomic<uint64_t> request_count_{0};
    std::atomic<uint64_t> byte_count_{0};

    void worker_loop();
};

}

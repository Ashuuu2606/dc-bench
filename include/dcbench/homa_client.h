#pragma once

#include <string>
#include <vector>
#include <thread>
#include <atomic>
#include <mutex>
#include <unordered_map>

#include "dcbench/homa_api.h"
#include "dcbench/statistics.h"
#include "dcbench/workload.h"
#include "dcbench/tcp_client.h"

namespace dcbench {

class HomaClient {
public:
    HomaClient(const std::string& server_host, uint16_t server_port);

    BenchmarkResult run_closed_loop(const WorkloadConfig& cfg);
    BenchmarkResult run_open_loop(const WorkloadConfig& cfg);

private:
    std::string server_host_;
    uint16_t server_port_;
    std::atomic<uint64_t> total_bytes_{0};

    void closed_loop_worker(const WorkloadConfig& cfg,
                            uint32_t num_requests,
                            uint64_t seed,
                            std::vector<uint64_t>& samples);

    void open_loop_receiver(HomaSocket& sock,
                            std::unordered_map<uint64_t, uint64_t>& pending,
                            std::mutex& pending_mu,
                            std::vector<uint64_t>& samples,
                            std::atomic<bool>& running,
                            uint32_t warmup_count);
};

}

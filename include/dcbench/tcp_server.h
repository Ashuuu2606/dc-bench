#pragma once

#include <cstdint>
#include <vector>
#include <thread>
#include <atomic>
#include <mutex>
#include "dcbench/statistics.h"

namespace dcbench {

class TcpServer {
public:
    TcpServer(uint16_t port, bool dctcp = false);
    ~TcpServer();

    void start();
    void stop();
    bool running() const;

    const LatencyHistogram& processing_latency() const;
    uint64_t total_requests() const;
    uint64_t total_bytes() const;

private:
    uint16_t port_;
    bool dctcp_;
    int listen_fd_ = -1;
    std::atomic<bool> running_{false};
    std::thread accept_thread_;
    std::mutex threads_mu_;
    std::vector<std::thread> conn_threads_;
    std::vector<int> client_fds_;
    std::mutex fds_mu_;
    LatencyHistogram processing_latency_;
    std::atomic<uint64_t> request_count_{0};
    std::atomic<uint64_t> byte_count_{0};

    void setup_listener();
    void accept_loop();
    void connection_handler(int fd);

    static bool recv_exact(int fd, void* buf, size_t len);
    static bool send_exact(int fd, const void* buf, size_t len);
};

}

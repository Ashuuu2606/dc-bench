#include "dcbench/tcp_client.h"
#include "dcbench/message.h"
#include "dcbench/timing.h"

#include <sys/socket.h>
#include <cstring>
#include <iostream>
#include <chrono>

namespace dcbench {

TcpClient::TcpClient(const PoolConfig& pool_cfg, SchedulingPolicy sched_policy)
    : pool_(pool_cfg), scheduler_(sched_policy, pool_cfg.pool_size) {}

BenchmarkResult TcpClient::run_closed_loop(const WorkloadConfig& cfg) {
    pool_.connect_all();

    uint32_t pool_sz = pool_.size();
    uint32_t total = cfg.num_requests;
    uint32_t per_thread = total / pool_sz;
    uint32_t remainder = total % pool_sz;

    std::vector<std::vector<uint64_t>> thread_samples(pool_sz);
    std::vector<std::thread> workers;
    total_bytes_ = 0;

    Stopwatch timer;

    for (uint32_t i = 0; i < pool_sz; ++i) {
        uint32_t count = per_thread + (i < remainder ? 1 : 0);
        workers.emplace_back(&TcpClient::closed_loop_worker, this,
                             static_cast<int>(i), std::ref(cfg), count,
                             std::ref(thread_samples[i]));
    }

    for (auto& w : workers) w.join();

    double elapsed = timer.elapsed_ms() / 1000.0;

    BenchmarkResult result;
    for (auto& samples : thread_samples) {
        result.latency.add_samples(samples);
    }

    result.total_requests = result.latency.count();
    result.total_bytes = total_bytes_.load(std::memory_order_relaxed);
    result.duration_seconds = elapsed;
    result.throughput_rps = static_cast<double>(result.total_requests) / elapsed;
    result.goodput_mbps = (static_cast<double>(result.total_bytes) * 8.0) /
                          (elapsed * 1'000'000.0);

    pool_.close_all();
    return result;
}

BenchmarkResult TcpClient::run_open_loop(const WorkloadConfig& cfg) {
    pool_.connect_all();

    uint32_t pool_sz = pool_.size();
    std::vector<BoundedQueue<PendingRequest>> queues(pool_sz);
    std::vector<std::vector<uint64_t>> thread_samples(pool_sz);
    std::vector<std::thread> workers;
    std::atomic<bool> running{true};
    total_bytes_ = 0;

    for (uint32_t i = 0; i < pool_sz; ++i) {
        workers.emplace_back(&TcpClient::open_loop_worker, this,
                             static_cast<int>(i),
                             std::ref(queues[i]),
                             std::ref(thread_samples[i]),
                             std::ref(running));
    }

    Stopwatch timer;

    WorkloadGenerator gen(cfg, 42);
    uint32_t total = cfg.warmup_requests + cfg.num_requests;
    auto next_time = std::chrono::steady_clock::now();

    for (uint32_t i = 0; i < total; ++i) {
        double wait_us = gen.next_interarrival_us();
        next_time += std::chrono::microseconds(static_cast<int64_t>(wait_us));
        precise_sleep_until(next_time);

        uint32_t size = gen.next_size();
        uint8_t priority = gen.priority_for_size(size);
        uint32_t conn_idx = scheduler_.select(size);

        PendingRequest req;
        req.id = i;
        req.size = size;
        req.priority = priority;
        req.warmup = (i < cfg.warmup_requests);
        queues[conn_idx].push(std::move(req));
    }

    running = false;
    for (auto& w : workers) w.join();

    double elapsed = timer.elapsed_ms() / 1000.0;

    BenchmarkResult result;
    for (auto& samples : thread_samples) {
        result.latency.add_samples(samples);
    }

    result.total_requests = result.latency.count();
    result.total_bytes = total_bytes_.load(std::memory_order_relaxed);
    result.duration_seconds = elapsed;
    result.throughput_rps = static_cast<double>(result.total_requests) / elapsed;
    result.goodput_mbps = (static_cast<double>(result.total_bytes) * 8.0) /
                          (elapsed * 1'000'000.0);

    pool_.close_all();
    return result;
}

void TcpClient::closed_loop_worker(int conn_idx, const WorkloadConfig& cfg,
                                    uint32_t num_requests,
                                    std::vector<uint64_t>& samples) {
    WorkloadGenerator gen(cfg, 42 + static_cast<uint64_t>(conn_idx));
    int fd = pool_.fd_at(static_cast<uint32_t>(conn_idx));
    uint32_t warmup = cfg.warmup_requests / pool_.size();

    samples.reserve(num_requests);

    for (uint32_t i = 0; i < warmup + num_requests; ++i) {
        uint32_t size = gen.next_size();
        uint8_t priority = gen.priority_for_size(size);

        uint64_t rtt = do_request(fd, i, size, priority);

        if (rtt > 0 && i >= warmup) {
            samples.push_back(rtt);
        }

        total_bytes_.fetch_add(sizeof(MessageHeader) + size,
                               std::memory_order_relaxed);
    }
}

void TcpClient::open_loop_worker(int conn_idx,
                                  BoundedQueue<PendingRequest>& queue,
                                  std::vector<uint64_t>& samples,
                                  std::atomic<bool>& running) {
    int fd = pool_.fd_at(static_cast<uint32_t>(conn_idx));

    while (running.load(std::memory_order_relaxed) || queue.size() > 0) {
        PendingRequest req;
        if (!queue.pop(req, 100)) continue;

        uint64_t rtt = do_request(fd, req.id, req.size, req.priority);

        if (rtt > 0 && !req.warmup) {
            samples.push_back(rtt);
        }

        total_bytes_.fetch_add(sizeof(MessageHeader) + req.size,
                               std::memory_order_relaxed);
    }
}

uint64_t TcpClient::do_request(int fd, uint64_t id, uint32_t size, uint8_t priority) {
    thread_local std::vector<uint8_t> send_buf;
    thread_local std::vector<uint8_t> recv_buf;

    MessageHeader hdr{};
    hdr.id = id;
    hdr.payload_size = size;
    hdr.priority = priority;
    hdr.type = MessageType::REQUEST;
    hdr.send_timestamp_ns = now_ns();

    uint8_t hdr_buf[sizeof(MessageHeader)];
    serialize_header(hdr, hdr_buf);

    if (!send_exact(fd, hdr_buf, sizeof(MessageHeader))) return 0;

    if (size > 0) {
        if (send_buf.size() < size) send_buf.resize(size, 0);
        if (!send_exact(fd, send_buf.data(), size)) return 0;
    }

    uint8_t resp_hdr_buf[sizeof(MessageHeader)];
    if (!recv_exact(fd, resp_hdr_buf, sizeof(MessageHeader))) return 0;

    MessageHeader resp = deserialize_header(resp_hdr_buf);

    if (resp.payload_size > 0) {
        if (recv_buf.size() < resp.payload_size) recv_buf.resize(resp.payload_size);
        if (!recv_exact(fd, recv_buf.data(), resp.payload_size)) return 0;
    }

    return now_ns() - hdr.send_timestamp_ns;
}

bool TcpClient::recv_exact(int fd, void* buf, size_t len) {
    auto* ptr = static_cast<uint8_t*>(buf);
    size_t received = 0;
    while (received < len) {
        ssize_t n = ::recv(fd, ptr + received, len - received, 0);
        if (n <= 0) return false;
        received += static_cast<size_t>(n);
    }
    return true;
}

bool TcpClient::send_exact(int fd, const void* buf, size_t len) {
    auto* ptr = static_cast<const uint8_t*>(buf);
    size_t sent = 0;
    while (sent < len) {
        ssize_t n = ::send(fd, ptr + sent, len - sent, MSG_NOSIGNAL);
        if (n <= 0) return false;
        sent += static_cast<size_t>(n);
    }
    return true;
}

}

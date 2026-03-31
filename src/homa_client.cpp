#include "dcbench/homa_client.h"
#include "dcbench/message.h"
#include "dcbench/timing.h"

#include <arpa/inet.h>
#include <netdb.h>
#include <cstring>
#include <iostream>

namespace dcbench {

HomaClient::HomaClient(const std::string& server_host, uint16_t server_port)
    : server_host_(server_host), server_port_(server_port) {}

BenchmarkResult HomaClient::run_closed_loop(const WorkloadConfig& cfg) {
    uint32_t concurrency = cfg.closed_loop_concurrency;
    uint32_t per_thread = cfg.num_requests / concurrency;
    uint32_t remainder = cfg.num_requests % concurrency;

    std::vector<std::vector<uint64_t>> thread_samples(concurrency);
    std::vector<std::thread> workers;
    total_bytes_ = 0;

    Stopwatch timer;

    for (uint32_t i = 0; i < concurrency; ++i) {
        uint32_t count = per_thread + (i < remainder ? 1 : 0);
        workers.emplace_back(&HomaClient::closed_loop_worker, this,
                             std::ref(cfg), count, 42 + i,
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

    return result;
}

BenchmarkResult HomaClient::run_open_loop(const WorkloadConfig& cfg) {
    HomaSocket sock;
    if (!sock.valid()) {
        throw std::runtime_error("Failed to create Homa socket");
    }
    sock.bind(0);

    std::unordered_map<uint64_t, uint64_t> pending;
    std::mutex pending_mu;
    std::vector<uint64_t> recv_samples;
    std::atomic<bool> receiving{true};
    total_bytes_ = 0;

    std::thread receiver(&HomaClient::open_loop_receiver, this,
                         std::ref(sock), std::ref(pending), std::ref(pending_mu),
                         std::ref(recv_samples), std::ref(receiving),
                         cfg.warmup_requests);

    struct addrinfo hints{}, *res = nullptr;
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_DGRAM;
    if (::getaddrinfo(server_host_.c_str(), nullptr, &hints, &res) != 0 || !res)
        throw std::runtime_error("Invalid address: " + server_host_);
    struct sockaddr_in dest = *reinterpret_cast<struct sockaddr_in*>(res->ai_addr);
    dest.sin_port = htons(server_port_);
    ::freeaddrinfo(res);

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

        MessageHeader hdr{};
        hdr.id = i;
        hdr.payload_size = size;
        hdr.priority = priority;
        hdr.type = MessageType::REQUEST;
        hdr.send_timestamp_ns = now_ns();

        std::vector<uint8_t> msg_buf(sizeof(MessageHeader) + size, 0);
        serialize_header(hdr, msg_buf.data());

        uint64_t rpc_id = 0;
        int64_t sent = sock.send_request(msg_buf.data(), msg_buf.size(), dest, &rpc_id);

        if (sent >= 0) {
            std::lock_guard<std::mutex> lk(pending_mu);
            pending[rpc_id] = hdr.send_timestamp_ns;
        }

        total_bytes_.fetch_add(sizeof(MessageHeader) + size, std::memory_order_relaxed);
    }

    std::this_thread::sleep_for(std::chrono::seconds(2));
    receiving = false;
    if (receiver.joinable()) receiver.join();

    double elapsed = timer.elapsed_ms() / 1000.0;

    BenchmarkResult result;
    result.latency.add_samples(recv_samples);
    result.total_requests = result.latency.count();
    result.total_bytes = total_bytes_.load(std::memory_order_relaxed);
    result.duration_seconds = elapsed;
    result.throughput_rps = static_cast<double>(result.total_requests) / elapsed;
    result.goodput_mbps = (static_cast<double>(result.total_bytes) * 8.0) /
                          (elapsed * 1'000'000.0);

    return result;
}

void HomaClient::closed_loop_worker(const WorkloadConfig& cfg,
                                     uint32_t num_requests,
                                     uint64_t seed,
                                     std::vector<uint64_t>& samples) {
    HomaSocket sock;
    if (!sock.valid()) return;
    sock.bind(0);

    struct addrinfo hints{}, *res = nullptr;
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_DGRAM;
    if (::getaddrinfo(server_host_.c_str(), nullptr, &hints, &res) != 0 || !res)
        throw std::runtime_error("Invalid address: " + server_host_);
    struct sockaddr_in dest = *reinterpret_cast<struct sockaddr_in*>(res->ai_addr);
    dest.sin_port = htons(server_port_);
    ::freeaddrinfo(res);

    WorkloadGenerator gen(cfg, seed);
    uint32_t warmup = cfg.warmup_requests / cfg.closed_loop_concurrency;
    samples.reserve(num_requests);

    constexpr size_t RECV_BUF_SIZE = 4 * 1024 * 1024 + sizeof(MessageHeader);
    std::vector<uint8_t> recv_buf(RECV_BUF_SIZE);

    for (uint32_t i = 0; i < warmup + num_requests; ++i) {
        uint32_t size = gen.next_size();
        uint8_t priority = gen.priority_for_size(size);

        MessageHeader hdr{};
        hdr.id = i;
        hdr.payload_size = size;
        hdr.priority = priority;
        hdr.type = MessageType::REQUEST;
        hdr.send_timestamp_ns = now_ns();

        std::vector<uint8_t> send_buf(sizeof(MessageHeader) + size, 0);
        serialize_header(hdr, send_buf.data());

        uint64_t rpc_id = 0;
        int64_t sent = sock.send_request(send_buf.data(), send_buf.size(), dest, &rpc_id);
        if (sent < 0) continue;

        struct sockaddr_in src{};
        int64_t received = sock.recv(recv_buf.data(), RECV_BUF_SIZE,
                                      &src, &rpc_id, HOMA_RECV_RESPONSE);
        uint64_t recv_ts = now_ns();

        if (received > 0 && i >= warmup) {
            samples.push_back(recv_ts - hdr.send_timestamp_ns);
        }

        total_bytes_.fetch_add(sizeof(MessageHeader) + size, std::memory_order_relaxed);
    }
}

void HomaClient::open_loop_receiver(HomaSocket& sock,
                                     std::unordered_map<uint64_t, uint64_t>& pending,
                                     std::mutex& pending_mu,
                                     std::vector<uint64_t>& samples,
                                     std::atomic<bool>& running,
                                     uint32_t warmup_count) {
    constexpr size_t BUF_SIZE = 4 * 1024 * 1024 + sizeof(MessageHeader);
    std::vector<uint8_t> buf(BUF_SIZE);
    uint32_t received_count = 0;

    while (running.load(std::memory_order_relaxed)) {
        struct sockaddr_in src{};
        uint64_t rpc_id = 0;

        int64_t received = sock.recv(buf.data(), BUF_SIZE, &src, &rpc_id,
                                      HOMA_RECV_RESPONSE | HOMA_RECV_NONBLOCKING);

        if (received < 0) {
            std::this_thread::sleep_for(std::chrono::microseconds(50));
            continue;
        }

        uint64_t recv_ts = now_ns();
        uint64_t send_ts = 0;

        {
            std::lock_guard<std::mutex> lk(pending_mu);
            auto it = pending.find(rpc_id);
            if (it != pending.end()) {
                send_ts = it->second;
                pending.erase(it);
            }
        }

        ++received_count;
        if (send_ts > 0 && received_count > warmup_count) {
            samples.push_back(recv_ts - send_ts);
        }
    }
}

}

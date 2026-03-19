#include "dcbench/homa_server.h"
#include "dcbench/message.h"
#include "dcbench/timing.h"

#include <arpa/inet.h>
#include <cstring>
#include <iostream>
#include <vector>

namespace dcbench {

HomaServer::HomaServer(uint16_t port, uint32_t num_threads)
    : port_(port), num_threads_(num_threads) {}

HomaServer::~HomaServer() {
    stop();
}

void HomaServer::start() {
    if (!socket_.valid()) {
        throw std::runtime_error("Failed to create Homa socket (is the kernel module loaded?)");
    }

    if (!socket_.bind(port_)) {
        throw std::runtime_error("Failed to bind Homa socket on port " + std::to_string(port_));
    }

    running_ = true;

    for (uint32_t i = 0; i < num_threads_; ++i) {
        workers_.emplace_back(&HomaServer::worker_loop, this);
    }
}

void HomaServer::stop() {
    if (!running_) return;
    running_ = false;

    for (auto& w : workers_) {
        if (w.joinable()) w.join();
    }
    workers_.clear();
}

bool HomaServer::running() const {
    return running_;
}

const LatencyHistogram& HomaServer::processing_latency() const {
    return processing_latency_;
}

uint64_t HomaServer::total_requests() const {
    return request_count_.load(std::memory_order_relaxed);
}

uint64_t HomaServer::total_bytes() const {
    return byte_count_.load(std::memory_order_relaxed);
}

void HomaServer::worker_loop() {
    constexpr size_t BUF_SIZE = 4 * 1024 * 1024 + sizeof(MessageHeader);
    std::vector<uint8_t> buf(BUF_SIZE);

    while (running_) {
        struct sockaddr_in src{};
        uint64_t rpc_id = 0;

        int64_t received = socket_.recv(buf.data(), BUF_SIZE, &src, &rpc_id,
                                        HOMA_RECV_REQUEST | HOMA_RECV_NONBLOCKING);

        if (received < 0) {
            if (!running_) break;
            std::this_thread::sleep_for(std::chrono::microseconds(100));
            continue;
        }

        if (static_cast<size_t>(received) < sizeof(MessageHeader)) continue;

        MessageHeader hdr = deserialize_header(buf.data());
        hdr.type = MessageType::RESPONSE;
        serialize_header(hdr, buf.data());

        request_count_.fetch_add(1, std::memory_order_relaxed);
        byte_count_.fetch_add(static_cast<uint64_t>(received), std::memory_order_relaxed);

        socket_.send_response(buf.data(), static_cast<size_t>(received), src, rpc_id);
    }
}

}

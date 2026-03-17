#include "dcbench/tcp_server.h"
#include "dcbench/message.h"
#include "dcbench/timing.h"

#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <unistd.h>
#include <cstring>
#include <stdexcept>
#include <iostream>

namespace dcbench {

TcpServer::TcpServer(uint16_t port, bool dctcp)
    : port_(port), dctcp_(dctcp) {}

TcpServer::~TcpServer() {
    stop();
}

void TcpServer::start() {
    setup_listener();
    running_ = true;
    accept_thread_ = std::thread(&TcpServer::accept_loop, this);
}

void TcpServer::stop() {
    if (!running_) return;
    running_ = false;

    if (listen_fd_ >= 0) {
        ::shutdown(listen_fd_, SHUT_RDWR);
        ::close(listen_fd_);
        listen_fd_ = -1;
    }

    {
        std::lock_guard<std::mutex> lock(fds_mu_);
        for (int fd : client_fds_) {
            ::shutdown(fd, SHUT_RDWR);
            ::close(fd);
        }
        client_fds_.clear();
    }

    if (accept_thread_.joinable()) accept_thread_.join();

    {
        std::lock_guard<std::mutex> lock(threads_mu_);
        for (auto& t : conn_threads_) {
            if (t.joinable()) t.join();
        }
        conn_threads_.clear();
    }
}

bool TcpServer::running() const {
    return running_;
}

const LatencyHistogram& TcpServer::processing_latency() const {
    return processing_latency_;
}

uint64_t TcpServer::total_requests() const {
    return request_count_.load(std::memory_order_relaxed);
}

uint64_t TcpServer::total_bytes() const {
    return byte_count_.load(std::memory_order_relaxed);
}

void TcpServer::setup_listener() {
    listen_fd_ = ::socket(AF_INET, SOCK_STREAM, 0);
    if (listen_fd_ < 0) throw std::runtime_error("socket() failed");

    int opt = 1;
    ::setsockopt(listen_fd_, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    struct sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = INADDR_ANY;
    addr.sin_port = htons(port_);

    if (::bind(listen_fd_, reinterpret_cast<struct sockaddr*>(&addr), sizeof(addr)) < 0) {
        ::close(listen_fd_);
        throw std::runtime_error("bind() failed on port " + std::to_string(port_));
    }

    if (::listen(listen_fd_, 1024) < 0) {
        ::close(listen_fd_);
        throw std::runtime_error("listen() failed");
    }
}

void TcpServer::accept_loop() {
    while (running_) {
        struct sockaddr_in client_addr{};
        socklen_t addr_len = sizeof(client_addr);
        int client_fd = ::accept(listen_fd_,
                                 reinterpret_cast<struct sockaddr*>(&client_addr),
                                 &addr_len);
        if (client_fd < 0) {
            if (!running_) break;
            continue;
        }

        int flag = 1;
        ::setsockopt(client_fd, IPPROTO_TCP, TCP_NODELAY, &flag, sizeof(flag));

        if (dctcp_) {
            const char* cc = "dctcp";
            ::setsockopt(client_fd, IPPROTO_TCP, TCP_CONGESTION, cc, std::strlen(cc));
        }

        struct timeval tv;
        tv.tv_sec = 1;
        tv.tv_usec = 0;
        ::setsockopt(client_fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));

        {
            std::lock_guard<std::mutex> lock(fds_mu_);
            client_fds_.push_back(client_fd);
        }

        {
            std::lock_guard<std::mutex> lock(threads_mu_);
            conn_threads_.emplace_back(&TcpServer::connection_handler, this, client_fd);
        }
    }
}

void TcpServer::connection_handler(int fd) {
    thread_local std::vector<uint8_t> payload_buf;

    while (running_) {
        uint8_t hdr_buf[sizeof(MessageHeader)];
        if (!recv_exact(fd, hdr_buf, sizeof(MessageHeader))) {
            if (!running_) break;
            continue;
        }

        MessageHeader hdr = deserialize_header(hdr_buf);

        if (hdr.payload_size > MAX_PAYLOAD_SIZE) break;

        if (hdr.payload_size > 0) {
            if (payload_buf.size() < hdr.payload_size) {
                payload_buf.resize(hdr.payload_size);
            }
            if (!recv_exact(fd, payload_buf.data(), hdr.payload_size)) break;
        }

        request_count_.fetch_add(1, std::memory_order_relaxed);
        byte_count_.fetch_add(sizeof(MessageHeader) + hdr.payload_size,
                              std::memory_order_relaxed);

        hdr.type = MessageType::RESPONSE;
        serialize_header(hdr, hdr_buf);

        if (!send_exact(fd, hdr_buf, sizeof(MessageHeader))) break;

        if (hdr.payload_size > 0) {
            if (!send_exact(fd, payload_buf.data(), hdr.payload_size)) break;
        }
    }

    ::close(fd);

    std::lock_guard<std::mutex> lock(fds_mu_);
    client_fds_.erase(
        std::remove(client_fds_.begin(), client_fds_.end(), fd),
        client_fds_.end());
}

bool TcpServer::recv_exact(int fd, void* buf, size_t len) {
    auto* ptr = static_cast<uint8_t*>(buf);
    size_t received = 0;
    while (received < len) {
        ssize_t n = ::recv(fd, ptr + received, len - received, 0);
        if (n <= 0) return false;
        received += static_cast<size_t>(n);
    }
    return true;
}

bool TcpServer::send_exact(int fd, const void* buf, size_t len) {
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

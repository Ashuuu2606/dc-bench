#include "dcbench/connection_pool.h"

#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <cstring>
#include <stdexcept>

namespace dcbench {

ConnectionPool::ConnectionPool(const PoolConfig& cfg) : cfg_(cfg) {
    conns_.resize(cfg_.pool_size);
}

ConnectionPool::~ConnectionPool() {
    close_all();
}

void ConnectionPool::connect_all() {
    for (uint32_t i = 0; i < cfg_.pool_size; ++i) {
        conns_[i].fd = create_and_connect();
    }
}

void ConnectionPool::close_all() {
    for (auto& c : conns_) {
        if (c.fd >= 0) {
            ::close(c.fd);
            c.fd = -1;
        }
    }
}

int ConnectionPool::fd_at(uint32_t index) const {
    return conns_.at(index).fd;
}

uint32_t ConnectionPool::size() const {
    return cfg_.pool_size;
}

int ConnectionPool::create_and_connect() {
    int fd = ::socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) throw std::runtime_error("socket() failed");

    apply_socket_options(fd);

    struct sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_port = htons(cfg_.port);
    if (::inet_pton(AF_INET, cfg_.host.c_str(), &addr.sin_addr) <= 0) {
        ::close(fd);
        throw std::runtime_error("Invalid address: " + cfg_.host);
    }

    if (::connect(fd, reinterpret_cast<struct sockaddr*>(&addr), sizeof(addr)) < 0) {
        ::close(fd);
        throw std::runtime_error("connect() failed to " + cfg_.host + ":" + std::to_string(cfg_.port));
    }

    return fd;
}

void ConnectionPool::apply_socket_options(int fd) {
    if (cfg_.tcp_nodelay) {
        int flag = 1;
        ::setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &flag, sizeof(flag));
    }

    if (cfg_.dctcp) {
        const char* cc = "dctcp";
        ::setsockopt(fd, IPPROTO_TCP, TCP_CONGESTION, cc, std::strlen(cc));
    }

    if (cfg_.send_buffer_size > 0) {
        int sz = static_cast<int>(cfg_.send_buffer_size);
        ::setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &sz, sizeof(sz));
    }

    if (cfg_.recv_buffer_size > 0) {
        int sz = static_cast<int>(cfg_.recv_buffer_size);
        ::setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &sz, sizeof(sz));
    }
}

}

#pragma once

#include <vector>
#include <string>
#include <cstdint>

namespace dcbench {

struct PoolConfig {
    std::string host;
    uint16_t port = 9000;
    uint32_t pool_size = 1;
    bool tcp_nodelay = true;
    bool dctcp = false;
    uint32_t send_buffer_size = 0;
    uint32_t recv_buffer_size = 0;
};

class ConnectionPool {
public:
    explicit ConnectionPool(const PoolConfig& cfg);
    ~ConnectionPool();

    void connect_all();
    void close_all();

    int fd_at(uint32_t index) const;
    uint32_t size() const;

private:
    PoolConfig cfg_;

    struct Conn {
        int fd = -1;
    };

    std::vector<Conn> conns_;

    int create_and_connect();
    void apply_socket_options(int fd);
};

}

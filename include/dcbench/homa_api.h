#pragma once

#include <cstdint>
#include <cstring>
#include <sys/socket.h>
#include <netinet/in.h>

namespace dcbench {

#ifndef IPPROTO_HOMA
#define IPPROTO_HOMA 140
#endif

struct HomaSendmsgArgs {
    uint64_t id;
    uint64_t completion_cookie;
};

struct HomaRecvmsgArgs {
    uint64_t id;
    uint64_t completion_cookie;
    int flags;
    uint32_t num_bpages;
    uint64_t bpage_offsets[32];
};

constexpr int HOMA_RECV_REQUEST = 0x01;
constexpr int HOMA_RECV_RESPONSE = 0x02;
constexpr int HOMA_RECV_NONBLOCKING = 0x04;

class HomaSocket {
public:
    HomaSocket();
    ~HomaSocket();

    bool bind(uint16_t port);

    int64_t send_request(const void* buf, size_t len,
                         const struct sockaddr_in& dest,
                         uint64_t* rpc_id);

    int64_t send_response(const void* buf, size_t len,
                          const struct sockaddr_in& dest,
                          uint64_t rpc_id);

    int64_t recv(void* buf, size_t len,
                 struct sockaddr_in* src,
                 uint64_t* rpc_id,
                 int flags);

    int fd() const;
    bool valid() const;

private:
    int fd_;
};

}

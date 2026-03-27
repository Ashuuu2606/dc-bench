#include "dcbench/homa_api.h"

#include <unistd.h>
#include <sys/ioctl.h>
#include <cstring>
#include <stdexcept>

#define HOMA_IOCTL_SEND   1003101
#define HOMA_IOCTL_RECV   1003102
#define HOMA_IOCTL_REPLY  1003103

struct homa_send_args {
    void *request;
    const struct iovec *iovec;
    size_t length;
    struct sockaddr_in dest_addr;
    uint64_t id;
};

struct homa_recv_args {
    void *buf;
    const struct iovec *iovec;
    size_t len;
    struct sockaddr_in source_addr;
    int flags;
    uint64_t requestedId;
    uint64_t actualId;
    int type;
};

struct homa_reply_args {
    void *response;
    const struct iovec *iovec;
    size_t length;
    struct sockaddr_in dest_addr;
    uint64_t id;
};

namespace dcbench {

HomaSocket::HomaSocket() {
    fd_ = ::socket(AF_INET, SOCK_DGRAM, IPPROTO_HOMA);
}

HomaSocket::~HomaSocket() {
    if (fd_ >= 0) {
        ::close(fd_);
        fd_ = -1;
    }
}

bool HomaSocket::bind(uint16_t port) {
    struct sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = INADDR_ANY;
    addr.sin_port = htons(port);
    return ::bind(fd_, reinterpret_cast<struct sockaddr*>(&addr), sizeof(addr)) == 0;
}

int64_t HomaSocket::send_request(const void* buf, size_t len,
                                  const struct sockaddr_in& dest,
                                  uint64_t* rpc_id) {
    homa_send_args args{};
    args.request = const_cast<void*>(buf);
    args.iovec = nullptr;
    args.length = len;
    args.dest_addr = dest;
    args.id = 0;

    int result = ::ioctl(fd_, HOMA_IOCTL_SEND, &args);

    if (result >= 0 && rpc_id) {
        *rpc_id = args.id;
    }

    return result;
}

int64_t HomaSocket::send_response(const void* buf, size_t len,
                                   const struct sockaddr_in& dest,
                                   uint64_t rpc_id) {
    homa_reply_args args{};
    args.response = const_cast<void*>(buf);
    args.iovec = nullptr;
    args.length = len;
    args.dest_addr = dest;
    args.id = rpc_id;

    return ::ioctl(fd_, HOMA_IOCTL_REPLY, &args);
}

int64_t HomaSocket::recv(void* buf, size_t len,
                          struct sockaddr_in* src,
                          uint64_t* rpc_id,
                          int flags) {
    homa_recv_args args{};
    args.buf = buf;
    args.iovec = nullptr;
    args.len = len;
    if (src) args.source_addr = *src;
    args.flags = flags;
    args.requestedId = (rpc_id && *rpc_id != 0) ? *rpc_id : 0;
    args.actualId = 0;

    int result = ::ioctl(fd_, HOMA_IOCTL_RECV, &args);

    if (src) *src = args.source_addr;
    if (rpc_id) *rpc_id = args.actualId;

    if (result >= 0) return static_cast<int64_t>(args.len);
    return -1;
}

int HomaSocket::fd() const {
    return fd_;
}

bool HomaSocket::valid() const {
    return fd_ >= 0;
}

}

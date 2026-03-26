#include "dcbench/homa_api.h"

#include <unistd.h>
#include <cstring>
#include <stdexcept>

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
    HomaSendmsgArgs args{};
    args.id = 0;
    args.completion_cookie = 0;

    struct iovec iov;
    iov.iov_base = const_cast<void*>(buf);
    iov.iov_len = len;

    union {
        struct cmsghdr cmsg;
        char space[CMSG_SPACE(sizeof(HomaSendmsgArgs))];
    } control{};

    struct msghdr msg{};
    msg.msg_name = const_cast<struct sockaddr_in*>(&dest);
    msg.msg_namelen = sizeof(dest);
    msg.msg_iov = &iov;
    msg.msg_iovlen = 1;
    msg.msg_control = control.space;
    msg.msg_controllen = sizeof(control.space);

    struct cmsghdr* cmsg = CMSG_FIRSTHDR(&msg);
    cmsg->cmsg_level = IPPROTO_HOMA;
    cmsg->cmsg_type = 0;
    cmsg->cmsg_len = CMSG_LEN(sizeof(HomaSendmsgArgs));
    std::memcpy(CMSG_DATA(cmsg), &args, sizeof(args));

    ssize_t result = ::sendmsg(fd_, &msg, 0);

    if (result >= 0 && rpc_id) {
        std::memcpy(&args, CMSG_DATA(cmsg), sizeof(args));
        *rpc_id = args.id;
    }

    return result;
}

int64_t HomaSocket::send_response(const void* buf, size_t len,
                                   const struct sockaddr_in& dest,
                                   uint64_t rpc_id) {
    HomaSendmsgArgs args{};
    args.id = rpc_id;
    args.completion_cookie = 0;

    struct iovec iov;
    iov.iov_base = const_cast<void*>(buf);
    iov.iov_len = len;

    union {
        struct cmsghdr cmsg;
        char space[CMSG_SPACE(sizeof(HomaSendmsgArgs))];
    } control{};

    struct msghdr msg{};
    msg.msg_name = const_cast<struct sockaddr_in*>(&dest);
    msg.msg_namelen = sizeof(dest);
    msg.msg_iov = &iov;
    msg.msg_iovlen = 1;
    msg.msg_control = control.space;
    msg.msg_controllen = sizeof(control.space);

    struct cmsghdr* cmsg = CMSG_FIRSTHDR(&msg);
    cmsg->cmsg_level = IPPROTO_HOMA;
    cmsg->cmsg_type = 0;
    cmsg->cmsg_len = CMSG_LEN(sizeof(HomaSendmsgArgs));
    std::memcpy(CMSG_DATA(cmsg), &args, sizeof(args));

    return ::sendmsg(fd_, &msg, 0);
}

int64_t HomaSocket::recv(void* buf, size_t len,
                          struct sockaddr_in* src,
                          uint64_t* rpc_id,
                          int flags) {
    HomaRecvmsgArgs args{};
    args.id = (rpc_id && *rpc_id != 0) ? *rpc_id : 0;
    args.flags = flags;
    args.num_bpages = 0;

    struct iovec iov;
    iov.iov_base = buf;
    iov.iov_len = len;

    union {
        struct cmsghdr cmsg;
        char space[CMSG_SPACE(sizeof(HomaRecvmsgArgs))];
    } control{};

    struct msghdr msg{};
    msg.msg_name = src;
    msg.msg_namelen = src ? sizeof(*src) : 0;
    msg.msg_iov = &iov;
    msg.msg_iovlen = 1;
    msg.msg_control = control.space;
    msg.msg_controllen = sizeof(control.space);

    struct cmsghdr* cmsg = CMSG_FIRSTHDR(&msg);
    cmsg->cmsg_level = IPPROTO_HOMA;
    cmsg->cmsg_type = 0;
    cmsg->cmsg_len = CMSG_LEN(sizeof(HomaRecvmsgArgs));
    std::memcpy(CMSG_DATA(cmsg), &args, sizeof(args));

    ssize_t result = ::recvmsg(fd_, &msg, 0);

    if (result >= 0 && rpc_id) {
        std::memcpy(&args, CMSG_DATA(cmsg), sizeof(args));
        *rpc_id = args.id;
    }

    return result;
}

int HomaSocket::fd() const {
    return fd_;
}

bool HomaSocket::valid() const {
    return fd_ >= 0;
}

}

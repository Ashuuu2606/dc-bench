#pragma once

#include <cstdint>
#include <cstring>
#include <vector>

namespace dcbench {

enum class MessageType : uint8_t {
    REQUEST = 1,
    RESPONSE = 2
};

struct __attribute__((packed)) MessageHeader {
    uint64_t id;
    uint32_t payload_size;
    uint8_t priority;
    MessageType type;
    uint64_t send_timestamp_ns;
};

static_assert(sizeof(MessageHeader) == 22, "MessageHeader must be 22 bytes");

constexpr size_t MAX_PAYLOAD_SIZE = 4 * 1024 * 1024;

inline void serialize_header(const MessageHeader& hdr, uint8_t* buf) {
    std::memcpy(buf, &hdr, sizeof(MessageHeader));
}

inline MessageHeader deserialize_header(const uint8_t* buf) {
    MessageHeader hdr;
    std::memcpy(&hdr, buf, sizeof(MessageHeader));
    return hdr;
}

}

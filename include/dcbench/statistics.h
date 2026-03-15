#pragma once

#include <vector>
#include <string>
#include <cstdint>

namespace dcbench {

class LatencyHistogram {
public:
    void record(uint64_t latency_ns);
    void add_samples(const std::vector<uint64_t>& samples);
    void reset();

    uint64_t percentile(double p) const;
    uint64_t p50() const;
    uint64_t p95() const;
    uint64_t p99() const;
    uint64_t p999() const;
    uint64_t min_val() const;
    uint64_t max_val() const;
    double mean_val() const;
    size_t count() const;

    const std::vector<uint64_t>& raw_samples() const;
    void dump_csv(const std::string& path) const;
    void print_summary() const;

private:
    std::vector<uint64_t> samples_;
    mutable bool sorted_ = false;

    void ensure_sorted() const;
};

}

#include "dcbench/statistics.h"

#include <algorithm>
#include <numeric>
#include <fstream>
#include <iostream>
#include <iomanip>
#include <cmath>

namespace dcbench {

void LatencyHistogram::record(uint64_t latency_ns) {
    samples_.push_back(latency_ns);
    sorted_ = false;
}

void LatencyHistogram::add_samples(const std::vector<uint64_t>& samples) {
    samples_.insert(samples_.end(), samples.begin(), samples.end());
    sorted_ = false;
}

void LatencyHistogram::reset() {
    samples_.clear();
    sorted_ = false;
}

void LatencyHistogram::ensure_sorted() const {
    if (!sorted_) {
        std::sort(samples_.begin(), samples_.end());
        sorted_ = true;
    }
}

uint64_t LatencyHistogram::percentile(double p) const {
    if (samples_.empty()) return 0;
    ensure_sorted();
    size_t idx = static_cast<size_t>(std::ceil(p / 100.0 * samples_.size())) - 1;
    idx = std::min(idx, samples_.size() - 1);
    return samples_[idx];
}

uint64_t LatencyHistogram::p50() const { return percentile(50); }
uint64_t LatencyHistogram::p95() const { return percentile(95); }
uint64_t LatencyHistogram::p99() const { return percentile(99); }
uint64_t LatencyHistogram::p999() const { return percentile(99.9); }

uint64_t LatencyHistogram::min_val() const {
    if (samples_.empty()) return 0;
    ensure_sorted();
    return samples_.front();
}

uint64_t LatencyHistogram::max_val() const {
    if (samples_.empty()) return 0;
    ensure_sorted();
    return samples_.back();
}

double LatencyHistogram::mean_val() const {
    if (samples_.empty()) return 0;
    double sum = std::accumulate(samples_.begin(), samples_.end(), 0.0);
    return sum / static_cast<double>(samples_.size());
}

size_t LatencyHistogram::count() const {
    return samples_.size();
}

const std::vector<uint64_t>& LatencyHistogram::raw_samples() const {
    return samples_;
}

void LatencyHistogram::dump_csv(const std::string& path) const {
    ensure_sorted();
    std::ofstream out(path);
    out << "sample_idx,latency_ns,latency_us\n";
    for (size_t i = 0; i < samples_.size(); ++i) {
        out << i << "," << samples_[i] << ","
            << std::fixed << std::setprecision(2)
            << static_cast<double>(samples_[i]) / 1000.0 << "\n";
    }
}

void LatencyHistogram::print_summary() const {
    auto to_us = [](uint64_t ns) { return static_cast<double>(ns) / 1000.0; };

    std::cout << std::fixed << std::setprecision(1)
              << "  count:  " << count() << "\n"
              << "  min:    " << to_us(min_val()) << " us\n"
              << "  mean:   " << to_us(static_cast<uint64_t>(mean_val())) << " us\n"
              << "  p50:    " << to_us(p50()) << " us\n"
              << "  p95:    " << to_us(p95()) << " us\n"
              << "  p99:    " << to_us(p99()) << " us\n"
              << "  p99.9:  " << to_us(p999()) << " us\n"
              << "  max:    " << to_us(max_val()) << " us\n";
}

}

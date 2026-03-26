#include "dcbench/workload.h"

#include <stdexcept>
#include <algorithm>
#include <cmath>

namespace dcbench {

SizeDistribution parse_distribution(const std::string& name) {
    if (name == "fixed") return SizeDistribution::FIXED;
    if (name == "uniform") return SizeDistribution::UNIFORM;
    if (name == "bimodal") return SizeDistribution::BIMODAL;
    if (name == "pareto") return SizeDistribution::PARETO;
    throw std::runtime_error("Unknown distribution: " + name);
}

ArrivalModel parse_arrival_model(const std::string& name) {
    if (name == "open") return ArrivalModel::OPEN_LOOP;
    if (name == "closed") return ArrivalModel::CLOSED_LOOP;
    throw std::runtime_error("Unknown arrival model: " + name);
}

WorkloadGenerator::WorkloadGenerator(const WorkloadConfig& cfg, uint64_t seed)
    : cfg_(cfg), rng_(seed) {}

uint32_t WorkloadGenerator::next_size() {
    switch (cfg_.distribution) {
    case SizeDistribution::FIXED:
        return cfg_.fixed_size;

    case SizeDistribution::UNIFORM: {
        std::uniform_int_distribution<uint32_t> dist(cfg_.uniform_min, cfg_.uniform_max);
        return dist(rng_);
    }

    case SizeDistribution::BIMODAL: {
        std::bernoulli_distribution coin(cfg_.bimodal_small_fraction);
        return coin(rng_) ? cfg_.bimodal_small : cfg_.bimodal_large;
    }

    case SizeDistribution::PARETO:
        return generate_pareto();
    }

    return cfg_.fixed_size;
}

double WorkloadGenerator::next_interarrival_us() {
    if (cfg_.target_rps <= 0) return 0;
    double mean_interval_us = 1'000'000.0 / cfg_.target_rps;
    std::exponential_distribution<double> dist(1.0 / mean_interval_us);
    return dist(rng_);
}

uint8_t WorkloadGenerator::priority_for_size(uint32_t size) const {
    if (size <= 256) return 7;
    if (size <= 1024) return 6;
    if (size <= 4096) return 5;
    if (size <= 16384) return 4;
    if (size <= 65536) return 3;
    if (size <= 262144) return 2;
    if (size <= 1048576) return 1;
    return 0;
}

const WorkloadConfig& WorkloadGenerator::config() const {
    return cfg_;
}

uint32_t WorkloadGenerator::generate_pareto() {
    std::uniform_real_distribution<double> u(0.0, 1.0);
    double sample = u(rng_);
    double value = cfg_.pareto_scale / std::pow(1.0 - sample, 1.0 / cfg_.pareto_shape);
    return std::min(static_cast<uint32_t>(value), cfg_.pareto_max);
}

}

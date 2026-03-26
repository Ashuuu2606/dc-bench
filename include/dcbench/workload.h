#pragma once

#include <cstdint>
#include <random>
#include <string>

namespace dcbench {

enum class SizeDistribution { FIXED, UNIFORM, BIMODAL, PARETO };
enum class ArrivalModel { OPEN_LOOP, CLOSED_LOOP };

SizeDistribution parse_distribution(const std::string& name);
ArrivalModel parse_arrival_model(const std::string& name);

struct WorkloadConfig {
    SizeDistribution distribution = SizeDistribution::FIXED;
    ArrivalModel arrival = ArrivalModel::CLOSED_LOOP;

    uint32_t fixed_size = 1024;
    uint32_t uniform_min = 64;
    uint32_t uniform_max = 65536;

    uint32_t bimodal_small = 256;
    uint32_t bimodal_large = 1048576;
    double bimodal_small_fraction = 0.9;

    double pareto_shape = 1.5;
    uint32_t pareto_scale = 256;
    uint32_t pareto_max = 2097152;

    double target_rps = 10000;
    uint32_t closed_loop_concurrency = 16;
    uint32_t num_requests = 100000;
    uint32_t warmup_requests = 1000;
};

class WorkloadGenerator {
public:
    explicit WorkloadGenerator(const WorkloadConfig& cfg, uint64_t seed = 42);

    uint32_t next_size();
    double next_interarrival_us();
    uint8_t priority_for_size(uint32_t size) const;
    const WorkloadConfig& config() const;

private:
    WorkloadConfig cfg_;
    std::mt19937_64 rng_;

    uint32_t generate_pareto();
};

}

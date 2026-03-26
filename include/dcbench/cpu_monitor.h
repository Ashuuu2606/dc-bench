#pragma once

#include <cstdint>

namespace dcbench {

class CpuMonitor {
public:
    void start();
    void stop();
    double average_usage() const;

private:
    struct CpuTimes {
        uint64_t user = 0;
        uint64_t nice = 0;
        uint64_t system = 0;
        uint64_t idle = 0;
        uint64_t iowait = 0;
        uint64_t irq = 0;
        uint64_t softirq = 0;

        uint64_t total() const;
        uint64_t active() const;
    };

    CpuTimes start_times_;
    CpuTimes end_times_;

    static CpuTimes read_cpu_times();
};

}

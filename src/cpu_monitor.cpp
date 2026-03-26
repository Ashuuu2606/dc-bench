#include "dcbench/cpu_monitor.h"

#include <fstream>
#include <string>
#include <cstdio>

namespace dcbench {

uint64_t CpuMonitor::CpuTimes::total() const {
    return user + nice + system + idle + iowait + irq + softirq;
}

uint64_t CpuMonitor::CpuTimes::active() const {
    return total() - idle - iowait;
}

CpuMonitor::CpuTimes CpuMonitor::read_cpu_times() {
    CpuTimes t{};
    std::ifstream f("/proc/stat");
    if (!f.is_open()) return t;

    std::string line;
    std::getline(f, line);

    std::sscanf(line.c_str(), "cpu %lu %lu %lu %lu %lu %lu %lu",
                &t.user, &t.nice, &t.system, &t.idle,
                &t.iowait, &t.irq, &t.softirq);
    return t;
}

void CpuMonitor::start() {
    start_times_ = read_cpu_times();
}

void CpuMonitor::stop() {
    end_times_ = read_cpu_times();
}

double CpuMonitor::average_usage() const {
    uint64_t total_delta = end_times_.total() - start_times_.total();
    uint64_t active_delta = end_times_.active() - start_times_.active();
    if (total_delta == 0) return 0;
    return 100.0 * static_cast<double>(active_delta) / static_cast<double>(total_delta);
}

}

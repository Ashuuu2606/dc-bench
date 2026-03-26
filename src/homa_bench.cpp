#include "dcbench/homa_server.h"
#include "dcbench/homa_client.h"
#include "dcbench/workload.h"
#include "dcbench/cpu_monitor.h"
#include "dcbench/timing.h"

#include <iostream>
#include <string>
#include <filesystem>
#include <csignal>
#include <atomic>
#include <memory>

using namespace dcbench;

static std::atomic<bool> g_running{true};

static void signal_handler(int) { g_running = false; }

struct Args {
    std::string mode;
    std::string host = "127.0.0.1";
    uint16_t port = 9500;
    uint32_t threads = 4;
    uint32_t concurrency = 8;
    std::string dist = "fixed";
    std::string arrival = "closed";
    double rps = 10000;
    uint32_t msg_size = 1024;
    uint32_t requests = 100000;
    uint32_t warmup = 1000;
    std::string output = "./results";
    uint32_t bimodal_small = 256;
    uint32_t bimodal_large = 1048576;
    double bimodal_ratio = 0.9;
    double pareto_shape = 1.5;
    uint32_t pareto_scale = 256;
    uint32_t uniform_min = 64;
    uint32_t uniform_max = 65536;
    bool cpu_monitor = false;
};

static void print_usage() {
    std::cerr << "Usage: homa_bench <server|client> [options]\n\n"
              << "Server options:\n"
              << "  --port PORT          Listen port (default: 9500)\n"
              << "  --threads N          Worker threads (default: 4)\n\n"
              << "Client options:\n"
              << "  --host HOST          Server address\n"
              << "  --port PORT          Server port\n"
              << "  --concurrency N      Concurrent RPCs (default: 8)\n"
              << "  --dist DIST          fixed|uniform|bimodal|pareto\n"
              << "  --arrival MODEL      open|closed\n"
              << "  --rps RATE           Target requests/sec for open-loop\n"
              << "  --msg-size BYTES     Fixed message size\n"
              << "  --requests N         Number of requests\n"
              << "  --warmup N           Warmup requests\n"
              << "  --output DIR         Output directory\n"
              << "  --cpu-monitor        Track CPU utilization\n";
}

static Args parse_args(int argc, char** argv) {
    Args a;
    if (argc < 2) { print_usage(); std::exit(1); }
    a.mode = argv[1];

    for (int i = 2; i < argc; ++i) {
        std::string key = argv[i];
        auto next = [&]() -> std::string {
            if (i + 1 >= argc) {
                std::cerr << "Missing value for " << key << "\n";
                std::exit(1);
            }
            return argv[++i];
        };

        if      (key == "--host")          a.host = next();
        else if (key == "--port")          a.port = static_cast<uint16_t>(std::stoi(next()));
        else if (key == "--threads")       a.threads = static_cast<uint32_t>(std::stoi(next()));
        else if (key == "--concurrency")   a.concurrency = static_cast<uint32_t>(std::stoi(next()));
        else if (key == "--dist")          a.dist = next();
        else if (key == "--arrival")       a.arrival = next();
        else if (key == "--rps")           a.rps = std::stod(next());
        else if (key == "--msg-size")      a.msg_size = static_cast<uint32_t>(std::stoi(next()));
        else if (key == "--requests")      a.requests = static_cast<uint32_t>(std::stoi(next()));
        else if (key == "--warmup")        a.warmup = static_cast<uint32_t>(std::stoi(next()));
        else if (key == "--output")        a.output = next();
        else if (key == "--bimodal-small") a.bimodal_small = static_cast<uint32_t>(std::stoi(next()));
        else if (key == "--bimodal-large") a.bimodal_large = static_cast<uint32_t>(std::stoi(next()));
        else if (key == "--bimodal-ratio") a.bimodal_ratio = std::stod(next());
        else if (key == "--pareto-shape")  a.pareto_shape = std::stod(next());
        else if (key == "--pareto-scale")  a.pareto_scale = static_cast<uint32_t>(std::stoi(next()));
        else if (key == "--uniform-min")   a.uniform_min = static_cast<uint32_t>(std::stoi(next()));
        else if (key == "--uniform-max")   a.uniform_max = static_cast<uint32_t>(std::stoi(next()));
        else if (key == "--cpu-monitor")   a.cpu_monitor = true;
        else { std::cerr << "Unknown option: " << key << "\n"; std::exit(1); }
    }
    return a;
}

static void run_server(const Args& args) {
    HomaServer server(args.port, args.threads);
    server.start();

    std::cout << "Homa server listening on port " << args.port
              << " with " << args.threads << " threads\n"
              << "Press Ctrl+C to stop.\n";

    while (g_running) {
        std::this_thread::sleep_for(std::chrono::seconds(1));
        std::cout << "\r  requests: " << server.total_requests()
                  << "  bytes: " << server.total_bytes() << std::flush;
    }

    server.stop();
    std::cout << "\n\nServer stopped.\n"
              << "  Total requests: " << server.total_requests() << "\n"
              << "  Total bytes:    " << server.total_bytes() << "\n";
}

static void run_client(const Args& args) {
    HomaClient client(args.host, args.port);

    WorkloadConfig wl;
    wl.distribution = parse_distribution(args.dist);
    wl.arrival = parse_arrival_model(args.arrival);
    wl.fixed_size = args.msg_size;
    wl.target_rps = args.rps;
    wl.num_requests = args.requests;
    wl.warmup_requests = args.warmup;
    wl.bimodal_small = args.bimodal_small;
    wl.bimodal_large = args.bimodal_large;
    wl.bimodal_small_fraction = args.bimodal_ratio;
    wl.pareto_shape = args.pareto_shape;
    wl.pareto_scale = args.pareto_scale;
    wl.uniform_min = args.uniform_min;
    wl.uniform_max = args.uniform_max;
    wl.closed_loop_concurrency = args.concurrency;

    std::unique_ptr<CpuMonitor> cpu;
    if (args.cpu_monitor) {
        cpu = std::make_unique<CpuMonitor>();
        cpu->start();
    }

    std::cout << "Running Homa benchmark...\n"
              << "  target:      " << args.host << ":" << args.port << "\n"
              << "  concurrency: " << args.concurrency << "\n"
              << "  dist:        " << args.dist << "\n"
              << "  mode:        " << args.arrival << "-loop\n";

    if (wl.arrival == ArrivalModel::OPEN_LOOP) {
        std::cout << "  rate:        " << args.rps << " rps\n";
    }
    std::cout << std::endl;

    BenchmarkResult result;
    if (wl.arrival == ArrivalModel::OPEN_LOOP) {
        result = client.run_open_loop(wl);
    } else {
        result = client.run_closed_loop(wl);
    }

    if (cpu) cpu->stop();

    std::cout << "\n=== Homa Benchmark Results ===\n"
              << "Duration:    " << result.duration_seconds << " s\n"
              << "Throughput:  " << result.throughput_rps << " rps\n"
              << "Goodput:     " << result.goodput_mbps << " Mbps\n"
              << "\nLatency distribution:\n";
    result.latency.print_summary();

    if (cpu) {
        std::cout << "\nCPU utilization: " << cpu->average_usage() << "%\n";
    }

    std::filesystem::create_directories(args.output);
    result.latency.dump_csv(args.output + "/latency.csv");
    std::cout << "\nRaw samples saved to " << args.output << "/latency.csv\n";
}

int main(int argc, char** argv) {
    std::signal(SIGINT, signal_handler);
    std::signal(SIGTERM, signal_handler);

    Args args = parse_args(argc, argv);

    if (args.mode == "server") {
        run_server(args);
    } else if (args.mode == "client") {
        run_client(args);
    } else {
        std::cerr << "Unknown mode: " << args.mode << "\n";
        print_usage();
        return 1;
    }

    return 0;
}

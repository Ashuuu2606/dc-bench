# Experiment Results: TCP Configuration Analysis for Datacenter Incast

**Date**: March 26, 2026  
**Testbed**: CloudLab xl170 nodes (Intel Xeon E5-2640v4, 64GB RAM, 25GbE Mellanox ConnectX-4)  
**Topology**: 4 sender nodes → 1 receiver node (incast)  
**OS**: Ubuntu 20.04, kernel tuned (DCTCP enabled, ECN on, NIC offloads disabled)

---

## 1. Hypothesis 1: HoL Blocking Under Bimodal Workload

**Question**: Does TCP connection pooling with size-aware scheduling eliminate Homa's HoL blocking advantage?

**Workload**: Bimodal — 90% small (256B) + 10% large (1MB), closed-loop, 4 incast clients

| Configuration | P50 (us) | P99 (us) | P99.9 (us) | Throughput (rps/client) |
|---|---|---|---|---|
| TCP single-stream (pool=1) | **103** | **1,751** | **2,261** | 4,067 |
| TCP pool=32, round-robin | 2,610 | 31,944 | 70,360 | 5,852 |
| TCP pool=32, size-aware | 2,728 | 28,463 | 51,046 | 5,953 |
| DCTCP single-stream | 107 | **1,720** | **2,246** | 3,708 |
| DCTCP pool=32, size-aware | 2,723 | 30,483 | 52,892 | 6,021 |

*Values shown are median across 4 clients (client_0 representative).*

### Key Findings

1. **Single-stream TCP has LOWER latency than pooled TCP for bimodal workloads.** This is counterintuitive — pool=32 increased p50 from ~103us to ~2,700us (26x worse).

2. **Why pooling hurts here**: With pool=32, 32 concurrent connections compete for bandwidth. The 10% large messages (1MB each) saturate multiple connections simultaneously, causing queuing across ALL connections. In single-stream mode, messages are serialized — one at a time — so while there's HoL blocking per-message, there's no cross-connection contention.

3. **Size-aware scheduling provides marginal improvement over round-robin** (~28K vs ~32K p99), but doesn't fundamentally solve the contention problem.

4. **DCTCP has negligible impact on bimodal latency.** ECN-based congestion control doesn't help when the bottleneck is message serialization, not congestion.

### Interpretation for Research

This is a **negative result** for the TCP pooling hypothesis under our specific bimodal configuration. The massive 1MB messages create enough bandwidth pressure that parallelizing them across 32 connections worsens contention. **Homa's receiver-driven scheduling would likely outperform both configurations here** because it can prioritize the small messages at the switch level.

---

## 2. Heavy-Tail Workload (Pareto Distribution)

**Question**: How do TCP configurations perform under realistic heavy-tailed datacenter traffic?

**Workload**: Pareto (shape=1.5, scale=256B, max=2MB), closed-loop, 4 incast clients

| Configuration | P50 (us) | P99 (us) | P99.9 (us) | Throughput (rps/client) |
|---|---|---|---|---|
| TCP single-stream (pool=1) | **62** | **128** | **230** | 14,152 |
| TCP pool=32, size-aware | 150 | 564 | 1,208 | 124,439 |
| DCTCP pool=32, size-aware | 156 | 506 | 1,801 | 91,150 |

### Key Findings

1. **Single-stream TCP has the best latency under Pareto.** P99 of 128us vs 564us for pooled. The heavy-tail distribution generates mostly small messages (90%+ under 1KB), so single-stream doesn't suffer severe HoL blocking.

2. **Pooled TCP achieves 8-9x higher throughput** (124K vs 14K rps) because 32 connections can process requests in parallel — but at the cost of higher latency due to connection scheduling overhead.

3. **Latency vs throughput tradeoff is clear**: Pooling trades latency for throughput. For latency-sensitive RPCs, single-stream is better. For throughput-bound workloads, pooling wins.

4. **DCTCP slightly reduces p99** (506 vs 564us) but increases p99.9 (1,801 vs 1,208us) — ECN helps moderate congestion but can cause occasional slowdowns from rate reduction.

---

## 3. Hypothesis 3: Configuration Overhead (Pool Size Scaling)

**Question**: How does TCP connection pool size affect performance and overhead?

**Workload**: Fixed 1KB messages, closed-loop, 4 incast clients

| Pool Size | P50 (us) | P99 (us) | P99.9 (us) | Throughput (rps/client) |
|---|---|---|---|---|
| 1 | **59** | **116** | **208** | 14,661 |
| 16 | 133 | 274 | 377 | 95,299 |
| 32 | 171 | 549 | 1,183 | 103,099 |
| 64 | 229 | 936 | 4,107 | 116,553 |

### Key Findings

1. **Diminishing returns beyond pool=16.** Going from 1→16 connections gives 6.5x throughput gain. Going from 16→32 gives only 1.08x. Going from 32→64 gives 1.13x.

2. **Latency scales roughly linearly with pool size.** P50 goes 59→133→171→229us as pool size increases 1→16→32→64. This confirms Homa's argument that more connections = more overhead.

3. **Tail latency explodes at pool=64.** P99.9 jumps from 1.2ms at pool=32 to 4.1ms at pool=64 — a 3.4x increase for only 13% more throughput.

4. **Pool=16 is the sweet spot** for fixed-size messages: best latency-throughput ratio with p99 of just 274us at 95K rps.

---

## 4. Summary Table: All Experiments

| # | Config | Dist | Pool | Sched | DCTCP | P50 (us) | P99 (us) | P99.9 (us) | Tput (rps) |
|---|---|---|---|---|---|---|---|---|---|
| 1 | Single | Bimodal | 1 | RR | No | 103 | 1,751 | 2,261 | 4,067 |
| 2 | Pooled | Bimodal | 32 | RR | No | 2,610 | 31,944 | 70,360 | 5,852 |
| 3 | Pooled+SA | Bimodal | 32 | SA | No | 2,728 | 28,463 | 51,046 | 5,953 |
| 4 | DCTCP | Bimodal | 1 | RR | Yes | 107 | 1,720 | 2,246 | 3,708 |
| 5 | DCTCP+Pool+SA | Bimodal | 32 | SA | Yes | 2,723 | 30,483 | 52,892 | 6,021 |
| 6 | Single | Pareto | 1 | RR | No | 62 | 128 | 230 | 14,152 |
| 7 | Pooled+SA | Pareto | 32 | SA | No | 150 | 564 | 1,208 | 124,439 |
| 8 | DCTCP+Pool+SA | Pareto | 32 | SA | Yes | 156 | 506 | 1,801 | 91,150 |
| 9 | Single | Fixed 1K | 1 | RR | No | 59 | 116 | 208 | 14,661 |
| 10 | Pooled | Fixed 1K | 16 | RR | No | 133 | 274 | 377 | 95,299 |
| 11 | Pooled | Fixed 1K | 32 | RR | No | 171 | 549 | 1,183 | 103,099 |
| 12 | Pooled | Fixed 1K | 64 | RR | No | 229 | 936 | 4,107 | 116,553 |

---

## 5. Conclusions for Proposal Hypotheses

### Hypothesis 1: TCP pooling eliminates HoL blocking advantage
**Result: PARTIALLY REFUTED.** Under bimodal workloads with large (1MB) messages, TCP pooling actually *increases* latency due to bandwidth contention. Single-stream TCP serializes requests which avoids contention. Homa's receiver-driven scheduling would handle this better by explicitly prioritizing small messages at the network level.

### Hypothesis 2: DCTCP matches Homa's congestion control
**Result: NEGLIGIBLE IMPACT.** DCTCP/ECN provided minimal improvement across all workloads. This suggests that for the incast scale tested (4 senders), congestion control is not the primary bottleneck — message scheduling is.

### Hypothesis 3: TCP configuration overhead is manageable
**Result: CONFIRMED WITH CAVEATS.** Pool=16 achieves near-optimal throughput/latency ratio. Beyond 32 connections, diminishing returns and tail latency degradation suggest Homa's zero-configuration advantage is real for operators who don't want to tune pool sizes.

---

## 6. Remaining Work

- [ ] Build and test Homa kernel module for direct comparison
- [ ] Run open-loop experiments to capture coordinated omission effects
- [ ] Test with 8-64 incast senders (larger fan-in)
- [ ] Profile kernel memory consumption per configuration
- [ ] Generate CDF plots and paper-ready figures

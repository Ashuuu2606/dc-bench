# Final Experiment Results: TCP vs Homa for Latency-Sensitive DC Traffic

**Authors**: Ashutosh Bharadwaj, Himanish Agarwal, Varun Mehrotra  
**Course**: DNS 8803 — Datacenter Network Systems  
**Date**: March 26, 2026  
**Testbed**: CloudLab xl170 (Intel Xeon E5-2640v4, 64GB RAM, 25GbE Mellanox ConnectX-4)  
**Topology**: 4 senders → 1 receiver (incast), Ubuntu 20.04, kernel 5.4.0  
**Homa**: HomaModule linux_5.4.80 branch (patched for Ubuntu kernel)

---

## 1. HEAD-TO-HEAD: TCP vs Homa

### 1a. Bimodal 256B/1MB (Extreme HoL Blocking)

| Protocol | Config | P50 (us) | P95 (us) | P99 (us) | P99.9 (us) | Throughput (rps) |
|---|---|---|---|---|---|---|
| **Homa** | concurrency=8 | **191** | **234** | **265** | **354** | **34,560** |
| TCP | single-stream | 99 | 1,240 | 1,751 | 2,221 | 4,067 |
| TCP | pool=32, size-aware | 2,730 | 14,778 | 28,755 | 49,032 | 6,469 |
| TCP+DCTCP | pool=32, size-aware | 2,682 | 16,630 | 32,055 | 50,018 | 5,873 |

**Homa wins decisively.** P99 is **6.6x better** than single-stream TCP (265 vs 1,751us) and **108x better** than pooled TCP (265 vs 28,755us). Homa's receiver-driven scheduling prevents large messages from blocking small ones at the protocol level. TCP pooling causes bandwidth saturation (128 concurrent flows on 25Gbps).

### 1b. Bimodal 256B/64KB (Moderate HoL Blocking)

| Protocol | Config | P50 (us) | P95 (us) | P99 (us) | P99.9 (us) | Throughput (rps) |
|---|---|---|---|---|---|---|
| **Homa** | concurrency=8 | 105 | **740** | **1,201** | **1,626** | 39,345 |
| TCP | single-stream | **79** | 187 | 255 | 335 | 9,733 |
| TCP | pool=32, size-aware | 236 | 525 | 694 | 966 | 69,720 |
| TCP+DCTCP | pool=32, size-aware | 233 | 541 | 712 | 1,014 | 86,641 |

**TCP pooled wins on tail latency here.** TCP pool=32 P99 is 694us vs Homa's 1,201us. Single-stream TCP has the best latency overall (P99=255us) but at 7x lower throughput. With moderate (64KB) large messages, TCP pooling effectively isolates HoL blocking without saturating bandwidth.

### 1c. Pareto Heavy-Tail

| Protocol | Config | P50 (us) | P95 (us) | P99 (us) | P99.9 (us) | Throughput (rps) |
|---|---|---|---|---|---|---|
| **Homa** | concurrency=8 | 163 | 257 | **318** | **531** | 43,613 |
| TCP | single-stream | **62** | 128 | 128 | 230 | 14,152 |
| TCP | pool=32, size-aware | 145 | 317 | 558 | 1,625 | 90,287 |

**Mixed.** Single-stream TCP has the best latency (P99=128us), but Homa is competitive (P99=318us) with 3x higher throughput. Pooled TCP has best throughput (90K rps) but worst tail (P99.9=1,625us vs Homa's 531us).

### 1d. Uniform Small (256B)

| Protocol | Config | P50 (us) | P95 (us) | P99 (us) | P99.9 (us) | Throughput (rps) |
|---|---|---|---|---|---|---|
| **Homa** | concurrency=8 | **77** | **210** | 233 | **283** | 63,908 |
| TCP | single-stream | 51 | 86 | **111** | 150 | 16,773 |
| TCP | pool=32 | 175 | 322 | 434 | 847 | 129,090 |

**TCP pool wins on throughput** (129K rps) and single-stream wins on latency (P99=111us). Homa sits in between — decent latency (P99=233us) with good throughput (64K rps). For uniform workloads with no HoL blocking, TCP is fully competitive.

### 1e. Fixed 1KB

| Protocol | Config | P50 (us) | P95 (us) | P99 (us) | P99.9 (us) | Throughput (rps) |
|---|---|---|---|---|---|---|
| **Homa** | concurrency=1 | 168 | 191 | 206 | **379** | 5,590 |
| TCP | single-stream | **59** | **86** | **116** | 208 | 14,661 |
| TCP | pool=16 | 133 | 274 | 274 | 377 | 95,299 |

**TCP wins.** For fixed-size messages, TCP single-stream has P50=59us vs Homa's 168us — Homa has higher base overhead from its connectionless design (each message requires a full ioctl roundtrip).

---

## 2. DCTCP/ECN Impact (Hypothesis 2)

| Workload | TCP P99 | DCTCP P99 | Change |
|---|---|---|---|
| Bimodal 1MB, pool=32 SA | 28,755 us | 32,055 us | +11% (worse) |
| Bimodal 64KB, pool=32 SA | 694 us | 712 us | +3% (negligible) |
| Pareto, pool=32 SA | 558 us | 506 us | -9% (slight improvement) |

**DCTCP provides minimal benefit at 4-sender incast.** At this scale, the bottleneck is message scheduling and bandwidth contention, not congestion-induced loss. Homa's grant-based flow control addresses a different problem (many-to-one scheduling), which DCTCP cannot replicate.

---

## 3. Configuration Overhead (Hypothesis 3)

### 3a. Pool Size vs Performance (Fixed 1KB)

| Pool | P50 (us) | P99 (us) | Throughput (rps) | Scaling Factor |
|---|---|---|---|---|
| 1 | 59 | 116 | 14,661 | 1.0x |
| 16 | 133 | 274 | 95,299 | 6.5x |
| 32 | 171 | 549 | 103,099 | 7.0x |
| 64 | 229 | 936 | 116,553 | 7.9x |

Pool=16 is the sweet spot: 6.5x throughput, 2.4x P99 increase. Beyond 32, diminishing returns.

### 3b. TCP_NODELAY: Critical Tuning Parameter

| Setting | P50 (us) | P99 (us) | P99.9 (us) | Throughput (rps) |
|---|---|---|---|---|
| NODELAY=ON | 52 | 111 | 152 | 16,806 |
| NODELAY=OFF | 76 | 278 | **44,218** | 1,868 |

Forgetting TCP_NODELAY causes **9x throughput drop** and **291x tail latency spike** (Nagle's 40ms batching). Validates Homa's argument that TCP requires expert tuning.

### 3c. Memory Overhead

| Pool Size | Connections | Memory Used | % of 64GB |
|---|---|---|---|
| 1 (×4 clients) | 4 | ~0 MB | 0.00% |
| 16 (×4 clients) | 64 | 7.3 MB | 0.01% |
| 32 (×4 clients) | 128 | 8.7 MB | 0.01% |
| 64 (×4 clients) | 256 | 20.5 MB | 0.03% |

Memory overhead is **negligible**. Even 256 connections use only 0.03% of server RAM.

### 3d. CPU Overhead

| Config | Client CPU |
|---|---|
| TCP pool=1, closed-loop | 2% |
| TCP pool=32, closed-loop | 17-38% |
| TCP pool=32, open-loop 10K rps | 4-7% |
| Homa concurrency=8 | 12-20% |

CPU tracks throughput, not connection count. Homa's CPU usage (12-20%) is comparable to TCP pooled.

---

## 4. Open-Loop (Realistic Load)

| Config | Rate | P50 (us) | P99 (us) | P99.9 (us) |
|---|---|---|---|---|
| TCP single, 5K rps | 4,571 | 96 | 286 | 398 |
| TCP pool=32 SA, 5K rps | 4,469 | 96 | 284 | 366 |
| TCP single, 10K rps | 9,157 | 80 | 252 | 368 |
| TCP pool=32 SA, 10K rps | 8,763 | 92 | 287 | 376 |

Under open-loop at moderate load, **pooling and single-stream are indistinguishable**. HoL blocking only manifests under saturation (closed-loop).

---

## 5. Final Verdict by Hypothesis

### H1: TCP pooling eliminates Homa's HoL blocking advantage

**DEPENDS ON MESSAGE SIZE.**
- 1MB large messages: **Homa wins by 108x** on P99. TCP pooling causes catastrophic bandwidth saturation. Even single-stream TCP can't compete with Homa here.
- 64KB large messages: **TCP pool wins** — P99 694us vs Homa's 1,201us. TCP pooling effectively isolates HoL at moderate message sizes.
- Uniform/Pareto: TCP single-stream has lowest latency; pooling trades latency for throughput.

### H2: DCTCP/ECN matches Homa's receiver-driven flow control

**NO.** DCTCP provides <10% improvement at 4-sender incast. It doesn't address the fundamental scheduling problem that Homa solves. Would need testing at 32-64 sender scale.

### H3: TCP configuration overhead is manageable

**YES, with critical caveats.**
- Memory/CPU overhead of pooling: negligible.
- BUT TCP_NODELAY misconfiguration causes 291x tail latency spike.
- Pool size requires tuning (16 optimal, 64 causes tail degradation).
- Homa works out-of-the-box with zero parameters — genuine operational advantage.

---

## 6. Key Takeaway

**Homa's advantages are real and largest for mixed-size workloads with extreme size variation (256B + 1MB).** TCP can compete with moderate size variation (64KB) and uniform workloads, but requires careful configuration. The ipSpace blog's argument that "TCP pooling solves HoL blocking" is only partially correct — it works for moderate message sizes but fails catastrophically when large messages saturate the link.

---

## Appendix: File Locations

| Item | Path |
|---|---|
| This document | `results/FINAL_RESULTS.md` |
| Raw TCP results | `results/exp01_*` through `results/exp24_*` |
| Raw Homa results | `results/homa_*` |
| Memory data | `results/mem_pool*` |
| Source code | `src/`, `include/dcbench/` |
| Experiment scripts | `cloudlab/run_from_mac.sh`, `cloudlab/run_homa.sh` |
| CloudLab profile | `cloudlab/profile.py` |

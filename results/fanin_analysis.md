# Fan-in Scaling Study: Analysis Summary

**Workload:** Bimodal (256B small / 1MB large, bimodal_ratio=0.9), closed-loop  
**Configs:** Homa (concurrency=8), TCP single-stream (pool=1), TCP DCTCP (pool=32, size-aware)  
**Fan-in levels:** 4, 8, 12 senders → 1 receiver

---

## 1. Latency Scaling

| Config         | Fan-in | P50 (µs) | P95 (µs) | P99 (µs) | P99.9 (µs) | Mean (µs) |
|----------------|--------|----------|----------|----------|------------|-----------|
| Homa           | 4      | 166.8    | 219.1    | 326.9    | 412.5      | 168.4     |
| Homa           | 8      | 167.3    | 211.1    | 323.6    | 409.4      | 169.6     |
| Homa           | 12     | 167.3    | 206.3    | 318.7    | 399.1      | 169.2     |
| TCP single     | 4      | 98.2     | 1,038    | 1,605    | 2,181      | 209.6     |
| TCP single     | 8      | 113.7    | 1,330    | 1,967    | 2,687      | 259.4     |
| TCP single     | 12     | 131.0    | 1,521    | 2,286    | 3,141      | 315.5     |
| TCP DCTCP-32   | 4      | 471.5    | 6,209    | 9,358    | 14,394     | 1,400     |
| TCP DCTCP-32   | 8      | 1,397.6  | 6,949    | 11,316   | 18,701     | 2,092     |
| TCP DCTCP-32   | 12     | 2,043.5  | 9,145    | 18,986   | 31,809     | 2,854     |

### Key observations

**Homa is stable under increasing incast.** P99 barely moves: 327 µs → 324 µs → 319 µs as fan-in grows from 4 to 12. Receiver-driven grant control absorbs the additional senders without queuing pressure growth.

**TCP single-stream tail scales with fan-in.** P99 grows from 1,605 µs (fi4) → 1,967 µs (fi8) → 2,286 µs (fi12), a 42% increase. The Homa-to-TCP P99 gap widens: 4.9× at fi4, 6.1× at fi8, 7.2× at fi12. TCP's sender-driven congestion response cannot coordinate across additional concurrent senders.

**DCTCP degrades catastrophically.** P99 goes 9,358 µs → 11,316 µs → 18,986 µs. At fi12, DCTCP P99 is 60× Homa P99 and 8.3× TCP single-stream P99. DCTCP with a large pool generates excessive concurrent flows; ECN marking under coordinated incast from 12 senders produces a feedback storm rather than a controlled response. This is a strong negative result for H2: DCTCP pooling fails worse than single-stream TCP as fan-in grows.

---

## 2. Fairness (Jain's Fairness Index)

| Config       | Fan-in | Jain   | CV    | Min/Max |
|--------------|--------|--------|-------|---------|
| Homa         | 4      | 0.9999 | 0.009 | 0.977   |
| Homa         | 8      | 0.9999 | 0.007 | 0.975   |
| Homa         | 12     | 1.0000 | 0.007 | 0.979   |
| TCP single   | 4      | 0.9996 | 0.019 | 0.954   |
| TCP single   | 8      | 0.9931 | 0.083 | 0.792   |
| TCP single   | 12     | 0.9847 | 0.125 | 0.658   |
| TCP DCTCP-32 | 4      | 0.9752 | 0.160 | 0.654   |
| TCP DCTCP-32 | 8      | 0.9367 | 0.260 | 0.473   |
| TCP DCTCP-32 | 12     | 0.8614 | 0.401 | 0.314   |

### Key observations

**Homa is near-perfectly fair at every fan-in level.** Jain index stays at ~1.000 regardless of sender count. CV remains at 0.007 across all levels — the grant mechanism distributes bandwidth uniformly across all senders.

**TCP single fairness degrades visibly with fan-in.** The Min/Max throughput ratio drops from 0.954 (fi4) to 0.658 (fi12): the slowest sender gets 34% less throughput than the fastest at 12 senders. This degradation is not visible in aggregate latency percentiles alone — fairness analysis reveals an additional structural penalty.

**DCTCP fairness collapses at scale.** By fi12, Jain index is 0.86 and Min/Max is 0.31 — the worst sender (client_8, 7,885 rps) gets less than a third the throughput of the best sender (client_0, 25,122 rps). DCTCP's per-flow ECN response does not equalize across senders; earlier senders that established flows before congestion built up sustain higher throughput, creating systematic unfairness.

---

## 3. Implication for H2

Both the latency and fairness results confirm the H2 conclusion from the baseline matrix: **DCTCP cannot substitute for Homa's receiver-driven grant control, and the gap widens with fan-in pressure.** TCP single-stream is a better choice than DCTCP pooling for incast scenarios — it loses on throughput but retains lower tail latency and better fairness.

---

## 4. Caveat: Homa Sample Counts

Each Homa client yields ~90,079 samples out of 100,000 requests (~90.1%), matching the 90% small-message fraction. This pattern matches the pre-fix behavior reported in Section 4.5.3, suggesting **the homa_server buffer fix was not yet deployed when these runs executed**. Large-message Homa latency is excluded from the measurements above. Homa latency figures reflect small (256B) messages only and should not be compared directly to TCP latency (which includes all message sizes) for the tail percentiles.

Rerun with the patched binary to capture full Homa behavior before including these figures in the final paper.

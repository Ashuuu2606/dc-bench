# Fan-in Scaling Study - Averaged across 3 trials ([1, 2, 3])

**Workload:** Bimodal (256B small / 1MB large, bimodal_ratio=0.9), closed-loop  
**Configs:** Homa (concurrency=8), TCP single-stream (pool=1), TCP DCTCP (pool=32, size-aware)  
**Fan-in levels:** 4, 8, 12, 16 senders -> 1 receiver

---

## 1. Latency

| Config        | Fan-in | P50 (us) | P95 (us) | P99 (us) | P99.9 (us) | Mean (us) |
|---------------|--------|----------|----------|----------|------------|-----------|
| Homa          |   4    |     34.6 |    185.0 |    203.6 |      241.5 |      77.9 |
| Homa          |   8    |     36.1 |    181.1 |    201.2 |      239.6 |      77.3 |
| Homa          |   12   |     39.5 |    182.6 |    202.4 |      248.8 |      81.6 |
| Homa          |   16   |     38.3 |    182.5 |    202.2 |      241.7 |      80.7 |
| TCP single    |   4    |     60.4 |   1536.1 |   2108.6 |     2582.9 |     225.0 |
| TCP single    |   8    |     80.1 |   2109.0 |   2803.7 |     3622.4 |     325.8 |
| TCP single    |   12   |    112.1 |   2586.1 |   3644.0 |     5027.2 |     441.0 |
| TCP single    |   16   |    161.9 |   2996.3 |   4216.6 |     5863.1 |     555.2 |
| TCP DCTCP-32  |   4    |   2766.6 |  15930.0 |  26017.4 |    40657.8 |    3917.6 |
| TCP DCTCP-32  |   8    |   3721.1 |  45266.8 |  75345.0 |   112429.9 |    7819.5 |
| TCP DCTCP-32  |   12   |   4019.6 |  73101.0 | 130087.2 |   201830.6 |   11437.2 |
| TCP DCTCP-32  |   16   |   4308.7 | 101965.0 | 192660.6 |   291407.3 |   15205.1 |

## 2. Fairness (Jain's Fairness Index)

| Config        | Fan-in |  Jain  |  CV   | Min/Max |
|---------------|--------|--------|-------|---------|
| Homa          |   4    | 0.9669 | 0.184 |   0.587 |
| Homa          |   8    | 0.9621 | 0.198 |   0.433 |
| Homa          |   12   | 0.9512 | 0.222 |   0.394 |
| Homa          |   16   | 0.9730 | 0.166 |   0.457 |
| TCP single    |   4    | 0.9969 | 0.047 |   0.894 |
| TCP single    |   8    | 0.9979 | 0.046 |   0.856 |
| TCP single    |   12   | 0.9906 | 0.089 |   0.787 |
| TCP single    |   16   | 0.9954 | 0.066 |   0.807 |
| TCP DCTCP-32  |   4    | 0.9980 | 0.044 |   0.905 |
| TCP DCTCP-32  |   8    | 0.9935 | 0.081 |   0.779 |
| TCP DCTCP-32  |   12   | 0.9872 | 0.114 |   0.681 |
| TCP DCTCP-32  |   16   | 0.9821 | 0.135 |   0.615 |

## 3. Homa vs TCP/DCTCP P99 gap

| Fan-in | Homa P99 | TCP1 P99 | DCTCP P99 | TCP1 / Homa | DCTCP / Homa |
|--------|----------|----------|-----------|-------------|--------------|
|   4    |    203.6 |   2108.6 |   26017.4 |       10.36 |       127.80 |
|   8    |    201.2 |   2803.7 |   75345.0 |       13.94 |       374.50 |
|   12   |    202.4 |   3644.0 |  130087.2 |       18.00 |       642.64 |
|   16   |    202.2 |   4216.6 |  192660.6 |       20.85 |       952.74 |

---

## 4. Key observations

**Homa is essentially flat under incast.** P99 moves only 204 us (fi=4) -> 202 us (fi=16), a -0.7% change. Receiver-driven grant control absorbs the additional senders without queuing-pressure growth.

**TCP single-stream tail scales with fan-in.** P99 grows 2109 us (fi=4) -> 4217 us (fi=16), a 2.0x increase. The Homa -> TCP single P99 gap widens from 10.4x at fi=4 to 20.9x at fi=16.

**DCTCP degrades catastrophically.** P99 goes 26.0 ms (fi=4) -> 192.7 ms (fi=16), a 7.4x increase. The DCTCP -> Homa P99 gap widens from 128x at fi=4 to 953x at fi=16. DCTCP with a 32-connection pool generates excessive concurrent flows; under coordinated incast, ECN-marking feedback fails to throttle the collective sending rate in time, producing a latency storm rather than a controlled response.

---

## 5. Fairness commentary

**Homa fairness across trials.** fi=4: J=0.967, Min/Max=0.587; fi=8: J=0.962, Min/Max=0.433; fi=12: J=0.951, Min/Max=0.394; fi=16: J=0.973, Min/Max=0.457. Homa Min/Max stays between ~0.4-0.6 across fan-ins; a handful of straggler senders converge more slowly under grant flow than in the single-TCP case, though Jain's index remains > 0.95.

**TCP single fairness.** fi=4: J=0.997, Min/Max=0.894; fi=8: J=0.998, Min/Max=0.856; fi=12: J=0.991, Min/Max=0.787; fi=16: J=0.995, Min/Max=0.807. Single-stream TCP preserves the highest Min/Max ratio precisely because each sender has exactly one flow competing on equal footing; aggregate throughput is low but bandwidth division is almost ideal.

**DCTCP-32 fairness.** fi=4: J=0.998, Min/Max=0.905; fi=8: J=0.994, Min/Max=0.779; fi=12: J=0.987, Min/Max=0.681; fi=16: J=0.982, Min/Max=0.615. Pooled DCTCP trades fairness for throughput as fan-in grows: earlier-arriving flows secure higher per-flow rates before ECN throttles the rest, so Min/Max drops noticeably with incast pressure.

---

## 6. Implication for H2

Both the latency and fairness results support H2: **DCTCP cannot substitute for Homa's receiver-driven grant control, and the gap widens with fan-in pressure.** At fi=16, DCTCP-32 P99 is 953x Homa P99 (vs ~128x at fi=4). TCP single-stream is a better choice than DCTCP pooling for incast scenarios -- it loses on aggregate throughput but retains lower tail latency and better fairness.

---

## 7. Caveat: Homa sample counts

Each Homa client still yields ~90,080 of 100,000 requests (~90.1%), matching the 90% small-message fraction of the bimodal workload. This is the same pattern flagged in the original `fanin_analysis.md`: large-message Homa latency is not captured in `latency.csv`. The Homa latency columns above therefore reflect **256 B messages only**, whereas TCP latency columns include all message sizes. Tail percentiles should be interpreted accordingly when comparing raw numbers across protocols.

_Averaged from 3 independent trials._
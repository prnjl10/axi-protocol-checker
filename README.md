# AXI4 Protocol Compliance Checker (PYNQ-Z2)

> A synthesizable, non-intrusive AXI4 protocol checker that monitors a live bus in
> FPGA fabric, classifies and timestamps violations, and streams protocol health to
> a Jupyter dashboard on the Zynq PS.

![status](https://img.shields.io/badge/status-in--development-yellow)
![platform](https://img.shields.io/badge/platform-PYNQ--Z2%20(Zynq--7020)-blue)
![license](https://img.shields.io/badge/license-MIT-green)

## Overview

AXI4 protocol violations (bad handshakes, illegal bursts, ID/ordering errors)
usually surface as hangs or silent data corruption far from their root cause.
This project builds a passive, synthesizable checker that watches an AXI interface
in the programmable logic, reports each violation to software with a type and
timestamp, and visualizes protocol health live. Every check is traced to a clause
of the AMBA AXI4 specification and proven against deliberately injected faults.

Full design rationale and methodology: `docs/proposal.pdf`.

## Architecture

```
+----------------- Programmable Logic (PL) -----------------+
|  Rogue AXI master ==== monitored bus ====> AXI slave       |
|  (legal + fault)  <===================== (BRAM/DDR, DMA)   |
|         | read-only tap                                    |
|         v                                                  |
|  AXI checker core  (monitors + ID tracker + classifier)    |
|         | events {id, type, timestamp}                     |
|         v                                                  |
|  CSR + event FIFO  ---- AXI4-Lite + IRQ ----+              |
+---------------------------------------------|--------------+
                                              v
                              ARM PS  (PYNQ + Jupyter dashboard)
```

The checker has **no outputs driving the bus** - attaching it cannot perturb traffic.

## Scope & versioning

Versioning has two axes, and every milestone runs entirely in the programmable logic (PL):

- **Protocol depth** - how much AXI the checker understands: **v1 (AXI4-Lite) -> v2 (full AXI4)**.
- **Maturity stage** - what machinery sits on top of the checker: **Stage 0 (checker) -> Stage 1 (reporting acceleration) -> Stage 2 (in-fabric analytics)**.

### Protocol depth

**v1 - AXI4-Lite (checks C01-C09).** Handshake/stability, reset, response-code
checks, write-strobe, address alignment, single-transaction ordering. Traffic
from the configurable rogue master. C04 is an X/unknown design-integrity check
(simulation-only); C05 covers EXOKAY legality on Lite.

**v2 - Full AXI4 (checks C10-C20).** Burst legality (4 KB boundary, burst type,
WRAP length, AxSIZE), data-phase beat counting (WLAST/RLAST), ID matching, per-ID
ordering, outstanding-transaction tracking. Adds an AXI DMA engine for realistic
burst traffic.

Check list and clause mapping: `docs/traceability_matrix.md`.

### Maturity stages (applied to each depth)

- **Stage 0 - checker:** detection, classification, timestamping, basic reporting, live Jupyter dashboard.
- **Stage 1 - reporting acceleration:** deep event FIFO, on-chip timestamping, per-type counters/summaries so events survive a violation storm at line rate.
- **Stage 2 - in-fabric analytics:** latency distributions, statistical protocol health, cross-channel / per-ID correlation.

The Stage 1/2 observability core is protocol-agnostic - built once for v1 and re-pointed at v2.

**Out of scope:** ACE/CHI, AXI3 write-data interleaving, active fault
recovery/regulation, full exclusive-access verification.

## Methodology

Each check follows the same path: **AXI4 spec clause -> SVA (simulation oracle,
bound to the bus) -> synthesizable RTL monitor**, graded against the Xilinx AXI
VIP in passthrough monitor mode as an independent reference. Every check is
clause-traceable and exercised by a fault-injection benchmark, and is tested
*both* ways - it must fire on injected faults and stay silent on compliant traffic
(a false positive is treated as seriously as a miss).

Most checks exist in two forms (SVA + synthesizable RTL). C04 is
simulation-only, since X values do not exist in synthesized hardware.

## Repository layout

| Path | Contents |
|------|----------|
| `rtl/checker/`      | axi_checker_core, per-channel monitors, classifier |
| `rtl/rogue_master/` | configurable fault-injecting AXI master |
| `rtl/common/`       | shared packages / parameters |
| `sva/`              | SVA reference assertions (sim cross-check) |
| `sim/`              | testbenches, xsim run scripts, AXI VIP oracle setup |
| `pynq/`             | overlay (.bit/.hwh) + Jupyter dashboard notebooks |
| `vivado/`           | block design / project Tcl |
| `docs/`             | proposal, traceability matrix, coverage report |

## Roadmap

Six milestones across the two axes (**v1.0 -> v1.1 -> v1.2 -> v2.0 -> v2.1 -> v2.2**):

- [ ] **v1.0** - AXI4-Lite checker (C01-C09), on board + live dashboard
  - [ ] Clause-traceability matrix (C01-C09)
  - [ ] Rogue master (AXI4-Lite) + fault modes (incl. rogue-slave mode for C07/C08)
  - [ ] Checker monitors (C01-C09) + SVA + sim coverage vs AXI VIP oracle
  - [ ] CSR + event FIFO + PS integration + Jupyter dashboard
- [ ] **v1.1** - reporting acceleration (deep FIFO, on-chip timestamps, per-type counters)
- [ ] **v1.2** - in-fabric analytics (latency distributions, protocol-health stats)
- [ ] **v2.0** - full AXI4 checker (C10-C20) + outstanding-ID tracker + AXI DMA traffic
- [ ] **v2.1** - reporting acceleration re-pointed at full-AXI4 events
- [ ] **v2.2** - per-ID / burst analytics

## License

MIT - see `LICENSE`.

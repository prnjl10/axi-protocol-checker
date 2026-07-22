# AXI4 Protocol Compliance Checker (PYNQ-Z2)

> A synthesizable, non-intrusive AXI4 protocol checker that monitors a live bus in
> FPGA fabric, classifies and timestamps violations, and streams protocol health to
> a Jupyter dashboard on the Zynq PS.

![status](https://img.shields.io/badge/v1.0-working%20on%20hardware-brightgreen)
![platform](https://img.shields.io/badge/platform-PYNQ--Z2%20(Zynq--7020)-blue)
![license](https://img.shields.io/badge/license-MIT-green)

## Status: v1.0 running on hardware

The AXI4-Lite checker is implemented, verified in simulation, and **running on a
PYNQ-Z2**. Faults are injected from Python, caught in fabric at line rate,
timestamped, and displayed live in a Jupyter dashboard.

| Metric | Result |
|---|---|
| Checks implemented | 7 synthesizable (C01–C03, C05, C07–C09) + C04 sim-only |
| Detection | every injected fault caught, correctly classified |
| False positives | none on compliant traffic |
| Utilization | ~1% LUT, ~1% FF, 0 BRAM, 0 DSP (XC7Z020) |
| Timing | WNS **+10.85 ns** at 50 MHz — implied Fmax ≈ 109 MHz |
| Sim vs hardware | identical event sequence and cycle spacing |

## Overview

AXI4 protocol violations (bad handshakes, illegal bursts, ID/ordering errors)
usually surface as hangs or silent data corruption far from their root cause.
This project builds a passive, synthesizable checker that watches an AXI interface
in the programmable logic, reports each violation to software with a type and
timestamp, and visualizes protocol health live. Every check is traced to a clause
of the AMBA AXI4 specification and proven against deliberately injected faults.

Full design rationale and methodology: `docs/proposal.pdf`.
Clause mapping and per-check status: `docs/traceability_matrix.md`.

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

### Implemented blocks (v1.0)

| Module | Role |
|---|---|
| `axi_handshake_monitor` | C01/C02 - instantiated once per channel (5x) |
| `axi_lite_comb_checks`  | C03/C05/C09 - combinational checks |
| `axi_ordering_monitor`  | C07/C08 - stateful scoreboard |
| `axi_checker_core`      | integrates all monitors into one 15-bit violation vector |
| `axi_event_fifo`        | edge-detects, timestamps, and buffers violations |
| `axi_lite_csr`          | AXI4-Lite slave - PS-facing register interface |
| `rogue_master`          | fault-injecting AXI4-Lite master (6 modes) |
| `axi_checker_top`       | top-level wrapper packaged as IP |

## Results

**Fault injection.** The rogue master supports six modes selectable at runtime from
Python: legal traffic, C01 retraction on AW and on W, C02 payload mutation on AW and
on W, and C09 misaligned address. Each mode perturbs exactly one rule while keeping
the rest of the transaction compliant.

**Detection.** Every armed fault produced its expected violation on the correct
channel-specific bit, with no cross-talk and no firing on legal traffic.

**Hardware matches simulation.** The same 7-event sequence appears in `xsim` and on
the board, with identical intra-transaction cycle spacing (16 cycles between repeated
retractions). Inter-transaction gaps differ only because software polling is slower
than simulation - hardware timestamps remain cycle-accurate regardless.

**Known limitation.** The event timestamp counter is 32 bits at 50 MHz, so it wraps
every ~86 s. The dashboard tracks wraps in software; widening `TS_W` is a v1.1 fix.

## Scope & versioning

Versioning has two axes, and every milestone runs entirely in the programmable logic (PL):

- **Protocol depth** - how much AXI the checker understands: **v1 (AXI4-Lite) -> v2 (full AXI4)**.
- **Maturity stage** - what machinery sits on top of the checker: **Stage 0 (checker) -> Stage 1 (reporting acceleration) -> Stage 2 (in-fabric analytics)**.

### Protocol depth

**v1 - AXI4-Lite (checks C01-C09).** Handshake/stability, reset, response-code
checks, address alignment, single-transaction ordering. Traffic from the
configurable rogue master. Two checks are scoped out of v1 by Lite's own
constraints: C04 becomes an X/unknown design-integrity check (simulation-only,
since AXI4 defines all four RESP encodings and leaves none reserved), and C06
(write-strobe legality) is deferred to v2, where AxSIZE and the address make
strobe checking falsifiable. C05 covers EXOKAY legality on Lite.

**v2 - Full AXI4 (checks C06, C10-C20).** Write-strobe legality (C06, deferred
from v1), burst legality (4 KB boundary, burst type, WRAP length, AxSIZE),
data-phase beat counting (WLAST/RLAST), ID matching, per-ID ordering,
outstanding-transaction tracking. Adds an AXI DMA engine for realistic burst
traffic.

### Maturity stages (applied to each depth)

- **Stage 0 - checker:** detection, classification, timestamping, basic reporting, live Jupyter dashboard.
- **Stage 1 - reporting acceleration:** deep event FIFO, on-chip timestamping, per-type counters/summaries so events survive a violation storm at line rate.
- **Stage 2 - in-fabric analytics:** latency distributions, statistical protocol health, cross-channel / per-ID correlation.

The Stage 1/2 observability core is protocol-agnostic - built once for v1 and re-pointed at v2.

**Out of scope:** ACE/CHI, AXI3 write-data interleaving, active fault
recovery/regulation, full exclusive-access verification.

## Methodology

Each check follows the same path: **AXI4 spec clause -> SVA (simulation oracle,
bound to the bus) -> synthesizable RTL monitor**, cross-validated in `xsim`. Every
check is clause-traceable and exercised by a fault-injection benchmark, and is
tested *both* ways - it must fire on injected faults and stay silent on compliant
traffic (a false positive is treated as seriously as a miss).

Most checks exist in two forms (SVA + synthesizable RTL). C04 is
simulation-only, since X values do not exist in synthesized hardware.

Two findings worth noting, both surfaced by the hand-translation from SVA to RTL:
- SVA's preponed sampling handles same-cycle timing for free; hand-written RTL sees
  live wires and needs explicit bypass logic (`aw_ok = aw_done || (AWVALID && AWREADY)`)
  to avoid false positives on a legal fast slave.
- Translating C02 exposed a classification ambiguity the SVA had quietly dodged: a
  retraction also mutates the payload, tripping both checks. Both representations
  were corrected so each check reports a distinct violation.

## Repository layout

| Path | Contents |
|------|----------|
| `rtl/checker/`      | checker core, per-channel monitors, event FIFO, CSR, top |
| `rtl/rogue_master/` | configurable fault-injecting AXI master |
| `rtl/common/`       | shared package (violation bit map) |
| `sim/tb/`           | per-module and system-level testbenches |
| `pynq/overlay/`     | bitstream (`.bit`) + hardware handoff (`.hwh`) |
| `pynq/notebooks/`   | Jupyter dashboard |
| `vivado/`           | Vivado project and packaged IP |
| `docs/`             | proposal, traceability matrix |

## Reproducing

**Simulation** (Vivado `xsim`, from the repo root):

```bash
xvlog -sv rtl/common/axi_checker_pkg.sv rtl/checker/*.sv rtl/rogue_master/*.sv sim/tb/tb_top.sv
xelab tb_top -debug typical
xsim tb_top -runall
```

**On hardware:** copy `pynq/overlay/axi_checker.{bit,hwh}` and
`pynq/notebooks/axi_checker_dashboard.ipynb` to the board, then run the notebook.

## Roadmap

Six milestones across the two axes (**v1.0 -> v1.1 -> v1.2 -> v2.0 -> v2.1 -> v2.2**):

- [x] **v1.0** - AXI4-Lite checker, on board + live dashboard
  - [x] Clause-traceability matrix
  - [x] Rogue master + fault modes
  - [x] Checker monitors + SVA + cross-validation in xsim
  - [x] CSR + event FIFO + PS integration + Jupyter dashboard
  - [ ] AXI VIP oracle, coverage report, demo video
- [ ] **v1.1** - reporting acceleration (deep FIFO, wider timestamps, per-type counters)
- [ ] **v1.2** - in-fabric analytics (latency distributions, protocol-health stats)
- [ ] **v2.0** - full AXI4 checker (C06, C10-C20) + outstanding-ID tracker + AXI DMA traffic
- [ ] **v2.1** - reporting acceleration re-pointed at full-AXI4 events
- [ ] **v2.2** - per-ID / burst analytics

## License

MIT - see `LICENSE`.

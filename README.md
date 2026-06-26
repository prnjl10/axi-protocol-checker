# AXI4 Protocol Compliance Checker (PYNQ-Z2)

> A synthesizable, non-intrusive AXI4 protocol checker that monitors a live bus in
> FPGA fabric, classifies and timestamps violations, and streams protocol health to
> a Jupyter dashboard on the Zynq PS. 

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

## Scope

### v1 - AXI4-Lite
Handshake/stability, reset, response-code legality, write-strobe, address
alignment, single-transaction ordering (checks **C01-C09**). Traffic from the
configurable rogue master. Target: on-board + live dashboard.

### v2 - Full AXI4
Burst legality (4 KB boundary, burst type, WRAP length, AxSIZE), data-phase beat
counting (WLAST/RLAST), ID matching, per-ID ordering, outstanding-transaction
tracking (checks **C10-C20**). Adds an AXI DMA engine for realistic burst traffic.

Check list and clause mapping: `docs/traceability_matrix.md`.

**Out of scope:** ACE/CHI, AXI3 write-data interleaving, active fault
recovery/regulation, full exclusive-access verification.

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

- [ ] Clause-traceability matrix (C01-C20)
- [ ] Rogue master (AXI4-Lite) + fault modes
- [ ] Checker v1 (C01-C09) + SVA + sim coverage
- [ ] CSR + PS integration + Jupyter dashboard (on-board v1)
- [ ] Full AXI4 checks (C10-C20) + outstanding-ID tracker
- [ ] AXI DMA realistic-traffic demo + combined coverage report

## License

MIT - see `LICENSE`.

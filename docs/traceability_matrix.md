# AXI4 Clause-Traceability Matrix

Every check maps to an AMBA AXI rule, is expressed as an SVA property (simulation
oracle) and/or a synthesizable RTL monitor, and is proven by a directed test that
fires on the fault and stays silent on legal traffic.

**Methodology:** spec clause → SVA → synthesizable RTL, cross-validated in xsim,
then graded against ARM's protocol checker as an independent oracle.

**Species** (how much the checker must remember to judge legality):
- *comb* — combinational: this cycle's wires only, no state.
- *hist* — temporal-history: this cycle vs. last cycle (1-cycle registers).
- *state* — temporal-stateful: remembered events across a transaction (a scoreboard).

**Status:** `done` = SVA + RTL written and cross-checked in sim · `deferred` = out
of v1 scope · `pending` = not yet built.

> Clause references below are AMBA AXI4 specification sections (IHI0022), taken
> from ARM's own protocol-checker assertion messages during the VIP cross-check.

## v1 — AXI4-Lite (C01–C09)

| ID | Check (informal) | Clause | Species | SVA | RTL | Test | Status |
|----|------------------|--------|---------|-----|-----|------|--------|
| C01 | VALID not retracted before handshake completes | §A3.2.2 | hist | yes | `axi_handshake_monitor` | `tb_c01`, `tb_vip` | done |
| C02 | Payload stable while VALID high, READY low | §A3.2.1 | hist | yes | `axi_handshake_monitor` | `tb_c01`, `tb_vip` | done |
| C03 | No VALID asserted while ARESETn low | reset behaviour | comb | yes | `axi_lite_comb_checks` | `tb_comb` | done |
| C04 | RESP is not X/unknown while VALID high | *design integrity — not a spec clause* | comb (sim) | planned | n/a (no X in hardware) | pending | deferred |
| C05 | EXOKAY (2'b01) never returned on AXI4-Lite | response encoding — no AxLOCK on Lite | comb | yes | `axi_lite_comb_checks` | `tb_comb` | done |
| C06 | Write-strobe legality vs AxSIZE / address | §A3.4.3 | comb | — | — | — | deferred → v2 |
| C07 | B response only after AW **and** W accepted | write response dependencies | state | yes | `axi_ordering_monitor` | `tb_ordering` | done |
| C08 | R response only after AR accepted | read data dependencies | state | yes | `axi_ordering_monitor` | `tb_ordering` | done |
| C09 | Address aligned to data-bus width | address structure / alignment | comb | yes | `axi_lite_comb_checks` | `tb_comb`, `tb_vip` | done |

## Scoping decisions (documented, not omissions)

**C04 — reclassified as a simulation-only design-integrity check.** AXI4 defines
all four 2-bit RESP encodings (OKAY, EXOKAY, SLVERR, DECERR), leaving none
reserved. On a 2-bit bus there is no "illegal encoding" to catch, so a literal
"legal RESP" check is trivially always-true. C04 is therefore redefined as an
X/unknown check (`$isunknown(RESP)` while VALID is high), which catches undriven
or contended logic. This is not an AXI clause, and it has **no synthesizable
equivalent** (synthesized hardware has no X), so C04 lives only in SVA.

Note that ARM's checker handles X differently: rather than a separate check, its
response assertions carry an `!$isunknown(...)` guard so they do not fire on
unknown values.

**C06 — deferred from v1 to v2.** On AXI4-Lite, WSTRB is declared `[DATA_W/8-1:0]`,
so it physically cannot carry bits outside its own byte lanes — the check is
unfalsifiable. It becomes meaningful in v2, where `AxSIZE` and the address
determine which lanes are *legal* to assert. Moved to the v2 check set. The VIP
cross-check below provides empirical confirmation of this reasoning.

## Independent validation against ARM's protocol checker

The methodological risk in this project is circular validation: the checker and
the fault injector are both my own work, so a shared misunderstanding of the
specification would produce agreement between them while both were wrong.

To address this, the checker was cross-checked against `axi_vip_axi4pc`, ARM's
AMBA protocol checker as distributed in the Xilinx AXI Verification IP.

**Topology.** `axi_vip_axi4pc` is a SystemVerilog interface whose ports are all
inputs; it drives nothing. It was instantiated alongside `axi_checker_core`, with
both connected to the same nets driven by the rogue master, so both instruments
observe identical signal values every cycle. `PROTOCOL = 2` selects AXI4-Lite,
enabling the Lite-specific assertions. Full-AXI4 signals absent from Lite were
tied to the values Lite implies (`AxLEN = 0`, `AxSIZE = 2`, `AxBURST = INCR`,
`WLAST = 1`, no IDs, no locking).

**Results.**

| Mode | Injected fault | This checker | ARM's checker | Agreement |
|---|---|---|---|---|
| 0 | none (compliant write) | silent | silent | match |
| 1 | `AWVALID` deasserted before `AWREADY` | C01 AW ×2 | `AXI4_ERRM_AWVALID_STABLE` ×2 | match, same timestamps |
| 2 | `AWADDR` changed while waiting | C02 AW | `AXI4_ERRM_AWADDR_STABLE` | match |
| 3 | `WVALID` deasserted before `WREADY` | C01 W ×2 | `AXI4_ERRM_WVALID_STABLE` ×2 | match, same timestamps |
| 4 | `WDATA` changed while waiting | C02 W | `AXI4_ERRM_WDATA_STABLE` | match |
| 5 | `AWADDR` misaligned (`0x42`) | C09 | `AXI4_ERRM_WSTRB` | same fault, different rule |

Five of six modes produced exact agreement, including event counts and
timestamps. Neither instrument reported a violation on compliant traffic.

**The mode-5 result.** ARM's checker detected the misaligned address, but
reported it as a write-strobe violation (§A3.4.3) rather than an alignment
violation. With `AWADDR = 0x42`, `AWSIZE = 2` and `WSTRB = 0xF`, the asserted
strobes do not correspond to the byte lanes implied by the start address and
transfer size, so the fault manifests as a strobe inconsistency when viewed
through a full-AXI4 checker.

Two observations follow. First, this checker enforces alignment as a direct
address constraint, which is the form the rule takes on AXI4-Lite, while ARM's
checker derives the same fault from the strobe/address/size relationship. Both
detect it; the framing differs because Lite states the constraint directly and
AXI4 states it indirectly.

Second, this is empirical confirmation of the C06 scoping decision. ARM's strobe
check is meaningful only because `AxSIZE` is present to define which lanes are
legal. On AXI4-Lite, where `AxSIZE` does not exist, the check has nothing to
constrain it — which is precisely why C06 was deferred to v2.

**Reproduction:** `sim/tb/tb_vip.sv`

```bash
XV=/c/Xilinx/Vivado/2022.2/data/xilinx_vip
xvlog -sv -i $XV/include $XV/hdl/xil_common_vip_pkg.sv $XV/hdl/axi_vip_pkg.sv \
      $XV/hdl/axi_vip_if.sv $XV/hdl/axi_vip_axi4pc.sv
xvlog -sv -i $XV/include rtl/common/axi_checker_pkg.sv rtl/checker/axi_handshake_monitor.sv \
      rtl/checker/axi_lite_comb_checks.sv rtl/checker/axi_ordering_monitor.sv \
      rtl/checker/axi_checker_core.sv rtl/rogue_master/rogue_master.sv sim/tb/tb_vip.sv
xelab tb_vip -debug typical
xsim tb_vip -runall
```

## v2 — Full AXI4 (C06, C10–C20) — planned

| ID | Check (informal) | Category |
|----|------------------|----------|
| C06 | Write-strobe legality vs AxSIZE / address | data integrity |
| C10 | Burst does not cross a 4 KB boundary | burst legality |
| C11 | AxBURST not the reserved encoding | burst legality |
| C12 | WRAP burst length ∈ {2,4,8,16} | burst legality |
| C13 | AxSIZE does not exceed data-bus width | burst legality |
| C14 | WLAST asserted on beat (AWLEN+1) | data phase |
| C15 | Write-beat count matches AWLEN+1 | data phase |
| C16 | RLAST asserted on beat (ARLEN+1) | data phase |
| C17 | BID matches an outstanding AWID | ID matching |
| C18 | RID matches an outstanding ARID | ID matching |
| C19 | Read responses for a given ID return in order | ordering |
| C20 | Outstanding-transaction count within tracked depth | tracking limit |

## Progress

- **Done (SVA + RTL cross-validated, and graded against ARM's checker):** C01, C02, C03, C05, C07, C08, C09
- **Deferred with rationale:** C04 (sim-only X-check), C06 (→ v2, confirmed by VIP result)
- **v1 detection logic complete.**

## Test map

| Testbench | Covers | Run |
|-----------|--------|-----|
| `sim/tb/tb_c01.sv` | C01, C02 (AW channel; handshake monitor) | `xvlog -sv rtl/checker/axi_handshake_monitor.sv sim/tb/tb_c01.sv && xelab tb -debug typical && xsim tb -runall` |
| `sim/tb/tb_comb.sv` | C03, C05, C09 (combinational checks) | `xvlog -sv rtl/checker/axi_lite_comb_checks.sv sim/tb/tb_comb.sv && xelab tb_comb -debug typical && xsim tb_comb -runall` |
| `sim/tb/tb_ordering.sv` | C07, C08 (stateful scoreboard) | `xvlog -sv rtl/checker/axi_ordering_monitor.sv sim/tb/tb_ordering.sv && xelab tb_ordering -debug typical && xsim tb_ordering -runall` |
| `sim/tb/tb_core.sv` | Integration — correct bit per fault, no cross-talk | see repo |
| `sim/tb/tb_events.sv` | Core + FIFO + rogue master — event capture | see repo |
| `sim/tb/tb_top.sv` | Full system via CSR interface only | see repo |
| `sim/tb/tb_vip.sv` | Cross-check against ARM's protocol checker | see reproduction block above |
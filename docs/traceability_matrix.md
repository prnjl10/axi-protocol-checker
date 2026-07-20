# AXI4 Clause-Traceability Matrix

Every check maps to an AMBA AXI rule, is expressed as an SVA property (simulation
oracle) and/or a synthesizable RTL monitor, and is proven by a directed test that
fires on the fault and stays silent on legal traffic.

**Methodology:** spec clause → SVA → synthesizable RTL, cross-validated in xsim.
Most checks exist in both forms; exceptions are noted.

**Species** (how much the checker must remember to judge legality):
- *comb* — combinational: this cycle's wires only, no state.
- *hist* — temporal-history: this cycle vs. last cycle (1-cycle registers).
- *state* — temporal-stateful: remembered events across a transaction (a scoreboard).

**Status:** `done` = SVA + RTL written and cross-checked in sim · `partial` = RTL +
test done, SVA pending · `deferred` = out of v1 scope · `pending` = not yet built.

> Clause anchors below use the ARM protocol-assertion naming convention. Exact
> section numbers depend on the IHI0022 issue (D/E/F/G); fill your copy's numbers
> in the *Clause* column as you go.

## v1 — AXI4-Lite (C01–C09)

| ID | Check (informal) | Clause / rule anchor | Species | SVA | RTL | Test | Status |
|----|------------------|----------------------|---------|-----|-----|------|--------|
| C01 | VALID not retracted before handshake completes | Handshake process — `*VALID_STABLE` | hist | yes | `axi_handshake_monitor` | `tb_c01` | done |
| C02 | Payload stable while VALID high, READY low | Handshake process — `*ADDR/DATA_STABLE` | hist | yes | `axi_handshake_monitor` | `tb_c01` | done |
| C03 | No VALID asserted while ARESETn low | Reset — VALID low during reset | comb | yes | `axi_lite_comb_checks` | `tb_comb` | done |
| C04 | RESP is not X/unknown while VALID high | *design integrity — not a spec clause* | comb (sim) | planned | n/a (no X in hardware) | pending | deferred |
| C05 | EXOKAY (2'b01) never returned on AXI4-Lite | Response encoding — no AxLOCK on Lite | comb | yes | `axi_lite_comb_checks` | `tb_comb` | done |
| C06 | Write-strobe legality (WSTRB within legal lanes) | Write strobes — needs AxSIZE | comb | — | — | — | deferred → v2 |
| C07 | B response only after AW **and** W accepted | Write response dependencies | state | yes | axi_ordering_monitor | tb_ordering | done |
| C08 | R response only after AR accepted | Read data dependencies | state | yes | axi_ordering_monitor | tb_ordering | done |
| C09 | Address aligned to data-bus width | Address structure / alignment | comb | yes | `axi_lite_comb_checks` | `tb_comb` | done |

## Scoping decisions (documented, not omissions)

**C04 — reclassified as a simulation-only design-integrity check.** AXI4 defines
all four 2-bit RESP encodings (OKAY, EXOKAY, SLVERR, DECERR), leaving none
reserved. On a 2-bit bus there is no "illegal encoding" to catch, so a literal
"legal RESP" check is trivially always-true. C04 is therefore redefined as an
X/unknown check (`$isunknown(RESP)` while VALID is high), which catches undriven
or contended logic. This is not an AXI clause, and it has **no synthesizable
equivalent** (synthesized hardware has no X), so C04 lives only in SVA.

**C06 — deferred from v1 to v2.** On AXI4-Lite, WSTRB is declared `[DATA_W/8-1:0]`,
so it physically cannot carry bits outside its own byte lanes — the check is
unfalsifiable. It becomes meaningful in v2, where `AxSIZE` and the address
determine which lanes are *legal* to assert. Moved to the v2 check set.

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

- **Done (SVA + RTL cross-validated):** C01, C02, C03, C05, C09
- **Deferred with rationale:** C04 (sim-only X-check), C06 (→ v2)
- **Pending:** C07, C08 (stateful ordering — the last v1 engineering)

## Test map

| Testbench | Covers | Run |
|-----------|--------|-----|
| `sim/tb/tb_c01.sv`  | C01, C02 (AW channel; handshake monitor) | `xvlog -sv rtl/checker/axi_handshake_monitor.sv sim/tb/tb_c01.sv && xelab tb -debug typical && xsim tb -runall` |
| `sim/tb/tb_comb.sv` | C03, C05, C09 (combinational checks) | `xvlog -sv rtl/checker/axi_lite_comb_checks.sv sim/tb/tb_comb.sv && xelab tb_comb -debug typical && xsim tb_comb -runall` |
# LoongArch64 guest-SP residency: rejected experiment, 2026-09-13

Status: **rejected and not deployed**. Cross-region SP residency did not meet
the performance gate and has been withdrawn. The `$a7` SP convention, its three
refresh loads, the early-load experiment, explicit exit alignment, and the
later MOV-alias fast path are all absent from the current production candidate.
The `$a6` diagnostic was never a correct SP-residency implementation.

This is a historical research record. All SP-residency ABI descriptions, test
counts, binaries and timings below belong to discarded experimental revisions.
The `candidate-final` revision passed 195/195 device tests and built successfully,
but its matching-phase comparison still reproduced regressions. The word
`final` in artifact names does not mean accepted or deployed.

The smaller current `lite-only` candidate restores the baseline runtime file
and SP cache selection. It retains only SP immediate operand improvements and
redundant-branch removal. The intervening `stack-exit` revision passed 190/190
tests but also failed its targeted performance gate, so direct outside-residence
stores were withdrawn. [The current candidate report](BERBERIS_STACK_MEMORY.md)
records that revision's separate build, 190-test pass and successful complete
23-scenario, five-pair gate. That smaller revision was subsequently deployed;
the SP-residency experiments remain rejected and were never deployed. No
game-loading gain was measured.

Workspace evidence: `logs/jit-sp-residency-20260913/`. The source baseline is
binary_translation commit `aad4bb6127918b3e6ec7974a1e234c775afdd74d`, with library
SHA-256 `c2183d42f05ed207619f9b5e8291ab75b9f58df7ccc0e5897021147cd70f16c4`.
The baseline is the fifth-batch library described in
[the SIMD fallback report](BERBERIS_SIMD_FALLBACKS.md).

## Workload evidence

The user-delimited loading capture is
`logs/jkchess-match-simd-fallback-20260913-180302/`. Its requested window is
228.368476 seconds; 229 telemetry points actually cover 228.053434 seconds.
The Unity main thread is host TID **7579**, Android TID **5001**, startticks
**27871**, within host PID 7511 / Android PID 4933. Other threads temporarily
share the UnityMain name, so attribution uses thread identity rather than comm.

The main thread consumes 197.26 CPU seconds by `/proc/.../stat` and
197.253362 seconds by `schedstat`, with only 3.730257 seconds waiting in the
run queue. In the 81.020–117.028 second interval it runs for 99.77% of wall time,
while all 36 interval-start GPU readings are zero and process-attributed storage
reads total 0.91 MiB. Other intervals include resource reading and GPU activity;
the whole capture is not a single uniform application phase.

Offline LoongArch instruction decoding attributes **5.3918%** of the main
thread's sampled user-cycle weight to guest-SP loads from ThreadState, including
**5.0021%** to SP loads into the region-local GPR cache. These are subsets of
ThreadState-read weight and must not be added to it. They motivate removing
repeat SP loads across generated-region dispatch, without deferring state writes.

These percentages are sampled `cycles:u` period weights, not instruction counts,
cache-miss measurements, directly removable cost, or predicted loading gains.
The code-word snapshot was read about 141.762 seconds after sampling stopped;
matching mappings do not prove that every byte was unchanged throughout sampling.
PMU skid can also attribute a preceding stall to a subsequent instruction. See
`telemetry-analysis.json`, `telemetry-report.md`, `instruction-analysis.json`,
and `instruction-analysis.md` in the capture directory for input hashes and limits.

## Rejected generated-code ABI and state consistency

The experimental LoongArch generated-code ABI reserved **`$a7` / r11 for guest SP**,
alongside `$s8` for ThreadState and `$s7` for guest PC. This is an internal
generated-code convention. `$a7` remains caller-saved under the native C/C++ ABI;
native helpers may clobber it. The existing 96-byte native entry frame is unchanged.

`ReadXOrSp(31)` directly returned `$a7` in both Lite translation modes,
including `enable_reg_mapping=false`. `StoreXOrSp(31)` first wrote the complete
architectural value to `ThreadState.cpu.sp`, then updated `$a7`. This protocol
allowed direct and indirect dispatch to chain mapped and unmapped regions
without reloading SP at each region entry. Interpreter execution continued to
update ThreadState; its generated continuation refreshed the resident copy.

The experiment added three refresh points to `runtime/runtime_library_loongarch64.cc`:

| Entry or continuation | Refresh timing |
| --- | --- |
| `berberis_RunGeneratedCode` | Load SP from ThreadState after frame stores and the guest-PC load, before marking residence inside generated code |
| `berberis_entry_Interpret` | Reload after both `berberis_HandleInterpret` and the final `berberis_GetDispatchAddress` call |
| `berberis_entry_WrappedHostCall` | Reload after both `berberis_RunHostCallFromGuest` and the final `berberis_GetDispatchAddress` call |

The continuation reload must follow the **last C++ call**, since either helper
may clobber a caller-saved register, and an interpreter, native trampoline, nested
guest callback, or signal path may change architectural SP. Entries that unwind
back to C++ use the next `berberis_RunGeneratedCode` entry to refresh it.

The archived `candidate-final` entry used the original **late load**. Earlier
load scheduling and explicit exit alignment were separate experiments. The
current production candidate removes the SP load entirely and restores the
baseline native entry; none of these residency schedules is retained.

ThreadState remains authoritative at instruction boundaries. Signal polling and
fault recovery do not need a deferred SP flush. A memory instruction's pre/post
index writeback still happens only after its required memory operations succeed;
a preceding completed SP update remains visible if that instruction faults.
TBI masks the temporary effective address, preserving the tagged architectural SP.
Existing WSP zero-extension and SP-versus-XZR semantics remain in force.

The experiment excluded SP from dynamic GPR-cache selection and load scheduling,
leaving all seven `$s0`–`$s6` slots for x0–x30. The current source restores the
baseline selection over x0–x30 and SP; SP can again occupy a region-local slot.
There is no new `$a7` contract for future tiers or helpers.

Non-flag-setting ADD/SUB immediates in the experiment consumed `$a7` directly.
The operand improvement survives separately using the baseline region-local
SP cache, with the result in a temporary and the existing write-through store.
It no longer depends on any resident register at runtime boundaries.

## Removal of branches to the next instruction

The same candidate removes **16 emitter sites** that generated an unconditional
`B +4` to the immediately following `done` label. These became redundant after
memory-fault recovery exits moved out of the hot instruction bodies. Each such
emission previously added one four-byte host branch; 16 refers to source emission
sites, not the number of executed branches or a fixed whole-program size saving.

The sites cover scalar/vector memory helpers, pairs, tag-zeroing, exclusive
accesses and atomics. Required conditional branches and shared join labels remain;
the final fallthrough no longer branches to itself. Recovery points, memory
access ordering, barriers, reservation-state updates, and architectural writeback
ordering retain their prior semantics. Existing memory, exclusive, atomic and
fault tests remain part of the required correctness gate.

SP residency and redundant-branch removal are separate mechanisms in the same
candidate. Gains in general memory scenarios cannot be assigned entirely to SP
residency without a separately isolated comparison.

## Added correctness coverage

Six experimental tests in `runtime/arm64/runtime_library_loongarch64_test.cc`
exercised actual generated code and runtime boundaries. All six passed in the
**195/195** device suite (`final-device/correctness.log`, 3215 ms), including
1680 immediate-boundary differential executions in the sixth added case.

| Test suffix under `LoongArch64RuntimeLibraryTest` | Coverage |
| --- | --- |
| `LiteResidentSpDispatchesAcrossRegisterMappingModes` | Direct/indirect cached dispatch; all four source/target mapping combinations; pending-signal exit; changed SP on reentry |
| `LiteResidentSpRefreshesAfterRealInterpreterDispatch` | Actual `kEntryInterpret` execution changes SP, takes a non-sequential branch, and resumes a cached Lite region |
| `LiteResidentSpRefreshesAfterWrappedHostCallAndReentry` | Actual registered host trampoline changes SP and deliberately clobbers `$a7`; optional nested generated execution; pending return and reentry with another SP |
| `LiteResidentSpNeedsNoRegionReloadOrDynamicCacheSlot` | No emitted ThreadState SP load with mapping enabled or disabled; seven ordinary GPR cache slots remain usable |
| `LiteResidentSpImmediateSourcesMatchInterpreterAtBoundaries` | SP-source ADD/SUB boundaries, X/W widths, both mapping modes, SP and ordinary destinations; interpreter and independent modular-arithmetic checks |
| `LiteResidentSpCommitsBeforeFaultWithoutEarlyWriteback` | Real PROT_NONE load/store faults; handler checks ThreadState SP and ucontext r11 before executing the generated recovery entry |

Cached target regions have execution counters, proving they really ran as
generated code. The interpreter test caches both intermediate PCs and branches
non-sequentially, so it works with either cache-lookup policy and a one-instruction
fallback batch. The fault test checks both post-index load and pre-index store,
both mapping modes, the preceding completed SP update, unchanged faulting
instruction state, and the precise guest recovery PC.

The immediate case covers ADD and SUB, X/W widths, shifts 0 and 12, immediates
0, 1, 2047, 2048 and 4095, SP and ordinary destinations, and seven input values
including high-bit and modular-overflow cases. It compares all GPRs, SP, flags
and PC against the interpreter and checks results using independent arithmetic.
Existing WSP, tagged memory, zero-register, pending-signal, reentry and fault
assertions are preserved.

On withdrawal, the five tests dedicated to SP residency and their helpers were
removed. The original 189 tests were restored byte-for-byte; only the immediate
differential test remains, renamed
`LiteSpImmediateSourcesMatchInterpreterAtBoundaries`. The resulting 190-test
suite has separate runs for the reduced candidates, recorded in
[BERBERIS_STACK_MEMORY.md](BERBERIS_STACK_MEMORY.md).

## Sixteen-region benchmark

Two new benchmark names use the same 64 guest instructions split into sixteen
four-instruction regions:

```asm
add x0, sp, #32
add sp, sp, #16
sub sp, sp, #16
b next_region
```

`sp_region_chain` enables ordinary register mapping;
`sp_region_chain_unmapped` disables it. The first fifteen regions use actual
translation-cache dispatch, and only the final region returns to C++. All regions
are translated and installed before timed execution. Warm-up is untimed, and
generated byte counts include all sixteen regions. Timing is normalized by
64 executed guest instructions per iteration.

SP is balanced and never dereferenced. A fixed initial SP of `0x200000` makes
SP-derived checksums comparable across ASLR layouts. Completion checks require
the final guest PC, SP `0x200000`, and x0 `0x200020`. The scenario's terminal
`B next_region` performs real region dispatch; it is not one of the removed
redundant memory-helper `B +4` instructions.

The `candidate-final` comparison used the **same expanded benchmark harness**,
including `[[gnu::aligned(64)]]` on `RunBenchmark`. Its SHA-256 is
`720bdeb83d62caaa0a66f1bed29bc7719d039d1523dfa35f0cef28d24e2b917b`.
`baseline-loop-aligned.json` and `candidate-final-artifacts.json` record both
builds. Earlier same-harness records describe superseded experimental binaries.
Existing benchmark scenarios remain regression controls with the normal 3%
gate; improving only the new SP chains does not satisfy that gate.

`final-native-layout-audit.json` records those experimental binaries' address phases:

| Native location | Baseline address modulo 64 | Candidate address modulo 64 |
| --- | ---: | ---: |
| `RunBenchmark` | 0 | 0 |
| Timed loop | 32 | 32 |
| `berberis_RunGeneratedCode` | 32 | 32 |
| Runtime exit | 0 | 0 |

The timed loop spans 120 bytes at function offset `0x11e0`; only its call
displacement differs. Exit bytes match exactly. Entry instructions match in
order except for the additional late `ld.d $a7, $s8, 264` in the candidate.
Matching these phases controls one source of layout variation; it does not
equalize all generated-code or data placement.

The `candidate-final` run planned five alternating baseline/candidate pairs, with the
game absent, 20,000,000 iterations and CPU0 affinity. It was stopped after
reproducing logical/integer regressions. Raw completed and partial measurements
remain in `paired/final-no-game-ab-1/`; the stop reason is recorded in
`layout-controlled-stop.json`. There is no completed passing five-pair table
for this candidate.

The **three complete rounds** of that stopped run give the following diagnostic
medians. The eight records from the partial fourth round are excluded. Percent
changes use raw `elapsed_ns` medians; displayed ns/guest values are rounded.

| Scenario | Baseline ns/guest | Candidate ns/guest | Elapsed change | Host bytes before → after |
| --- | ---: | ---: | ---: | ---: |
| `sp_region_chain` | 0.9556 | 0.8820 | −7.71% | 1692 → 1436 |
| `sp_region_chain_unmapped` | 1.5743 | 0.8849 | −43.79% | 1500 → 1436 |
| `logical_cached` | 0.2890 | 0.3344 | +15.69% | 544 → 544 |
| `integer_w` | 0.2700 | 0.2863 | +6.06% | 800 → 800 |

Checksums match in these measurements. The SP-chain improvement and code-size
reduction do not cancel the regressions in the existing controls. The formal
five-round comparison was not reached; these partial-run statistics are not a
passing acceptance result.

These two artificial chains isolate repeated SP use across short regions more
closely than a single long-region benchmark. They still include dispatch and
native entry/exit costs, and do not reproduce a game's memory traffic, region
distribution or application dependencies. The extra SP load at a native entry
also applies to code that never reads SP, making non-SP controls necessary.
No game-loading speedup can be inferred from synthetic results alone.

## Historical candidate-final artifacts and validation

| Item | Historical result / evidence |
| --- | --- |
| Baseline provenance | Saved in `baseline.json`, `baseline/`, and `baseline-source/` |
| Baseline using the aligned expanded harness | `baseline-loop-aligned.json`, `baseline-loop-aligned-build.log` |
| Candidate source | `candidate-final-source/`, `candidate-final-source.diff`, `candidate-final-artifacts.json` |
| Candidate module build | Passed: library, device tests and microbenchmark; `candidate-final-build.log` (1m18s) |
| Six new tests and full correctness suite | 195/195 passed; `final-device/correctness.log` (3215 ms) |
| Host assembler checks | 20/20 passed; `host-assembler-tests.log` |
| Paired benchmark and regression gate | Not passed; latest run stopped with recurring regressions; `final-no-game-ab-1.log`, `layout-controlled-stop.json` |
| System/vendor image build | Passed with `-j8`; `final-images-build.log` (1m29s), `candidate-final-images.json` |
| Deployment, installed hash and rollback record | Not deployed; installed library remains baseline, verified in `device-before-paired.txt` |
| Subsequent user-delimited game capture | Not performed; experiment was not deployed |

Evidence paths are workspace build products, not source files to commit. The
`final` names identify this measurement revision, not acceptance. Failed
candidates and partial pairs remain available for investigation.

The additional full x86 host suite was stopped after slow WSL death-test
processing. `HostFunctionWrapperTest.WrapReturnedFunction` did pass after
131984 ms, and a later death test was still waiting when stopped. The host
uses the `wsl-capture-crash` piped core handler; the observed pipe waits suggest
core processing overhead but do not establish its exact source. This incomplete
1175-test run is neither a passing full suite nor a demonstrated translator
regression. Its log and termination record are retained. The relevant 20-test
LoongArch assembler filter completed separately.

| Artifact | SHA-256 |
| --- | --- |
| Candidate library | `0182aebc7212f2ef0a5ac5ea5486f66823c9fad3eedd492be96f0b07d14b62ce` |
| Baseline benchmark | `3ed26567c0bbebf83cd85ba522ad5b1e3a479b112a73f4b85d49c783986e954d` |
| Candidate benchmark | `8171df550354f470d233a8ff117fe33ec2a11c49f5bad18f97a84cf1e6e5b58d` |
| Candidate device tests | `77c99b09d8f8605a119e0da742165778a5514dd5ea3c2a388324215f8f553a12` |
| Candidate `system.img` | `72843d4e632ace3fd437c72051d5a552dbc3e461cec7910c3eb5b292e848e29d` |
| Candidate `vendor.img` | `673ad0de578670b693fc6e6c2563a3c8aa65e3fd3c5a06d6daa1a41d1fd11bb7` |

## Failed comparisons and diagnostic experiments

The initial no-game comparison completed five alternating pairs per scenario
at 20,000,000 iterations, pinned to CPU0 with user-cycle, instruction, branch
and branch-miss counters. Every checksum matched and each version generated
stable byte counts. The normal 3% gate rejected this first candidate:
`logical_cached` latency +16.88%, `integer_w` +6.54%, and
`sp_region_chain_unmapped` generated size +8.53%. All initial measurements
remain under `paired/no-game-ab-1/`; they are not the final accepted result.

The extra unmapped-region size came from SP copy/writeback overhead. Direct
SP-source ADD/SUB immediates remove the input copies while retaining
write-through. In the sixteen-region chain they remove three source-copy
instructions per region. The later comparisons show the size problem resolved,
while logical/integer latency regressions remain.

An independent binary-copy experiment moved only the native entry SP load,
preserving all bytes outside that function and all symbol addresses. Its
patched executable passed the then-current 194/194 tests. Against the initial
candidate, three paired rounds changed logical elapsed time by +0.45% and
integer time by +0.53%; early loading did not remedy either regression.
`early-sp-experiment/REPORT.md` records this isolated control. That historical
194-test result must not be confused with the later 195-test suite.

The following full-build comparisons were stopped once regressions repeated.
They use only complete rounds from each directory's `all-records.jsonl`, with
percent changes computed from raw elapsed-time medians:

| Revision | Complete rounds | Logical elapsed change | Integer elapsed change | Evidence under `paired/` |
| --- | ---: | ---: | ---: | --- |
| Refined SP immediates / early-load entry | 3 | +15.19% | +6.23% | `refined-no-game-ab-1/` |
| Explicit 64-byte exit alignment | 2 | +15.55% | +5.61% | `aligned-no-game-ab-1/` |
| Late entry load / same aligned benchmark harness | 3 | +15.69% | +6.06% | `final-no-game-ab-1/` |

These are not completed five-round gates. Partial next rounds are retained
but excluded above. The early-entry and explicit-exit-alignment changes were
withdrawn. Matching the latest native benchmark, loop, entry and exit phases
still did not remove the regressions, so loop layout alone is not an established
explanation. Actual generated-code and ThreadState placement require separate
inspection.

The one-word NOP control in `nop-sp-control/REPORT.md` replaced the initial
candidate's entry SP load with NOP while preserving every other file byte and
all addresses. Three paired rounds changed logical elapsed time by **−4.14%**,
integer time by **+1.16%**, and GPR time by **+11.65%**. This inconsistent response
does not establish a uniform fixed cost for the additional load or identify a
pipeline mechanism. NOP still executes an instruction; it is not a zero-cost
baseline. The modified copy lacks guest-SP correctness and was restricted to
three controls that do not access SP. It was never a deployable candidate and
did not run the full correctness suite or SP benchmarks.

Earlier attempts with the game running are preserved separately. The affinity
guardian aborted when a game thread restored its own CPU mask; restoration
left all independently changed masks intact. A later unisolated diagnostic
was interrupted after the user authorized exiting the game. Neither partial
run is included in the no-game gate.

## Subsequent controls and withdrawal

Replacing outside-residence marker sequences with direct `$zero` stores passed
195/195 tests while still using SP residency. Five paired rounds of three
targeted controls passed GPR (−7.70%) and integer (+0.40%), but logical remained
**+7.84%**, failing the 3% gate (`direct-residence-targeted.log`). This was not a
passing complete benchmark suite.

A later ORR/MOV-alias fast path passed 196/196 tests and reduced logical host
code size by 11.76%, yet logical elapsed time regressed **30.80%** against its
paired baseline (`mov-targeted.log`). That fast path and its test were reverted.
Fewer generated instructions did not establish lower latency in this control.

The one-byte destination-register control changed only the SP load's destination
from `$a7` to `$a6`. It did not materially improve logical or integer latency
(`a6-destination-control/REPORT.md`). As with the NOP control, it covered only
three non-SP scenarios and was explicitly not SP-correct or deployable. Its
historical suggestion to retain `$a7` was superseded by the withdrawal decision.

The scope was first reduced to three changes in the `stack-exit` revision.
Although it built and passed 190/190 tests, its targeted comparison regressed
logical latency by 30.34% and GPR latency by 30.73% (integer: +0.07%). The runtime
direct-zero change was then withdrawn; `runtime_library_loongarch64.cc` now
matches the baseline. The current `lite-only` build retains just SP immediate
operand improvements and 16 redundant-branch removals. It has built and passed
190/190 tests plus three targeted controls; the complete 23-scenario × five-pair
performance gate has passed for that separate revision. Artifact identities and results for those
two revisions are separated in [BERBERIS_STACK_MEMORY.md](BERBERIS_STACK_MEMORY.md).

Cross-region SP residency, early loading, explicit exit alignment, MOV
specialization and direct outside-residence stores are all absent from the
current candidate. No passing correctness result or synthetic SP-chain gain
in this record overrides the failed performance gates or establishes
game-loading gain.

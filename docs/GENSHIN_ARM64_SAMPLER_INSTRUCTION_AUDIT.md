# Genshin sampler initialization: ARM64 instruction recheck — 2026-09-13

The user challenged whether an ARM64 instruction alias, encoding variant or
translation error had been mistaken for an application sampler-binding bug.
The visual correction alone cannot answer that question. This follow-up checks
the original bytes, their independently executed semantics and the recorded
API boundary separately.

## Original bytes and aliases

A fresh read-only device check copied 196,608 bytes starting at guest ELF
virtual address `0x5290000`. The current process mapping, installed game file
and September 12 snapshot are identical:

`0cd16ad69176d30fd11f06a87ec899f94b4ddc25745598922ae3cb2fee2481f5`

The original library's containing `PT_LOAD` has file offset and virtual address
zero, so those addresses coincide for this slice. The diagnostic synthetic
ELF is different: its `.text` starts at file offset `0x40`; its section contents
were separately checked against the raw slice. This avoids confusing a virtual
address with a synthetic ELF file offset.

Capstone 5.0.6 independently decoded 189 instructions from the raw bytes,
without reading the previous LLVM assembly listings. Thirty key
instruction fields were also decoded explicitly. Examples:

| Guest address | Encoding | Base instruction / verified meaning |
| --- | --- | --- |
| `0x52a4670` | `0x2a0003e1` | `ORR W1, WZR, W0, LSL #0`, aliased as `MOV W1,W0`; clears X1's upper 32 bits; preserves NZCV |
| `0x52a4640` | `0x36000268` | `TBZ W8,#0,0x52a468c`; tests bit 0, independently of NZCV |
| `0x52a463c` | `0xb9402e68` | `LDR W8,[X19,#0x2c]`; 32-bit load, not 64-bit |
| `0x52a40dc` | `0x395c3529` | `LDRB W9,[X9,#0x70d]`; unsigned byte load |
| `0x52b11ac` | `0x7a422940` | `CCMP W10,#2,#0,HS`; immediate operand, compare rather than add |
| `0x52b11b8` | `0x1a9f27e9` | `CSINC W9,WZR,WZR,HS`, aliased as `CSET W9,LO`; the alias inverts the encoded condition |
| `0x52a4664` | `0xb8777902` | `LDR W2,[X8,X23,LSL #2]`; 64-bit index register, not UXTW |

The SUB and MOV between CCMP and CSET do not update flags. The decoded version
predicate remains:

```c
flag = (uint32_t)(version - 10) < 3 ||
       (uint32_t)(version - 3) < 2;
```

The current read-only capability snapshot again reports version enum 4 and
flag 1. This is a snapshot, not an instruction-by-instruction observation of
the original initialization.

## Independent execution without Berberis

Unicorn 2.1.4 executed the unmodified ARM64 slice at its original virtual
addresses. Only external GLES calls were replaced with test functions supplying
prescribed active-uniform names and valid location results. The real guest
helper, loop, loads, calls, branches and argument-copy instructions executed.
The test functions also clobber caller-saved registers and supply return values
with nonzero upper 32 bits.

- 128 MOV cases cover high-bit values and all 16 incoming NZCV states.
- 368 version-predicate cases cover version boundaries, unsigned wraparound
  and all 16 incoming NZCV states.
- 28 complete sampler-loop cases cover both location ranges, even/odd strategy
  words and return-register high-bit contamination.
- All 2,940 checks pass. Flag bit 0 set produces `(location, location)`;
  clear produces `(location, sequential_texture_unit)`.

The helper's positive-location path is covered. The `location == -1` uniform
block fallback, complete capability initialization, real GLES driver execution
and physical ARM hardware are outside this control. No Berberis decoder or
translator participates in this test.

## Dynamic API evidence independent of instruction names

A new parser decoded the original September 12 `perf.data` payloads directly,
without using the old text or analysis output. It reconstructed 279,204 samples.
All 49,697 guest/native integer-uniform setter arguments match; their ordered triples
also match the native driver's uniform writes.

For each of the 14 historical water samplers, the original trace directly
records the uniform-location query result, followed by matching wrong guest
and native setter arguments. The first is:

```text
glGetUniformLocation(342, "_CameraDepthTexture") returns 423
bridge entry: saved guest X0=423, X1=423
native glUniform1i entry: location=423, value=423
Mesa _mesa_uniform: program=342, location=423, count=1, value=423
```

The native callee was independently resolved through captured maps, ELF
symbols and matching build ID to `glUniform1i`. The API identity was not guessed
from the game's function-table offset.

The historical initialization trace does **not** contain W8 at TBZ, the
stack-local strategy flag at that moment, before/after MOV register snapshots
or the generated LoongArch region for this call. A later global flag read of 1
must not be described as a simultaneous branch-input measurement. These gaps
limit claims about the correctness of all upstream execution.

## Scope of the conclusion

### Isolated Berberis execution on the LoongArch64 device

A separate native executable ran four focused tests, comparing independently
specified C++ architectural results against `InterpretInsn`, JIT with register
mapping disabled, and JIT with mapping enabled. All four tests passed in
555 ms, totaling 70,272 complete CPU-state and memory comparisons. The tests
check all guest GPRs, SP, NZCV, PC, SIMD values, other CPUState fields and a
2 KiB memory fixture. Inputs include all 16 initial NZCV combinations,
nonzero upper register bits and boundary/wraparound values.

The cases cover the ten requested exact instruction words, the complete
44-byte original version predicate, a clearly marked fixture combining the
original flag load/TBZ/two MOV alternatives, and a repeated MOV fixture that
exercises register mapping. The index-load test compensates the base address
using full 64-bit modular arithmetic so a high-bit X23 index still addresses
valid test memory; incorrectly using UXTW would select another address.

No interpreter/JIT discrepancy was found in these cases. The test executable
was compiled and linked separately from existing build inputs; it was not
injected into the game. Its SHA-256 is
`407c25604943f495f1d80c75ba01e24b999002c70a51ffc5144fba8fffb6ba58`.
The product library remained at fifth-batch SHA-256 `c2183d42…`. However, the
test module uses `static_lto-none` archives while the product library uses
`static` archives, so this is not a claim that the exact deployed shared
library executed the test. See the private test build manifest and source
audit for dependency details.

A second bounded link attempt replaced 17 Berberis archives with the product
library's actual ThinLTO inputs and used the product's ThinLTO flags. It failed
before producing an executable with the known LoongArch entry-stub relocation
error `R_LARCH_B26 cannot refer to absolute symbol`, involving runtime entry
symbols such as `berberis_HandleNotTranslated`. This is a linker failure, not
a failed instruction assertion. No product-input device run is claimed; the
successful no-LTO result and its artifacts remain intact. The link arguments,
input hashes and errors are recorded in
`translator-test/product-inputs-build-manifest.json` and
`translator-test/link-product-inputs.log`.

The game retained its process start time and host boot, with `TracerPid=0`.
No game library, property, image, shader binding or cache was changed during
this instruction audit. The earlier temporary water correction remains a
separate experiment.

### Interpretation

The recheck supports the identified local instruction meanings and shows that
the original ARM64 fragment itself produces the wrong mapping under the
tested inputs, without Berberis. Separately, the API trace establishes that
those wrong values really reached the driver. The reversible visual control
establishes their effect on the currently displayed water.

This does not prove every translated instruction correct, prove the complete
initialization path correct, or explain why a physical ARM phone may choose a
different path or layout. The compatible repair direction remains preserving
the intended sampler units across variants, while any evidence of an upstream
translator fault must be investigated on its own merits.

Private evidence is in outer-workspace
`logs/genshin-arm64-redecode-20260913/`: `live-opcodes-summary.json`,
`static-redecode.json`, `static-redecode.md`, `unicorn-result.json`,
`replay-unicorn.py`, `dynamic-perf-audit.json`, and `dynamic-evidence-audit.md`.
The `translator-test/` directory contains the isolated test source, compiler
and linker manifest, dependency hashes and executable; `device-tests.txt`
records the device result.
See also [the variant investigation](GENSHIN_SHADER_VARIANT_BINDINGS.md) and
[the reversible water correction](GENSHIN_WATER_SAMPLER_REPAIR.md).

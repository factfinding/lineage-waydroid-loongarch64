# Genshin water: renderer identity and instancing paths — 2026-09-13

Subsequent deployment: the [Genshin-only GPU profile](GENSHIN_GPU_PROFILE.md)
now selects the 32/32 initialization on la64. The current in-game water scene
renders correctly, with matching CPU and fragment sampler units and no manual
sampler correction. The analysis below records the earlier comparison.

The LDPlayer control has a real graphics-identity difference that does not
require ARM64 translation to reproduce. A native x86_64 EGL probe reports
Qualcomm / Adreno 750 with an ordinary process name, but ARM / Mali-G77MC9
with the Genshin process name. The running game's graphics capability object
also stores ARM / Mali-G77MC9.

This advances the [emulator comparison](GENSHIN_EMULATOR_COMPARISON.md).
It does not establish that every Berberis instruction is correct, or identify
the cause of the earlier whole-host resets.

## Process-name control

The same native executable, launcher, UID/EUID 2000 and EGL pbuffer setup
were used in both cases. The launcher supplies the name as `argv[0]` before
the child's dynamic libraries load; the probe also sets its own `comm` before
its first EGL call. The actual `/proc/self/cmdline` first item was verified.

| Process-name configuration | GL vendor | GL renderer |
| --- | --- | --- |
| `org.example.GLProbe` | Qualcomm | Adreno (TM) 750 |
| `com.miHoYo.Yuanshen` | ARM | Mali-G77MC9 |

A third run returned to the ordinary name and again received Qualcomm /
Adreno 750. Across the first two successful runs, all nine queried limits
and the GL extension list agree; only vendor and renderer identity differ.

This is a positive control for name-dependent graphics behavior in LDPlayer.
It does not distinguish an `argv[0]` selector from a `comm` selector or locate
the implementing layer. No game memory, package identity, UID or emulator
configuration was changed.

The ARM64 launcher controls exited before EGL because Houdini presented
`/system/bin/houdini64` as the `/proc/self/cmdline` first item. They failed the
probe's identity check and provide no GL comparison. They are not counted as
successful tests or shader failures.

## Live capability differences

Both games use version code 1223; the earlier comparison also matched five
resource revision markers. Offsets below are relative to the initialized
game capability object, not Android properties or the independent probe.

| Field | LDPlayer | la64 |
| --- | ---: | ---: |
| Version enum, `+0x728` | 4 | 4 |
| Sampler reuse strategy, `+0x70d` | 1 | 1 |
| Initial instancing size, `+0x760` | 32 | 32 |
| Alternate initial instancing size, `+0x764` | 32 | 2 |
| Mali/Maleoon family classification, `+0x7a6` | 1 | 0 |
| Model classification including G77, `+0x7b0` | 1 | 0 |
| Actual GLES major/minor, `+0x80c` / `+0x810` | 3.1 | 3.2 |
| Secondary capability `+0x92`, program-binary permission | 0 | 1 |

The original ARM64 renderer-classification instructions recognize the Mali
family and G77 model. These classifications explain the observed 32/32
versus 32/2 initial-size settings. A 267-instruction audit cross-checks the
original instruction words against independent disassembly. The source
builder selects one of these two sizes using a resource flag and applies a
resource-specific limit when present.

The binary/source program builder does not itself select full reflection
versus reflection reuse. Both successful binary import and source linking
return success to their caller. Initial shader construction calls full
reflection; successful construction in the on-demand variant function calls
the reuse function. No game `glProgramBinary` calls were captured in the
earlier LDPlayer startup trace.

## Actual LDPlayer water object

A bounded, read-only heap scan found the owner of water-interface program
1247. Its variant array has one entry: **key 0, program 1247**. The owner is
in ordinary source mode, retains its vertex and fragment sources, and records
the runtime-instancing marker. Repeated header and variant reads agreed.
The retained sources' hashes also agree with the scanner's earlier reads.

The vertex source is a template: it contains a default macro value of 2 and
one recorded replacement offset pointing at the 35-character
`UNITY_RUNTIME_INSTANCING_ARRAY_SIZE` token. That template alone does not
tell us the size passed to the compiler.

The startup trace for program 1247 queried three uniform-block members for
each `unity_Builtins0Array[0]` through `[31]`, with no `[32]` or higher
queries. This supports a 32-instance initial interface. The queried locations
are -1 because these are uniform-block members; that is separate from the
valid locations of the water samplers. The trace did not capture
`glGetActiveUniform` output or a direct `GL_UNIFORM_SIZE` measurement.

The initial program always receives variant key **0**, independently of the
size substituted into its source. Therefore a capability size of 32 is not
itself evidence of a variant key of 32, or proof that no later variant can
be created. Program 1247's single-entry owner also must not be treated as a
later variant of program 1003 merely because their interfaces match.

## The array-extent gate

The original ARM64 full-reflection code parses the integer in a uniform name
of the form `name[INDEX].member`. For positive indices, the audited path stores
`INDEX + 1` in a 40-byte structure record and maintains the maximum across
matching members. Index zero has a separate member-record path. The resulting
field is the enumerated structure-array extent, not a sampler location or a
texture unit.

The instancing metadata constructor initially enables a dynamic flag from a
global policy byte. Both live processes have policy byte 7. Full reflection
marks uniform blocks whose names begin with `UnityInstancing`; the saved
LDPlayer vertex template names its block `UnityInstancing_PerDraw0`.
The constructor then clears the flag if the selected instancing block's
reflection list contains ordinary members,
does not contain exactly one 40-byte structure record, or that record's extent
is **not 2**. Consequently, a 32-element structure fails this gate; a
2-element structure can retain the dynamic path if the other conditions hold.

The relevant original-file locations are:

| Operation | ARM64 RVA |
| --- | --- |
| Parse bracketed index through the verified `atoi` import | `0x524e460` |
| Pass the name and index-output address from full reflection | `0x5295490` |
| Initialize extent with index + 1 | `0x5295b0c` / `0x5295b18` |
| Increase extent to max(previous, index + 1) | `0x5295c58`–`0x5295c68` |
| Require extent 2; otherwise clear the dynamic flag | `0x5257c04`–`0x5257c10` |
| Supply an on-demand key through graphics vtable slot `0x378` | `0x525acbc` |
| Store the supplied key at graphics + `0x5a44` | `0x528a7fc` |

The last setter copies its fifth argument unchanged. With the observed global
policy bit set, its caller rounds the requested count upward to a multiple of
32 and caps it by an instancing metadata limit. That limit has additional
reflection and buffer-budget calculations; it must not be equated with the
capability object's initial shader size.

This supplies a concrete mechanism connecting the renderer-dependent initial
array size to the choice of initialization path. LDPlayer's observed extent
32 disables this dynamic path, consistent with its single initial program and
correct full reflection. The current la64 water programs 276 and 278 both
expose only `unity_Builtins0Array[0]` and `[1]`, which satisfy the extent part
of the gate. Their 99-uniform interfaces and locations are identical.

## Current la64 owner confirms the same-size variant

The first 512 MiB la64 scan did not locate an owner. Coverage review found
large scudo primary pools had not been examined, so a second scan used the
same budget with those pools first. It found one validated owner containing
all three related programs and stopped after 0.388 seconds. Both scans
reported stable process identity and zero read errors.

| Owner entry key | Program | Reflected instance extent | Owner selection |
| --- | ---: | ---: | --- |
| 0 | 276 | 2 | Initial entry |
| 2 | 278 | 2 | Active entry at the snapshot |
| 32 | 277 | 32 | Another retained variant |

Repeated header and variant-array reads agree. A subsequent bounded read
again verifies the header, entries and source hashes. The la64 owner retains
exactly the same 2,818-byte vertex template as LDPlayer program 1247, including
the same runtime-macro replacement offset. Their fragment templates differ;
the game controls still have ten versus eleven known samplers and are not
identical rendering configurations.

**The current failing program is the key-2 variant, with the same compiled
array extent as the initial key-0 program.** An increase in array size or
uniform locations is therefore unnecessary for this mapping failure. This
owner also has a separate key-32 variant; it must not be confused with the
selected key-2 program or the historical 14-sampler fixture.

The current owner-to-program/key relationship is established. Its creation
and selection history was not traced live; the inference about its initializer
comes from the audited original variant constructor. The owner's active entry
is a state observation, not a new draw trace. The earlier passive draw trace
and reversible visual correction independently associate program 278's sampler
mapping with the missing water.

The erroneous sampler setter itself remains the previously audited original
`MOV W1,W0` at `0x52a4670`. Correct ARM64 execution copies the queried
location into the value argument there. This path-specific finding does not
justify changing that instruction's translation semantics globally.

Independent Unicorn execution of the original instruction fragments passed
10,384 checks: 4,480 layout-gate cases, 80 extent-creation cases, 560
extent-update cases and 16 disabled-metadata return cases. This validates the
selected raw ARM64 fragments with constructed inputs. It is not execution of
the complete game or a test of the deployed Berberis library.

A three-second read-only sampling attempt made 2,791 successful reads of the
located LDPlayer graphics object's current-shader/key fields, but none matched
the recorded water owner. It provides no water-key or draw evidence. The
reader exited normally; no debugger or trace probes were installed by it.

## Evidence and limits

Private evidence is in the outer workspace's
`logs/genshin-init-path-20260913/`: `identity-probe-comparison.json`,
`capability-comparison.json`, `emulator-program1247-source-audit.json`,
the bounded scanner results and the original-instruction audits. The
original APK ELF matches three independently read installed-file slices.
Proprietary game binaries, shader sources and process addresses remain
outside this public integration repository.

The scans read at most 512 MiB each, inspect present anonymous pages and stop
within ten seconds. Their coverage is incomplete; a missing object is not
evidence of absence. Finding an allocated shader object does not independently
prove a current draw. These controls do not change shader cache data or
deploy a persistent fix.

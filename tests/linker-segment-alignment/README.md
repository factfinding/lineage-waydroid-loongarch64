# PT_LOAD alignment regression probe

Some protected ELF files declare 16 KiB alignment while a file-backed load
segment's virtual address and file offset are congruent only modulo 4 KiB.
On a 16 KiB host, the ordinary file mapping silently exposes the wrong bytes.
The linker must select its existing 4 KiB compatibility copying loader.

Build from the Android tree:

```sh
m -j8 linker native_bridge_guest_linker.native_bridge linker_segment_alignment_probe
```

Generate native LoongArch64 data-only DSOs with `python3 generate.py OUTPUT_DIR`.
Copy them, `system/bin/linker_segment_alignment_probe`, and the candidate
`system/bin/bootstrap/linker64` to Android `/data/local/tmp/`. The generator
also accepts an ELF machine number (e.g. 183 for ARM64) as its second argument.
There is no proprietary application code in these fixtures.

For each fixture, run on the Android device:

```sh
/data/local/tmp/linker_segment_alignment_probe /data/local/tmp/overstated-16k.so
/data/local/tmp/linker64 /data/local/tmp/linker_segment_alignment_probe /data/local/tmp/overstated-16k.so
```

The first invocation uses the installed native linker; the second explicitly
uses the candidate without replacing the native linker in the runtime APEX.
The probe reads exported data rather than executing the mis-mapped region.

2026-09-18 LoongArch64 device results (`page_size=16384`):

| Fixture | Installed linker | Candidate |
| --- | --- | --- |
| congruent-16k.so | PASS | PASS |
| declared-4k.so | PASS | PASS |
| overstated-16k.so | FAIL: zero | PASS |

Every passing case reads `0x123456789abcdef0`. This exercises the common linker
mapping implementation natively; the ARM64 guest linker is built from the same
source and separately validated by launching the affected application.

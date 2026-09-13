# Genshin-associated host resets — 2026-09-12

The user reports that launching Genshin now restarts the entire LoongArch64
computer, including the system startup screen. Host boot IDs, uptime, wtmp
and journal boundaries confirm seven unexpected host restarts on September 12.
The available saved logs do not establish their cause. This is separate from
the previously observed water sampler-binding defect; a shared cause has not
been demonstrated.

**September 13 follow-up:** after restoring fifth-batch JIT, the user cleared
Genshin's application data and reports no further host reset so far. Read-only
checks at approximately 09:28 UTC+8 verify mode 1 with 130,945 JIT successes in
the live game and the same host boot as the 09:15 restoration. A screenshot
shows a fresh 48,552.73 MB resource download at 0.71%, rather than the earlier
174.51 MB update-download path. This is an improvement reported under changed
application data, not a completed matched-stage or in-world stability control.
The exact cleared files were not inventoried. Application data/cache and the
paths selected by them warrant priority; no particular cache file, data
corruption, JIT fault, or driver/kernel failure has been isolated. Evidence:
outer-workspace `logs/genshin-cleared-data-20260913/`. No further device changes
were made by the agent during this follow-up.

**September 13, 12:29 UTC+8:** the user reports successful entry into gameplay
with water still missing. A new screenshot confirms gameplay. Read-only checks
find the same host boot and game PID as 09:28, about three hours earlier; the
same fifth-batch library reports mode 1, 347,752 JIT successes and 118,222
gear-ups. Thus observation has advanced beyond the fresh-download screen
without a host reboot in that interval. This is not a repeated-launch or
long-term reliability test. Clearing data did not resolve the water symptom;
the reset and water symptoms should be tracked separately without claiming
their root causes have been proven independent. Current evidence is in
`runtime-in-world.json` and `observation-in-world.json` in the same artifact
directory. No settings, resources or runtime bindings were changed by the agent.

**September 13, 13:06 UTC+8:** a reversible live sampler correction restored
water with fifth-batch JIT enabled. Restoring the wrong values removed the
water again, and reapplying restored it. The final check finds the same host
boot and game process, with all debugger attachments and uprobes removed.
No reboot occurred during this control. This directly links the current water
symptom to sampler mapping but does not determine the earlier host-reset cause.
The correction is temporary; no product library, image or persistent setting
was changed. See [the controlled repair](GENSHIN_WATER_SAMPLER_REPAIR.md).

## Observed restart boundaries

| Previous boot ID | Last saved journal entry (UTC+8) |
| --- | --- |
| `c5c92a91aa6c48e78394fc27db1cabdb` | 21:27:38.272 |
| `e43212df63c14eab95a3854f15d2d946` | 21:35:59.137 |
| `21911a8482e845c9aef7f1694cb4e2f7` | 22:08:25.215 |
| `308c4f1378dc4554aeccd6e8d2dd644e` | 22:35:09.844 |
| `1431744dffa74c0f9bbd82e32e7a107b` | 22:57:00.845 |
| `1415cf78cb35488080c7d5f8143d341f` | 23:38:01.074030 |
| `826bfb8973c946c193b9d29ee6f02d51` | 23:44:50.084998 |

The boot after the third reset was `308c4f1378dc4554aeccd6e8d2dd644e`. At 22:09:55 the host
reported approximately 58 seconds of uptime. Early boot wall-clock timestamps
start at an old firmware date and subsequently jump forward, so the first
journal wall-clock entry must not be used as the real boot time.

After the user reported another launch, the boot ID had changed to
`1431744dffa74c0f9bbd82e32e7a107b`; at 22:36:43 the host reported approximately
53 seconds of uptime. The preceding boot contains Genshin UID 10114 process
setup activity at 22:35:07.736 and its last saved message at 22:35:09.844.
Its saved kernel/journal records again contain no panic or GPU fault identifying
the cause. Artifacts from this fourth reset are under `repro-2235/`.

Full kernel-channel logs and bounded journal tails/warnings from these boots
were copied to the development computer before further investigation. They
end abruptly. There is no recorded kernel panic/oops, GPU timeout/reset,
OOM kill, power-key event or host PID 1 orderly shutdown sequence explaining
the reset. The current boot reports an uncleanly closed user journal.
An error that never reached persistent storage remains possible.

The third completed boot contains Android UID 10114 activity at 22:08:06.942, followed by
isolated-UID service requests at 22:08:10.647/652. A subsequent read of the
current Android `packages.list` confirms UID 10114 belongs to
`com.miHoYo.Yuanshen`. Those kernel-channel records are not themselves a full
application launch trace and do not identify the failing operation.

## Optimization state and change history

The preceding user request to restore optimizations resulted in read-only
verification, not a new deployment or reboot. Both overlay and mounted libraries
already matched fifth-batch SHA-256
`c2183d42f05ed207619f9b5e8291ab75b9f58df7ccc0e5897021147cd70f16c4`.
Their restoration occurred on September 11 at 19:48, before all seven resets.
Berberis and ART JIT enabling properties remained set during that verification. Genshin host PID 6739
had 15,200 JIT successes and 3,679 gear-ups during that verification; the next
journal boundary is 21:35:59. This chronology alone does not establish a JIT
regression or exclude software as a trigger.

The compared boots use the same `7.1.7-aosc-main-4k` kernel build. The checked
package-manager history files showed no September 11/12 kernel or graphics
update; their last modification dates were August 29. This does not exclude
changes outside those package-manager records.

## Hardware observations and their limits

Post-restart idle readings were CPU 37°C, GPU 52°C and NVMe approximately
53.85°C, with available memory and zero GPU PCIe AER counters. These readings
do not measure the instant of failure and cannot exclude transient power,
thermal, GPU or memory problems under game startup load.

The memory-controller driver reports the same MC1 `16 CE` message about every
2.048 seconds, beginning early in each boot. The same pattern is present in
September 8/9 logs and a September 11 boot that shut down normally. It is not
a newly observed event specific to these resets.

Disassembly of the deployed `loongson_edac.ko` shows it reports differences
between hardware counter reads. However, its page, offset and syndrome fields
are hardcoded zero and it only reports CE events. Consequently:

- The log cannot identify a bad physical address or DIMM from those zero fields.
- A zero exported UE counter is not proof of healthy memory on this driver.
- The pattern does not by itself distinguish physical faults from counter or
  firmware compatibility problems, or prove that EDAC caused the restarts.

## Why the saved logs cannot rule out a kernel crash

The initial pre-reproduction and post-restart checks found `kernel.panic=30`, allowing
automatic reboot after a panic.
No kdump crash kernel is configured; EFI pstore is disabled, and both live
pstore and archived pstore/crash directories are empty. Systemd's runtime
watchdog is disabled and no watchdog device was found.

Dynamic netconsole is available in the kernel but has no configured target.
The machine currently uses Wi-Fi; its wired interface `enp2s0` has no carrier.
Serial ports exist, but the only active kernel console is tty0. No netconsole,
serial or firmware-storage setting was changed in this investigation. After
the fifth reset, the panic reboot timeout was temporarily changed as documented
below.

## External capture coverage and correction

Bounded, read-only SSH streams save kernel messages, one-second hardware/memory
telemetry, and Android launch/warning logs on the development computer. They
were limited to ten minutes per stream. This avoids depending only on the
failing computer's disk, but SSH requires functioning userspace and networking;
it is not a guaranteed replacement for netconsole or a serial panic capture.

The initial streams ended at approximately 22:26–22:28, before the user's
22:35 launch. The kernel and Android commands exited with timeout status 124;
the telemetry loop completed its 600-second interval normally. Its 599 samples
span 22:17:25–22:27:25, all within the old boot. They do not measure the fourth
failure, and their temperatures must not be presented as pre-crash values.
The initial user-facing readiness message did not clearly state this deadline;
that capture-window error was acknowledged. The replacement collector provides
an explicit deadline and reconnects after disconnection or a new host boot.

The user currently has Wi-Fi only. A short UDP request/response test between
the device and the Windows development host succeeded without firewall changes;
this verifies ordinary userspace connectivity, not panic-time Wi-Fi delivery.
No kernel netconsole target was installed.

The replacement `scripts/capture-la64-host-reset.py` passed local syntax checks
and two read-only smoke windows totaling ten seconds. Its final smoke received
direct dmesg records and sensor samples, then removed all of its remote process
groups. Reconnection is implemented but was not tested by deliberately rebooting
the machine. App-specific collection was not yet verified with a running game.

An actual one-hour instance was then started at **22:47:07 UTC+8**, with an
explicit deadline of **23:47:07 UTC+8**, writing to `continuous-01/`. Its
`status.json` showed armed only after actual kernel data arrived; sensor
records were also received. Android streams retry read-only when Waydroid is
unavailable. This readiness observation is time-limited: consult the live
status and deadline before treating a later launch as covered.

The agent did not launch the game or initiate a restart while collecting the
existing evidence. User confirmation was requested before a controlled launch
because the reported trigger can restart the whole computer. No product code,
game data, shader cache or optimization setting was changed during that initial
collection. The later authorized interpreter comparison is recorded below.

## Fifth reset: externally captured startup and resource verification

The user reported another reboot after the continuous collector was armed.
It captured the end of boot `1431744dffa74c0f9bbd82e32e7a107b` and automatically
reconnected to new boot `1415cf78cb35488080c7d5f8143d341f`.

Genshin's main process started at **22:55:34.319 device time**, host PID 8026,
Android PID 4999. Four later launch records belong to auxiliary processes.
The last identifiable game milestone was `OnStartVerify Normal` at
**22:57:08.544**, followed by `File num to verify = 1684` at **22:57:08.548**.
The last Android record was at **22:57:08.660**, about 94.34 seconds after the
main process launch. Resource verification is the last observed stage, not
an established cause of the host reset or evidence of a water rendering fault.

The saved journal ends at **22:57:00.845279**, monotonic 1269.665023.
Direct dmesg captured about another 6.10 seconds of kernel events, ending with
the recurring EDAC message at monotonic **1275.763431**. Neither source contains
an actual panic/oops, GPU timeout/reset, OOM kill, or orderly host shutdown.
The Android streams contain no observed fatal signal, ANR or app crash.
Broad searches for `BUG:` match `binder_debug`; an apparent shader-compile
error match is a GL extension name. Neither is an actual failure report.

The 590 sensor samples from the old boot end at **22:57:08.434675 device time**:

| Metric | Last sample | Maximum or minimum over the captured old boot |
| --- | --- | --- |
| CPU temperature | 44°C | 47°C maximum |
| GPU temperature | 54°C | 59°C maximum |
| Available RAM | 7.237 GiB | 7.102 GiB minimum |
| Swap used | 0 | 0 |
| GPU reported power | 29.220 W | 47.153 W maximum |

There is no observed sustained overheating or memory exhaustion. I/O pressure
was already high before Genshin launched and declined near the end; the
capture does not attribute that pressure to a device or process. One-second
telemetry cannot exclude a short power transient or a kernel/GPU fault.

The first SSH timeout at **22:56:35 development-computer time** was followed by
a connection to the same boot at 22:56:37. The sensor series has an 8.937-second
gap around that reconnection; the final 28 seconds are continuous. The last
old-boot Android record reached the development computer at **22:57:05.884**,
and the second SSH timeout was at **22:57:11**. A new-boot connection succeeded
at **23:00:19.433**. The developer and device clocks differ by about 2.78 seconds
before the reset; boot IDs and remote monotonic values should be used for
cross-channel alignment. The new kernel's estimated uptime origin is around
22:57:33.6 developer time, not a measurement of the precise hardware reset.
The interval alone does not establish a 30-second panic reboot.

## Temporary panic hold and its limits

After collecting and analyzing the fifth reset, at **23:10:25 device time**,
`kernel.panic` was changed from **30 to 0** in boot
`1415cf78cb35488080c7d5f8143d341f`, then read back as 0.
This only changes the current boot; no persistent sysctl or bootloader file
was edited. The prior value can be restored with
`ssh la64-root 'sysctl -w kernel.panic=30'`.

The device already has `drm.panic_screen=kmsg`, and the GPU registered panic
planes at boot. A zero panic timeout stops Linux's normal panic reboot timer,
allowing a displayed panic message to remain for a photograph; the machine
may then require a manual restart. The display is best-effort and may fail
if graphics or the hardware is no longer usable. A continuing automatic reset
would argue against this ordinary panic timer as the reboot mechanism; it
would not alone prove a PSU fault or exclude other software reset paths.
See the [kernel panic setting documentation](https://docs.kernel.org/admin-guide/sysctl/kernel.html#panic)
and [DRM panic implementation](https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/drm_panic.c).

No panic or game launch was deliberately triggered to test this setting.
The existing collector remained armed after reconnection, with the same
**23:47:07 development-computer time** deadline. This is diagnostic preparation,
not a fix for the reset. Product libraries and optimization settings were
unchanged at that point. The exact mutation and rollback are recorded in
`repro-2257/panic-hold-change.json`.

## Sixth and seventh resets: automatic restarts and video evidence

The user confirmed that both later restarts, around **23:38** and **23:44**,
occurred automatically without pressing a reset or power button. The continuous
collector captured both launches and their final successful kernel, Android and
sensor reads. It reconnected after the sixth reset to boot
`826bfb8973c946c193b9d29ee6f02d51`. After the seventh reset, SSH remained
unavailable through the **23:47:07 development-computer time** collector
deadline. SSH recovered around **23:51**, allowing the two persistent journals
and new boot `ebd8ae9f591d4181bdd96b9ed2854ddd` to be verified.

| Evidence endpoint (device time, UTC+8) | Sixth reset, boot `1415cf78…` | Seventh reset, boot `826bfb89…` |
| --- | --- | --- |
| Last persistent journal entry | 23:38:01.074030 | 23:44:50.084998 |
| Last direct kernel message, monotonic | 2430.766882 s | 377.831378 s |
| Approximate wall time of that kernel message | 23:38:07.168886 | 23:44:54.060353 |
| Last sensor sample | 23:38:08.693372 | 23:44:55.161685 |

Both final kernel messages are the recurring EDAC CE report. Neither the direct
kernel streams nor the subsequently recovered journals contain a real
panic/oops, GPU fault/timeout/reset, OOM kill, critical-temperature shutdown,
power-button event, or orderly host shutdown explaining these restarts. The
Android allowlist found no fatal signal, fatal exception or target ANR. The
last successful read is not a measurement of the exact hardware-reset instant.

The final minute of sensor data is continuous in both episodes. CPU/GPU
temperatures peak at **46/59°C** and **49/59°C** respectively, available RAM
remains above **7.859 GiB** and **7.001 GiB**, and swap remains unused. These
windows show no sustained overheating or memory exhaustion. They cannot
exclude a brief power transient or a kernel/GPU fault. Full sensor and timing
limits are recorded in `repro-2343/SENSOR_ANALYSIS.md` and
`repro-2343/collector-coverage.md`.

The 123.85-second recording `2026-09-12 23-43-28.mp4` was visually reviewed:

| Position in recording | Observed display |
| --- | --- |
| 84.5 s | Genshin resource download at **1.11%**, **1.94/174.51 MB**. |
| 84.7667–96.2 s | Entire display is black; the interval also matches `blackdetect`. |
| Approximately 96.2–98.9 s | A blue rectangle with no readable text. |
| Approximately 101 s onward | Loongson firmware logo, followed by GRUB and system startup. |

This confirms a whole-computer restart while the displayed game stage was
resource download. The textless blue rectangle is **not evidence of a kernel
panic screen**. The recording contains no readable panic message or stack, and
does not identify whether the reset originated in hardware, firmware, or a
software failure. Recording positions have not been precisely synchronized to
device wall time; the filename alone cannot provide that alignment. Extracted
frames and black-screen measurements are under `repro-2343/video/`.

Only the sixth-reset boot had the earlier verified `kernel.panic=0` write.
The collector did not sample that sysctl, so its value at the sixth reset is
not independently verified. The seventh-reset boot was a fresh boot and must
not be described as another confirmed test with `panic=0`.

In both boots, Android init attempted `panic_on_oops=1` and explicitly failed
with a read-only filesystem. The local init source writes that parameter, not
`kernel.panic`. These failures do not show Android overwriting the panic reboot
delay. On the new boot reached at 23:51, `kernel.panic` is **30**, consistent with
the existing `/etc/sysctl.d/00-kernel.conf` setting; pstore remains empty.

If zero remained effective during the sixth reset and Linux entered its
ordinary panic-wait path, the normal panic timeout would not explain an
automatic restart. The missing final sysctl value, absent fatal output, and
possible alternative reset paths prevent that conditional from excluding all
kernel/software causes or proving a power-supply fault. The observed automatic
restarts therefore narrow the question without establishing the cause.

## Authorized Berberis interpreter comparison — result pending

At **23:55:27**, after backing up configuration, the user-authorized comparison
sets only `berberis.mode=interpret-only`; ART JIT remains enabled and the
Berberis library retains SHA-256 `c2183d42…f16c4`. See the
[configuration record](../../logs/genshin-host-reset-20260912/no-jit-control/configure-result.txt).
This prepares a controlled comparison; it has not yet established whether
Berberis JIT is required to trigger the host reset.

## Evidence

Outer-workspace directory: `logs/genshin-host-reset-20260912/`.

- `collection.json` and `{daytime,earlier,previous,current}-*.txt`: journal
  collections and exact boot identities.
- `collected-log-audit.md/.json`, `audit-collected-logs.py`: independently
  reviewed boundaries and aggregated messages.
- `history-control.json`: earlier orderly shutdown, kernel identity and
  recurring EDAC control.
- `hardware/`: read-only sensors, EDAC driver analysis, and crash-capture settings.
- `live-kernel.txt`, `live-telemetry.jsonl`, `live-android.txt`: bounded external
  streams, with command/script and stderr files beside them.
- `continuous-01/`: reconnecting external streams that cover the fifth through
  seventh resets up to their final successful reads.
  Raw Android logs may contain private account/session data and must not be
  published; use the sanitized reports below.
- `repro-2257/`: exact previous-boot journals, `SENSOR_ANALYSIS.md`,
  `collector-coverage.md`, machine-readable summaries and the temporary panic
  timeout change record.
- `repro-2343/`: sixth/seventh persistent journals, direct-kernel audit,
  sensor/coverage analyses, extracted video frames, and recovered panic settings.
- `no-jit-control/`: subsequent authorized interpreter comparison configuration
  and runtime verification; the reproduction outcome is pending.

See [optimization restoration verification](RUNTIME_STATUS.md) and
[water sampler investigation](GENSHIN_SHADER_VARIANT_BINDINGS.md) for the
preceding, distinct findings.

# Installing on arcfox (Motorola razr 50 ultra)

A step-by-step install guide for the Motorola razr 50 ultra / razr+ 2024
(codename **arcfox**, SM8635).

If you downloaded a released build rather than building one, use
**[INSTALL-RELEASE.md](INSTALL-RELEASE.md)** instead — it is self-contained and
covers the prerequisites.

`FLASHING.md` is the *developer* runbook — the rules behind these steps, and why
each exists. This file is the procedure itself.

> **This erases everything on the phone.** There is no path that keeps your
> data — `/data` cannot survive the crossing (see section 4). Back up first.

---

## 0. What you need

| | |
|---|---|
| An **unlocked bootloader** | Motorola issues the unlock code — see their official [bootloader unlock page](https://en-us.support.motorola.com/app/standalone/bootloader/unlock-your-device-a). Unlocking itself wipes the device and voids the warranty. |
| `fastboot` | From Android platform-tools. Anything reasonably recent works; these steps were run with 36.0.2. |
| The LineageOS package | `lineage-23.2-<date>-UNOFFICIAL-arcfox.zip` plus the raw images, or a tree you built yourself (see [README.md](README.md)). |
| A stock firmware package | Only needed to go *back* to stock. Motorola's Rescue and Smart Assistant downloads one and leaves it under `ProgramData/RSA/Download/RomFiles/`. |
| A good USB cable | Flashing `super` moves ~5 GB. A marginal cable or hub shows up as `error -71`/`-32` in the host's `dmesg` and aborts a flash mid-write. |

Check your bootloader is unlocked:

```bash
fastboot getvar unlocked          # must print: unlocked: yes
```

---

## 1. Getting into the bootloader

Everything below happens in the **bootloader**, never in `fastbootd`.

- **From a working Android with USB debugging on:** `adb reboot bootloader`
- **From anything else — including a fresh stock install:** power the phone off
  completely, then hold **Volume Down + Power**.

⚠️ **From a fresh stock install the manual key combo is the only option.** Stock
ships with USB debugging off; the phone still enumerates and `adb devices` even
lists it as `device`, but every command returns `error: closed`. Do not read that
listing as a working connection.

⚠️ **Never use `adb reboot fastboot`** — that is `fastbootd` (userspace fastboot),
and on arcfox `fastbootd` cannot open `super` **at all**. It enumerates, answers
`getvar`, and looks perfectly healthy, then fails every logical-partition write
with `No such file or directory`. Nothing is written when it fails, so it is not
destructive — just useless.

### Gate check — run this before writing anything

```bash
fastboot getvar is-userspace            # MUST be: no      (yes = fastbootd, wrong mode)
fastboot getvar partition-size:super    # MUST be: 0x0000000632700000
```

`fastboot devices` proves only that USB enumerated. A wedged bootloader still
enumerates. Always probe with a real `getvar`.

---

## 2. Returning to stock

Verified end to end on 2026-09-02: 23/23 `super` chunks, zero failures, booted.

The package ships a `flashfile.xml` listing every file, its partition, the exact
order, **and an MD5 for each**. The script below follows that order rather than
an invented one, and nothing else should either.

```bash
# 1. verify the package first - these files are often copied off a Windows volume
./scripts/verify-rsa-package.sh /path/to/RomFiles/ARCFOX_G_W1UXS36H....xml
#    expect: 37 files, 0 BAD

# 2. flash, with the phone in the BOOTLOADER
R=/path/to/RomFiles/ARCFOX_G_W1UXS36H....xml ./scripts/flash-stock.sh
```

The script refuses to run unless `getvar product` says `arcfox` and
`is-userspace` says `no`, and it aborts rather than continuing if any write
fails. What it does, in Motorola's order:

1. `oem fb_mode_set`
2. `gpt.bin` → `partition`, then `bootloader`, `vbmeta`, `vbmeta_system`,
   `radio`, `BTFM.bin` → `bluetooth`, `dspso.bin` → `dsp`, `logo`, `boot`,
   `init_boot`, `vendor_boot`, `dtbo`, `recovery`, `pvmfw`
3. 23 × `super.img_sparsechunk.N` → `super`
4. erase `apdp`, `apdpb`, `debug_token`, `carrier`, `userdata`, `metadata`, `ddr`
5. `oem fb_mode_clear`, `oem config unset console`, `oem config unset cmdl`
6. reboot

⚠️ **If a `super` chunk fails, do not reboot.** Re-run from the bootloader. A
half-written `super` will not boot, and rebooting into that state can wedge the
bootloader badly enough to need a second full cycle to recover.

Stock takes a few minutes to first boot after the userdata erase.

---

## 3. Installing LineageOS

Verified end to end on 2026-09-02, from a freshly restored stock handset with
only `recovery` replaced. `adb sideload` is the supported route: the `.zip` is
all you need.

```bash
# 1. in the BOOTLOADER (see step 1), replace only the recovery partition
fastboot flash recovery recovery.img

# 2. boot it
fastboot reboot recovery
```

**3. On the phone: Advanced -> Enable ADB.**

There is no host-side way to do this and no on-screen prompt to accept. Until
you do it the phone enumerates as `18d1:d001` and `adb devices` reports
`unauthorized`. The toggle resets every time recovery leaves sideload mode, so
expect to set it again between steps.

```bash
# 4. switch recovery into sideload mode, then send the package
adb reboot sideload
adb sideload lineage-23.2-<date>-UNOFFICIAL-arcfox.zip

# 5. reboot
adb reboot
```

Verification takes ~65 s before any progress appears, and the whole install
about 5 minutes. The phone reboots onto the **other slot** — starting on `_a`
you will come up on `_b`.

### Reading the result honestly

`adb sideload` printing `Total xfer: 1.00x` means the *file was sent*, nothing
more. The install result is in `/tmp/recovery.log` on the device (re-enable ADB,
then `adb pull /tmp/recovery.log`). Success looks like:

```
update_engine_sideload: Update successfully applied, waiting to reboot.
Install from ADB complete (status: 0).
```

⚠️ **`I:failed to verify against RSA key 0` is normal and is not an error.**
Recovery holds two certificates and tries them in order; key 0 is the Lineage
release cert and key 1 is the test key that actually signed the package. The
next line, `whole-file signature verified against RSA key 1`, is the one that
matters. Do not go hunting for a signing problem on the strength of that line —
it costs an afternoon.

⚠️ **`Failed to mount /metadata: File exists` is also expected here** and does
not stop the install. Motorola's flash sequence erases `metadata`, so it has no
filesystem (`Invalid f2fs superblock`); update_engine logs
`Skip cancelling update in ResetUpdate because /metadata is not mounted` and
proceeds.

### If sideload dies instantly with `Can't run update_engine_sideload`

The recovery you flashed predates commit `401c0a0`. `AB_OTA_UPDATER := true`
packages an A/B payload but installs nothing able to apply one, because this
product inherits `full_base_telephony.mk` and only `generic_system.mk` /
`mainline_system.mk` carry `update_engine`. Rebuild with a tree at or after that
commit; every zip built before it is uninstallable by this route.

### The alternative: raw images over fastboot

Still available, and useful when you have a build tree rather than just a zip.
It needs a **coherent set** — mixing our boot chain with stock's system produced
`No valid operating system found` twice. From the bootloader:

```bash
fastboot flash boot boot.img
fastboot flash init_boot init_boot.img
fastboot flash vendor_boot vendor_boot.img
fastboot flash dtbo dtbo.img
fastboot flash vbmeta vbmeta.img
fastboot flash super super.img          # repack first: ./build-super-mix.sh all
fastboot -w
```

⚠️ `super.img` is **not** rebuilt by `brunch` — that produces the OTA payload.
Repack it with `build-super-mix.sh all` and confirm the `=== composition ===`
block prints `OURS` six times, or you will flash a stale system while every
step reports success.

## 4. About wiping /data

`/data` must be empty when you cross between stock and LineageOS. It is not a
precaution: carrying an existing `/data` across bootloops with
`init_user0_failed`, because the encryption metadata does not survive the
crossing.

**Following section 2 then section 3, you do not need a separate wipe.**
Motorola's flash sequence already erases `userdata` and `metadata`, so `/data`
is blank by the time LineageOS first boots. Measured: the sideload above booted
straight to a working system with no manual format.

**If you are sideloading onto a phone that already has data** — an existing
LineageOS, or a stock install you did not just reflash — wipe it explicitly,
either from recovery (**Factory reset -> Format data**) or from the bootloader:

```bash
fastboot -w
```

## 5. If something goes wrong

Nothing here is a hard brick as long as the bootloader still answers.

```bash
fastboot devices                  # enumerating at all?
fastboot getvar product           # answers = bootloader is alive
```

If it answers, go back to [step 2](#2-returning-to-stock) and flash stock. That
is the escape hatch, and it works from any broken system state, because the
bootloader is never touched by a failed system flash.

If the phone shows a black screen but the host sees a fastboot device, it is
fine — flash stock. If the host sees nothing at all on any cable or port, check
the host's `dmesg` before concluding the phone is dead: a full-speed connection
or `error -71`/`-32` there means the cable or hub, not the device.

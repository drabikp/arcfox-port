# Installing on arcfox (Motorola razr 50 ultra)

A step-by-step install guide for the Motorola razr 50 ultra / razr+ 2024
(codename **arcfox**, SM8635).

`FLASHING.md` is the *developer* runbook — the rules behind these steps, and why
each exists. This file is the procedure itself.

> **This erases everything on the phone.** There is no path that keeps your data:
> the userdata wipe is mandatory (see step 4). Back up first.

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

*Being validated in this session — this section will be filled in with the route
that actually worked, not the route that ought to.*

Two candidate routes exist, and which one is correct is a genuine open question
on this device:

- **`adb sideload` from recovery** — the standard LineageOS route, and the only
  one that works from the `.zip` alone. Historically noted as impossible on
  arcfox because recovery rendered but never enumerated over USB. That note
  predates the from-source kernel and the current recovery image, so it is being
  re-tested rather than taken on faith.
- **Flashing raw images from the bootloader** — known to work here, but needs the
  built images rather than just the distributable zip.

---

## 4. The userdata wipe is not optional

`fastboot -w` (or the `erase userdata` + `erase metadata` pair) **must** run when
moving between stock and LineageOS in either direction.

Skipping it to preserve `/data` does not merely risk a problem — it bootloops
with `init_user0_failed`, every time. The encryption metadata does not survive
the crossing.

---

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

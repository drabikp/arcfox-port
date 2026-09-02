# Installing a downloaded arcfox build

For people installing a released build on a **Motorola razr 50 ultra / razr+ 2024**
(codename `arcfox`). You need the download and a computer — no build tree, no
source, no compiling.

If you are building from source instead, see [README.md](README.md); if you want
the developer runbook and the reasoning behind each rule, see
[FLASHING.md](FLASHING.md).

> **Everything on the phone is erased.** `/data` cannot survive the crossing from
> stock. Back up first.
>
> This is an **unofficial** build signed with the public AOSP test keys. It is
> not endorsed by Motorola or the LineageOS project. Installing it voids your
> warranty and, on an unlocked bootloader, the phone will show a warning screen
> at every boot.

---

## ⚠️ First: your phone must already be running recent Motorola firmware

**This has only ever been tested installing onto stock `W1UXS36H.72-45-10-7`**
(Android 16, build date 2026-06-24). That is not a formality — it is the single
most likely reason an install goes wrong for you but not for us.

**The package does not contain your phone's firmware.** It updates only:

```
boot  dtbo  init_boot  vendor_boot  vbmeta
system  system_ext  product  vendor  system_dlkm  vendor_dlkm
```

Everything else keeps whatever your phone already has — **the modem/radio,
bootloader, DSP, Bluetooth firmware, `pvmfw`, the partition table and the boot
logo are never written.** The port's proprietary vendor files were also
extracted from that exact firmware train, so the vendor code you install expects
the modem and DSP firmware that shipped with it.

Consequences if your phone is on an older (or much newer) train:

- Mobile data, VoLTE, or the cameras may fail in ways that look like ROM bugs
  but are a firmware mismatch.
- Nothing here is a brick risk — it is a compatibility risk, and it is
  recoverable by flashing stock.

### Check what you have

**On the phone: Settings → About phone → Build number.** It should read
`W1UXS36H.72-45-10-7`. This is the reliable check — use it.

The `adb` equivalent works *only if USB debugging is already enabled*, which it
is not on an untouched stock phone:

```bash
adb devices -l                                                   # find your serial
adb -s <serial> shell getprop ro.build.version.incremental       # W1UXS36H.72-45-10-7
adb -s <serial> shell getprop ro.product.device                  # must be: arcfox
```

⚠️ **Always pass `-s <serial>`.** With another Android device plugged in, a bare
`adb shell` silently answers from *that* device — during testing it cheerfully
reported a completely different phone's build, which would have sent a reader
off to "fix" firmware that was already correct.

⚠️ **`adb devices` listing the phone as `device` does not mean adb works.** On
this phone it says `device` while every command returns `error: closed`, both on
stock and on a freshly installed LineageOS before you enable USB debugging.
Trust `adb shell echo ok`, not the device list.

If `ro.product.device` is not `arcfox`, stop — this build is for a different
phone.

### If you are on something else

Update the phone to the current Motorola release the normal way (system
updates), or flash a stock package with **Motorola's Rescue and Smart
Assistant**. Section 2 of [INSTALL.md](INSTALL.md) documents flashing a stock
package by hand, following Motorola's own `flashfile.xml` order.

Firmware **newer** than the tested train will probably be fine and is the normal
situation as Motorola ships updates — but it is untested here, and it is worth
saying so rather than implying a guarantee.

---

## Prerequisites

| | |
|---|---|
| **Unlocked bootloader** | Motorola issues the unlock code — see their [bootloader unlock page](https://en-us.support.motorola.com/app/standalone/bootloader/unlock-your-device-a). Unlocking **wipes the phone** and voids the warranty. Do this first and let the phone boot once. |
| **`adb` and `fastboot`** | Android platform-tools. Tested with 36.0.2 on Linux. Distribution packages are often broken or ancient; prefer Google's official platform-tools download. |
| **The release files** | `lineage-23.2-<date>-UNOFFICIAL-arcfox.zip` **and** `recovery.img`. The zip alone is not enough — you need the recovery image to install it. |
| **A good USB cable** | Preferably the one that came with the phone, plugged directly into the computer, not through a hub. |
| **Charge** | 50% or more. |
| **Time** | About 15 minutes, most of it waiting. |

Confirm the tools see your phone before starting:

```bash
fastboot --version
adb version
```

---

## Verify your download

```bash
sha256sum -c lineage-23.2-<date>-UNOFFICIAL-arcfox.zip.sha256sum
```

A corrupted download wastes a full install cycle: recovery spends ~65 seconds
verifying the package before it tells you the signature is bad.

---

## Install

### 1. Get into the bootloader

Power the phone **off completely**, then hold **Volume Down + Power**.

If the phone is running and has USB debugging on, `adb reboot bootloader` also
works. From an untouched stock install it does not — stock ships with USB
debugging off, and although `adb devices` may still list the phone, every
command returns `error: closed`.

⚠️ **Do not use `adb reboot fastboot`.** That is `fastbootd`, and on this phone
`fastbootd` cannot write the partitions that matter. It looks completely healthy
and then fails every write.

Check you are in the right place:

```bash
fastboot devices                        # your serial, then "fastboot"
fastboot getvar securestate             # must be: flashing_unlocked
fastboot getvar is-userspace            # must be: no
```

⚠️ Do **not** use `fastboot getvar unlocked` — this bootloader has no such
variable and answers `unlocked: not found`, which reads as "locked" and is not.
`securestate` is the one that answers. Ignore the neighbouring `secure: yes`
too; it is unrelated to whether the bootloader is unlocked.

### 2. Flash the recovery image

```bash
fastboot flash recovery recovery.img
fastboot reboot recovery
```

### 3. On the phone: Advanced → Enable ADB

Use the phone's screen — **Advanced → Enable ADB**. There is no prompt to accept
and no way to do this from the computer. Until you do, `adb devices` shows
`unauthorized`.

This toggle resets whenever recovery leaves sideload mode, so you will set it
again later.

### 4. Send the package

```bash
adb reboot sideload
adb sideload lineage-23.2-<date>-UNOFFICIAL-arcfox.zip
```

Expect **~65 seconds of nothing** while the signature is verified, then progress,
then a few minutes of installing. `Total xfer: 1.00x` means the file was sent.

The phone installs onto the *other* slot and switches to it, so if you started
on slot `a` you will boot on `b`. That is correct.

### 5. Wipe data — do not skip this

If recovery asks *"To install additional packages, you need to reboot recovery
first"*, that means your package installed. Decline it.

**You must now erase `/data`.** Coming from a stock install that has been booted
even once, skipping this leaves the phone in a state where **no app can reach
the network** — the browser reports `ERR_INTERNET_DISCONNECTED` while the phone
is plainly online. See [the explanation below](#after-installing-apps-have-no-internet).

Two routes. **The bootloader one is what was tested here**; the recovery menu is
the equivalent standard route but was not exercised in this round, so follow the
first if you want the path with evidence behind it.

**From the bootloader** (this is the tested one):

```bash
adb reboot bootloader          # needs Advanced -> Enable ADB again first
fastboot -w                    # erases userdata + metadata
fastboot reboot
```

`fastboot -w` prints `Erase successful, but not automatically formatting` and
`File system type raw not supported` — both are normal. The system formats the
partitions on the next boot. Observed here: the phone then reboots **twice**,
once to format `/data` and once into the system.

**From recovery** (menu equivalent): Factory reset → **Format data**, confirm,
then go back and choose **Reboot system now**. Do not forget the reboot — the
format leaves you sitting in recovery.

### 6. First boot

First boot takes 2–3 minutes and lands on the setup wizard.

USB debugging is off again after the wipe (it lives in `/data`), so you will
need to re-enable it through Developer options if you want adb afterwards.
Confirming an on-screen "Allow USB debugging" prompt during the reboots is not
enough on its own — that only re-approves the computer's key, it does not turn
the developer setting back on.

---

## Confirming it worked

The phone boots to the LineageOS setup wizard. To check from the computer, enable
USB debugging (Settings → About phone → tap **Build number** seven times →
Developer options → USB debugging):

```bash
adb -s <serial> shell getprop ro.lineage.version    # 23.2-<date>-UNOFFICIAL-arcfox
adb -s <serial> shell getprop ro.boot.slot_suffix   # the other slot from where you started
```

Until you enable USB debugging these return `error: closed`, even though
`adb devices` lists the phone as `device`.

---

## Messages that look like failures and are not

Recovery is noisy. These three are all normal on this phone, and each has sent
someone chasing a bug that was not there:

| Message | Why it is fine |
|---|---|
| `failed to verify against RSA key 0` | Recovery holds two certificates and tries them in order. Key 0 is not the one that signed the package; the **next** line, `whole-file signature verified against RSA key 1`, is the result that matters. |
| `Failed to mount /metadata: File exists` / `Invalid f2fs superblock` | `metadata` has no filesystem because Motorola's own flash sequence erases it. The installer logs that it is skipping a step and carries on. |
| `Total xfer: 1.00x` | Only means the file reached the phone. It is not an install result. |

### After installing, apps have no internet

Symptom: the browser shows `net::ERR_INTERNET_DISCONNECTED` or
`ERR_NAME_NOT_RESOLVED`, and other apps behave as though offline — while the
status bar shows a normal 5G/LTE connection and the phone really is online
(`adb shell ping` and `curl` from a shell both work).

That contrast is the tell: `adb shell` runs as uid 2000 and bypasses the per-app
network firewall, so shell tests pass while every ordinary app is blocked.

**Cause: `/data` was not erased during the install.** Stock Android leaves
`/data/system/netpolicy.xml` behind, stamped `version="14"` and with no
`lineageVersion` attribute. LineageOS reads that, concludes it is upgrading an
existing system rather than installing fresh, and runs a migration that denies
network to every app not on an allow-list — an allow-list that upstream no
longer populates. On a genuinely fresh `/data` the file does not exist, the
migration is skipped entirely, and everything works.

Measured on this device, same zip both times:

| | apps blocked | browser |
|---|---|---|
| installed without wiping `/data` | 21 | dead |
| installed with `fastboot -w` | 3 | works |

The three that remain are apps with no INTERNET permission, which is correct.

**Fix — wipe `/data`** as in step 5. That is the real fix and it is what the
install procedure now does.

**Rescue, if the phone is already installed and you do not want to wipe:**

```bash
adb -s <serial> shell settings put global restricted_networking_mode 0
```

This works immediately and survives reboots, but it is a blunt instrument: that
mode is also what powers LineageOS's per-app "block network access" feature, so
turning it off disables that feature too. Prefer the wipe.

**One message that is a real failure:**

```
E:Can't run /system/bin/update_engine_sideload (No such file or directory)
```

Your `recovery.img` is older than the build that fixed this. Use a `recovery.img`
and zip from the same release, both newer than 2026-09-02.

---

## Recovering

Nothing here is a permanent brick as long as the bootloader still responds:

```bash
fastboot devices
fastboot getvar product        # answers = the bootloader is alive
```

If it answers, you can always flash stock and start again — a failed system
install never touches the bootloader. Get a stock package with Motorola's Rescue
and Smart Assistant, or follow section 2 of [INSTALL.md](INSTALL.md).

If the computer sees nothing at all, check your computer's `dmesg` before
assuming the phone is dead: a `error -71` / `error -32` there, or a link that
negotiates at full speed, means the cable or hub.

---

## What you get

See [README.md](README.md) for the full list. In short: telephony including
VoLTE and VoWiFi, both displays and both touchscreens, all 8 cameras, WiFi,
Bluetooth, NFC, fingerprint, sensors and fold postures all work.

The one functional difference from stock is that **thermal profile switching
does not happen**. Thermal protection itself is fine — the phone still throttles
and protects itself normally — but stock's per-situation tuning (a separate
profile for camera, gaming and so on) is not applied, so under sustained heavy
load the phone starts easing off slightly sooner than stock would. In stock's
own numbers that is a 40°C rather than 42°C first mitigation point during camera
use. You are unlikely to notice it in ordinary use, and it is not an overheating
risk. README explains why it cannot be fixed.

A few things that get reported as bugs are hardware behaviour, identical on
stock: no OIS on the telephoto lens (so a zoomed photo preview shakes), and face
unlock not being accepted for payments (the sensor is a 2D camera).

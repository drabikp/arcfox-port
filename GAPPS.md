# Installing Google Apps on arcfox (razr 50 ultra)

This is the complete procedure for putting Google Apps on the LineageOS 23.2
build for the Motorola razr 50 ultra / razr+ 2024 (`arcfox`). It was run end to
end on this device on 2026-09-10 with the package named below, starting from a
freshly flashed and booted stock W1UXS36H.72-45-10-7 and following
[INSTALL-RELEASE.md](INSTALL-RELEASE.md) and then Procedure A of this document
exactly as written. (That test build was never published; the 20260915 release
adds the removal of a leftover bring-up diagnostic, official USB-debugging
semantics and the cover-display layout changes, none of which touch this
procedure.)

**Requires build `lineage-23.2-20260915-UNOFFICIAL-arcfox` or later.** Earlier
builds cannot take GApps at all — see [If you are on the 20260902 build](#if-you-are-on-the-20260902-build).

---

## The package

The [LineageOS wiki](https://wiki.lineageos.org/gapps) names one package for
LineageOS 23 (Android 16), and it is the only one that has been tested here:

| | |
|---|---|
| Package | **MindTheGapps 16.0.0 arm64** |
| Download | <https://github.com/MindTheGapps/16.0.0-arm64/releases/latest> |
| Tested build | `MindTheGapps-16.0.0-arm64-20260828_065733.zip` |
| Needs | about 1.1 GB free in `product` — the 20260915 build reserves 1.9 GB |

Download the `.zip` and its `.sha256sum`, then check it:

```bash
sha256sum -c MindTheGapps-16.0.0-arm64-*.zip.sha256sum
```

Do not take the `-ATV` variant; that is for Android TV.

---

## The one rule that matters

**GApps go in after the ROM and before the ROM's first boot.** Android builds
the app database, the runtime permission grants and Google's setup flow on the
very first boot after a wipe, from whatever is in the system images at that
moment. If the phone boots LineageOS once without GApps, you have to wipe
`/data` again after adding them — otherwise Play Services runs without the
permissions it needs and keeps crashing.

So the order is always:

```
sideload ROM  →  reboot to recovery  →  sideload GApps  →  wipe /data  →  boot
```

---

## Prerequisites

- Unlocked bootloader, recent Motorola firmware, and the LineageOS recovery
  from the **same** build as the ROM zip — see
  [INSTALL-RELEASE.md](INSTALL-RELEASE.md) for all of that.
- `adb` from Google's platform-tools on your computer.
- The ROM zip and the MindTheGapps zip, both checksum-verified.

Two things about LineageOS recovery on this phone that trip people up:

- **ADB in recovery is off until you turn it on**, from the phone's screen:
  *Advanced → Enable ADB*. There is no computer-side prompt. Until you do,
  `adb devices` shows `unauthorized`. The toggle resets every time recovery
  leaves sideload mode, so you will do this more than once.
- **The phone has two slots.** A package sideloaded from recovery installs to
  the *other* slot and switches to it. That is why the "reboot to recovery"
  step below exists: it boots the recovery of the slot you just installed to.

---

## Procedure A — fresh install (from stock, or wiping anyway)

This is the normal path. It takes about 15 minutes.

### 1. Boot LineageOS recovery

From the bootloader (Volume Down + Power from power-off):

```bash
fastboot flash recovery recovery.img
fastboot reboot recovery
```

If LineageOS 20260915 or later is already installed, `adb reboot recovery`
from the running system works too.

### 2. Sideload the ROM

On the phone: *Advanced → Enable ADB*. Then:

```bash
adb reboot sideload
adb sideload lineage-23.2-<date>-UNOFFICIAL-arcfox.zip
```

Expect about a minute of nothing while the signature is checked, then progress,
then a few minutes of installing. `Total xfer: 1.00x` on the computer means the
file was sent; the phone's screen shows the install result.

### 3. Reboot to the new slot's recovery

Recovery now asks:

> *To install additional packages, you need to reboot recovery first.*

**Answer yes.** The phone reboots into the recovery of the slot the ROM was
just installed to, in about 20 seconds.

If you dismissed the prompt, use *Advanced → Reboot to recovery* instead. Do
**not** choose *Reboot system now* here — that boots the ROM without GApps and
sends you to [Procedure B](#procedure-b--adding-gapps-to-an-installed-rom).

### 4. Sideload GApps

On the phone again: *Advanced → Enable ADB*. Then:

```bash
adb reboot sideload
adb sideload MindTheGapps-16.0.0-arm64-<date>.zip
```

Recovery will say **"Signature verification failed"** and ask whether to
install anyway. **Choose yes.** That is expected: the package is signed with
MindTheGapps' own key, not the ROM's. The installer then prints its own lines
on the phone (*Mounting partitions*, *Copying files*, *Done!*).

### 5. Wipe `/data`

On the phone: *Factory Reset → Format Data/Factory Reset → Format Data*,
confirm. This is three menus deep. It is required on a fresh install anyway
(see INSTALL-RELEASE.md for why), and it is what makes GApps take effect.

### 6. Boot

*Reboot system now.* First boot takes 2–3 minutes and lands on **Google's**
setup wizard, which offers to sign in to a Google account. Play Store, Play
Services and the Google app are present.

---

## Procedure B — adding GApps to an installed ROM

Use this when LineageOS 20260915 or later is already installed and has been
booted. Your data will be wiped; back it up first.

1. From the running system: `adb reboot recovery`
   (or hold Volume Down + Power from power-off, then `fastboot reboot recovery`).
2. *Advanced → Enable ADB*, then `adb reboot sideload` and
   `adb sideload MindTheGapps-16.0.0-arm64-<date>.zip`.
   Choose **yes** at "Signature verification failed".
3. *Factory Reset → Format Data/Factory Reset → Format Data*, confirm.
4. *Reboot system now.*

Skipping step 3 is the mistake to avoid. The install itself succeeds, but Play
Services will not work on a `/data` that was created without it.

---

## If you are on the 20260902 build

That build has two defects that make this impossible without a slot switch:

- its package did not write a recovery to the slot it installed to, so that
  slot still holds Motorola's recovery;
- its `vendor_boot` lacks the kernel modules recovery mode needs, so **no**
  recovery image can start on that slot — Motorola's or LineageOS'.

Any "reboot to recovery" on that slot restarts the phone over and over with
nothing on USB. **Do not** try `fastboot flash recovery` + `fastboot reboot recovery`
there: it loops the same way, and this bootloader keeps the recovery request
armed until a recovery actually starts, so even `fastboot reboot` re-enters the
loop.

The way out is the slot you installed *from*, which still has stock firmware
plus the LineageOS recovery you flashed at install time:

```bash
# hold Volume Down + Power until the bootloader appears, then:
fastboot getvar current-slot           # the slot you are stuck on, e.g. b
fastboot --set-active=a                # the other one
fastboot reboot recovery               # starts the recovery you flashed at install
```

From that recovery follow [Procedure A](#procedure-a--fresh-install-from-stock-or-wiping-anyway)
from step 2 with the **20260915 or later** ROM zip. It lands on the slot you
came from, replaces its boot chain and recovery, and the "reboot to recovery"
prompt then works. Your data survives the ROM update; the wipe in step 5 is
still required for GApps.

---

## After installing

Check from the computer if you like:

```bash
adb shell pm list packages | grep -E "gms|vending|gsf"
# com.google.android.gms, com.android.vending, com.google.android.gsf
```

**The browser icon is missing from the dock.** This is cosmetic and expected.
The launcher fills that dock slot at its first start by resolving a plain web
link, and only does so when exactly one system app answers. During Google's
setup wizard a wizard component also answers web links, so the slot is skipped;
the wizard disables that component again once setup is over. Jelly is installed
and is the default browser. Drag it into the dock, or *Settings → Apps →
Trebuchet → Storage → Clear storage* to rebuild the default layout with the
browser in place.

**Updating the ROM later.** A ROM zip replaces the `product` partition of the
slot it installs to, which is where GApps live. After sideloading a new ROM,
answer yes to the "reboot recovery" prompt and sideload GApps again before
booting. No wipe is needed for an update: your data and accounts stay.

---

## Troubleshooting

| What you see | Meaning |
|---|---|
| `adb devices` says `unauthorized` in recovery | ADB is off. *Advanced → Enable ADB* on the phone. It resets after every sideload. |
| `adb: error: closed` in the system after a wipe | The computer's key was wiped too. Accept the USB-debugging prompt on the phone. |
| *Signature verification failed* | Normal for MindTheGapps. Choose yes. |
| *Not enough space for GApps! Aborting* | You are on a build older than 20260915. Its images ship 100% full. Update the ROM first. |
| Phone restarts endlessly after "reboot to recovery", nothing on USB | You are on the 20260902 build. See [above](#if-you-are-on-the-20260902-build). |
| *Error in /sideload/package.zip (status 1)* with no other text | The installer aborted before printing. Almost always the space case above. |
| Play Services keeps stopping after boot | GApps were added after a boot without them. Wipe `/data` (Procedure B step 3) and boot again. |

Only MindTheGapps has been tested. Other packages are outside what this
document can vouch for.

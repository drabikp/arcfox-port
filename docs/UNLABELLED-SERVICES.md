# 22 vendor services init CANNOT start (found 2026-08-12)

Every binary below is **shipped and present on the device**, its `.rc` file is
shipped and parsed, and init still refuses to start the service:

```
E init: Control message: Could not ctl.start for 'vendor.motosxf' from pid ...:
  File /vendor/bin/hw/motosxf (labeled "u:object_r:vendor_file:s0") has incorrect
  label or no domain transition from u:r:init:s0 to another SELinux domain defined.
```

The binaries carry generic `vendor_file` because this tree never shipped their
`file_contexts` lines or their domains. Same class of bug as `init.oem.hw.sh`
(fixed, and it turned out to be what unblocked UTAGs) and `init.mmi.usb.sh`
(still deliberately deferred).

**Note on detection:** `init.svc.<name>` does NOT exist for a service that has
never been started, so its absence is not proof the rc failed to parse. Prove it
by running `start <service>` and reading the init error.

## How this was found

```sh
adb shell 'for f in /vendor/etc/init/*.rc; do awk "/^service /{print \$2\" \"\$3}" $f; done' \
  | sort -u | while read name bin; do ls -lZ "${bin/#\/system\/vendor//vendor}"; done
```
128 services declared, 128 binaries present, **22 labelled `vendor_file`**.

## The 22, with stock's label

| service | binary | stock label | stock cil rules |
|---|---|---|---|
| `dms-hal` | `/vendor/bin/hw/vendor.dolby.dms.service` | `u:object_r:hal_aidl_dms_default_exec:s0` | 14 |
| `ifaa-1-0` | `/vendor/bin/hw/vendor.zui.hardware.ifaa@1.0-service` | `u:object_r:hal_ifaa_default_exec:s0` | 26 |
| `imgtuner-hal` | `/vendor/bin/hw/motorola.hardware.camera.imgtuner.aidl-service` | `u:object_r:hal_imagetuner_default_exec:s0` | 12 |
| `panel-aidl-service` | `/vendor/bin/hw/com.motorola.hardware.display.panel-service` | `u:object_r:hal_moto_panel_default_exec:s0` | 26 |
| `vendor.diagcommd` | `/vendor/bin/diagcommd` | `(none in stock)` | 0 |
| `vendor.ese_upgrade` | `/vendor/bin/hw/ese_upgrade` | `u:object_r:ese_upgrade_exec:s0` | 19 |
| `vendor.face-default` | `/vendor/bin/hw/android.hardware.biometrics.face@1.0-service.face` | `(none in stock)` | 0 |
| `vendor.mot.camera.desktop-hal-2-0` | `/vendor/bin/hw/motorola.hardware.camera.desktop@2.0-service` | `(none in stock)` | 0 |
| `vendor.mot.fdr-hal` | `/vendor/bin/hw/motorola.hardware.fdr-service` | `u:object_r:hal_fdrcontrol_default_exec:s0` | 18 |
| `vendor.mot.health-hal-aidl` | `/vendor/bin/hw/motorola.hardware.health-service` | `u:object_r:hal_mothealth_default_exec:s0` | 18 |
| `vendor.mot.health-storage-hal-aidl` | `/vendor/bin/hw/motorola.hardware.health.storage-service` | `u:object_r:hal_health_storage_default_exec:s0` | 14 |
| `vendor.mot.input-hal-1-1` | `/vendor/bin/hw/motorola.hardware.input@1.1-service` | `u:object_r:hal_motinput_default_exec:s0` | 13 |
| `vendor.mot.powershare-hal` | `/vendor/bin/hw/motorola.hardware.wireless.powershare-service` | `u:object_r:hal_motpowershare_default_exec:s0` | 17 |
| `vendor.mot.touch-hal` | `/vendor/bin/hw/com.motorola.hardware.display.touch-service` | `u:object_r:hal_mottouch_default_exec:s0` | 19 |
| `vendor.mot.touch-hal-1-2` | `/vendor/bin/hw/com.motorola.hardware.display.touch@1.2-service` | `u:object_r:hal_mottouch_default_exec:s0` | 19 |
| `vendor.mot.vibrator-hal-1-0` | `/vendor/bin/hw/motorola.hardware.vibrator@1.0-service` | `u:object_r:hal_motvibrator_default_exec:s0` | 13 |
| `vendor.mot.wlc-hal` | `/vendor/bin/hw/motorola.hardware.wireless.wlc-service` | `u:object_r:hal_motwlc_default_exec:s0` | 17 |
| `vendor.motosxf` | `/vendor/bin/hw/motosxf` | `u:object_r:hal_motsxf_default_exec:s0` | 43 |
| `vendor.thermalstatus` | `/vendor/bin/hw/com.motorola.thermalstatus@service` | `u:object_r:hal_thermalstatus_default_exec:s0` | 18 |
| `vendor.tzlogd` | `/vendor/bin/tzlogd` | `u:object_r:tzlogd_exec:s0` | 13 |
| `vendor.zui_power_off_alarm` | `/vendor/bin/zui_power_off_alarm` | `u:object_r:zui_power_off_alarm_exec:s0` | 16 |
| `zui-alarm-hal-1-0` | `/vendor/bin/hw/vendor.zuialarm.hardware.alarm@1.0-service` | `u:object_r:hal_alarm_zui_default_exec:s0` | 17 |

## Priority — CORRECTED after measuring, and it is lower than it first looked

My first pass ranked wireless charging and powershare as "plausibly dead
features". **That was wrong** and is retracted. What the device actually shows:

* `/sys/class/power_supply/wireless` exists, reports `type=Wireless`, and is
  already correctly labelled `vendor_sysfs_usb_supply`. AOSP's own health HAL
  reads it — `dumpsys battery` prints `Wireless powered: false` with nothing on
  the pad. **The standard wireless-charging path works without the Motorola
  HAL.** Same for battery, touch, display, sensors and input: all work today
  through AOSP/QCOM paths.
* **Nothing on the framework side ever asks for these interfaces.** A grep of a
  full logcat for `motorola.*` / `com.motorola.*` / `vendor.zui.*` service
  lookups returns *zero*. LineageOS does not ship the Motorola framework
  components that would bind `motorola.hardware.*`, so a started HAL would have
  no client.

So this is **correctness and parity work, not a functional repair.** Do not
expect a user-visible feature to appear.

### The one thing that IS genuinely wrong

Our vendor VINTF manifest **declares 19 of these HALs** (`vintf dm` lists
com.motorola.hardware.display.panel, .touch, thermalstatus, health,
health.storage, input, wireless.powershare, wireless.wlc, sxf, fdr,
camera.desktop, imgtuner, ifaa, zuialarm …), and
`device/motorola/sm8635-common/device_framework_matrix.xml` puts 19 motorola
entries in the framework matrix — while **not one of those services can start.**

`checkvintf` never caught it because it compares the vendor *manifest* against
the framework *matrix*: declarations against declarations. It has no idea
whether anything actually serves the interface. Same failure shape as the
codec2 lesson in HANDOFF-NEXT — a manifest entry is a promise, not a service.

So the honest choice is between two consistent end states, not one:

  a. **Port the domains** so the declarations become true, or
  b. **Remove the declarations** for HALs we do not intend to run, so the
     manifest stops promising what the device cannot deliver.

(b) is cheaper, carries no boot risk, and is arguably more correct for a port
that does not ship Motorola's framework. (a) is the right answer only for HALs
something will actually call.

### If porting anyway, in rough order of defensibility

`mot.health` + `mot.health.storage` (stock runs these *instead of* AOSP's
`hal_health_default`, and their absence is why AOSP's hit the power-supply
denials fixed in 450fd3e) > `thermalstatus` > `panel` / `touch` / `input`
(parity for the display stack) > everything else.

**Low value, explicitly:** `mot vibrator` (haptics already work via the QTI
vibrator service — real amplitude-stepped effects measured in
`VibratorManagerService` history), `ifaa` / `zui` alarm (Chinese-market Alipay
auth and ZUI alarm, irrelevant on a `reteu` unit), Dolby `dms-hal`
(`dolbycodec2` was already deliberately dropped — shipping DMS alone is half a
pair).

**Three have no stock `file_contexts` entry at all** — `vendor.diagcommd`,
`vendor.face-default`, `vendor.mot.camera.desktop-hal-2-0`. Stock cannot start
those either, so they are stock parity. Do NOT invent labels for them.

## How to port one

For each, two halves are required — the label alone is not enough:

1. `sepolicy/vendor/file_contexts` — take stock's line verbatim from
   `vendor/etc/selinux/vendor_file_contexts` (escapes intact).
2. `sepolicy/vendor/<domain>.te` — port the rules from
   `vendor/etc/selinux/vendor_sepolicy.cil`. Extract with:

```sh
CIL=.../vendor/etc/selinux/vendor_sepolicy.cil
grep -E "\bhal_motwlc_default\b" $CIL
```

CIL is s-expression form; translate `(allow X Y (class (perms)))` to
`allow X Y:class { perms };`. Domain skeleton is the usual
`type X, domain; type X_exec, exec_type, vendor_file_type, file_type;
init_daemon_domain(X)` plus `hal_server_domain` where it is a HAL.

## ⚠️ Do this in its own boot cycle

18 new domains at once is a lot of new attack surface on a device whose only
channel is adb. A bad domain can cost the boot. Land them in small batches, keep
`m selinux_policy` green at every step, and have fastboot ready — the same
discipline `init.mmi.usb.sh` is waiting on.

---

## CORRECTIONS (2026-09-01, re-audited)

⚠️ **The set is 44 services / 43 distinct binaries, not 22.** The earlier audit
walked only `/vendor/etc/init/*.rc` and missed `/vendor/etc/init/hw/*.rc` — the
whole `init.mmi.*` family.

⚠️ **`motorola.hardware.camera.desktop@2.0-service` DOES have a stock label**
(`hal_cameradesktop_default_exec`, 18 CIL references, matched by the regex at
`vendor_file_contexts:394`). This document lists it as "(none in stock)".
Only THREE binaries genuinely have no stock label: `diagcommd`,
`android.hardware.biometrics.face@1.0-service.face`, and `sys_monitor` — the
last of which the earlier audit missed entirely.

⚠️ **The audit recipe in this document can no longer be run as written.**
`adb shell ls -Z /vendor/bin` now returns "Permission denied" — the shell domain
has lost getattr there. Reproduce it offline instead: implement `selabel_lookup`
against the built `plat`/`system_ext`/`product`/`vendor`/`odm` `file_contexts`
in `out/target/product/arcfox` (regex specs first, exact specs last, reverse
order, first match wins), then intersect with `installed-files-vendor.json`.

**Do NOT port these 43 binaries.** Measured across a full cold boot plus 25
minutes of steady state, the complete set of interfaces any process failed to
find contains ZERO `motorola.*`, `com.motorola.*`, `vendor.zui*` or
`vendor.dolby.*` entries. Nothing on the device ever asks for them; labelling
them would start 43 daemons with no clients. The correct action was the inverse
— stop DECLARING the 12 HALs we cannot serve, done 2026-09-01.

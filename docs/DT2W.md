# Double-tap-to-wake is firmware-backed

Charter rule: devices MUST NOT implement touch-wake features in software when the
touchscreen firmware has no hardware-backed support. Checked 2026-09-16 on build 20260915.

## How arcfox does it

1. `init.arcfox-touch-gesture.rc` writes 49 to `/sys/class/touchscreen/{primary,secondary}/gesture`.
   That only sets `gesture_mode_type` in Motorola's `touchscreen_mmi` framework.
2. At panel-off, `ts_mmi_panel_off()` takes the `TS_MMI_PM_GESTURE` branch and the panel
   driver (`goodix_brl_mmi` for the inner GT9916P, `goodix_gt96x_mmi` for the cover
   "marseille") runs `goodix_berlin_gesture_setup()`: it builds the IC gesture mask with the
   double-tap bit and sends Goodix command 0xA6 (`brl_gesture()`), then re-enables the IRQ
   and calls `enable_irq_wake()`.
3. The IC's firmware detects the double tap and raises the IRQ with event status 0x20 and
   gesture ID byte 0xCC (`GOODIX_GESTURE_DOUBLE_TAP`). The kernel does no tap timing or
   coordinate analysis: `goodix_ts_gesture.c` maps 0xCC to evcode 4,
   `ts_mmi_gesture_handler()` maps evcode 4 to `BTN_TRIGGER_HAPPY6`, and the keylayouts for
   the `double-tap` / `s-double-tap` input devices map that key to `KEYCODE_WAKEUP`.

## Runtime evidence (phone folded, cover panel active)

```
touchscreen secondary: ts_mmi_panel_off: try to enter Gesture mode
[GDX-CLI-INF][goodix_berlin_gesture_setup] Provisioned gestures 0x04; rc = 0
[GDX-CLI-INF][goodix_berlin_gesture_setup] enable double gesture mode cmd 0xff7f
[GDX-CLI-INF][goodix_berlin_gesture_setup] Send enable gesture mode 0xff7f
[GDX-CLI-INF][brl_irq_enbale] Irq enabled
```

* `/sys/kernel/irq/271/wakeup` (gdx_cli) and `/sys/kernel/irq/362/wakeup` (goodix_ts) read
  `enabled` while asleep; only the gesture branch calls `enable_irq_wake()`.
* Touch IRQ counters do not move while asleep and untouched (15 s window), so the IC is not
  streaming touch reports to a software detector.
* Stock W1UXS36H ships the same three modules (`goodix_brl_mmi`, `goodix_gt96x_mmi`,
  `touchscreen_mmi`) with the same `goodix_berlin_gesture_setup` / `brl_gesture` path, and
  stock's touch HAL writes the same node value (see the rc comments).

## Cost

With the gesture armed the IC sits in its low-power gesture mode instead of deep sleep.
`ro.vendor.arcfox.dt2w=0` in vendor.prop disables it.

## Optional confirmation

Double-tap the closed phone, then within two minutes run:

```
adb shell dmesg | grep -E "gesture_type = 204|double tap; x="
```

The first line is the IC's ID 0xCC arriving; the second is the framework turning it into
the wake key.

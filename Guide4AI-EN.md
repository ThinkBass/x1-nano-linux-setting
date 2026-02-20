[한국어](Guide4AI.md) | **English**

# ThinkPad X1 Nano Gen 2 — Linux Hardware Issue Root Cause Analysis

This document summarizes the **root cause analysis** of hardware issues encountered when running Linux on the ThinkPad X1 Nano Gen 2. Intended as a reference for those who want to fix issues manually or with the help of AI, without relying on pre-made scripts.

## 1. Audio — Volume Keys Don't Change Actual Volume

### Symptoms

- Pressing volume keys (F1–F3) moves the on-screen volume slider, but actual speaker output volume does not change.
- `amixer sget Speaker` shows no `pvolume` (hardware volume) entry.

### Cause

The audio codec is **Realtek ALC287**.

The kernel's HDA driver (`snd-hda-intel`) applies codec quirks based on subsystem ID. The X1 Nano Gen 2's subsystem ID **`17aa:22fa`** has no quirk registered in the kernel.

This causes a fallback to the generic entry (`17aa:0000`), which routes the speaker output (Node `0x17`) to **DAC `0x06` — a DAC without a volume amplifier**. As a result, software volume adjustments have no effect on actual output.

### Key Details

| Item | Value |
|------|-------|
| Codec | Realtek ALC287 |
| Subsystem ID | `17aa:22fa` |
| Problematic DAC | `0x06` (no volume amp) |
| Correct DAC | `0x02` (has volume amp) |
| Speaker node | `0x17` |

### Fix Direction

Disabling DAC `0x06` forces the speaker to reroute to DAC `0x02` which has a volume amplifier. Apply the `model=alc295-disable-dac3` hint to the `snd-hda-intel` module.

Config location: create a file under `/etc/modprobe.d/`.

Alternative model hints (if the above doesn't work):
- `alc287-yoga9-bass-spk-pin`
- `alc285-speaker2-to-dac1`

---

## 2. WWAN Modem — Dies After Hibernate Resume

### Symptoms

- After hibernation resume, the WWAN modem gets stuck in `disabled` or `low power` state.
- `mmcli -m 0 --enable` returns `"Invalid transition"` error.
- `dmesg` shows MHI probe failure (`-110` timeout).

### Cause

The WWAN modem is **Foxconn T99W175** (Qualcomm SDX55-based), connected as a PCI device (address: `0000:08:00.0`). The kernel driver is `mhi-pci-generic`.

Four issues occur simultaneously during hibernate:

| Cause | Result |
|-------|--------|
| Stale MHI controller state persists in hibernate image | Driver probe failure (-110 timeout) on resume |
| Modem hardware is not reset | Stuck in `disabled`/`low power` state |
| ModemManager (MM) holds stale modem object | "Invalid transition" when trying to enable |
| FCC lock state is not cleared | Cannot enable modem (OperationNotAllowed) |

### Key Details

| Item | Value |
|------|-------|
| Modem | Foxconn T99W175 (SDX55) |
| PCI address | `0000:08:00.0` |
| Kernel driver | `mhi-pci-generic` |
| FCC unlock | Lenovo official snap `lenovo-wwan-dpr` |

### Fix Direction

A systemd sleep hook (`/lib/systemd/system-sleep/`) is needed to manually tear down and restore the modem around hibernate.

**Before hibernate (pre):**
1. Disconnect WWAN connection (gsm)
2. Disable modem (`mmcli -m 0 --disable`)
3. Stop ModemManager
4. Unbind MHI PCI driver (`/sys/bus/pci/drivers/mhi-pci-generic/unbind`)
5. Remove PCI device (`/sys/bus/pci/devices/0000:08:00.0/remove`)

**After hibernate resume (post):**
1. PCI bus rescan (`/sys/bus/pci/rescan`)
2. rfkill toggle (block → unblock) to hardware-reset the modem
3. Restart ModemManager
4. Restart `lenovo-wwan-dpr` (DPR/FCC unlock)

Adequate delays are needed between steps — especially after PCI rescan for device recognition and after DPR restart for FCC unlock completion.

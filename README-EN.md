[한국어](README.md) | **English**

# ThinkPad X1 Nano Gen 2 — Linux (Linux Mint) Setup Troubleshooting

A collection of scripts to fix hardware issues on the ThinkPad X1 Nano Gen 2 running Linux Mint.

Tested on **Linux Mint 22.3 Cinnamon**.

## Background

While installing and setting up Linux Mint on the X1 Nano Gen 2, several hardware features were found to be non-functional out of the box. Root causes were investigated one by one, and fixes were packaged into scripts. This repo only covers issues personally encountered, so it does not cover every possible issue.

For root cause analysis to fix issues manually or with AI assistance, see [Guide4AI-EN.md](Guide4AI-EN.md).

## Issues Addressed

| # | Issue | Symptom | Script |
|---|-------|---------|--------|
| 1 | Audio volume keys not working | Volume slider moves but actual sound doesn't change | `fix-audio.sh` |
| 2 | No hibernate option | Hibernate missing from power menu | `setup-hibernate.sh` |
| 3 | WWAN modem FCC unlock | Modem unusable | `setup-wwan-driver.sh` |
| 4 | WWAN dies after hibernate | Modem stuck in disabled state after hibernate resume | `setup-wwan-hibernate.sh` |
| 5 | Excessive CPU boost | P-cores boost up to 4.8GHz, causing heat and power drain | `setup-cpu-freq-limit.sh` |

## Execution Order

Scripts have dependencies, so the following order is recommended.

```
1. fix-audio.sh              ← Run if you have audio issues
2. setup-hibernate.sh        ← Skip if you don't need hibernate
3. setup-wwan-driver.sh      ← Skip if you don't have or use a WWAN modem
4. setup-wwan-hibernate.sh   ← Only run if both 2 and 3 are applied
5. setup-cpu-freq-limit.sh   ← Optional
```

> **Note**: #4 (`setup-wwan-hibernate.sh`) only makes sense when both #2 (Hibernate) and #3 (WWAN driver) are applied. If you don't use hibernate or WWAN, you can skip #2–4 entirely.

---

### Test Hardware

| Item | Spec |
|------|------|
| CPU | Intel Core i7-1280P |
| RAM | 32GB |
| WWAN | Snapdragon X55 5G (Foxconn T99W175) |
| Display | 13" 2K (non-touch) |

---

## 1. Audio — Volume Key Fix

**Script**: `fix-audio.sh` (reboot required)

### Problem

Pressing volume keys (F1–F3) moves the on-screen slider but doesn't change actual speaker output.

### Cause

The kernel's HDA driver (`snd-hda-intel`) has no quirk registered for this laptop's subsystem ID (`17aa:22fa`), so it falls back to generic (`17aa:0000`). This routes the speaker (Node 0x17) to **DAC 0x06 which has no volume amplifier**, making software volume adjustments ineffective.

### Fix

Apply the `alc295-disable-dac3` model hint to disable DAC 0x06. The speaker is then rerouted to DAC 0x02 which has a volume amplifier.

```bash
sudo ./fix-audio.sh
sudo reboot
```

### Verification

```bash
sudo dmesg | grep -i 'alc287.*fixup'   # Should show "alc295-disable-dac3"
amixer sget Speaker                      # Should show pvolume
```

### Notes

- Alternative model hints if the above doesn't work: `alc287-yoga9-bass-spk-pin`, `alc285-speaker2-to-dac1`

---

## 2. Hibernate Setup

**Script**: `setup-hibernate.sh` (reboot required)

### Problem

"Hibernate" option missing from the power menu.

### Cause

1. Default swap (8GB) is smaller than RAM (32GB), insufficient for hibernate image
2. Kernel lacks `resume=` parameter for restore
3. polkit policy doesn't allow hibernate

### Fix

Auto-detects RAM size and expands swap (RAM + 25%) → adds GRUB resume parameter → enables polkit policy → configures initramfs, all in one step.

```bash
sudo ./setup-hibernate.sh
sudo reboot
```

### Verification

```bash
sudo systemctl hibernate
```

### Notes

- Swap file must be created with `dd`. `fallocate` leaves unwritten blocks causing hibernate restore failure (`PM: Image not found, code -22`)
- If swap file is recreated, `resume_offset` changes — re-run the script
- Swap size is auto-calculated (RAM + 25%, e.g. 32GB RAM → 40GB swap)
- Secure Boot may require additional configuration

---

## 3. WWAN Driver Installation

**Script**: `setup-wwan-driver.sh` (no reboot required)

### Problem

WWAN modem (Foxconn T99W175) is unusable without FCC unlock.

### Fix

Installs Lenovo's official snap driver `lenovo-wwan-dpr`. On Linux Mint, snapd is blocked by default, so the script handles: removing snap block → installing/enabling snapd → installing the driver.

```bash
sudo ./setup-wwan-driver.sh
```

### Verification

```bash
snap list lenovo-wwan-dpr
snap services lenovo-wwan-dpr
```

### Notes

- Linux Mint blocks snapd via `/etc/apt/preferences.d/nosnap.pref`; the script removes it automatically
- Must be run before `setup-wwan-hibernate.sh`

---

## 4. WWAN Hibernate Recovery

**Script**: `setup-wwan-hibernate.sh` (no reboot required)

### Problem

Foxconn T99W175 (SDX55) modem dies after hibernate resume. MHI controller context is lost, modem gets stuck in `disabled`/`low power`, and `mmcli --enable` returns "Invalid transition".

### Cause

| Cause | Result |
|-------|--------|
| Stale MHI state in hibernate image | Driver probe failure (-110) on resume |
| Modem hardware not reset | Stuck in disabled/low power |
| ModemManager holds stale modem object | "Invalid transition" on enable |
| FCC lock state persists | Cannot enable modem (OperationNotAllowed) |

### Fix

Installs a systemd sleep hook for automatic cleanup before and recovery after hibernate:

- **Pre-hibernate**: Disconnect WWAN → disable modem → stop MM → unbind driver → PCI remove
- **Post-hibernate**: PCI rescan → rfkill toggle → restart MM → restart DPR (FCC unlock)

```bash
sudo ./setup-wwan-hibernate.sh
```

### Verification

Check if WWAN auto-recovers after hibernate. Logs:

```bash
cat /var/log/wwan-hibernate.log
```

### Notes

- `setup-hibernate.sh` must be applied first so hibernate actually works
- WWAN connection (NetworkManager) autoconnect must be enabled for automatic reconnection after recovery

---

## 5. CPU Frequency Limit (Optional)

**Script**: `setup-cpu-freq-limit.sh` (no reboot required, applied immediately)

### Problem

P-cores boost up to 4.7–4.8GHz by default, causing excessive heat and power consumption.

### Cause

12th gen Alder Lake's default turbo boost policy is too aggressive for mobile use.

### Fix

Auto-detects CPU model and registers a systemd service that limits P-cores to max 3.6GHz and E-cores to max 2.4GHz.

Supported CPUs:

| Model | Configuration |
|-------|---------------|
| i7-1280P | 6P(12t) + 8E |
| i7-1270P / 1260P | 4P(8t) + 8E |
| i5-1250P / 1240P | 4P(8t) + 8E |
| i7-1265U / 1255U | 2P(4t) + 8E |
| i5-1245U / 1235U | 2P(4t) + 8E |

If auto-detection fails, a manual selection menu is shown. To change frequency limits, modify `P_CORE_MAX` and `E_CORE_MAX` at the top of the script.

```bash
sudo ./setup-cpu-freq-limit.sh
```

### Verification

```bash
systemctl status cpu-freq-limit.service
```

### To Disable

```bash
sudo systemctl disable --now cpu-freq-limit.service
```

---

## Modified System Files

| File | Script | Purpose |
|------|--------|---------|
| `/etc/modprobe.d/alc287-fix.conf` | fix-audio.sh | Audio DAC model hint |
| `/swap.img` | setup-hibernate.sh | Swap file (RAM + 25%) |
| `/etc/default/grub` | setup-hibernate.sh | Add resume parameter |
| `/etc/polkit-1/rules.d/10-enable-hibernate.rules` | setup-hibernate.sh | Allow hibernate |
| `/etc/initramfs-tools/conf.d/resume` | setup-hibernate.sh | initramfs resume config |
| `/lib/systemd/system-sleep/wwan-hibernate.sh` | setup-wwan-hibernate.sh | WWAN hibernate recovery hook |
| `/usr/local/bin/cpu-freq-limit.sh` | setup-cpu-freq-limit.sh | CPU frequency limit script |
| `/etc/systemd/system/cpu-freq-limit.service` | setup-cpu-freq-limit.sh | CPU frequency limit service |

**한국어** | [English](README-EN.md)

# ThinkPad X1 Nano Gen 2 — 리눅스 (Linux Mint) 세팅 트러블슈팅

ThinkPad X1 Nano Gen 2에서 Linux Mint를 사용할 때 발생하는 하드웨어 이슈들을 해결하는 스크립트 모음.

**Linux Mint 22.3 Cinnamon** 에서 테스트됨.

## 배경

X1 Nano Gen 2에 Linux Mint를 설치하고 세팅하는 과정에서, 정상 작동하지 않는 기능들을 발견함. 
원인을 하나하나 파악하고 수정한 내용을 스크립트로 정리했음. 
직접 사용하면서 발견한 문제만 다루고 있으므로, 모든 이슈를 포괄하지는 않음.

스크립트 없이 직접 해결하거나, AI의 도움을 받아 해결하려는 경우 [Guide4AI.md](Guide4AI.md)에 원인 분석을 정리해 두었음.

## 해결한 문제 목록

| # | 문제 | 증상 | 스크립트 |
|---|------|------|----------|
| 1 | 오디오 볼륨 키 안 먹힘 | 볼륨 게이지만 움직이고 실제 소리 불변 | `fix-audio.sh` |
| 2 | 최대 절전모드 없음 | 전원 메뉴에 Hibernate 미표시 | `setup-hibernate.sh` |
| 3 | WWAN 모뎀 FCC unlock | 모뎀 사용 불가 | `setup-wwan-driver.sh` |
| 4 | WWAN hibernate 후 죽음 | hibernate 복귀 후 모뎀 disabled 고착 | `setup-wwan-hibernate.sh` |
| 5 | CPU 과도한 부스트 | P-core 4.8GHz까지 부스트, 발열·전력 소모 큼 | `setup-cpu-freq-limit.sh` |

## 실행 순서

스크립트 간 의존관계가 있으므로 아래 순서대로 실행을 권장함.

```
1. fix-audio.sh              ← 오디오 문제가 있다면 실행
2. setup-hibernate.sh        ← 최대 절전모드를 사용하지 않는다면 건너뛰기
3. setup-wwan-driver.sh      ← WWAN 모뎀이 없거나 사용하지 않는다면 건너뛰기
4. setup-wwan-hibernate.sh   ← 2, 3을 모두 적용한 경우에만 실행
5. setup-cpu-freq-limit.sh   ← 선택 사항
```

> **참고**: 4번(`setup-wwan-hibernate.sh`)은 2번(Hibernate)과 3번(WWAN 드라이버)이 모두 적용된 상태에서만 의미 있음. 최대 절전모드나 WWAN을 사용하지 않는다면 2~4번은 건너뛰어도 됨.

---

### 테스트 사양

| 항목 | 사양 |
|------|------|
| CPU | Intel Core i7-1280P |
| RAM | 32GB |
| WWAN | Snapdragon X55 5G (Foxconn T99W175) |
| Display | 13" 2K (non-touch) |

---

## 1. 오디오 — 볼륨 키 수정

**스크립트**: `fix-audio.sh` (재부팅 필요)

### 문제

볼륨 키(F1~F3)를 눌러도 실제 소리가 안 바뀜. 게이지만 움직임.

### 원인

커널에 이 노트북의 서브시스템 ID(`17aa:22fa`)에 대한 quirk가 없어서 제네릭 폴백(`17aa:0000`)으로 떨어짐. 이 경우 스피커(Node 0x17)가 **볼륨 앰프 없는** DAC 0x06에 연결되어 소프트웨어 볼륨이 실제 출력에 반영되지 않음.

### 해결

`alc295-disable-dac3` 모델 힌트를 적용하여 DAC 0x06을 비활성화. 스피커가 볼륨 앰프가 있는 DAC 0x02로 재연결됨.

```bash
sudo ./fix-audio.sh
sudo reboot
```

### 확인

```bash
sudo dmesg | grep -i 'alc287.*fixup'   # "alc295-disable-dac3" 표시 확인
amixer sget Speaker                      # pvolume 존재 확인
```

### 주의사항

- 위 모델 힌트가 안 될 경우 대안: `alc287-yoga9-bass-spk-pin`, `alc285-speaker2-to-dac1`

---

## 2. 최대 절전모드 (Hibernate) 활성화

**스크립트**: `setup-hibernate.sh` (재부팅 필요)

### 문제

전원 메뉴에 "최대 절전 모드"가 없음.

### 원인

1. 기본 Swap(8GB)이 RAM(32GB)보다 작아 hibernate 이미지 저장 불가
2. 커널에 `resume=` 파라미터가 없어 복원 불가
3. polkit 정책이 hibernate를 허용하지 않음

### 해결

RAM 용량을 자동 감지하여 Swap 확장(RAM + 25%) → GRUB resume 파라미터 추가 → polkit 허용 → initramfs 설정을 한번에 처리.

```bash
sudo ./setup-hibernate.sh
sudo reboot
```

### 확인

```bash
sudo systemctl hibernate
```

### 주의사항

- Swap 파일은 반드시 `dd`로 생성해야 함. `fallocate`는 unwritten 블록이 남아 hibernate 복원 실패 (`PM: Image not found, code -22`)
- Swap 파일을 재생성하면 `resume_offset`이 바뀌므로 스크립트를 다시 실행해야 함
- Swap 크기는 자동 계산됨 (RAM + 25%, 예: 32GB RAM → 40GB Swap)
- Secure Boot 환경에서는 추가 설정이 필요할 수 있음

---

## 3. WWAN 드라이버 설치

**스크립트**: `setup-wwan-driver.sh` (재부팅 불필요)

### 문제

WWAN 모뎀(Foxconn T99W175)이 FCC unlock 없이는 사용 불가.

### 해결

Lenovo 공식 snap 드라이버 `lenovo-wwan-dpr`을 설치. Linux Mint의 경우 snapd가 기본 차단되어 있으므로, snap 차단 해제 → snapd 설치/활성화 → 드라이버 설치를 자동 처리.

```bash
sudo ./setup-wwan-driver.sh
```

### 확인

```bash
snap list lenovo-wwan-dpr
snap services lenovo-wwan-dpr
```

### 주의사항

- Linux Mint는 `/etc/apt/preferences.d/nosnap.pref`로 snapd를 차단하고 있으며, 스크립트가 자동으로 제거함
- `setup-wwan-hibernate.sh`보다 먼저 실행해야 함

---

## 4. WWAN Hibernate 복구

**스크립트**: `setup-wwan-hibernate.sh` (재부팅 불필요)

### 문제

Foxconn T99W175 (SDX55) 모뎀이 hibernate 복귀 후 죽음. MHI 컨트롤러 컨텍스트가 소실되어 모뎀이 `disabled`/`low power`에 고착되며, `mmcli --enable` 시 "Invalid transition" 발생.

### 원인

| 원인 | 증상 |
|------|------|
| hibernate 이미지에 stale MHI 상태 잔존 | 복귀 후 probe 실패 (-110) |
| 모뎀 하드웨어 리셋 안 됨 | disabled/low power 고착 |
| MM이 stale 모뎀 객체 보유 | "Invalid transition" |
| FCC lock 상태 유지 | 모뎀 enable 불가 (OperationNotAllowed) |

### 해결

systemd sleep hook을 설치하여 hibernate 전후로 자동 처리:

- **Pre-hibernate**: WWAN 연결 해제 → 모뎀 disable → MM 중지 → 드라이버 unbind → PCI remove
- **Post-hibernate**: PCI rescan → rfkill 토글 → MM 재시작 → DPR(FCC unlock) 재실행

```bash
sudo ./setup-wwan-hibernate.sh
```

### 확인

hibernate 후 WWAN이 자동 복구되는지 확인. 로그:

```bash
cat /var/log/wwan-hibernate.log
```

### 주의사항

- `setup-hibernate.sh`를 먼저 실행하여 hibernate가 동작하는 상태여야 의미 있음
- WWAN 연결(NetworkManager)의 autoconnect가 켜져 있어야 복구 후 자동 재연결됨

---

## 5. CPU 클럭 제한 (옵션)

**스크립트**: `setup-cpu-freq-limit.sh` (재부팅 불필요, 즉시 적용)

### 문제

기본 상태에서 P-core가 4.7~4.8GHz까지 부스트되어 발열 및 전력 소모가 큼.

### 원인

12세대 Alder Lake의 기본 터보 부스트 정책이 모바일 환경에서 과도함.

### 해결

CPU 모델을 자동 감지하여 P-core 최대 3.6GHz, E-core 최대 2.4GHz로 제한하는 systemd 서비스를 등록.

지원 CPU:

| 모델 | 구성 |
|------|------|
| i7-1280P | 6P(12t) + 8E |
| i7-1270P / 1260P | 4P(8t) + 8E |
| i5-1250P / 1240P | 4P(8t) + 8E |
| i7-1265U / 1255U | 2P(4t) + 8E |
| i5-1245U / 1235U | 2P(4t) + 8E |

자동 감지 실패 시 수동 선택 메뉴가 표시됨. 제한 주파수를 변경하려면 스크립트 상단의 `P_CORE_MAX`, `E_CORE_MAX` 변수를 수정하면 됨.

```bash
sudo ./setup-cpu-freq-limit.sh
```

### 확인

```bash
systemctl status cpu-freq-limit.service
```

### 해제 방법

```bash
sudo systemctl disable --now cpu-freq-limit.service
```

---

## 생성/수정되는 시스템 파일

| 파일 | 스크립트 | 용도 |
|------|----------|------|
| `/etc/modprobe.d/alc287-fix.conf` | fix-audio.sh | 오디오 DAC 모델 힌트 |
| `/swap.img` | setup-hibernate.sh | Swap 파일 (RAM + 25%) |
| `/etc/default/grub` | setup-hibernate.sh | resume 파라미터 추가 |
| `/etc/polkit-1/rules.d/10-enable-hibernate.rules` | setup-hibernate.sh | Hibernate 권한 허용 |
| `/etc/initramfs-tools/conf.d/resume` | setup-hibernate.sh | initramfs resume 설정 |
| `/lib/systemd/system-sleep/wwan-hibernate.sh` | setup-wwan-hibernate.sh | WWAN hibernate 복구 hook |
| `/usr/local/bin/cpu-freq-limit.sh` | setup-cpu-freq-limit.sh | CPU 클럭 제한 스크립트 |
| `/etc/systemd/system/cpu-freq-limit.service` | setup-cpu-freq-limit.sh | CPU 클럭 제한 서비스 |

**한국어** | [English](Guide4AI-EN.md)

# ThinkPad X1 Nano Gen 2 — Linux 하드웨어 이슈 원인 분석

이 문서는 ThinkPad X1 Nano Gen 2에서 Linux 사용 시 발생하는 하드웨어 이슈의 **원인 분석**을 정리한 것임.
스크립트를 사용하지 않고 직접 해결하려는 경우, 또는 AI의 도움을 받아 해결하려는 경우 참고용으로 작성됨.

## 1. 오디오 — 볼륨 키로 실제 볼륨이 안 바뀌는 문제

### 증상

- 볼륨 키(F1~F3)를 누르면 화면의 볼륨 게이지는 움직이지만, 실제 스피커 출력 음량은 변하지 않음.
- `amixer sget Speaker` 실행 시 `pvolume`(하드웨어 볼륨) 항목이 없음.

### 원인

이 노트북의 오디오 코덱은 **Realtek ALC287**임.

커널의 HDA 드라이버(`snd-hda-intel`)는 서브시스템 ID를 기준으로 코덱 quirk(모델별 보정)를 적용하는데, X1 Nano Gen 2의 서브시스템 ID **`17aa:22fa`** 에 대한 quirk가 커널에 등록되어 있지 않음.

이 때문에 제네릭 폴백(`17aa:0000`)으로 떨어지며, 스피커 출력(Node `0x17`)이 **볼륨 앰프가 없는 DAC `0x06`** 에 연결됨. 결과적으로 소프트웨어에서 볼륨을 조절해도 실제 출력에 반영되지 않음.

### 핵심 정보

| 항목 | 값 |
|------|------|
| 코덱 | Realtek ALC287 |
| 서브시스템 ID | `17aa:22fa` |
| 문제 DAC | `0x06` (볼륨 앰프 없음) |
| 정상 DAC | `0x02` (볼륨 앰프 있음) |
| 스피커 노드 | `0x17` |

### 해결 방향

DAC `0x06`을 비활성화하면 스피커가 볼륨 앰프가 있는 DAC `0x02`로 재연결됨. `snd-hda-intel` 모듈에 `model=alc295-disable-dac3` 힌트를 적용하면 됨.

적용 위치: `/etc/modprobe.d/` 아래에 설정 파일 생성.

대안 모델 힌트 (위 힌트가 안 될 경우):
- `alc287-yoga9-bass-spk-pin`
- `alc285-speaker2-to-dac1`

---

## 2. WWAN 모뎀 — Hibernate 복귀 후 죽는 문제

### 증상

- Hibernate(최대 절전모드) 후 복귀하면 WWAN 모뎀이 `disabled` 또는 `low power` 상태에 고착됨.
- `mmcli -m 0 --enable` 실행 시 `"Invalid transition"` 에러 발생.
- `dmesg`에 MHI probe 실패 (`-110` timeout) 로그가 남음.

### 원인

WWAN 모뎀은 **Foxconn T99W175** (Qualcomm SDX55 기반)이며, PCI 디바이스로 연결됨 (주소: `0000:08:00.0`). 커널 드라이버는 `mhi-pci-generic`을 사용함.

Hibernate 시 다음 네 가지 문제가 복합적으로 발생함:

| 원인 | 결과 |
|------|------|
| Hibernate 이미지에 stale MHI 컨트롤러 상태가 잔존 | 복귀 후 드라이버 probe 실패 (-110 timeout) |
| 모뎀 하드웨어가 리셋되지 않음 | `disabled`/`low power` 상태 고착 |
| ModemManager(MM)가 stale 모뎀 객체를 보유 | `mmcli --enable` 시 "Invalid transition" |
| FCC lock 상태가 해제되지 않음 | 모뎀 enable 불가 (OperationNotAllowed) |

### 핵심 정보

| 항목 | 값 |
|------|------|
| 모뎀 | Foxconn T99W175 (SDX55) |
| PCI 주소 | `0000:08:00.0` |
| 커널 드라이버 | `mhi-pci-generic` |
| FCC unlock | Lenovo 공식 snap `lenovo-wwan-dpr` |

### 해결 방향

systemd sleep hook (`/lib/systemd/system-sleep/`)을 사용하여 hibernate 전후에 모뎀을 수동으로 정리/복구해야 함.

**Hibernate 진입 전 (pre):**
1. WWAN 연결(gsm) 해제
2. 모뎀 disable (`mmcli -m 0 --disable`)
3. ModemManager 중지
4. MHI PCI 드라이버 unbind (`/sys/bus/pci/drivers/mhi-pci-generic/unbind`)
5. PCI 디바이스 제거 (`/sys/bus/pci/devices/0000:08:00.0/remove`)

**Hibernate 복귀 후 (post):**
1. PCI 버스 재스캔 (`/sys/bus/pci/rescan`)
2. rfkill 토글 (block → unblock)로 모뎀 하드웨어 리셋
3. ModemManager 재시작
4. `lenovo-wwan-dpr` (DPR/FCC unlock) 재실행

각 단계 사이에 대기 시간이 필요하며, 특히 PCI rescan 후 디바이스 인식과 DPR 완료까지 충분히 기다려야 함.

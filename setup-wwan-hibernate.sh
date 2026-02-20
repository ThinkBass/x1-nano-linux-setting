#!/bin/bash
# setup-wwan-hibernate.sh — WWAN Hibernate 복구 sleep hook 설치
# 재부팅 불필요

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "이 스크립트는 root 권한이 필요합니다. sudo로 실행해주세요."
    exit 1
fi

HOOK_FILE="/lib/systemd/system-sleep/wwan-hibernate.sh"

echo "=== WWAN Hibernate 복구 sleep hook 설치 ==="

cat > "$HOOK_FILE" << 'HOOKEOF'
#!/bin/bash
# WWAN hibernate recovery — Foxconn T99W175 (SDX55)

LOGFILE="/var/log/wwan-hibernate.log"
PCI_ADDR="0000:08:00.0"

log() { echo "$(date '+%H:%M:%S') $1" >> "$LOGFILE"; }

# 조건 충족까지 대기 (인자: 설명, 조건 커맨드, 최대 초)
wait_for() {
    local desc="$1" cmd="$2" max="$3" i=0
    while [ $i -lt $max ]; do
        eval "$cmd" && { log "$desc: ready (${i}s)"; return 0; }
        sleep 1; i=$((i+1))
    done
    log "$desc: timeout (${max}s)"
    return 1
}

case "$1/$2" in
  pre/hibernate)
    log "=== PRE-HIBERNATE START ==="

    # gsm 타입 활성 연결 자동 감지 후 해제
    WWAN_CONN=$(nmcli -t -f NAME,TYPE connection show --active 2>/dev/null | awk -F: '$2=="gsm"{print $1}')
    if [ -n "$WWAN_CONN" ]; then
        nmcli connection down "$WWAN_CONN" 2>/dev/null
        log "connection '$WWAN_CONN' down"
    fi
    sleep 2

    # 모뎀 비활성화
    mmcli -m 0 --disable 2>/dev/null
    log "modem disabled"; sleep 2

    # ModemManager 중지
    systemctl stop ModemManager
    log "MM stopped"; sleep 1

    # MHI PCI 드라이버 unbind
    echo "$PCI_ADDR" > /sys/bus/pci/drivers/mhi-pci-generic/unbind 2>/dev/null
    log "driver unbound"; sleep 1

    # PCI 디바이스 제거
    echo 1 > "/sys/bus/pci/devices/$PCI_ADDR/remove" 2>/dev/null
    log "PCI device removed"

    log "=== PRE-HIBERNATE DONE ==="
    ;;

  post/hibernate)
    log "=== POST-HIBERNATE START ==="

    # PCI 버스 재스캔
    echo 1 > /sys/bus/pci/rescan 2>/dev/null
    log "PCI rescan triggered"
    wait_for "PCI device" "[ -d /sys/bus/pci/devices/$PCI_ADDR ]" 10

    # rfkill 토글로 모뎀 하드웨어 리셋
    rfkill block wwan 2>/dev/null; sleep 2
    rfkill unblock wwan 2>/dev/null
    log "rfkill toggled"; sleep 3

    # ModemManager 재시작
    systemctl restart ModemManager
    log "MM restarted"
    wait_for "modem detect" "mmcli -L 2>/dev/null | grep -q foxconn" 15

    # DPR(FCC unlock) 재실행
    snap restart lenovo-wwan-dpr 2>/dev/null
    log "DPR restarted"
    wait_for "DPR done" "journalctl --since '1 min ago' --no-pager -q -g 'SAR tables is correctly set' 2>/dev/null | grep -q SAR" 30

    log "=== POST-HIBERNATE DONE ==="
    ;;
esac
HOOKEOF

# 실행 권한 부여
chmod +x "$HOOK_FILE"

echo "[완료] $HOOK_FILE 설치"
echo "다음 hibernate부터 자동 적용됩니다."
echo "로그 확인: cat /var/log/wwan-hibernate.log"

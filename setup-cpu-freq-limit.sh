#!/bin/bash
# setup-cpu-freq-limit.sh — CPU 클럭 제한 서비스 설정
# 재부팅 불필요 (즉시 적용)
# 지원: 12세대 Alder Lake P/U 시리즈

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "이 스크립트는 root 권한이 필요합니다. sudo로 실행해주세요."
    exit 1
fi

FREQ_SCRIPT="/usr/local/bin/cpu-freq-limit.sh"
SERVICE_FILE="/etc/systemd/system/cpu-freq-limit.service"

# 제한 주파수
P_CORE_MAX="3600MHz"
E_CORE_MAX="2400MHz"

echo "=== CPU 클럭 제한 서비스 설정 ==="

# ─── CPU 모델 감지 ───────────────────────────────────────────────────

CPU_MODEL=$(grep -m1 'model name' /proc/cpuinfo | sed 's/.*: //')
echo "감지된 CPU: $CPU_MODEL"

# CPU 모델별 코어 구성 (P-core HT 포함 범위, E-core 범위)
#   1280P:                6P(12t) + 8E = cpu0-11, cpu12-19
#   1270P/1260P/1250P/1240P: 4P(8t) + 8E = cpu0-7, cpu8-15
#   1265U/1255U/1245U/1235U: 2P(4t) + 8E = cpu0-3, cpu4-11
detect_cpu() {
    case "$CPU_MODEL" in
        *1280P*)
            P_CORES="0-11"; E_CORES="12-19" ;;
        *1270P*|*1260P*|*1250P*|*1240P*)
            P_CORES="0-7";  E_CORES="8-15" ;;
        *1265U*|*1255U*|*1245U*|*1235U*)
            P_CORES="0-3";  E_CORES="4-11" ;;
        *)
            return 1 ;;
    esac
    return 0
}

# 자동 감지 실패 시 수동 선택
select_cpu() {
    echo ""
    echo "자동 감지 실패. CPU 모델을 선택해주세요:"
    echo "  1) i7-1280P          (6P + 8E, 20스레드)"
    echo "  2) i7-1270P / 1260P  (4P + 8E, 16스레드)"
    echo "  3) i5-1250P / 1240P  (4P + 8E, 16스레드)"
    echo "  4) i7-1265U / 1255U  (2P + 8E, 12스레드)"
    echo "  5) i5-1245U / 1235U  (2P + 8E, 12스레드)"
    echo ""
    read -rp "선택 (1-5): " choice
    case "$choice" in
        1)   P_CORES="0-11"; E_CORES="12-19" ;;
        2|3) P_CORES="0-7";  E_CORES="8-15" ;;
        4|5) P_CORES="0-3";  E_CORES="4-11" ;;
        *)   echo "잘못된 선택입니다."; exit 1 ;;
    esac
}

if ! detect_cpu; then
    select_cpu
fi

echo "  P-core: cpu${P_CORES} → 최대 ${P_CORE_MAX}"
echo "  E-core: cpu${E_CORES} → 최대 ${E_CORE_MAX}"

# ─── cpupower 설치 확인 ──────────────────────────────────────────────

KVER=$(uname -r)
if ! cpupower --version &> /dev/null 2>&1; then
    echo "cpupower 설치 중 (커널: ${KVER})..."
    apt-get install -y "linux-tools-${KVER}" linux-tools-generic
fi

# ─── 클럭 제한 스크립트 생성 ─────────────────────────────────────────

cat > "$FREQ_SCRIPT" << EOF
#!/bin/bash
# P-core(cpu${P_CORES}) 최대 ${P_CORE_MAX}
cpupower -c ${P_CORES} frequency-set -u ${P_CORE_MAX}

# E-core(cpu${E_CORES}) 최대 ${E_CORE_MAX}
cpupower -c ${E_CORES} frequency-set -u ${E_CORE_MAX}
EOF

chmod +x "$FREQ_SCRIPT"

# ─── systemd 서비스 생성 ─────────────────────────────────────────────

cat > "$SERVICE_FILE" << EOF
[Unit]
Description=CPU frequency limit (P-core ${P_CORE_MAX}, E-core ${E_CORE_MAX})
After=multi-user.target

[Service]
Type=oneshot
ExecStart=$FREQ_SCRIPT
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# ─── 서비스 등록 및 즉시 실행 ────────────────────────────────────────

# systemd에 새 서비스 파일 인식시킴
systemctl daemon-reload

# 부팅 시 자동 실행 등록
systemctl enable cpu-freq-limit.service

# 지금 바로 적용
systemctl start cpu-freq-limit.service

echo ""
echo "[완료] 서비스 활성화 및 즉시 적용"
echo ""
echo "해제 방법:"
echo "  sudo systemctl disable --now cpu-freq-limit.service"

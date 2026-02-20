#!/bin/bash
# setup-wwan-driver.sh — snapd 활성화 및 Lenovo WWAN 드라이버 설치
# 재부팅 불필요

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "이 스크립트는 root 권한이 필요합니다. sudo로 실행해주세요."
    exit 1
fi

echo "=== Lenovo WWAN 드라이버 (lenovo-wwan-dpr) 설치 ==="

# ─── snapd 설치 확인 ──────────────────────────────────────────────────

NOSNAP_FILE="/etc/apt/preferences.d/nosnap.pref"
SNAPD_NEED_INSTALL=false
SNAPD_NEED_ENABLE=false

# snapd 설치 여부 확인
if command -v snap &> /dev/null; then
    echo "[확인] snapd가 이미 설치되어 있습니다."
else
    echo "[미설치] snapd가 설치되어 있지 않습니다."
    SNAPD_NEED_INSTALL=true
fi

# ─── snapd 활성화 상태 확인 ───────────────────────────────────────────

if dpkg -l snapd &> /dev/null && ! $SNAPD_NEED_INSTALL; then
    # snapd 서비스 활성화(enabled) 여부
    if systemctl is-enabled snapd.socket &> /dev/null && systemctl is-enabled snapd &> /dev/null; then
        echo "[확인] snapd 서비스가 활성화(enabled) 상태입니다."
    else
        echo "[비활성] snapd 서비스가 비활성화(disabled) 상태입니다."
        SNAPD_NEED_ENABLE=true
    fi

    # snapd 서비스 실행(running) 여부
    if systemctl is-active snapd.socket &> /dev/null && systemctl is-active snapd &> /dev/null; then
        echo "[확인] snapd 서비스가 실행(running) 중입니다."
    else
        echo "[중지] snapd 서비스가 실행되고 있지 않습니다."
        SNAPD_NEED_ENABLE=true
    fi
else
    SNAPD_NEED_ENABLE=true
fi

# ─── snapd 설치 및 활성화 ─────────────────────────────────────────────
# Linux Mint는 기본적으로 snapd 설치를 차단하는 설정 파일이 존재함

if $SNAPD_NEED_INSTALL; then
    if [ -f "$NOSNAP_FILE" ]; then
        echo "snap 차단 설정 제거 중 ($NOSNAP_FILE)..."
        rm -f "$NOSNAP_FILE"
        apt-get update -qq
    fi

    echo "snapd 설치 중..."
    apt-get install -y snapd
fi

if $SNAPD_NEED_ENABLE; then
    echo "snapd 서비스 활성화 중..."
    systemctl enable --now snapd.socket
    systemctl enable --now snapd
fi

# snap core가 준비될 때까지 대기
echo "snapd 초기화 대기 중..."
snap wait system seed.loaded

# ─── lenovo-wwan-dpr 설치 ─────────────────────────────────────────────

if snap list lenovo-wwan-dpr &> /dev/null; then
    echo "lenovo-wwan-dpr 이미 설치됨. 최신 버전으로 갱신..."
    snap refresh lenovo-wwan-dpr
else
    echo "lenovo-wwan-dpr 설치 중..."
    snap install lenovo-wwan-dpr
fi

echo ""
echo "[완료] lenovo-wwan-dpr 설치 완료"
echo ""
echo "확인:"
echo "  snap list lenovo-wwan-dpr"
echo "  snap services lenovo-wwan-dpr"

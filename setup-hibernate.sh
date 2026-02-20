#!/bin/bash
# setup-hibernate.sh — 최대 절전모드(Hibernate) 설정
# 적용 후 재부팅 필요

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "이 스크립트는 root 권한이 필요합니다. sudo로 실행해주세요."
    exit 1
fi

SWAP_FILE="/swap.img"
GRUB_FILE="/etc/default/grub"

# RAM 용량 감지 후 swap 크기 계산 (RAM + RAM/4)
RAM_MB=$(awk '/MemTotal/{printf "%d", $2/1024}' /proc/meminfo)
SWAP_SIZE_MB=$(( RAM_MB + RAM_MB / 4 ))

echo "=== 최대 절전모드(Hibernate) 설정 ==="

# ─── 1. Swap 파일 확장 ───────────────────────────────────────────────

echo ""
echo "감지된 RAM: ${RAM_MB}MB"
echo "[1/4] Swap 파일 확장 (${SWAP_SIZE_MB}MB = RAM + 25%)..."

# 기존 swap 해제
if swapon --show | grep -q "$SWAP_FILE"; then
    swapoff "$SWAP_FILE"
fi

# 기존 swap 파일 삭제
if [[ -f "$SWAP_FILE" ]]; then
    rm "$SWAP_FILE"
fi

# swap 파일 생성 (fallocate 사용 금지 — unwritten 블록으로 hibernate 복원 실패)
dd if=/dev/zero of="$SWAP_FILE" bs=1M count="$SWAP_SIZE_MB" status=progress

# root만 읽기/쓰기
chmod 600 "$SWAP_FILE"

# swap 포맷
mkswap "$SWAP_FILE"

# swap 활성화
swapon "$SWAP_FILE"

# /etc/fstab에 swap 항목 없으면 추가
if ! grep -q "$SWAP_FILE" /etc/fstab; then
    echo "$SWAP_FILE none swap sw 0 0" >> /etc/fstab
fi

echo "  [완료]"

# ─── 2. GRUB resume 파라미터 ─────────────────────────────────────────

echo ""
echo "[2/4] GRUB resume 파라미터 설정..."

# 루트 파티션 UUID 자동 감지
ROOT_UUID=$(findmnt -no UUID /)

# swap 파일의 물리적 오프셋 자동 감지 (filefrag 첫 번째 extent)
RESUME_OFFSET=$(filefrag -v "$SWAP_FILE" | awk '/^ *0:/{print $4}' | cut -d'.' -f1)

echo "  UUID=$ROOT_UUID, offset=$RESUME_OFFSET"

if [[ -z "$ROOT_UUID" || -z "$RESUME_OFFSET" ]]; then
    echo "  [오류] UUID 또는 resume_offset 감지 실패"
    exit 1
fi

# GRUB 설정 백업
cp "$GRUB_FILE" "${GRUB_FILE}.bak"

# 기존 resume/resume_offset 파라미터 제거 후 새 값으로 교체
CURRENT=$(grep '^GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB_FILE" | sed 's/^GRUB_CMDLINE_LINUX_DEFAULT="//' | sed 's/"$//')
CLEANED=$(echo "$CURRENT" | sed -E 's/\s*resume=[^ ]*//g; s/\s*resume_offset=[^ ]*//g; s/^\s+//; s/\s+$//')
NEW_VALUE="$CLEANED resume=UUID=$ROOT_UUID resume_offset=$RESUME_OFFSET"
sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$NEW_VALUE\"|" "$GRUB_FILE"

# GRUB 설정 반영
update-grub

echo "  [완료]"

# ─── 3. polkit Hibernate 허용 ────────────────────────────────────────

echo ""
echo "[3/4] polkit hibernate 허용 정책 생성..."

# systemd-logind hibernate 액션 허용
cat > /etc/polkit-1/rules.d/10-enable-hibernate.rules << 'EOF'
polkit.addRule(function(action, subject) {
    if (action.id == "org.freedesktop.login1.hibernate" ||
        action.id == "org.freedesktop.login1.hibernate-multiple-sessions" ||
        action.id == "org.freedesktop.login1.hibernate-ignore-inhibit") {
        return polkit.Result.YES;
    }
});
EOF

echo "  [완료]"

# ─── 4. initramfs resume 설정 ────────────────────────────────────────

echo ""
echo "[4/4] initramfs resume 설정..."

# swap 파일 기반이므로 initramfs에서는 RESUME=none (커널 cmdline으로 처리)
echo "RESUME=none" > /etc/initramfs-tools/conf.d/resume

# 모든 커널 버전에 대해 initramfs 업데이트
update-initramfs -u -k all

echo "  [완료]"

# ─── 완료 ─────────────────────────────────────────────────────────────

echo ""
echo "=== 설정 완료 ==="
echo "재부팅 후 적용됩니다."
echo "확인: sudo systemctl hibernate"

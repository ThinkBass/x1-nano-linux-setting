#!/bin/bash
# fix-audio.sh — ALC287 오디오 볼륨 키 수정
# 적용 후 재부팅 필요

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "이 스크립트는 root 권한이 필요합니다. sudo로 실행해주세요."
    exit 1
fi

echo "=== ALC287 오디오 볼륨 수정 ==="

# DAC 0x06 비활성화 → 스피커가 볼륨 앰프 있는 DAC 0x02를 사용하게 함
echo 'options snd-hda-intel model=alc295-disable-dac3' > /etc/modprobe.d/alc287-fix.conf

echo "[완료] /etc/modprobe.d/alc287-fix.conf 생성"
echo ""
echo "재부팅 후 적용됩니다."
echo "확인 방법:"
echo "  sudo dmesg | grep -i 'alc287.*fixup'"
echo "  amixer sget Speaker"

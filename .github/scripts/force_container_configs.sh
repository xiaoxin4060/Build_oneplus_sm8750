#!/usr/bin/env bash
# Force-enable kernel configs required by Droidspaces containers.
# Must run AFTER gki_defconfig and BEFORE building Image.
# cwd = kernel_workspace/common
set -u

MK="make -j$(nproc --all) LLVM=1 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- O=out"
CFG="out/.config"

echo "===== [1/3] enable SYSVIPC first (IPC_NS depends on it) ====="
./scripts/config --file "$CFG" -e NAMESPACES -e SYSVIPC -e SYSVIPC_SYSCTL
$MK olddefconfig >/dev/null 2>&1 || { echo "::error::olddefconfig pass1 failed"; exit 1; }

echo "===== [2/3] enable namespaces and container filesystems ====="
./scripts/config --file "$CFG" \
  -e PID_NS -e IPC_NS -e USER_NS -e UTS_NS -e NET_NS \
  -e POSIX_MQUEUE -e POSIX_MQUEUE_SYSCTL \
  -e DEVTMPFS -e DEVTMPFS_MOUNT -e TMPFS -e TMPFS_XATTR -e TMPFS_POSIX_ACL
$MK olddefconfig >/dev/null 2>&1 || { echo "::error::olddefconfig pass2 failed"; exit 1; }

echo "===== [3/3] verify ====="
grep -E '^CONFIG_(NAMESPACES|PID_NS|IPC_NS|USER_NS|UTS_NS|NET_NS|SYSVIPC|SYSVIPC_SYSCTL|POSIX_MQUEUE|DEVTMPFS|DEVTMPFS_MOUNT|TMPFS|TMPFS_XATTR|TMPFS_POSIX_ACL)=' "$CFG" || true

REQUIRED="NAMESPACES PID_NS IPC_NS SYSVIPC SYSVIPC_SYSCTL POSIX_MQUEUE DEVTMPFS TMPFS_XATTR TMPFS_POSIX_ACL"
OPTIONAL="USER_NS DEVTMPFS_MOUNT UTS_NS NET_NS"

MISS=""
for k in $REQUIRED; do
  grep -qE "^CONFIG_${k}=y" "$CFG" || MISS="$MISS $k"
done

WARN=""
for k in $OPTIONAL; do
  grep -qE "^CONFIG_${k}=y" "$CFG" || WARN="$WARN $k"
done

if [ -n "$WARN" ]; then
  echo "::warning::optional configs not enabled:$WARN"
fi

if [ -n "$MISS" ]; then
  echo "::error::required configs not enabled:$MISS"
  for k in $MISS; do
    echo "----- dependency source of $k -----"
    grep -rn "^config ${k}$" --include="Kconfig*" . 2>/dev/null | head -3
  done
  exit 1
fi

echo "OK: all required container configs are enabled"

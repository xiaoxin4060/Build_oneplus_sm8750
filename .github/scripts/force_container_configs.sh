#!/usr/bin/env bash
# Force-enable kernel configs required by Droidspaces containers - MINIMAL EDITION (v8)
# Only layout-safe options: verified via full-BTF struct diff against the stock
# baseline (run #19). NF_TABLES/BRIDGE_NETFILTER/VLAN_FILTERING/NET_L3_MASTER_DEV
# are DELIBERATELY excluded: they change struct net/net_device/net_bridge layouts
# and break vendor module CRCs (bootloop, confirmed runs #26/#28).
# Docker networking works via legacy iptables (IP_NF_* already =y in stock).
set -u

MK="make -j$(nproc --all) LLVM=1 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- O=out"
CFG="out/.config"

pass() {
  $MK olddefconfig >/dev/null 2>&1 || { echo "::error::olddefconfig failed"; exit 1; }
}

echo "===== [1/3] SYSVIPC first (IPC_NS depends on it) ====="
./scripts/config --file "$CFG" -e NAMESPACES -e SYSVIPC -e SYSVIPC_SYSCTL
pass

echo "===== [2/3] namespaces + mqueue (layout-safe, BTF-verified) ====="
./scripts/config --file "$CFG" \
  -e PID_NS -e IPC_NS -e USER_NS -e UTS_NS -e NET_NS \
  -e POSIX_MQUEUE -e POSIX_MQUEUE_SYSCTL
pass

echo "===== [3/3] verify ====="
grep -E '^CONFIG_(NAMESPACES|PID_NS|IPC_NS|USER_NS|UTS_NS|NET_NS|SYSVIPC|SYSVIPC_SYSCTL|POSIX_MQUEUE|POSIX_MQUEUE_SYSCTL)=' "$CFG" || true

MISS=""
for k in NAMESPACES PID_NS IPC_NS SYSVIPC SYSVIPC_SYSCTL POSIX_MQUEUE; do
  grep -qE "^CONFIG_${k}=y" "$CFG" || MISS="$MISS $k"
done

if [ -n "$MISS" ]; then
  echo "::error::required configs not enabled:$MISS"
  exit 1
fi

echo "OK: namespace + sysvipc configs enabled (layout-safe set)"

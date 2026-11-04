#!/usr/bin/env bash
# Force-enable kernel configs required by Droidspaces containers.
# Also enables full Docker/Podman networking + NAT support.
# Must run AFTER gki_defconfig and BEFORE building Image.
# cwd = kernel_workspace/common
set -u

MK="make -j$(nproc --all) LLVM=1 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- O=out"
CFG="out/.config"

pass() {
  $MK olddefconfig >/dev/null 2>&1 || { echo "::error::olddefconfig failed"; exit 1; }
}

echo "===== [1/5] SYSVIPC first (IPC_NS depends on it) ====="
./scripts/config --file "$CFG" -e NAMESPACES -e SYSVIPC -e SYSVIPC_SYSCTL
pass

echo "===== [2/5] namespaces + container filesystems ====="
# DEVTMPFS_MOUNT stays OFF to match stock: Android init manages /dev itself.
./scripts/config --file "$CFG" \
  -e PID_NS -e IPC_NS -e USER_NS -e UTS_NS -e NET_NS \
  -e POSIX_MQUEUE -e POSIX_MQUEUE_SYSCTL \
  -e DEVTMPFS -d DEVTMPFS_MOUNT -e TMPFS -e TMPFS_XATTR -e TMPFS_POSIX_ACL
pass

echo "===== [3/5] nftables core (default backend of modern docker/podman) ====="
./scripts/config --file "$CFG" -e NF_TABLES -e NETFILTER_NETLINK
pass

echo "===== [4/5] full docker/podman networking + NAT ====="
./scripts/config --file "$CFG" \
  -e NF_TABLES_INET -e NF_TABLES_IPV4 -e NF_TABLES_IPV6 -e NF_TABLES_NETDEV \
  -e NFT_NAT -e NFT_MASQ -e NFT_CHAIN_NAT_IPV4 -e NFT_CHAIN_NAT_IPV6 -e NFT_FIB \
  -e BRIDGE_NETFILTER -e MACVLAN -e VXLAN \
  -e IP6_NF_NAT -e IP6_NF_TARGET_MASQUERADE \
  -e IP_SET -e NETFILTER_XT_SET \
  -e IP_SET_HASH_IP -e IP_SET_HASH_NET -e IP_SET_HASH_IPPORT -e IP_SET_HASH_IPPORTIP \
  -e IP_SET_HASH_IPPORTNET -e IP_SET_HASH_MAC -e IP_SET_HASH_NETPORT -e IP_SET_HASH_NETIFACE \
  -e IP_SET_HASH_IPMARK -e IP_SET_HASH_NETNET -e IP_SET_HASH_NETPORTNET -e IP_SET_HASH_IPMAC \
  -e IP_SET_BITMAP_IP -e IP_SET_BITMAP_IPMAC -e IP_SET_BITMAP_PORT -e IP_SET_LIST_SET \
  -e NETFILTER_XT_MATCH_ADDRTYPE -e NETFILTER_XT_MATCH_RECENT -e NETFILTER_XT_TARGET_LOG \
  -e NF_LOG_SYSLOG -e NF_LOG_IPV6 \
  -e CGROUP_PIDS
pass

echo "===== [5/5] verify ====="
grep -E '^CONFIG_(NAMESPACES|PID_NS|IPC_NS|USER_NS|UTS_NS|NET_NS|SYSVIPC|SYSVIPC_SYSCTL|POSIX_MQUEUE|DEVTMPFS|DEVTMPFS_MOUNT|TMPFS|TMPFS_XATTR|TMPFS_POSIX_ACL|MODULE_SCMVERSION|NF_TABLES|NFT_NAT|BRIDGE_NETFILTER|IP6_NF_NAT|IP6_NF_TARGET_MASQUERADE|MACVLAN|VXLAN|CGROUP_PIDS)=' "$CFG" || true
echo "----- ipset set types -----"
grep -E '^CONFIG_(IP_SET|NETFILTER_XT_SET)' "$CFG" || true

REQUIRED="NAMESPACES PID_NS IPC_NS SYSVIPC SYSVIPC_SYSCTL POSIX_MQUEUE DEVTMPFS TMPFS_XATTR TMPFS_POSIX_ACL"
NET_CORE="BRIDGE_NETFILTER IP6_NF_NAT NF_TABLES NF_TABLES_INET NF_TABLES_IPV4 NF_TABLES_IPV6 NFT_NAT IP_SET_HASH_IPPORT IP_SET_HASH_MAC IP_SET_BITMAP_PORT CGROUP_PIDS"
OPTIONAL="USER_NS UTS_NS NET_NS IP6_NF_TARGET_MASQUERADE MACVLAN VXLAN NFT_MASQ NFT_FIB IP_SET_HASH_IPPORTIP IP_SET_HASH_IPPORTNET IP_SET_HASH_NETPORT IP_SET_HASH_NETIFACE IP_SET_HASH_IPMARK IP_SET_HASH_NETNET IP_SET_HASH_NETPORTNET IP_SET_HASH_IPMAC IP_SET_BITMAP_IP IP_SET_BITMAP_IPMAC IP_SET_LIST_SET"

MISS=""
for k in $REQUIRED $NET_CORE; do
  grep -qE "^CONFIG_${k}=y" "$CFG" || MISS="$MISS $k"
done

WARN=""
for k in $OPTIONAL; do
  grep -qE "^CONFIG_${k}=y" "$CFG" || WARN="$WARN $k"
done

# KMI parity with stock: not attainable on this OSS tree, warn only
grep -qE "^CONFIG_GKI_DYNAMIC_TASK_STRUCT_SIZE=y" "$CFG" \
  || echo "::warning::GKI_DYNAMIC_TASK_STRUCT_SIZE unavailable in this source tree (OPlus internal patch)"

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

echo "OK: all required container + networking configs are enabled"

#!/usr/bin/env bash
# Force-enable kernel configs required by Droidspaces containers.
# NOTE: CGROUP_PIDS deliberately NOT enabled - it grows CGROUP_SUBSYS_COUNT
# and breaks vendor module CRCs (bootloop), confirmed on GT8 Pro (6.12) and
# listed as red-line by the gt8pro-droidspaces-gki project. Re-add only with
# the cgroup kABI EXT_SLOTS patch (Goldzxcbug fix_cgroup_limits_kabi_6.6).
# Also enables full Docker/Podman networking + NAT support.
# Must run AFTER gki_defconfig and BEFORE building Image.
# cwd = kernel_workspace/common
#
# Every symbol below was verified against THIS tree's Kconfig:
#   net/netfilter/Kconfig, net/ipv4/netfilter/Kconfig, net/ipv6/netfilter/Kconfig
# Symbols that do not exist in this tree are deliberately NOT listed, because
# kconfig drops them silently and they only produce false confidence.
# Removed vs the previous revision:
#   NFT_CHAIN_NAT_IPV4 / NFT_CHAIN_NAT_IPV6  -> merged into NFT_NAT in 6.6
#   NFT_FIB / NFT_FIB_IPV4 / NFT_FIB_IPV6    -> hidden/select-only, unused by docker
set -u

MK="make -j$(nproc --all) LLVM=1 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- O=out"
CFG="out/.config"

pass() {
  $MK olddefconfig >/dev/null 2>&1 || { echo "::error::olddefconfig failed"; exit 1; }
}

echo "===== [1/6] SYSVIPC first (IPC_NS depends on it) ====="
./scripts/config --file "$CFG" -e NAMESPACES -e SYSVIPC -e SYSVIPC_SYSCTL
pass

echo "===== [2/6] namespaces + container filesystems ====="
# DEVTMPFS_MOUNT stays OFF to match stock: Android init manages /dev itself.
./scripts/config --file "$CFG" \
  -e PID_NS -e IPC_NS -e USER_NS -e UTS_NS -e NET_NS \
  -e POSIX_MQUEUE -e POSIX_MQUEUE_SYSCTL \
  -e DEVTMPFS -d DEVTMPFS_MOUNT -e TMPFS -e TMPFS_XATTR -e TMPFS_POSIX_ACL
pass

echo "===== [3/6] nftables core (default backend of modern docker/podman) ====="
./scripts/config --file "$CFG" \
  -e NF_TABLES -e NETFILTER_NETLINK \
  -e NF_TABLES_INET -e NF_TABLES_IPV4 -e NF_TABLES_IPV6 -e NF_TABLES_NETDEV
pass

echo "===== [4/6] nftables expression modules (were MISSING before) ====="
# NFT_CT is mandatory: docker/podman emit
#   'ct state established,related accept' and 'ct status dnat accept'
# Without nft_ct.o those rules fail to load and NAT silently breaks.
# NFT_COMPAT is mandatory for iptables-nft (x_tables over nf_tables).
# nft_counter has no CONFIG here: it is built into nf_tables unconditionally.
./scripts/config --file "$CFG" \
  -e NFT_CT -e NFT_COMPAT -e NFT_NAT -e NFT_MASQ -e NFT_REDIR -e NFT_REJECT \
  -e NFT_LOG -e NFT_LIMIT -e NFT_QUOTA -e NFT_HASH -e NFT_NUMGEN
pass
# second round so select-only dependents can latch on
./scripts/config --file "$CFG" \
  -e NFT_CT -e NFT_COMPAT -e NFT_REDIR -e NFT_REJECT -e NFT_LOG -e NFT_LIMIT
pass

echo "===== [5/6] iptables + ipset + bridge/NAT ====="
./scripts/config --file "$CFG" \
  -e NETFILTER_XTABLES -e NETFILTER_ADVANCED \
  -e IP_NF_IPTABLES -e IP_NF_FILTER -e IP_NF_NAT -e IP_NF_TARGET_MASQUERADE \
  -e IP_NF_TARGET_REDIRECT -e IP_NF_MANGLE \
  -e IP6_NF_IPTABLES -e IP6_NF_FILTER -e IP6_NF_NAT -e IP6_NF_TARGET_MASQUERADE \
  -e NF_CONNTRACK -e NF_NAT -e NF_CONNTRACK_MARK \
  -e NETFILTER_XT_MATCH_CONNTRACK -e NETFILTER_XT_MATCH_ADDRTYPE \
  -e NETFILTER_XT_MATCH_RECENT -e NETFILTER_XT_TARGET_LOG \
  -e NF_LOG_SYSLOG -e NF_LOG_IPV6 \
  -e BRIDGE -e BRIDGE_NETFILTER -e BRIDGE_VLAN_FILTERING -e VETH \
  -e MACVLAN -e IPVLAN -e VXLAN -e DUMMY \
  -e IP_SET -e NETFILTER_XT_SET \
  -e IP_SET_HASH_IP -e IP_SET_HASH_NET -e IP_SET_HASH_IPPORT -e IP_SET_HASH_IPPORTIP \
  -e IP_SET_HASH_IPPORTNET -e IP_SET_HASH_MAC -e IP_SET_HASH_NETPORT -e IP_SET_HASH_NETIFACE \
  -e IP_SET_HASH_IPMARK -e IP_SET_HASH_NETNET -e IP_SET_HASH_NETPORTNET -e IP_SET_HASH_IPMAC \
  -e IP_SET_BITMAP_IP -e IP_SET_BITMAP_IPMAC -e IP_SET_BITMAP_PORT -e IP_SET_LIST_SET \
pass

echo "===== [6/6] verify ====="
echo "----- container core -----"
grep -E '^CONFIG_(NAMESPACES|PID_NS|IPC_NS|USER_NS|UTS_NS|NET_NS|SYSVIPC|SYSVIPC_SYSCTL|POSIX_MQUEUE|DEVTMPFS|DEVTMPFS_MOUNT|TMPFS|TMPFS_XATTR|TMPFS_POSIX_ACL)=' "$CFG" || true
echo "----- nftables -----"
grep -E '^CONFIG_(NF_TABLES|NF_TABLES_INET|NF_TABLES_IPV4|NF_TABLES_IPV6|NF_TABLES_NETDEV|NFT_CT|NFT_COMPAT|NFT_NAT|NFT_MASQ|NFT_REDIR|NFT_REJECT|NFT_LOG|NFT_LIMIT|NFT_QUOTA|NFT_HASH|NFT_NUMGEN)=' "$CFG" || true
echo "----- nat / bridge / virtual nic -----"
grep -E '^CONFIG_(NF_CONNTRACK|NF_NAT|NF_CONNTRACK_MARK|BRIDGE_NETFILTER|VETH|MACVLAN|IPVLAN|VXLAN|DUMMY|IP6_NF_NAT|IP6_NF_TARGET_MASQUERADE)=' "$CFG" || true
echo "----- ipset types -----"
grep -cE '^CONFIG_IP_SET_(HASH|BITMAP)_[A-Z0-9_]+=y' "$CFG" | sed 's/^/enabled ipset types: /'

# Hard requirements: build stops if any of these is missing.
REQUIRED="NAMESPACES PID_NS IPC_NS SYSVIPC SYSVIPC_SYSCTL POSIX_MQUEUE DEVTMPFS TMPFS_XATTR TMPFS_POSIX_ACL"
NET_CORE="NF_TABLES NF_TABLES_INET NF_TABLES_IPV4 NF_TABLES_IPV6 NFT_CT NFT_COMPAT NFT_NAT NFT_MASQ NFT_REDIR NFT_REJECT BRIDGE_NETFILTER VETH IP6_NF_NAT IP6_NF_TARGET_MASQUERADE IP_SET_HASH_IPPORT IP_SET_HASH_MAC IP_SET_BITMAP_PORT"
# Nice to have: warn only.
OPTIONAL="USER_NS UTS_NS NET_NS MACVLAN IPVLAN VXLAN DUMMY NFT_LOG NFT_LIMIT NFT_QUOTA NFT_HASH NFT_NUMGEN BRIDGE_VLAN_FILTERING IP_SET_HASH_IPPORTIP IP_SET_HASH_IPPORTNET IP_SET_HASH_NETPORT IP_SET_HASH_NETIFACE IP_SET_HASH_IPMARK IP_SET_HASH_NETNET IP_SET_HASH_NETPORTNET IP_SET_HASH_IPMAC IP_SET_BITMAP_IP IP_SET_BITMAP_IPMAC IP_SET_LIST_SET"

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
    echo "----- why $k failed -----"
    if grep -rqE "^config ${k}$" --include="Kconfig*" . 2>/dev/null; then
      echo "symbol EXISTS, dependency unmet. Kconfig entry:"
      grep -rn -A6 "^config ${k}$" --include="Kconfig*" . 2>/dev/null | head -8
    else
      echo "symbol NOT DEFINED in this source tree (nothing to fix)"
    fi
  done
  exit 1
fi

echo "OK: all required container + networking configs are enabled"

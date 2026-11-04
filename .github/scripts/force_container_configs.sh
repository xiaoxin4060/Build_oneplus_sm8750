#!/usr/bin/env bash
# 寮哄埗鍐欏叆 Droidspaces 瀹瑰櫒鎵€闇€鍐呮牳閰嶇疆
# 蹇呴』鍦?gki_defconfig 涔嬪悗銆乥uild Image 涔嬪墠鎵ц锛宑wd = kernel_workspace/common
set -u

MK="make -j$(nproc --all) LLVM=1 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- O=out"

echo "===== [1/3] 鎵撳紑 SYSVIPC锛圛PC_NS 渚濊禆瀹冿紝鍚﹀垯绗﹀彿鍦?.config 涓牴鏈笉瀛樺湪锛?===="
./scripts/config --file out/.config -e NAMESPACES -e SYSVIPC -e SYSVIPC_SYSCTL
$MK olddefconfig >/dev/null 2>&1 || { echo "::error::olddefconfig 绗竴杞け璐?; exit 1; }

echo "===== [2/3] 鎵撳紑鍛藉悕绌洪棿涓庡鍣ㄦ枃浠剁郴缁?====="
./scripts/config --file out/.config \
  -e PID_NS -e IPC_NS -e USER_NS -e UTS_NS -e NET_NS \
  -e POSIX_MQUEUE -e POSIX_MQUEUE_SYSCTL \
  -e DEVTMPFS -e DEVTMPFS_MOUNT -e TMPFS -e TMPFS_XATTR -e TMPFS_POSIX_ACL
$MK olddefconfig >/dev/null 2>&1 || { echo "::error::olddefconfig 绗簩杞け璐?; exit 1; }

echo "===== [3/3] 閫愰」鏍稿 ====="
REQ="NAMESPACES PID_NS IPC_NS USER_NS SYSVIPC SYSVIPC_SYSCTL POSIX_MQUEUE DEVTMPFS DEVTMPFS_MOUNT TMPFS_XATTR TMPFS_POSIX_ACL"
grep -E "^CONFIG_($(echo $REQ | tr ' ' '|'))=" out/.config || true

MISS=""
for k in $REQ; do
  grep -qE "^CONFIG_${k}=y" out/.config || MISS="$MISS $k"
done

if [ -n "$MISS" ]; then
  echo "::error::浠ヤ笅閰嶇疆鏈兘鐢熸晥:$MISS"
  echo "----- 鐩稿叧 Kconfig 渚濊禆妫€鏌?-----"
  for k in $MISS; do
    grep -rn "^config ${k}$" --include="Kconfig*" . 2>/dev/null | head -3
  done
  exit 1
fi

echo "OK: 鍏ㄩ儴瀹瑰櫒鎵€闇€閰嶇疆宸茬敓鏁?

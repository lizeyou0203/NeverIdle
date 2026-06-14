#!/bin/bash
 
# ============ 架构识别 & 二进制选择 ============
ARCH=$(uname -m)
CPU_CORES=$(nproc)
TOTAL_MEM_KB=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
TOTAL_MEM_GB=$((TOTAL_MEM_KB / 1024 / 1024))
 
if [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]]; then
    BINARY="check_oracle_arm64"
elif [[ "$ARCH" == "x86_64" ]]; then
    BINARY="check_oracle_amd64"
else
    echo "未知架构 $ARCH，退出"
    exit 1
fi
 
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
if [ ! -f "$SCRIPT_DIR/$BINARY" ]; then
    echo "错误: 找不到 $SCRIPT_DIR/$BINARY"
    exit 1
fi
 
chmod +x "$SCRIPT_DIR/$BINARY"
 
echo "========================================="
echo "架构:   $ARCH"
echo "二进制: $BINARY"
echo "CPU:    $CPU_CORES 核"
echo "内存:   ${TOTAL_MEM_GB} GiB"
echo "========================================="

# ============ 防重复启动 ============
LOCKFILE="/tmp/neveridle_$(whoami).lock"
if [ -f "$LOCKFILE" ]; then
    OLD_PID=$(cat "$LOCKFILE")
    if kill -0 "$OLD_PID" 2>/dev/null; then
        echo "已有实例在运行 (PID $OLD_PID)，退出"
        exit 1
    else
        rm -f "$LOCKFILE"
    fi
fi
echo $$ > "$LOCKFILE"

# ============ 清理函数：按进程名查杀 ============
cleanup() {
    echo ""
    echo "[*] 收到终止信号，正在清理..."
    
    local target_pids=$(pidof "$BINARY" 2>/dev/null || pgrep -f "$BINARY" 2>/dev/null)
    
    if [ -n "$target_pids" ]; then
        echo "[*] 发现 $BINARY 进程: $target_pids，发送 SIGTERM..."
        kill -TERM $target_pids 2>/dev/null
        sleep 1
        local still_alive=$(pidof "$BINARY" 2>/dev/null || pgrep -f "$BINARY" 2>/dev/null)
        if [ -n "$still_alive" ]; then
            echo "[*] 发送 SIGKILL: $still_alive"
            kill -KILL $still_alive 2>/dev/null
            sleep 1
        fi
    else
        echo "[*] 未发现 $BINARY 进程"
    fi
    
    local final=$(pidof "$BINARY" 2>/dev/null || pgrep -f "$BINARY" 2>/dev/null)
    [ -n "$final" ] && kill -KILL $final 2>/dev/null
    
    rm -f "$LOCKFILE"
    echo "[*] 已清理，再见"
    exit 0
}

trap cleanup SIGINT SIGTERM
 
# ============ 参数适配 ============
if [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]]; then
    cp_dec=$(( RANDOM % 4 + 22 ))
    cp="0.${cp_dec}"
    
    # 内存: 目标 25~30%
    max_mem=$((TOTAL_MEM_GB * 30 / 100))
    min_mem=$((TOTAL_MEM_GB * 25 / 100))
    [ "$min_mem" -lt 1 ] && min_mem=1
    [ "$min_mem" -gt "$max_mem" ] && min_mem=$max_mem
    mem=$(( RANDOM % (max_mem - min_mem + 1) + min_mem ))
    [ "$mem" -gt "$max_mem" ] && mem=$max_mem
    [ "$mem" -lt "$min_mem" ] && mem=$min_mem
    
    n_hours=$(( RANDOM % 2 + 2 ))
    
    echo "检测到 ARM VPS — CPU/内存/网络三项全保"
    echo "CPU 目标: ${cp} (无 steal，实际≈设定值，安全线 0.20)"
    echo "内存范围: ${min_mem}~${max_mem} GiB (25~30%)"

else
    cp_dec=$(( RANDOM % 11 + 30 ))
    cp="0.${cp_dec}"
    mem=0
    n_hours=$(( RANDOM % 2 + 2 ))
    
    echo "检测到 AMD VPS — CPU + 网络双保（不占用内存）"
    echo "CPU 目标: ${cp} (steal~25%，实际可见约 20~25%，安全线 0.20)"
fi
 
echo "========================================="
echo "最终参数:"
echo "  CPU:     ${cp}"
echo "  内存:    ${mem} GiB"
echo "  网络间隔: ${n_hours}h"
echo "========================================="

# ============ 启动 NeverIdle（后台，不用函数） ============
ARGS="-cp $cp -n ${n_hours}h"
[ "$mem" -gt 0 ] && ARGS="$ARGS -m $mem"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] 启动: $SCRIPT_DIR/$BINARY $ARGS"
"$SCRIPT_DIR/$BINARY" $ARGS &
NEVERIDLE_PID=$!

if [ -n "$NEVERIDLE_PID" ] && kill -0 "$NEVERIDLE_PID" 2>/dev/null; then
    echo "[*] NeverIdle PID: $NEVERIDLE_PID"
else
    echo "错误: NeverIdle 启动失败"
    rm -f "$LOCKFILE"
    exit 1
fi

# ============ 脚本主进程保持前台 ============
echo "[*] 脚本主进程运行中，按 Ctrl+C 终止..."

while true; do
    if ! kill -0 "$NEVERIDLE_PID" 2>/dev/null; then
        echo "[*] NeverIdle 异常退出，重新启动..."
        "$SCRIPT_DIR/$BINARY" $ARGS &
        NEVERIDLE_PID=$!
        echo "[*] NeverIdle 重启 PID: $NEVERIDLE_PID"
        continue
    fi
    
    sleep 10
done

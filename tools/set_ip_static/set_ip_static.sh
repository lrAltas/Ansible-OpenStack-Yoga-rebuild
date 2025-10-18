#!/bin/bash

set -e

# 颜色打印
info() { echo -e "\033[1;34m[INFO]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }
success() { echo -e "\033[1;32m[SUCCESS]\033[0m $*"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; }

# 检查参数
if [[ "$1" != "-f" || -z "$2" ]]; then
    error "用法: $0 -f <配置文件路径>"
    exit 1
fi

CONFIG_FILE="$2"
HOSTNAME=$(hostname)

info "读取配置文件: $CONFIG_FILE"
info "当前主机名: $HOSTNAME"

# 提取主机配置段
SECTION_FOUND=0
declare -A IFACES
GATEWAY=""
DNS=""
NETMASK=""

while IFS= read -r line || [[ -n "$line" ]]; do
    line=$(echo "$line" | sed 's/^[ \t]*//;s/[ \t]*$//')  # 去除首尾空格
    [[ -z "$line" || "$line" =~ ^# ]] && continue         # 跳过空行和注释

    if [[ "$line" =~ ^\[(.*)\]$ ]]; then
        CURRENT_SECTION="${BASH_REMATCH[1]}"
        if [[ "$CURRENT_SECTION" == "$HOSTNAME" ]]; then
            SECTION_FOUND=1
        else
            SECTION_FOUND=0
        fi
        continue
    fi

    if [[ "$SECTION_FOUND" -eq 1 ]]; then
        KEY=$(echo "$line" | cut -d= -f1 | xargs)
        VALUE=$(echo "$line" | cut -d= -f2- | xargs)

        if [[ "$KEY" != "gateway" && "$KEY" != "dns" && "$KEY" != "netmask" ]]; then
            IFACES["$KEY"]="$VALUE"
        elif [[ "$KEY" == "gateway" ]]; then
            GATEWAY="$VALUE"
        elif [[ "$KEY" == "dns" ]]; then
            DNS="$VALUE"
        elif [[ "$KEY" == "netmask" ]]; then
            NETMASK="$VALUE"
        fi
    fi
done < "$CONFIG_FILE"

if [[ ${#IFACES[@]} -eq 0 ]]; then
    error "未找到主机 [$HOSTNAME] 的接口配置！"
    exit 1
fi

# 配置网卡
for IFACE in "${!IFACES[@]}"; do
    IP=${IFACES[$IFACE]}
    info "配置 $IFACE: IP=$IP, Netmask=$NETMASK, Gateway=$GATEWAY, DNS=$DNS"

    nmcli con mod "$IFACE" ipv4.addresses "$IP/$NETMASK"
    nmcli con mod "$IFACE" ipv4.gateway "$GATEWAY"
    nmcli con mod "$IFACE" ipv4.dns "$DNS"
    nmcli con mod "$IFACE" ipv4.method manual

    # 重新连接接口
    info "重启网络接口 $IFACE"
    nmcli con down "$IFACE" || true
    nmcli con up "$IFACE"
done

info "网络配置完成！"

# 网络连通性测试
info "开始网络连通性测试..."

# 测试网关连通性
info "测试网关连通性: $GATEWAY"
if ping -c 3 -W 2 "$GATEWAY" &> /dev/null; then
    success "网关 $GATEWAY 连通正常"
else
    error "网关 $GATEWAY 无法连通"
    GATEWAY_FAILED=1
fi

# 测试DNS解析
info "测试DNS解析: $DNS"
if nslookup www.baidu.com "$DNS" &> /dev/null; then
    success "DNS解析正常"
else
    error "DNS解析失败"
    DNS_FAILED=1
fi# ...existing code...
        # 只要不是 gateway/dns/netmask，都认为是网卡名
        if [[ "$KEY" != "gateway" && "$KEY" != "dns" && "$KEY" != "netmask" ]]; then
            IFACES["$KEY"]="$VALUE"
        elif [[ "$KEY" == "gateway" ]]; then
            GATEWAY="$VALUE"
        elif [[ "$KEY" == "dns" ]]; then
            DNS="$VALUE"
        elif [[ "$KEY" == "netmask" ]]; then
            NETMASK="$VALUE"
        fi
# ...existing code...

# 测试互联网连通性
info "测试互联网连通性: www.baidu.com"
if ping -c 3 -W 3 www.baidu.com &> /dev/null; then
    success "互联网连通正常 (www.baidu.com)"
else
    warn "互联网连通测试失败，尝试使用curl测试..."
    if curl -s --connect-timeout 5 -I www.baidu.com &> /dev/null; then
        success "互联网连通正常 (通过curl)"
    else
        error "互联网无法连通"
        INTERNET_FAILED=1
    fi
fi

# 显示测试总结
echo
info "=== 网络测试总结 ==="
if [[ -z "$GATEWAY_FAILED" && -z "$DNS_FAILED" && -z "$INTERNET_FAILED" ]]; then
    success "所有网络测试通过！网络配置成功。"
else
    warn "部分网络测试失败："
    [[ -n "$GATEWAY_FAILED" ]] && warn "  - 网关连通性测试失败"
    [[ -n "$DNS_FAILED" ]] && warn "  - DNS解析测试失败"
    [[ -n "$INTERNET_FAILED" ]] && warn "  - 互联网连通性测试失败"
    echo
    info "请检查网络配置是否正确！"
fi
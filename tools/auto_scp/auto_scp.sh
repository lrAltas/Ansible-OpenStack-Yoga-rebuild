#!/bin/bash

set -e

# 颜色和输出函数
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m' # No Color

info() { 
    echo -e "${BLUE}[INFO] $1${NC}"
    echo -e "${BLUE}[信息] $2${NC}" 
}
success() { 
    echo -e "${GREEN}[SUCCESS] $1${NC}"
    echo -e "${GREEN}[成功] $2${NC}" 
}
warn() { 
    echo -e "${YELLOW}[WARNING] $1${NC}"
    echo -e "${YELLOW}[警告] $2${NC}" 
}
error() { 
    echo -e "${RED}[ERROR] $1${NC}" >&2
    echo -e "${RED}[错误] $2${NC}" >&2
}

# 显示用法
show_usage() {
    echo "Usage: $0 -i <hosts_file> -f <file_or_directory> -p <destination_path>"
    echo "用法: $0 -i <主机清单文件> -f <要传输的文件或目录> -p <目标路径>"
    echo ""
    echo "Options:"
    echo "选项:"
    echo "  -i <file>    Hosts list file (one host per line, IP or hostname)"
    echo "  -i <文件>    主机清单文件 (每行一个主机，IP或主机名)"
    echo "  -f <path>    File or directory to transfer"
    echo "  -f <路径>    要传输的文件或目录"
    echo "  -p <path>    Destination path on remote hosts"
    echo "  -p <路径>    远程主机上的目标路径"
    echo "  -h           Show this help message"
    echo "  -h           显示此帮助信息"
    echo ""
    echo "Note: SSH password-less login must be configured for all hosts in the list."
    echo "注意: 必须为列表中的所有主机配置SSH免密登录。"
}

# 变量初始化
HOSTS_FILE=""
SOURCE_PATH=""
DEST_PATH=""
FAILED_HOSTS=()

# 解析命令行参数
while getopts "i:f:p:h" opt; do
    case $opt in
        i)
            HOSTS_FILE="$OPTARG"
            ;;
        f)
            SOURCE_PATH="$OPTARG"
            ;;
        p)
            DEST_PATH="$OPTARG"
            ;;
        h)
            show_usage
            exit 0
            ;;
        \?)
            error "Invalid option" "无效选项"
            show_usage
            exit 1
            ;;
        :)
            error "Option -$OPTARG requires an argument" "选项 -$OPTARG 需要一个参数"
            show_usage
            exit 1
            ;;
    esac
done

# 验证参数
if [[ -z "$HOSTS_FILE" || -z "$SOURCE_PATH" || -z "$DEST_PATH" ]]; then
    error "Missing required parameters" "缺少必要参数"
    show_usage
    exit 1
fi

if [[ ! -f "$HOSTS_FILE" ]]; then
    error "Hosts file not found: $HOSTS_FILE" "主机文件未找到: $HOSTS_FILE"
    exit 1
fi

if [[ ! -e "$SOURCE_PATH" ]]; then
    error "Source file/directory not found: $SOURCE_PATH" "源文件/目录未找到: $SOURCE_PATH"
    exit 1
fi

# 读取主机列表
readarray -t HOSTS < "$HOSTS_FILE"

if [[ ${#HOSTS[@]} -eq 0 ]]; then
    error "No hosts found in the hosts file" "主机文件中未找到任何主机"
    exit 1
fi

info "Starting file transfer to ${#HOSTS[@]} hosts" "开始向 ${#HOSTS[@]} 台主机传输文件"
info "Source: $SOURCE_PATH" "源路径: $SOURCE_PATH"
info "Destination: $DEST_PATH" "目标路径: $DEST_PATH"
echo ""

# 传输文件函数
transfer_file() {
    local host="$1"
    local source="$2"
    local dest="$3"
    
    info "Transferring to $host..." "正在传输到 $host..."
    
    # 检查是否是目录
    local scp_opts=""
    if [[ -d "$source" ]]; then
        scp_opts="-r"
        info "Source is a directory, using recursive copy" "源为目录，使用递归复制"
    fi
    
    # 执行SCP传输
    if scp $scp_opts -o ConnectTimeout=10 -o BatchMode=yes "$source" "${host}:${dest}" 2>/dev/null; then
        success "Transfer to $host completed successfully" "传输到 $host 完成成功"
        return 0
    else
        error "Transfer to $host failed" "传输到 $host 失败"
        return 1
    fi
}

# 批量传输
TOTAL_HOSTS=${#HOSTS[@]}
SUCCESS_COUNT=0
FAILED_COUNT=0

for host in "${HOSTS[@]}"; do
    # 去除空白字符
    host=$(echo "$host" | xargs)
    
    # 跳过空行和注释
    if [[ -z "$host" || "$host" =~ ^# ]]; then
        continue
    fi
    
    if transfer_file "$host" "$SOURCE_PATH" "$DEST_PATH"; then
        ((SUCCESS_COUNT++))
    else
        ((FAILED_COUNT++))
        FAILED_HOSTS+=("$host")
    fi
    echo "----------------------------------------"
done

# 输出总结报告
echo ""
info "=== TRANSFER SUMMARY ===" "=== 传输总结报告 ==="
success "Successful transfers: $SUCCESS_COUNT/$TOTAL_HOSTS" "成功传输: $SUCCESS_COUNT/$TOTAL_HOSTS"

if [[ $FAILED_COUNT -gt 0 ]]; then
    warn "Failed transfers: $FAILED_COUNT/$TOTAL_HOSTS" "失败传输: $FAILED_COUNT/$TOTAL_HOSTS"
    echo ""
    warn "Failed hosts list:" "失败主机列表:"
    for failed_host in "${FAILED_HOSTS[@]}"; do
        echo "  - $failed_host"
    done
    echo ""
    warn "Please check:" "请检查:"
    warn "1. SSH password-less login configuration" "1. SSH免密登录配置"
    warn "2. Network connectivity to failed hosts" "2. 到失败主机的网络连接"
    warn "3. Destination path permissions" "3. 目标路径权限"
    warn "4. Hostname/IP validity" "4. 主机名/IP有效性"
else
    success "All transfers completed successfully!" "所有传输均成功完成！"
fi

# 如果有失败的主机，以错误状态退出
if [[ $FAILED_COUNT -gt 0 ]]; then
    exit 1
else
    exit 0
fi
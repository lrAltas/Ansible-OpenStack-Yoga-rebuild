#!/bin/bash

# 脚本名称：auto_ssh.sh
# 作者：LRAltas

show_usage() {
    cat << EOF
用法/Usage: $0 [选项/options]

选项/Options:
    -f FILE    指定配置文件，根据配置进行免密登录设置
               Specify config file for password-free login setup
    -h         显示此帮助信息
               Show this help message

配置文件格式/Config file format:
    格式为INI样式，每个[]代表一个主机配置
    Format is INI-style, each [] represents a host configuration
    
    示例/Example:
        [controller]
        username = root
        ip = 192.168.122.100
        password = liuziyi212
        
        [compute1]
        username = root
        ip = 192.168.122.101
        password = liuziyi212

注意/Notes:
    1. 请确保本机已安装sshpass工具，如未安装请执行: yum install -y sshpass
    2. 配置文件如无密码，将提示输入
    3. 脚本会在本机生成SSH密钥对（如果不存在）
    4. 脚本会将公钥分发到配置文件中指定的所有机器

EOF
}

# 检查依赖工具
check_dependencies() {
    local missing_tools=()
    
    if ! command -v sshpass &> /dev/null; then
        missing_tools+=("sshpass")
    fi
    
    if ! command -v ssh-keygen &> /dev/null; then
        missing_tools+=("openssh-clients")
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        echo "错误: 缺少必要的工具: ${missing_tools[*]}"
        echo "Error: Missing required tools: ${missing_tools[*]}"
        echo "请执行以下命令安装/Please run to install: yum install -y ${missing_tools[*]}"
        exit 1
    fi
}

# 生成SSH密钥对
generate_ssh_key() {
    local key_file="$HOME/.ssh/id_rsa"
    
    if [ ! -f "$key_file" ]; then
        echo "生成SSH密钥对... | Generating SSH key pair..."
        ssh-keygen -t rsa -b 4096 -f "$key_file" -N "" -q
        if [ $? -eq 0 ]; then
            echo "SSH密钥对生成成功 | SSH key pair generated successfully"
        else
            echo "错误: SSH密钥对生成失败 | Error: SSH key pair generation failed"
            exit 1
        fi
    else
        echo "SSH密钥对已存在，跳过生成 | SSH key pair exists, skipping generation"
    fi
}

# 分发公钥到远程主机
distribute_ssh_key() {
    local user="$1"
    local ip="$2"
    local password="$3"
    local hostname="$4"
    
    echo "正在处理主机/Processing host: $hostname ($user@$ip)"
    
    # 测试SSH连接
    if sshpass -p "$password" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$user@$ip" "echo '连接测试成功 | Connection test successful'" &> /dev/null; then
        echo "  ✓ SSH连接测试成功 | SSH connection test successful"
    else
        echo "  ✗ SSH连接测试失败 | SSH connection test failed"
        return 1
    fi
    
    # 检查远程主机是否已有公钥
    local public_key_content=$(cat ~/.ssh/id_rsa.pub)
    if sshpass -p "$password" ssh -o StrictHostKeyChecking=no "$user@$ip" "grep -qF \"$public_key_content\" ~/.ssh/authorized_keys 2>/dev/null"; then
        echo "  ✓ 公钥已存在，跳过分发 | Public key exists, skipping distribution"
        return 0
    fi
    
    # 分发公钥
    echo "  正在分发公钥... | Distributing public key..."
    if sshpass -p "$password" ssh-copy-id -o StrictHostKeyChecking=no -f "$user@$ip" &> /dev/null; then
        echo "  ✓ 公钥分发成功 | Public key distributed successfully"
        
        # 验证免密登录
        if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$user@$ip" "echo '免密登录测试成功 | Password-free login test successful'" &> /dev/null; then
            echo "  ✓ 免密登录验证成功 | Password-free login verified successfully"
        else
            echo "  ✗ 免密登录验证失败 | Password-free login verification failed"
            return 1
        fi
    else
        echo "  ✗ 公钥分发失败 | Public key distribution failed"
        return 1
    fi
    
    return 0
}

# 解析INI格式配置文件
parse_ini_file() {
    local config_file="$1"
    local current_section=""
    declare -A config
    
    # 检查配置文件是否存在
    if [ ! -f "$config_file" ]; then
        echo "错误: 配置文件 $config_file 不存在 | Error: Config file $config_file does not exist" >&2
        exit 1
    fi
    
    # 检查配置文件是否可读
    if [ ! -r "$config_file" ]; then
        echo "错误: 配置文件 $config_file 不可读 | Error: Config file $config_file is not readable" >&2
        exit 1
    fi
    
    echo "开始解析配置文件/Start parsing config file: $config_file" >&2
    
    # 逐行读取配置文件
    while IFS= read -r line || [[ -n "$line" ]]; do
        # 跳过空行和注释行
        line_trimmed=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [[ -z "$line_trimmed" || "$line_trimmed" =~ ^[[:space:]]*# ]]; then
            continue
        fi
        
        # 检查是否是节头 [section]
        if [[ "$line_trimmed" =~ ^\[([^]]+)\]$ ]]; then
            current_section="${BASH_REMATCH[1]}"
            echo "找到配置节/Found section: $current_section" >&2
            continue
        fi
        
        # 解析键值对
        if [[ "$line_trimmed" =~ ^([^=]+)=(.*)$ ]]; then
            key=$(echo "${BASH_REMATCH[1]}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            value=$(echo "${BASH_REMATCH[2]}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            
            if [[ -n "$current_section" ]]; then
                config["${current_section}_${key}"]="$value"
                echo "  设置参数/Set parameter: $key = $value" >&2
            fi
        fi
    done < "$config_file"
    
    # 返回关联数组
    declare -p config
}

# 处理配置文件
process_config_file() {
    local config_file="$1"
    local success_count=0
    local fail_count=0
    
    echo "开始处理配置文件/Start processing config file: $config_file"
    echo "========================================"
    
    # 解析INI文件
    local ini_output
    ini_output=$(parse_ini_file "$config_file")
    eval "$ini_output"
    
    # 获取所有唯一的节名
    declare -A sections
    for key in "${!config[@]}"; do
        section="${key%_*}"
        sections["$section"]=1
    done
    
    # 处理每个节
    for section in "${!sections[@]}"; do
        echo "----------------------------------------"
        echo "处理配置节/Processing section: $section"
        
        # 获取该节的配置
        local user="${config[${section}_username]}"
        local ip="${config[${section}_ip]}"
        local password="${config[${section}_password]}"
        
        # 验证必需字段
        if [[ -z "$user" || -z "$ip" ]]; then
            echo "错误: 节 '$section' 缺少username或ip字段 | Error: Section '$section' missing username or ip field"
            fail_count=$((fail_count + 1))
            continue
        fi
        
        # 如果没有密码，提示输入
        if [[ -z "$password" ]]; then
            read -s -p "请输入 $user@$ip ($section) 的密码（不会显示）/Enter password for $user@$ip ($section): " password
            echo ""
            if [[ -z "$password" ]]; then
                echo "错误: 未输入密码，跳过该主机 | Error: No password entered, skipping host"
                fail_count=$((fail_count + 1))
                continue
            fi
        fi
        
        # 分发公钥
        if distribute_ssh_key "$user" "$ip" "$password" "$section"; then
            success_count=$((success_count + 1))
        else
            fail_count=$((fail_count + 1))
        fi
    done
    
    echo "========================================"
    echo "处理完成! | Processing completed!"
    echo "成功/Success: $success_count 台, 失败/Failed: $fail_count 台"
    
    if [ $fail_count -gt 0 ]; then
        echo "警告: 部分主机配置失败，请检查日志 | Warning: Some hosts configuration failed, please check logs"
        exit 1
    fi
}

# 主函数
main() {
    local config_file=""
    
    # 解析命令行参数
    while getopts "f:h" opt; do
        case $opt in
            f)
                config_file="$OPTARG"
                ;;
            h)
                show_usage
                exit 0
                ;;
            \?)
                echo "错误: 无效选项 -$OPTARG | Error: Invalid option -$OPTARG"
                show_usage
                exit 1
                ;;
            :)
                echo "错误: 选项 -$OPTARG 需要参数 | Error: Option -$OPTARG requires an argument"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # 检查是否指定了配置文件
    if [ -z "$config_file" ]; then
        echo "错误: 必须使用 -f 选项指定配置文件 | Error: Must specify config file using -f option"
        show_usage
        exit 1
    fi
    
    # 检查依赖
    check_dependencies
    
    # 生成SSH密钥对
    generate_ssh_key
    
    # 处理配置文件
    process_config_file "$config_file"
}

# 脚本入口
if [ $# -eq 0 ]; then
    show_usage
    exit 1
fi

main "$@"
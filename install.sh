#!/bin/bash


red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

url="https://api.github.com/repos/jeessy2/ddns-go/releases"

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}错误：${plain} 必须使用root用户运行此脚本！\n" && exit 1

# check os
if [[ -f /etc/redhat-release ]]; then
    release_info=$(cat /etc/redhat-release)
    if [[ $release_info == *"Fedora"* ]]; then
        release="fedora"
    else
        release="centos"
    fi
elif cat /etc/issue | grep -Eqi "debian"; then
    release="debian"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat|rocky|alma|oracle linux"; then
    release="centos"
elif cat /proc/version | grep -Eqi "debian"; then
    release="debian"
elif cat /proc/version | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /proc/version | grep -Eqi "centos|red hat|redhat|rocky|alma|oracle linux"; then
    release="centos"
else
    echo -e "${red}未检测到系统版本，请联系脚本作者！${plain}\n" && exit 1
fi

arch=$(arch)

if [[ $arch == "x86_64" || $arch == "x64" || $arch == "amd64" ]]; then
    arch="x86_64"
elif [[ $arch == "aarch64" || $arch == "arm64" ]]; then
    arch="arm64"
elif [[ $arch == "s390x" ]]; then
    arch="i386"
else
    arch="x86_64"
    echo -e "${red}检测架构失败，使用默认架构: ${arch}${plain}"
fi

echo "架构: ${arch}"

# os version
if [[ -f /etc/os-release ]]; then
    os_version=$(awk -F'[= ."]' '/VERSION_ID/{print $3}' /etc/os-release)
fi
if [[ -z "$os_version" && -f /etc/lsb-release ]]; then
    os_version=$(awk -F'[= ."]+' '/DISTRIB_RELEASE/{print $2}' /etc/lsb-release)
fi

if [[ x"${release}" == x"centos" || x"${release}" == x"fedora" ]]; then
    if [[ x"${release}" == x"fedora" ]]; then
        os_version=$(grep -oP 'VERSION="[0-9]+' /etc/os-release | grep -oP '[0-9]+')
        if [[ ${os_version} -le 36 ]]; then
            echo -e "${red}请使用 Fedora 36 或更高版本的系统！${plain}\n" && exit 1
        fi
    fi
    if [[ ${os_version} -le 6 ]]; then
        echo -e "${red}请使用 CentOS 7 或更高版本的系统！${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"ubuntu" ]]; then
    if [[ ${os_version} -lt 16 ]]; then
        echo -e "${red}请使用 Ubuntu 16 或更高版本的系统！${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"debian" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red}请使用 Debian 8 或更高版本的系统！${plain}\n" && exit 1
    fi
fi

echo "系统: ${os_version}"

install_base() {
    if [[ x"${release}" == x"centos" ]]; then
        yum install epel-release -y
        yum install wget curl unzip tar crontabs socat jq -y
    elif [[ x"${release}" == x"fedora" ]]; then
        dnf install wget curl unzip tar cronie socat jq -y
    else
        apt-get update -y
        apt install wget curl unzip tar cron socat jq -y
    fi
}

check_status() {
    if [[ ! -f /etc/systemd/system/ddns-go.service ]]; then
        return 2
    fi
    temp=$(systemctl status ddns-go | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
    if [[ x"${temp}" == x"running" ]]; then
        return 0
    else
        return 1
    fi
}

install_ddns() {
    if [[ -e /etc/ddns-go/ ]]; then
        rm -rf /etc/ddns-go/
    fi

    mkdir /etc/ddns-go/ -p
    cd /etc/ddns-go/

    last_version=$(curl -Ls "${url}/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

    if  [ $# == 0 ] ;then
        if [[ ! -n "$last_version" ]]; then
            echo -e "${red}检测 ddns-go 版本失败，可能是超出 Github API 限制，请稍后再试，或手动指定 ddns-go 版本安装${plain}"
            exit 1
        fi
        echo -e "检测到 ddns-go 最新版本：${last_version}，开始安装"
        json=$(curl -Ls "${url}")
        last_version=$(echo "$last_version" | sed 's/^v//')
        filename="ddns-go_${last_version}_linux_${arch}.tar.gz"
        echo -e "下载的文件名：${filename}"
        download_url=$(echo "${json}" | jq -r --arg filename "${filename}" '.[0].assets[] | select(.name == $filename) | .url')
        echo -e $download_url
        wget -q --header='Accept:application/octet-stream' -N --no-check-certificate -O /usr/local/ddns-go/ddns-go-linux.tar.gz "${download_url}"
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载 ddns-go 失败，请确保你的服务器能够下载 Github 的文件${plain}"
            exit 1
        fi
    else
        tag_name=$1
        last_version=$(echo "$tag_name" | sed 's/^v//')
        json=$(curl -Ls "${url}")
        filename="ddns-go_${last_version}_linux_${arch}.tar.gz"
        download_url=$(echo "${json}" | jq -r --arg filename "${filename}" --arg tag "${tag_name}" 'select(.tag_name == $tag) | .assets[] | select(.name == $filename) | .url')
        echo -e "开始安装 ddns-go $1"
        wget -q --header='Accept:application/octet-stream' -N --no-check-certificate -O /usr/local/ddns-go/ddns-go-linux.tar.gz "${download_url}"
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载 ddns-go $1 失败，请确保此版本存在${plain}"
            exit 1
        fi
    fi

    if [[ ! -f /etc/ddns-go/config.yaml ]]; then
        echo -e "全新安装，请输入ddns-go监听端口："
        while true; do
            echo -n "请输入监听端口（默认: 9877）: "
            read port

            if [[ -z "$port" ]]; then
                port=9877
                break
            fi

            if [[ $port -ge 0 && $port -le 65535 ]]; then
                break
            else
                echo "端口不在合法范围内，请输入0到65535之间的端口。"
            fi
        done
    fi


    tar -xzvf ddns-go-linux.tar.gz
    rm -f LICENSE
    rm -f README.md
    chmod +x ddns-go
    rm config.yaml -f
    touch config.yaml
    rm /etc/systemd/system/ddns-go.service -f
    systemctl daemon-reload
    /etc/ddns-go/ddns-go -s install -l ":$port" -f 600 -c /etc/ddns-go/config.yaml
    echo -e "${green}ddns-go ${last_version}${plain} 安装完成，你可以通过/etc/ddns-go/config.yaml来设置ddns-go配置"
    curl -o /usr/bin/ddns-go -Ls https://raw.githubusercontent.com/kogekiplayer/ddns-go-script/master/ddns-go.sh
    chmod +x /usr/bin/ddns-go


    cd $cur_dir
    rm -f install.sh
    echo -e ""
    echo "ddns-go 管理脚本使用方法: "
    echo "-------------------------------------------"
    echo "ddns-go               - 显示管理菜单 (功能更多)"
    echo "ddns-go start         - 启动 ddns-go"
    echo "ddns-go stop          - 停止 ddns-go"
    echo "ddns-go restart       - 重启 ddns-go"
    echo "ddns-go status        - 查看 ddns-go 状态"
    echo "ddns-go enable        - 设置 ddns-go 开机自启"
    echo "ddns-go disable       - 取消 ddns-go 开机自启"
    echo "ddns-go log           - 查看 ddns-go 日志"
    echo "ddns-go update        - 更新 ddns-go"
    echo "ddns-go update vx.x.x - 更新 ddns-go 指定版本"
    echo "ddns-go config        - 编辑 ddns-go 配置文件"
    echo "ddns-go install       - 安装 ddns-go"
    echo "ddns-go uninstall     - 卸载 ddns-go"
    echo "ddns-go reset         - 修改 ddns-go 监听端口"
    echo "-------------------------------------------"


    
}

install_base
install_ddns
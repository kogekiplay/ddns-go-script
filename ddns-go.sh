#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}错误: ${plain} 必须使用root用户运行此脚本！\n" && exit 1

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

echo -e "检测到系统类型: ${release}"

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

confirm() {
    if [[ $# > 1 ]]; then
        echo && read -rp "$1 [默认$2]: " temp
        if [[ x"${temp}" == x"" ]]; then
            temp=$2
        fi
    else
        read -rp "$1 [y/n]: " temp
    fi
    if [[ x"${temp}" == x"y" || x"${temp}" == x"Y" ]]; then
        return 0
    else
        return 1
    fi
}

confirm_restart() {
    confirm "是否重启ddns-go" "y"
    if [[ $? == 0 ]]; then
        restart
    else
        show_menu
    fi
}

before_show_menu() {
    echo && echo -n -e "${yellow}按回车返回主菜单: ${plain}" && read temp
    show_menu
}

install() {
    bash <(curl -Ls https://raw.githubusercontent.com/kogekiplay/ddns-go-script/master/install.sh)
    if [[ $? == 0 ]]; then
        if [[ $# == 0 ]]; then
            start
        else
            start 0
        fi
    fi
}

update() {
    if [[ $# == 0 ]]; then
        echo && echo -n -e "输入指定版本(默认最新版): " && read version
    else
        version=$2
    fi
    bash <(curl -Ls https://raw.githubusercontent.com/kogekiplay/ddns-go-script/master/install.sh) $version
    if [[ $? == 0 ]]; then
        echo -e "${green}更新完成，已自动重启 ddns-go，请使用 systemctl status ddns-go 查看运行日志${plain}"
        exit
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

config() {
    echo "ddns-go在修改配置后会自动尝试重启"
    vim /etc/ddns-go/config.yml
    sleep 2
    check_status
    case $? in
        0)
            echo -e "ddns-go状态: ${green}已运行${plain}"
            ;;
        1)
            echo -e "检测到您未启动ddns-go或ddns-go自动重启失败，是否查看日志？[Y/n]" && echo
            read -e -rp "(默认: y):" yn
            [[ -z ${yn} ]] && yn="y"
            if [[ ${yn} == [Yy] ]]; then
               show_log
            fi
            ;;
        2)
            echo -e "ddns-go状态: ${red}未安装${plain}"
    esac
}

uninstall() {
    confirm "确定要卸载 ddns-go 吗?" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    systemctl stop ddns-go
    systemctl disable ddns-go
    rm /etc/systemd/system/ddns-go.service -f
    systemctl daemon-reload
    systemctl reset-failed
    rm /etc/ddns-go/ -rf

    echo ""
    echo -e "卸载成功，如果你想删除此脚本，则退出脚本后运行 ${green}rm /usr/bin/ddns-go -f${plain} 进行删除"
    echo ""

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

start() {
    check_status
    if [[ $? == 0 ]]; then
        echo ""
        echo -e "${green}ddns-go已运行，无需再次启动，如需重启请选择重启${plain}"
    else
        systemctl start ddns-go
        sleep 2
        check_status
        if [[ $? == 0 ]]; then
            echo -e "${green}ddns-go 启动成功，请使用 systemctl status ddns-go 查看运行日志${plain}"
        else
            echo -e "${red}ddns-go可能启动失败，请稍后使用 systemctl status ddns-go 查看日志信息${plain}"
        fi
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

stop() {
    systemctl stop ddns-go
    sleep 2
    check_status
    if [[ $? == 1 ]]; then
        echo -e "${green}ddns-go 停止成功${plain}"
    else
        echo -e "${red}ddns-go停止失败，可能是因为停止时间超过了两秒，请稍后查看日志信息${plain}"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

restart() {
    systemctl restart ddns-go
    sleep 2
    check_status
    if [[ $? == 0 ]]; then
        echo -e "${green}ddns-go 重启成功，请使用 systemctl status ddns-go 查看运行日志${plain}"
    else
        echo -e "${red}ddns-go可能启动失败，请稍后使用 systemctl status ddns-go 查看日志信息${plain}"
    fi
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

status() {
    systemctl status ddns-go --no-pager -l
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

enable() {
    systemctl enable ddns-go
    if [[ $? == 0 ]]; then
        echo -e "${green}ddns-go 设置开机自启成功${plain}"
    else
        echo -e "${red}ddns-go 设置开机自启失败${plain}"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

disable() {
    systemctl disable ddns-go
    if [[ $? == 0 ]]; then
        echo -e "${green}ddns-go 取消开机自启成功${plain}"
    else
        echo -e "${red}ddns-go 取消开机自启失败${plain}"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

show_log() {
    journalctl -u ddns-go.service -e --no-pager -f
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

update_shell() {
    wget -O /usr/bin/ddns-go -N --no-check-certificate https://raw.githubusercontent.com/kogekiplay/ddns-go-script/master/ddns-go.sh
    if [[ $? != 0 ]]; then
        echo ""
        echo -e "${red}下载脚本失败，请检查本机能否连接 Github${plain}"
        before_show_menu
    else
        chmod +x /usr/bin/ddns-go
        echo -e "${green}升级脚本成功，请重新运行脚本${plain}" && exit 0
    fi
}

# 0: running, 1: not running, 2: not installed
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

check_enabled() {
    temp=$(systemctl is-enabled ddns-go)
    if [[ x"${temp}" == x"enabled" ]]; then
        return 0
    else
        return 1;
    fi
}

check_uninstall() {
    check_status
    if [[ $? != 2 ]]; then
        echo ""
        echo -e "${red}ddns-go已安装，请不要重复安装${plain}"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

check_install() {
    check_status
    if [[ $? == 2 ]]; then
        echo ""
        echo -e "${red}请先安装ddns-go${plain}"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

show_status() {
    check_status
    case $? in
        0)
            echo -e "ddns-go状态: ${green}已运行${plain}"
            show_enable_status
            ;;
        1)
            echo -e "ddns-go状态: ${yellow}未运行${plain}"
            show_enable_status
            ;;
        2)
            echo -e "ddns-go状态: ${red}未安装${plain}"
    esac
}

show_enable_status() {
    check_enabled
    if [[ $? == 0 ]]; then
        echo -e "是否开机自启: ${green}是${plain}"
    else
        echo -e "是否开机自启: ${red}否${plain}"
    fi
}

reset() {
    check_status
    if [[ $? -eq 0 || $? -eq 1 ]]; then
        echo "ddns-go 服务已安装或正在运行，首先执行卸载操作..."
        /etc/ddns-go/ddns-go -s uninstall
    fi
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
    /etc/ddns-go/ddns-go -s install -l ":$port" -f 600 -c /etc/ddns-go/config.yaml
}

show_usage() {
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

show_menu() {
    echo -e "
  ${green}ddns-go 后端管理脚本，${plain}${red}不适用于docker${plain}
--- https://github.com/kogekiplay/ddns-go-script ---
  ${green}0.${plain} 修改配置
————————————————
  ${green}1.${plain} 安装 ddns-go
  ${green}2.${plain} 更新 ddns-go
  ${green}3.${plain} 卸载 ddns-go
————————————————
  ${green}4.${plain} 启动 ddns-go
  ${green}5.${plain} 停止 ddns-go
  ${green}6.${plain} 重启 ddns-go
  ${green}7.${plain} 查看 ddns-go 状态
  ${green}8.${plain} 查看 ddns-go 日志
————————————————
  ${green}9.${plain} 设置 ddns-go 开机自启
  ${green}10.${plain} 取消 ddns-go 开机自启
————————————————
  ${green}11.${plain} 升级 ddns-go 维护脚本
  ${green}12.${plain} 修改 ddns-go 监听端口
 "
 #后续更新可加入上方字符串中
    show_status
    echo && read -rp "请输入选择 [0-11]: " num

    case "${num}" in
        0) config ;;
        1) check_uninstall && install ;;
        2) check_install && update ;;
        3) check_install && uninstall ;;
        4) check_install && start ;;
        5) check_install && stop ;;
        6) check_install && restart ;;
        7) check_install && status ;;
        8) check_install && show_log ;;
        9) check_install && enable ;;
        10) check_install && disable ;;
        11) update_shell ;;
        12) reset ;;
        *) echo -e "${red}请输入正确的数字 [0-12]${plain}" ;;
    esac
}



if [[ $# > 0 ]]; then
    case $1 in
        "start") check_install 0 && start 0 ;;
        "stop") check_install 0 && stop 0 ;;
        "restart") check_install 0 && restart 0 ;;
        "status") check_install 0 && status 0 ;;
        "enable") check_install 0 && enable 0 ;;
        "disable") check_install 0 && disable 0 ;;
        "log") check_install 0 && show_log 0 ;;
        "update") check_install 0 && update 0 $2 ;;
        "config") config $* ;;
        "install") check_uninstall 0 && install 0 ;;
        "uninstall") check_install 0 && uninstall 0 ;;
        "reset") reset ;;
        *) show_usage
    esac
else
    show_menu
fi


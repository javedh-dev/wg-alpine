# Set these values so the installer can still run in color
COL_NC='\e[0m' # No Color
COL_LIGHT_GREEN='\e[1;32m'
COL_LIGHT_RED='\e[1;31m'
TICK="[${COL_LIGHT_GREEN}✓${COL_NC}]"
CROSS="[${COL_LIGHT_RED}✗${COL_NC}]"
INFO="[i]"
OVER="\\r\\033[K"
TEMP_DIR="/opt/wireguard/temp"

show_ascii_logo() {
    echo -e "
    ${COL_LIGHT_RED}
     _  _   ___          __   __    ____  __   __ _  ____ 
    / )( \ / __) ${COL_LIGHT_GREEN} ___ ${COL_LIGHT_RED}  / _\ (  )  (  _ \(  ) (  ( \(  __)
    \ /\ /( (_ \ ${COL_LIGHT_GREEN}(___) ${COL_LIGHT_RED}/    \/ (_/\ ) __/ )(  /    / ) _) 
    (_/\_) \___/       \_/\_/\____/(__)  (__) \_)__)(____)
     ${COL_NC}     
"
}

os_check() {
    printf "%b Detecting Operating System." "${INFO}"
    detected_os=$(grep "\bID\b" /etc/os-release | cut -d '=' -f2 | tr -d '"')
    detected_version=$(grep VERSION_ID /etc/os-release | cut -d '=' -f2 | tr -d '"')
    if ! grep -iq "alpine" <(echo "$detected_os"); then
        printf "%b%b This installer only supports Alpine Linux." "${OVER}" "${INFO}"
        printf "\n%b ${detected_os} is not yet supported\n\n" "${CROSS}"
        exit 1
    else
        printf "%b%b OS : %b-%b " "${OVER}" "${TICK}" "${detected_os}" "${detected_version}"
    fi
}
is_command() {
    # Checks to see if the given command (passed as a string argument) exists on the system.
    # The function returns 0 (success) if the command exists, and 1 if it doesn't.
    local check_command="$1"

    command -v "${check_command}" >/dev/null 2>&1
}

package_manager_detect() {
    printf "\n\n%b Detecting Package Manager." "${INFO}"
    if is_command apk; then
        printf "%b%b APK package manager is detected." "${OVER}" "${TICK}"
        PKG_MANAGER="apk"
        UPDATE_PKG_CACHE="${PKG_MANAGER} update"
        PKG_INSTALL=("${PKG_MANAGER}" add)
        PKG_COUNT="${PKG_MANAGER} upgrade --simulate --no-progress | head -n -1 | wc -l"
        INSTALLER_DEPS=(curl git jq openrc grep tar)
        WG_DEPS=(wget wireguard-tools iptables)
    # If apk package managers was not found
    else
        # we cannot install required packages
        printf "%b%b No supported package manager found\\n" "${OVER}" "${CROSS}"
        # so exit the installer
        exit
    fi
}

update_alpine() {
    printf "\n\n%b Updating alpine linux" "${INFO}"
    apk update &>/dev/null
    apk upgrade &>/dev/null
    printf "%b%b Updated alpine linux" "${OVER}" "${TICK}"
}

install_dependent_packages() {
    # Install packages passed in via argument array
    # No spinner - conflicts with set -e
    declare -a installArray

    for i in "$@"; do
        printf "  %b Checking for %s..." "${INFO}" "${i}"
        if "${PKG_MANAGER}" info | grep -Eq "^${i}\$" &>/dev/null; then
            printf "%b  %b Checking for %s\\n" "${OVER}" "${TICK}" "${i}"
        else
            printf "%b  %b Checking for %s (will be installed)\\n" "${OVER}" "${INFO}" "${i}"
            installArray+=("${i}")
        fi
    done
    # If there's anything to install, install everything in the list.
    if [[ "${#installArray[@]}" -gt 0 ]]; then
        printf "  %b Processing %s install(s) for: %s, please wait...\\n" "${INFO}" "${PKG_MANAGER}" "${installArray[*]}"
        printf '%*s\n' "${c}" '' | tr " " -
        "${PKG_INSTALL[@]}" "${installArray[@]}"
        printf '%*s\n' "${c}" '' | tr " " -

        # Initialize openrc if we installed it
        if [[ "${installArray[*]}" =~ "openrc" ]] && [[ ! -d /run/openrc ]]; then
            mkdir /run/openrc
            touch /run/openrc/softlevel
            openrc
        fi
        return
    fi
    printf "\\n"
    return 0
}

install_dependencies() {
    printf "\n\n%b Setup will install Wireguard VPN with wireguard UI" "${INFO}"
    printf "\n\n%b Checking for / Installing Required dependencies for Installer...\\n" "${INFO}"
    install_dependent_packages "${INSTALLER_DEPS[@]}"
    printf "\n\n%b Checking for / Installing Required dependencies for Wireguard...\\n" "${INFO}"
    install_dependent_packages "${WG_DEPS[@]}"
}

setup_wireguard() {
    printf "%b Setup wireguard configurations\n" "${INFO}"
    printf "  %b Adding iptable to start at boot\n" "${INFO}"
    rc-update add iptables default &>/dev/null
    printf "%b  %b Added iptable to start at boot\n" "${OVER}" "${TICK}"

    printf "  %b Adding environment variables to start wireguard\n" "${INFO}"
    export WGUI_USERNAME="wg-alpine" &>/dev/null
    export WGUI_PASSWORD="wg-alpine" &>/dev/null
    export WGUI_SERVER_POST_UP_SCRIPT="iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE;iptables -A FORWARD -o wg0 -j ACCEPT" &>/dev/null
    export WGUI_SERVER_POST_DOWN_SCRIPT="iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE;iptables -D FORWARD -o wg0 -j ACCEPT" &>/dev/null
    printf "%b  %b Added environment variables to start wireguard\n" "${OVER}" "${TICK}"

    printf "  %b Adding sysctl confugrations\n" "${INFO}"
    echo "net.ipv4.ip_forward = 1" >>/etc/sysctl.conf
    echo "net.ipv6.conf.all.forwarding = 1" >>/etc/sysctl.conf
    echo "net.ipv4.conf.all.proxy_arp = 1" >>/etc/sysctl.conf
    printf "%b  %b Added sysctl confugrations\n" "${OVER}" "${TICK}"

    printf "  %b Allowing to IPv4 forwarding\n" "${INFO}"
    sed -i 's/IPFORWARD="no"/IPFORWARD="yes"/g' /etc/conf.d/iptables &>/dev/null
    /etc/init.d/iptables save &>/dev/null
    rc-service iptables restart &>/dev/null
    printf "%b  %b Allowed to IPv4 forwarding\n" "${OVER}" "${TICK}"

}

get_architecture() {
    ARCH=$(uname -m)
    if (ARCH=='x86_64'); then
        echo "amd64"
    else
        printf "\n%b Currently only x86_64 architecture is supported" "${CROSS}"
        exit 1
    fi
}

download_wireguard_ui() {

    WGUI_URL="https://api.github.com/repos/ngoduykhanh/wireguard-ui/releases/"
    printf "\n%b Downloading Wireguard UI..." "${INFO}"
    #  curl -s https://api.github.com/repos/ngoduykhanh/wireguard-ui/releases/109655349/assets | jq 'map(select(.browser_download_url | test("linux-amd64.tar.gz$")) .browser_download_url) | .[0]'

    printf "\n  %b Determining Latest release version" "${INFO}"
    LATEST_RELEASE=$(curl -s https://api.github.com/repos/ngoduykhanh/wireguard-ui/releases | jq 'max_by(.id) .id')
    LATEST_VERSION=$(curl -s https://api.github.com/repos/ngoduykhanh/wireguard-ui/releases | jq 'max_by(.id) .tag_name')
    printf "%b  %b Latest version is %b" "${OVER}" "${TICK}" "${LATEST_VERSION}"

    printf "\n  %b Determining os architecture to download..." "${INFO}"
    OS_ARCH=$(get_architecture)
    printf "%b  %b OS Architecture : \"%b\"" "${OVER}" "${TICK}" "${OS_ARCH}"

    printf "\n  %b Setting up temp directory" "${INFO}"
    rm -rf ${TEMP_DIR}
    mkdir -p ${TEMP_DIR}
    cd ${TEMP_DIR}
    printf "%b  %b Temp directory setup successfully" "${OVER}" "${TICK}"

    printf "\n  %b Determining download url" "${INFO}"
    DOWNLOAD_URL=$(curl -s https://api.github.com/repos/ngoduykhanh/wireguard-ui/releases/109655349/assets | jq -r 'map(select(.browser_download_url | test("linux-'"${OS_ARCH}"'.tar.gz$")) .browser_download_url) | .[0]')
    printf "%b  %b Downloading from url - \"%b\"\n" "${OVER}" "${INFO}" "${DOWNLOAD_URL}"
    wget -p -q ${DOWNLOAD_URL} -O wireguard-ui.tar.gz
    printf "%b%b  %b Download complete\n" "${OVER}" "${OVER}" "${TICK}"
}


create_wgui_restart(){
    cat > /opt/wireguard/wgui-restart <<BLOCK
#!/bin/sh
rc-service wgui restart
BLOCK
}

create_wgui_service(){
    cat > /etc/init.d/wgui <<BLOCK
#!/sbin/openrc-run
description="A wireguard service which will be autorestart on config changes"

pidfile="/run/\${RC_SVCNAME}.pid"
command="/opt/wireguard/wgui"
command_background=yes
output_log="/var/log/wgui.log"
error_log="/var/log/wgui.log"

start_pre() {
    if (ls /sys/class/net | grep wg0 &>/dev/null); then
        echo "wg0 interface is already up. Restarting !!!"
        wg-quick down wg0
    fi
    
    if (ls /etc/wireguard/wg0.conf &>/dev/null); then
        wg-quick up wg0
    fi
    
}

stop_post() {
    if ! (ls /sys/class/net | grep wg0 >/dev/null); then
        echo "wg0 interface is already down. Skipping !!!"
    fi
    if (ls /etc/wireguard/wg0.conf &>/dev/null); then
        wg-quick down wg0
    fi
}
BLOCK
}

create_wgui_watch_service(){
    cat > /etc/init.d/wgui-watch <<BLOCK
#!/sbin/openrc-run
description="A wireguard UI watcher service"

pidfile="/run/\${RC_SVCNAME}.pid"
command="/sbin/inotifyd"
command_args="/opt/wireguard/wgui-restart /etc/wireguard/wg0.conf:w"
command_background=yes
output_log="/var/log/wgui-watch.log"
error_log="/var/log/wgui-watch.log"
BLOCK
}

# Enable service so that it will start with next reboot
enable_service() {
    # Local, named variables
    local str="Enabling ${1} service to start on reboot"
    printf "  %b %s..." "${INFO}" "${str}"
    rc-update add "${1}" &>/dev/null
    printf "%b  %b %s...\\n" "${OVER}" "${TICK}" "${str}"
}

setup_wgui() {
    printf "\n%b Setting Up WGUI" "${INFO}"

    printf "\n  %b Extracting binary and making it executable" "${INFO}"
    tar -xzf wireguard-ui.tar.gz
    mv wireguard-ui wgui
    chmod +x wgui
    cp wgui ../wgui
    printf "%b  %b Extracted Successfully" "${OVER}" "${TICK}"

    printf "\n  %b Creating a service restarter" "${INFO}"
    create_wgui_restart
    chmod +x /opt/wireguard/wgui-restart
    printf "%b  %b Created a service restarter" "${OVER}" "${TICK}"

    printf "\n  %b Creating wgui and watch services" "${INFO}"
    create_wgui_service
    create_wgui_watch_service
    chmod +x /etc/init.d/wgui
    chmod +x /etc/init.d/wgui-watch
    printf "%b  %b Created wgui and watch services" "${OVER}" "${TICK}"

    printf "\n  %b Enabling services to start at boot" "${INFO}" 
    enable_service "wgui"
    enable_service "wgui-watch"
    printf "%b  %b Enabled services to start at boot" "${OVER}" "${TICK}"

    printf "\n  %b Creating empty config file" "${INFO}" 
    touch /etc/wireguard/wg0.conf
    printf "%b  %b Created empty config file" "${OVER}" "${TICK}"
}

show_completion() {
    show_ascii_logo
    printf "%b Setup completed succesfully\n" "${TICK}"
    
    printf "\n\n%b System Reboot is required. \n\n\n" "${INFO}"
    read -p "Press 'y' reboot...." ans

    if [[ $ans == 'y' ]]; then
        reboot
    fi
    # printf "\n\n\n"
}



start_setup() {
    clear
    show_ascii_logo
    os_check
    package_manager_detect
    update_alpine
    install_dependencies
    setup_wireguard
    download_wireguard_ui
    setup_wgui
    show_completion

}

start_setup

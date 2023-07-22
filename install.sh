# Set these values so the installer can still run in color
COL_NC='\e[0m' # No Color
COL_LIGHT_GREEN='\e[1;32m'
COL_LIGHT_RED='\e[1;31m'
TICK="[${COL_LIGHT_GREEN}✓${COL_NC}]"
CROSS="[${COL_LIGHT_RED}✗${COL_NC}]"
INFO="[i]"
OVER="\\r\\033[K"

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

update_alpine() {
    printf "\n\n%b Updating alpine linux" "${INFO}"
    #sudo apt-get update && sudo apt-get upgrade -y
}

is_command() {
    # Checks to see if the given command (passed as a string argument) exists on the system.
    # The function returns 0 (success) if the command exists, and 1 if it doesn't.
    local check_command="$1"

    command -v "${check_command}" >/dev/null 2>&1
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

package_manager_detect() {
    printf "\n\n%b Detecting Package Manager." "${INFO}"
    if is_command apk; then
        printf "%b%b APK package manager in detected." "${OVER}" "${TICK}"
        PKG_MANAGER="apk"
        UPDATE_PKG_CACHE="${PKG_MANAGER} update"
        PKG_INSTALL=("${PKG_MANAGER}" add)
        PKG_COUNT="${PKG_MANAGER} upgrade --simulate --no-progress | head -n -1 | wc -l"
        INSTALLER_DEPS=(curl git jq openrc grep tar)
        WG_DEPS=(wget wireguard-tools)
    # If apk package managers was not found
    else
        # we cannot install required packages
        printf "%b%b No supported package manager found\\n" "${OVER}" "${CROSS}"
        # so exit the installer
        exit
    fi
}

# Start/Restart service passed in as argument
restart_service() {
    # Local, named variables
    local str="Restarting ${1} service"
    printf "  %b %s..." "${INFO}" "${str}"
    service "${1}" restart &>/dev/null
    printf "%b  %b %s...\\n" "${OVER}" "${TICK}" "${str}"
}

# Enable service so that it will start with next reboot
enable_service() {
    # Local, named variables
    local str="Enabling ${1} service to start on reboot"
    printf "  %b %s..." "${INFO}" "${str}"
    rc-update add "${1}" &>/dev/null
    printf "%b  %b %s...\\n" "${OVER}" "${TICK}" "${str}"
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
    printf "%b  %b OS Architecture : %b" "${OVER}" "${TICK}" "${OS_ARCH}"

    printf "\n  %b Setting up temp directory" "${INFO}"
    mkdir -p /usr/share/wireguard/temp
    cd /usr/share/wireguard/temp
    printf "\n  %b Temp directory setup successfully" "${TICK}"

    printf "\n  %b Determining download url" "${INFO}"
    DOWNLOAD_URL=$(curl -s https://api.github.com/repos/ngoduykhanh/wireguard-ui/releases/109655349/assets | jq -r 'map(select(.browser_download_url | test("linux-'"${OS_ARCH}"'.tar.gz$")) .browser_download_url) | .[0]')
    printf "%b  %b Downloading from url - \"%b\"\n" "${OVER}" "${INFO}" "${DOWNLOAD_URL}"
    wget -p -q ${DOWNLOAD_URL} -O wireguard-ui.tar.gz
    printf "%b%b  %b Download complete\n" "${OVER}" "${OVER}" "${TICK}"
}

setup_wgui() {
    printf "\n%b Setting Up WGUI" "${INFO}"

    printf "\n  %b Extracting binary" "${INFO}"
    tar -xvf wireguard-ui.tar.gz
    printf "\n  %b Extracted Successfully" "${TICK}"

}

start_setup() {
    show_ascii_logo
    os_check
    package_manager_detect
    printf "\n\n%b Setup will install Wireguard VPN with wireguard UI" "${INFO}"
    printf "\n\n%b Checking for / Installing Required dependencies for Installer...\\n" "${INFO}"
    install_dependent_packages "${INSTALLER_DEPS[@]}"
    printf "\n\n%b Checking for / Installing Required dependencies for Wireguard...\\n" "${INFO}"
    install_dependent_packages "${WG_DEPS[@]}"
    download_wireguard_ui
    setup_wgui
    printf "\n\n"
}

start_setup

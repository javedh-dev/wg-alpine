# Set these values so the installer can still run in color
COL_NC='\e[0m' # No Color
COL_LIGHT_GREEN='\e[1;32m'
COL_LIGHT_RED='\e[1;31m'
TICK="[${COL_LIGHT_GREEN}✓${COL_NC}]"
CROSS="[${COL_LIGHT_RED}✗${COL_NC}]"
INFO="[i]"

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

update_alpine(){
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
        printf "%b This installer only supports Alpine Linux." "${INFO}"
        printf "\n%b ${detected_os} is not yet supported\n\n" "${CROSS}"
        exit 1
    else
        printf "%b OS : %b-%b " "${TICK}" "${detected_os}" "${detected_version}"
    fi
}

package_manager_detect() {
if is_command apk ; then
    PKG_MANAGER="apk"
    UPDATE_PKG_CACHE="${PKG_MANAGER} update"
    PKG_INSTALL=("${PKG_MANAGER}" add)
    PKG_COUNT="${PKG_MANAGER} upgrade --simulate --no-progress | head -n -1 | wc -l"
    INSTALLER_DEPS=(git openrc grep tar)
    WG_DEPS=(wget)
# If apk package managers was not found
else
    # we cannot install required packages
    printf "  %b No supported package manager found\\n" "${CROSS}"
    # so exit the installer
    exit
fi
}


start_setup() {
    show_ascii_logo
    os_check
    package_manager_detect
    printf "\n\n%b Setup will install Wireguard VPN with wireguard UI on alpine linux" "${INFO}"
    printf "\n%b Initializing Wireguard on alpine" "${TICK}"
    update_alpine

    printf "\n\n"
}

start_setup

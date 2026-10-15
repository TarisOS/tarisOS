#!/bin/bash
export LC_ALL=C
readonly SELF=$0
readonly COREDIR=/opt/siliconmotion
readonly OTHERPDDIR=/opt/displaylink
readonly LOGDIR=/var/log/SMIUSBDisplay
readonly PRODUCT="Silicon Motion Linux USB Display Software"
VERSION=4.3.6.0
ACTION=install

DEB_DEPENDENCIES=(libusb-1.0-0-dev mokutil pkg-config libdrm-dev libc6-dev coreutils gcc)

readonly DEB_DEPENDENCIES


prompt_yes_no()
{
  read -rp "$1 (Y/n) " CHOICE
  [[ ! ${CHOICE:-Y} == "${CHOICE#[Yy]}" ]]
}

prompt_command()
{
  echo "> $*"
  prompt_yes_no "Do you want to continue?" || exit 0
  "$@"
}

error()
{
  echo "ERROR: $*" >&2
}


uninstall_evdi_module()
{
  local TARGZ=$1
  local EVDI=$2

  if ! tar xf "$TARGZ" -C "$EVDI"; then
    error "Unable to extract $TARGZ to $EVDI"
    return 1
  fi

  make -C "${EVDI}/module" uninstall_dkms
}

is_armv8()
{
  [[ "$(uname -m)" == "aarch64" ]]
}

is_32_bit()
{
  [ "$(getconf LONG_BIT)" == "32" ]
}

add_upstart_script()
{
  cat > /etc/init/smiusbdisplay.conf <<'EOF'
description "SiliconMotion Driver Service"


start on login-session-start
stop on desktop-shutdown

# Restart if process crashes
respawn

# Only attempt to respawn 10 times in 5 seconds
respawn limit 10 5

chdir /opt/siliconmotion

pre-start script
    . /opt/siliconmotion/smi-udev.sh

    if [ "\$(get_siliconmotion_dev_count)" = "0" ]; then
        stop
        exit 0
    fi
end script
script
    [ -r /etc/default/siliconmotion ] && . /etc/default/siliconmotion
    modprobe evdi
    if [ $? != 0 ]; then
	local v=$(awk -F '=' '/PACKAGE_VERSION/{print $2}' /opt/siliconmotion/module/dkms.conf)
	dkms remove -m evdi -v $v --all
	if [ $? != 0 ]; then
    		rm –rf /var/lib/dkms/$v
	fi
	dkms install /opt/siliconmotion/module/
	if [ $? == 0 ]; then
		cp /opt/siliconmotion/evdi.conf /etc/modprobe.d 
		modprobe evdi
	fi
    fi
    exec /opt/siliconmotion/SMIUSBDisplayManager
end script
EOF

  chmod 0644 /etc/init/smiusbdisplay.conf
}

add_smi_script()
{
  MODVER="$1"
  cat > /usr/share/X11/xorg.conf.d/20-smi.conf <<'EOF'
Section "Device"
        Identifier "SiliconMotion"
        Driver "modesetting"
	Option "PageFlip" "false"
EndSection
EOF

chown root: /usr/share/X11/xorg.conf.d/20-smi.conf
chmod 644 /usr/share/X11/xorg.conf.d/20-smi.conf

}

remove_smi_script()
{
  rm -f /usr/share/X11/xorg.conf.d/20-smi.conf
}

add_wayland_script()
{
if [ "$(lsb_release -r --short)"  == "20.04" ];
then
  mkdir -p /usr/share/xsessions/hidden
  dpkg-divert --rename --divert /usr/share/xsessions/hidden/ubuntu.desktop --add /usr/share/xsessions/ubuntu.desktop
fi
}

remove_wayland_script()
{
if [ "$(lsb_release -r --short)"  == "20.04" ];
then
  dpkg-divert --rename --remove /usr/share/xsessions/ubuntu.desktop
fi
}


add_systemd_service()
{
  cat > /lib/systemd/system/smiusbdisplay.service <<'EOF'
[Unit]
Description=SiliconMotion Driver Service
After=display-manager.service
Conflicts=getty@tty7.service

[Service]
ExecStartPre=/bin/bash -c "modprobe evdi || (dkms remove -m evdi -v $(awk -F '=' '/PACKAGE_VERSION/{print $2}' /opt/siliconmotion/module/dkms.conf) --all; if [ $? != 0 ]; then rm –rf /var/lib/dkms/$(awk -F '=' '/PACKAGE_VERSION/{print $2}' /opt/siliconmotion/module/dkms.conf) ;fi; dkms install /opt/siliconmotion/module/ && cp /opt/siliconmotion/evdi.conf /etc/modprobe.d && modprobe evdi)"

ExecStart=/opt/siliconmotion/SMIUSBDisplayManager
Restart=always
WorkingDirectory=/opt/siliconmotion
RestartSec=5

EOF

  chmod 0644 /lib/systemd/system/smiusbdisplay.service
}

trigger_udev_if_devices_connected()
{
  for device in $(grep -lw 090c /sys/bus/usb/devices/*/idVendor); do
    udevadm trigger --action=add "$(dirname "$device")"
  done
}
remove_upstart_script()
{
  rm -f /etc/init/smiusbdisplay.conf
}

remove_systemd_service()
{
  driver_name="smiusbdisplay"
  echo "Stopping ${driver_name} systemd service"
  systemctl stop ${driver_name}.service
  systemctl disable ${driver_name}.service
  rm -f /lib/systemd/system/${driver_name}.service
}

add_pm_script()
{
  cat > $COREDIR/smipm.sh <<EOF
#!/bin/bash

suspend_usb()
{
# anything want to do for suspend
}

resume_usb()
{
# anything want to do for resume
}

EOF

  if [ "$1" = "upstart" ]
  then
    cat >> $COREDIR/smipm.sh <<EOF
case "\$1" in
  thaw)
    resume_usb
    ;;
  hibernate)
    suspend_usb
    ;;
  suspend)
    suspend_usb
    ;;
  resume)
    resume_usb
    ;;
esac

EOF
  elif [ "$1" = "systemd" ]
  then
    cat >> $COREDIR/smipm.sh <<EOF
case "\$1/\$2" in
  pre/*)
    suspend_usb
    ;;
  post/*)
    resume_usb
    ;;
esac

EOF
  fi

  chmod 0755 $COREDIR/smipm.sh
  if [ "$1" = "upstart" ]
  then
    ln -sf $COREDIR/smipm.sh /etc/pm/sleep.d/smipm.sh
  elif [ "$1" = "systemd" ]
  then
    ln -sf $COREDIR/smipm.sh /lib/systemd/system-sleep/smipm.sh
  fi
}

remove_pm_scripts()
{
  rm -f /etc/pm/sleep.d/smipm.sh
  rm -f /lib/systemd/system-sleep/smipm.sh
}

cleanup()
{
  rm -rf $COREDIR
  rm -rf $LOGDIR
  rm -f /usr/bin/smi-installer
  rm -f /usr/bin/SMIFWLogCapture
  rm -f /etc/modprobe.d/evdi.conf
  rm -rf /etc/modules-load.d/evdi.conf
}

binary_location()
{
  if is_armv8; then
     echo "aarch64"
  else
    local PREFIX="x64"
    local POSTFIX="ubuntu"

    is_32_bit && PREFIX="x86"
    echo "$PREFIX"
  fi
}

install_with_standalone_installer()
{
  local scriptDir
  scriptDir=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
  if [[ $scriptDir == "$COREDIR" ]]; then
    error "SiliconMotion driver is already installed"
    exit 1
  fi

  echo "Installing"
  install -d "$COREDIR" "$LOGDIR"

  install "$SELF" "$COREDIR"
  ln -sf "$COREDIR/$(basename "$SELF")" /usr/bin/smi-installer

  echo "[ Installing EVDI ]"

  local temp_dir
  temp_dir=$(mktemp -d)
  finish() {
    rm -rf "$temp_dir"
  }
  trap finish EXIT



  finish
  
  local BINS SMI LIBUSB_SO GETFWLOG LIBUSB_PATH
  BINS=$(binary_location)
  SMIM="$BINS/SMIUSBDisplayManager"
  GETFWLOG="$BINS/SMIFWLogCapture"
  LIBUSB_SO="libusb-1.0.so.0.2.0"
  LIBUSB_PATH="$BINS/$LIBUSB_SO"
  


  echo "[ Installing $SMIM ]"
  install "$SMIM" "$COREDIR"
  
  if [ "$BINS" != "aarch64" ]; then
    echo "[ Installing $GETFWLOG ]"
    install "$GETFWLOG" "$COREDIR"
  fi
  echo "[ Installing libraries ]"
  install "$LIBUSB_PATH" "$COREDIR"
  ln -sf "$LIBUSB_SO" "$COREDIR/libusb-1.0.so.0"
  ln -sf "$LIBUSB_SO" "$COREDIR/libusb-1.0.so"

  echo "[ Installing firmware packages ]"
  install -m 0644 ./*.bin "$COREDIR"

  if [ "$BINS" != "aarch64" ]; then
    ln -sf "$COREDIR/SMIFWLogCapture" /usr/bin/SMIFWLogCapture
    chmod 0755 /usr/bin/SMIFWLogCapture
  fi

  source smi-udev-installer.sh
  local siliconmotion_bootstrap_script="$COREDIR/smi-udev.sh"
  create_bootstrap_file "$SYSTEMINITDAEMON" "$siliconmotion_bootstrap_script"
  
  add_wayland_script

  echo "[ Adding udev rule for SiliconMotion devices ]"
  create_udev_rules_file /etc/udev/rules.d/99-smiusbdisplay.rules
  xorg_running || udevadm control -R
  xorg_running || udevadm trigger

  echo "[ Adding upstart scripts ]"
  if [ "upstart" == "$SYSTEMINITDAEMON" ]; then
    echo "Starting SMIUSBDisplay upstart job"
    add_upstart_script
#   add_pm_script "upstart"
  elif [ "systemd" == "$SYSTEMINITDAEMON" ]; then
    echo "Starting SMIUSBDisplay systemd service"
    add_systemd_service
#  add_pm_script "systemd"
  fi

  xorg_running || trigger_udev_if_devices_connected
  xorg_running || $siliconmotion_bootstrap_script START

  echo -e "\nInstallation complete!"
  echo -e "\nPlease reboot your computer to ensure SMI driver works."
  xorg_running || exit 0
  read -rp 'Xorg is running. Do you want to reboot now? (Y/n)' CHOICE
  [[ ${CHOICE:-Y} =~ ^[Nn]$ ]] && exit 0
  reboot
}


uninstall_standalone()
{
  echo "[ Uninstalling ]"

  if [ "upstart" == "$SYSTEMINITDAEMON" ]; then
    echo "Stopping SMIUSBDisplay upstart job"
    stop smiusbdisplay
    remove_upstart_script
  elif [ "systemd" == "$SYSTEMINITDAEMON" ]; then
    echo "Stopping SMIUSBDisplay systemd service"
    systemctl stop smiusbdisplay.service
    remove_systemd_service

  fi

  echo "[ Removing suspend-resume hooks ]"
  #remove_pm_scripts

  echo "[ Removing udev rule ]"
  rm -f /etc/udev/rules.d/99-smiusbdisplay.rules
  udevadm control -R
  udevadm trigger
  
  remove_wayland_script

  echo "[ Removing Core folder ]"
  cleanup

  modprobe -r evdi

  if [ -d $OTHERPDDIR ]; then
	  echo "WARNING: There are other products in the system using EVDI."
  else 
	  echo "Removing EVDI from kernel tree, DKMS, and removing sources."
    cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" || exit
    local temp_dir
    temp_dir=$(mktemp -d)
    uninstall_evdi_module "evdi.tar.gz" "$temp_dir"
    rm -rf "$temp_dir"
  fi

  echo -e "\nUninstallation steps complete."
  if [ -f /sys/devices/evdi/count ]; then
    echo "Please note that the evdi kernel module is still in the memory."
    echo "A reboot is required to fully complete the uninstallation process."
  fi
}

uninstall()
{
  check_requirements
  uninstall_standalone
}

missing_requirement()
{
  echo "Unsatisfied dependencies. Missing component: $1." >&2
  echo "This is a fatal error, cannot install $PRODUCT." >&2
  exit 1
}

version_lt()
{
  local left
  left=$(echo "$1" | cut -d. -f-2)
  local right
  right=$(echo "$2" | cut -d. -f-2)

  local greater
  greater=$(echo -e "$left\n$right" | sort -Vr | head -1)

  [ "$greater" != "$left" ]
}

program_exists()
{
  command -v "${1:?}" >/dev/null
}

install_dependencies()
{
  program_exists apt || return 0
  install_dependencies_apt
}

check_installed()
{
  program_exists apt || return 0
  apt list -qq --installed "${1:?}" 2>/dev/null | sed 's:/.*$::' | grep -q -F "$1"
}

check_dkms()
{
  #hash apt 2>/dev/null || return
  apt list -qq --installed dkms 2>/dev/null | grep -q dkms
}

check_libdrm()
{
  #hash apt 2>/dev/null || return
  apt list -qq --installed libdrm-dev 2>/dev/null | grep -q libdrm-dev
}

check_pkg()
{
  #hash apt 2>/dev/null || return
  apt list -qq --installed pkg-config 2>/dev/null | grep -q pkg-config
}

check_gcc()
{
  #hash apt 2>/dev/null || return
  apt list -qq --installed gcc 2>/dev/null | grep -q gcc
}

apt_ask_for_dependencies()
{
  apt --simulate install "$@" 2>&1 |  grep  "^E: " > /dev/null && return 1
  apt --simulate install "$@" | grep -v '^Inst\|^Conf'
}

apt_ask_for_update()
{
  echo "Need to update package list."
  prompt_yes_no "apt update?" || return 1
  apt update
}

install_dependencies_apt()
{
  echo "[ Dependency check ]"
  local packages=()
  program_exists dkms || packages+=(dkms)

  for item in "${DEB_DEPENDENCIES[@]}"; do
    check_installed "$item" || packages+=("$item")
  done

  if [[ ${#packages[@]} -gt 0 ]]; then
    echo "[ Installing dependencies ]"

    if ! apt_ask_for_dependencies "${packages[@]}"; then
      # shellcheck disable=SC2015
      apt_ask_for_update && apt_ask_for_dependencies "${packages[@]}" || check_requirements
    fi

    prompt_command apt install -y "${packages[@]}" || check_requirements
  fi
}

uninstall_older_version()
{
  local local_version
  local smi_bin=/opt/siliconmotion/SMIUSBDisplayManager
  
  [[ -f "$smi_bin" ]] || return
  
  local_version=$("$smi_bin" -version | awk '{print $NF}')
  echo "Uninstalling older smi-driver v${local_version}"
  uninstall
}

check_requirements()
{
  local missing=()
  program_exists dkms || missing+=("DKMS")

  for item in "${DEB_DEPENDENCIES[@]}"; do
    check_installed "$item" || missing+=("${item%-dev}")
  done

  [[ ${#missing[@]} -eq 0 ]] || missing_requirement "${missing[*]}"

  # Required kernel version
  local KVER
  KVER=$(uname -r)
  local KVER_MIN="4.15"
  version_lt "$KVER" "$KVER_MIN" && missing_requirement "Kernel version $KVER is too old. At least $KVER_MIN is required"

  # Linux headers
  [[ -d "/lib/modules/$KVER/build" ]] || missing_requirement "Linux headers for running kernel, $KVER"
}

usage()
{
  echo
  echo "Installs $PRODUCT, version $VERSION."
  echo "Usage: $SELF [ install | uninstall ]"
  echo
  echo "The default operation is install."
  echo "If unknown argument is given, a quick compatibility check is performed but nothing is installed."
  exit 1
}

detect_init_daemon()
{
  local init
  init=$(readlink /proc/1/exe)

  if [[ $init == "/sbin/init" ]]; then
    init=$(/sbin/init --version)
  fi

  case $init in
    *upstart*)
      SYSTEMINITDAEMON="upstart" ;;
    *systemd*)
      SYSTEMINITDAEMON="systemd" ;;
    *runit*)
      SYSTEMINITDAEMON="runit" ;;
    *)
      echo "ERROR: the installer script is unable to find out how to start DisplayLinkManager service automatically on your system." >&2
      echo "Please set an environment variable SYSTEMINITDAEMON to 'upstart', 'systemd' or 'runit' before running the installation script to force one of the options." >&2
      echo "Installation terminated." >&2
      exit 1
  esac
}

detect_distro()
{
  if hash lsb_release 2>/dev/null; then
    echo -n "Distribution discovered: "
    lsb_release -d -s
  else
    echo "WARNING: This is not an officially supported distribution." >&2
  fi
}

xorg_running()
{
  local SESSION_NO
  SESSION_NO=$(loginctl | awk "/$(logname)/ {print \$1; exit}")
  [[ $(loginctl show-session "$SESSION_NO" -p Type) == *=x11 ]]
}
check_preconditions()
{
  modprobe evdi

  if [ -f /sys/devices/evdi/count ]; then

    echo "WARNING: EVDI kernel module is already running." >&2
	
	if [ -d $COREDIR ]; then
	  echo "Uninstall all other versions of $PRODUCT before attempting to install." >&2
	if [ -d $OTHERPDDIR ]; then
		echo "WARNING: There are other products in the system using EVDI." >&2
		echo "Removing old EVDI from kernel tree, DKMS, and removing sources."
		echo "SMI USB Display will re-install new EVDI."
	else
		echo "Please reboot before attempting to re-install $PRODUCT." >&2
		echo "Installation terminated." >&2
		exit 1	
	fi
  fi
  fi
}

if [ "$(id -u)" != "0" ]; then
  echo "You need to be root to use this script." >&2
  exit 1
fi

echo "$PRODUCT $VERSION install script called: $*"
[ -z "$SYSTEMINITDAEMON" ] && detect_init_daemon || echo "Trying to use the forced init system: $SYSTEMINITDAEMON"
detect_distro

while [ -n "$1" ]; do
  case "$1" in
    install)
      ACTION="install"
      ;;

    uninstall)
      ACTION="uninstall"
      ;;
    *)
      usage
      ;;
  esac
  shift
done

if [ "$ACTION" == "install" ]; then
  install_dependencies
  check_requirements
  check_preconditions
  uninstall_older_version
  install_with_standalone_installer
elif [ "$ACTION" == "uninstall" ]; then
  uninstall
fi

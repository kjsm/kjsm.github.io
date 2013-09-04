#/bin/sh

set -e

main()
{
  if [ ! -f $HOME/.shutils ]; then
    wget -O .shutils http://kjsm.github.io/debian/shutils
  fi
  . $HOME/.shutils

  if [ -z "$HOST_ADDRESS" ]; then
    echo "not given HOST_ADDRESS"
    exit 1
  fi

  if [ -z "$USERNAME" ]; then
    echo "not given USERNAME"
    exit 1
  fi

  setup_packages
  setup_network
  setup_sudo
  setup_system
  disable_ipv6
  setup_virtualbox_guest_additions
}

setup_packages()
{
  for package in nfs-common rpcbind at
  do
    installed $package && uninstall $package
  done

  for package in ssh sudo build-essential
  do
    installed $package || install $package
  done

  if [ "$SETUP_PACKAGES_ONLY" ]; then
    exit 0
  fi
}

setup_network()
{
  if ! match "$HOST_ADDRESS" /etc/network/interfaces; then
    cp /etc/network/interfaces /etc/network/interfaces.orig
    cat > /etc/network/interfaces <<__END__
# The loopback network interface
auto lo
iface lo inet loopback

# The primary network interface (VirtualBox NAT adapter)
auto eth0
allow-hotplug eth0
iface eth0 inet dhcp

# The secondary network interface (VirtualBox Host-Only adapter)
auto eth1
allow-hotplug eth1
iface eth1 inet static
address $HOST_ADDRESS
netmask 255.255.255.0
__END__
    /etc/init.d/networking stop && /etc/init.d/networking start
    success "setup network"
  fi
}

setup_sudo()
{
  if ! match "$USERNAME" /etc/sudoers; then
    chmod 600 /etc/sudoers
    cat >> /etc/sudoers <<__END__
root ALL=(ALL) NOPASSWD: ALL
$USERNAME ALL=(ALL) NOPASSWD: ALL
__END__
    chmod 440 /etc/sudoers
    success "setup sudo"
  fi
}

setup_system()
{
  # disable unnecessary consoles
  if match '^[2-6]:23:' /etc/inittab; then
    sed -i.orig -e 's/^\([2-6]\):23:\(.\+\)/#\1:23:\2/g' /etc/inittab
    success "disable unnecessary consoles"
  fi

  # add this host
  if ! match "$HOST_ADDRESS" /etc/hosts; then
    sed -i.orig -e "1i$HOST_ADDRESS\t`uname -n`" /etc/hosts
    success "add this host"
  fi

  # enable cron logging
  if match '^#cron\.\*' /etc/rsyslog.conf; then
    sed -i.orig -e 's/^#cron\.\*/cron.*/g' /etc/rsyslog.conf
    success "enable cron logging"
  fi
}

disable_ipv6()
{
  # disable ipv6 hosts
  if match '^\(::\|[0-9a-f]\{4\}::\)' /etc/hosts; then
    sed -i.orig -e 's/^\(::\|[0-9a-f]\{4\}::\)\(.\+\)/#\1\2/g' /etc/hosts
    /etc/init.d/networking stop && /etc/init.d/networking start
    success "disable ipv6 hosts"
  fi

  # disable ipv6 mail
  if match "^dc_local_interfaces='127.0.0.1 ; ::1'" /etc/exim4/update-exim4.conf.conf; then
    sed -i.orig -e "s/^dc_local_interfaces=\(.\+\)/dc_local_interfaces='127.0.0.1'/" /etc/exim4/update-exim4.conf.conf
    /etc/init.d/exim4 reload
    success "disable ipv6 mail"
  fi

  # disable ipv6 ssh
  if match '^#ListenAddress 0.0.0.0' /etc/ssh/sshd_config; then
    sed -i.orig -e 's/^#ListenAddress 0.0.0.0$/ListenAddress 0.0.0.0/' /etc/ssh/sshd_config
    /etc/init.d/ssh reload
    success "disable ipv6 ssh"
  fi

  # disable ipv6 network
  if [ ! -f /etc/sysctl.d/ipv6.conf ]; then
    echo "net.ipv6.conf.all.disable_ipv6 = 1" > /etc/sysctl.d/ipv6.conf
    success "disable ipv6 network"
  fi
}

setup_virtualbox_guest_additions()
{
  if ask "Install virtualbox guest additions ?"; then
    notice "Please mount guest additions cd-rom (Devices > Install Guest Additions)"
    enter

    if installed virtualbox-guest-utils; then
      uninstall virtualbox-guest-utils
      apt-get -qq autoremove
    fi

    installed module-assistant || install module-assistant
    m-a prepare

    mount -r /media/cdrom
    sh /media/cdrom/VBoxLinuxAdditions.run
    umount /media/cdrom

    # patch for virtualbox 4.2.4 (https://www.virtualbox.org/ticket/11634)
    if [ -f /opt/VBoxGuestAdditions-4.2.4/src/vboxguest-4.2.4/vboxvideo/vboxvideo_drm.c ]; then
      patch -d /opt/VBoxGuestAdditions-4.2.4/src/vboxguest-4.2.4/vboxvideo -u <<__END__
--- a/trunk/src/VBox/Additions/linux/drm/vboxvideo_drm.c
+++ b/trunk/src/VBox/Additions/linux/drm/vboxvideo_drm.c
@@ -80,4 +80,12 @@
 #include "vboxvideo_drm.h"

+# ifndef RHEL_RELEASE_CODE
+#  if LINUX_VERSION_CODE >= KERNEL_VERSION(3, 2, 39) && LINUX_VERSION_CODE < KERNEL_VERSION(3, 3, 0)
+#   ifdef DRM_SWITCH_POWER_ON
+#    define DRM_DEBIAN_34ON32
+#   endif
+#  endif
+# endif
+
 static struct pci_device_id pciidlist[] = {
         vboxvideo_PCI_IDS
@@ -92,5 +100,5 @@
 #endif
 }
-#if LINUX_VERSION_CODE >= KERNEL_VERSION(3, 3, 0) || defined(DRM_RHEL63)
+#if LINUX_VERSION_CODE >= KERNEL_VERSION(3, 3, 0) || defined(DRM_RHEL63) || defined(DRM_DEBIAN_34ON32)
 /* since linux-3.3.0-rc1 drm_driver::fops is pointer */
 static struct file_operations driver_fops =
@@ -118,5 +126,5 @@
     .get_reg_ofs = drm_core_get_reg_ofs,
 #endif
-# if LINUX_VERSION_CODE < KERNEL_VERSION(3, 3, 0) && !defined(DRM_RHEL63)
+# if LINUX_VERSION_CODE < KERNEL_VERSION(3, 3, 0) && !defined(DRM_RHEL63) && !defined(DRM_DEBIAN_34ON32)
     .fops =
     {
@@ -135,5 +143,5 @@
         .fasync = drm_fasync,
     },
-#else /* LINUX_VERSION_CODE >= KERNEL_VERSION(3, 3, 0) || defined(DRM_RHEL63) */
+#else /* LINUX_VERSION_CODE >= KERNEL_VERSION(3, 3, 0) || defined(DRM_RHEL63) || defined(DRM_DEBIAN_34ON32) */
     .fops = &driver_fops,
 #endif
__END__
      success "patch vboxvideo_drm.c"

      /etc/init.d/vboxadd setup
    fi

    success "setup virtualbox guest additions"
  fi
}

help()
{
  echo "Usage: `basename $0` [-u USERNAME] [-a HOST_ADDRESS] [-p]"
}

while getopts "pa:u:" flag; do
  case $flag in
    p) SETUP_PACKAGES_ONLY=1;;
    a) HOST_ADDRESS="$OPTARG";;
    u) USERNAME="$OPTARG";;
    *) help; exit 1;;
  esac
done

main


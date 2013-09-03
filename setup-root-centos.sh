#/bin/sh

set -e

main()
{
  if [ -z "$HOST_ADDRESS" ]; then
    echo "not given HOST_ADDRESS"
    exit 1
  fi

  if [ -z "$USERNAME" ]; then
    echo "not given USERNAME"
    exit 1
  fi

  setup_user
  setup_sudo
  setup_system
  setup_repositories
  setup_virtualbox_guest_additions
}

setup_user()
{
  if [ ! -d /home/$USERNAME ]; then
    useradd $USERNAME
    echo $USERNAME | passwd --stdin $USERNAME
    success "create user ($USERNAME)"

    if not_match '^root: ' /etc/aliases; then
      echo "root: $USERNAME" >> /etc/aliases
      newaliases
      success "add aliases root to $USERNAME"
    fi
  fi
}

setup_sudo()
{
  if not_match "$USERNAME" /etc/sudoers; then
    chmod 600 /etc/sudoers
    echo -e "\nroot ALL=(ALL) NOPASSWD: ALL\n$USERNAME ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
    chmod 440 /etc/sudoers
    success "setup sudo"
  fi
}

setup_system()
{
  # disable unnecessary consoles
  if match '^ACTIVE_CONSOLES=/dev/tty\[1-6\]' /etc/sysconfig/init; then
    sed -i.orig -e 's/^\(ACTIVE_CONSOLES\)=.\+/\1=\/dev\/tty1/' /etc/sysconfig/init
    success "disable unnecessary consoles"
  fi

  # setup hosts file
  if not_match "$HOST_ADDRESS" /etc/hosts; then
    cp /etc/hosts /etc/hosts.orig
    cat > /etc/hosts <<__END__
$HOST_ADDRESS	`uname -n`
127.0.0.1	localhost
__END__
    success "setup hosts file"
  fi
}

setup_repositories()
{
  if [ ! -f /etc/yum.repos.d/rpmforge.repo ]; then
    curl -sL http://pkgs.repoforge.org/rpmforge-release/rpmforge-release-0.5.3-1.el6.rf.i686.rpm -o rpmforge.rpm && rpm -Uv rpmforge.rpm && rm rpmforge.rpm
    sed -i -e "s/enabled = 1/enabled = 0/g" /etc/yum.repos.d/rpmforge.repo
    success "setup rpmforge repository"
  fi

  if [ ! -f /etc/yum.repos.d/epel.repo ]; then
    curl -sL http://dl.fedoraproject.org/pub/epel/6/i386/epel-release-6-8.noarch.rpm -o epel.rpm && rpm -Uv epel.rpm && rm epel.rpm
    sed -i -e "s/enabled=1/enabled=0/g" /etc/yum.repos.d/epel.repo
    success "setup epel repository"
  fi
}

setup_virtualbox_guest_additions()
{
  if ask "Install virtualbox guest additions ?"; then
    local readonly install_kernel_devel="kernel-devel-`uname -r`"
    local input

    echo -e "Please mount guest additions cd-rom (Devices > Install Guest Additions)\n\n(Press enter to continue)"
    read input

    for package in $install_kernel_devel gcc make patch;
    do
      if not_installed $package; then
        install $package
      fi
    done

    mkdir -p /mnt/cdrom
    mount -r /dev/cdrom /mnt/cdrom
    sh /mnt/cdrom/VBoxLinuxAdditions.run
    umount /mnt/cdrom

    # patch for virtualbox 4.2.4 (https://www.virtualbox.org/ticket/11586)
    if [ -f /opt/VBoxGuestAdditions-4.2.4/src/vboxguest-4.2.4/vboxvideo/vboxvideo_drm.c ]; then
      patch -d /opt/VBoxGuestAdditions-4.2.4/src/vboxguest-4.2.4/vboxvideo -u <<__END__
--- vboxvideo_drm.c.orig  2013-09-02 12:52:10.102252738 +0900
+++ vboxvideo_drm.c 2013-09-02 12:53:02.877636281 +0900
@@ -107,7 +107,7 @@
     /* .driver_features = DRIVER_USE_MTRR, */
     .load = vboxvideo_driver_load,
 #if LINUX_VERSION_CODE < KERNEL_VERSION(3, 6, 0)
-    .reclaim_buffers = drm_core_reclaim_buffers,
+    //.reclaim_buffers = drm_core_reclaim_buffers,
 #endif
     /* As of Linux 2.6.37, always the internal functions are used. */
 #if LINUX_VERSION_CODE < KERNEL_VERSION(2, 6, 37) && !defined(DRM_RHEL61)
__END__
      success "patch vboxvideo_drm.c"

      /etc/init.d/vboxadd setup
    fi

    success "setup virtualbox guest additions"
  fi
}

match()
{
  local readonly expression="$1"
  local readonly path="$2"

  if [ -z "$expression" ]; then
    error "Not given expression"
    exit 1
  fi
  if [ -z "$path" ]; then
    error "Not given path"
    exit 1
  fi

  if cat $path | grep "$expression" > /dev/null; then
    return 0
  else
    return 1
  fi
}

not_match()
{
  if ! match "$1" "$2"; then
    return 0
  else
    return 1
  fi
}

install()
{
  local readonly package="$1"

  if [ -z "$package" ]; then
    error "Not given package name"
    exit 1
  fi

  yum -q -y install $package
  success "install $package"
}

installed()
{
  local package="$1"

  if [ -z "$package" ]; then
    error "Not given package name"
    exit 1
  fi

  if yum info $package 2>&1 | grep '^Installed Packages' > /dev/null; then
    return 0
  else
    return 1
  fi
}

not_installed()
{
  if ! installed "$1"; then
    return 0
  else
    return 1
  fi
}

ask()
{
  local input

  echo -n -e "\033[1;33m[ask] $1 (y/n)>\033[0m "
  read input

  if [ "$input" = "y" ]; then
    return 0
  else
    return 1
  fi
}

success()
{
  echo -e "\033[1;32m[success] $1\033[0m"
}

error()
{
  echo -e "\033[1;31m[error] $1\033[0m"
}

help()
{
  echo "Usage: `basename $0` [-u USERNAME] [-a HOST_ADDRESS]"
}

while getopts "u:a:" flag; do
  case $flag in
    u) USERNAME="$OPTARG";;
    a) HOST_ADDRESS="$OPTARG";;
    *) help; exit 1;;
  esac
done

main


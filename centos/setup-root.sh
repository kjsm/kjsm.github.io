#/bin/sh

set -e

# epel repository
readonly EPEL_RPM_URL="http://dl.fedoraproject.org/pub/epel/6/x86_64/epel-release-6-8.noarch.rpm"

# rpmforge repository
readonly RPMFORGE_RPM_URL="http://pkgs.repoforge.org/rpmforge-release/rpmforge-release-0.5.3-1.el6.rf.x86_64.rpm"

main()
{
  if [ ! -f $HOME/.shutils ]; then
    curl -o $HOME/.shutils -O http://kjsm.github.io/centos/shutils
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

    if ! match '^root: ' /etc/aliases; then
      echo "root: $USERNAME" >> /etc/aliases
      newaliases
      success "add aliases root to $USERNAME"
    fi
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
  if match '^ACTIVE_CONSOLES=/dev/tty\[1-6\]' /etc/sysconfig/init; then
    sed -i.orig -e 's/^\(ACTIVE_CONSOLES\)=.\+/\1=\/dev\/tty1/' /etc/sysconfig/init
    success "disable unnecessary consoles"
  fi

  # setup hosts file
  if ! match "$HOST_ADDRESS" /etc/hosts; then
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
  if [ ! -f /etc/yum.repos.d/epel.repo ]; then
    curl -sL $EPEL_RPM_URL -o epel.rpm && rpm -Uv epel.rpm && rm epel.rpm
    sed -i -e "s/enabled=1/enabled=0/g" /etc/yum.repos.d/epel.repo
    success "setup epel repository"
  fi

  if [ ! -f /etc/yum.repos.d/rpmforge.repo ]; then
    curl -sL $RPMFORGE_RPM_URL -o rpmforge.rpm && rpm -Uv rpmforge.rpm && rm rpmforge.rpm
    sed -i -e "s/enabled = 1/enabled = 0/g" /etc/yum.repos.d/rpmforge.repo
    success "setup rpmforge repository"
  fi
}

setup_virtualbox_guest_additions()
{
  if ask "Install virtualbox guest additions ?"; then
    local readonly install_kernel_devel="kernel-devel-`uname -r`"

    notice "Please mount guest additions cd-rom (Devices > Install Guest Additions)"
    enter

    for package in $install_kernel_devel gcc make patch perl
    do
      installed $package || install $package
    done

    mkdir -p /mnt/cdrom
    mount -r /dev/cdrom /mnt/cdrom
    sh /mnt/cdrom/VBoxLinuxAdditions.run
    umount /mnt/cdrom

    success "setup virtualbox guest additions"
  fi
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


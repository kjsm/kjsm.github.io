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
    error "not given HOST_ADDRESS (-a)"
    exit 1
  fi

  if [ -z "$USERNAME" ]; then
    error "not given USERNAME (-u)"
    exit 1
  fi

  install_virtualbox_guest_additions

  disable_firewall
  disable_selinux
  add_user_of_administrator
  add_root_alias
  create_wheel_group_sudoers
  add_users_to_wheel_group
  add_hostname_to_hosts
  add_repositories
  add_essential_packages
}

install_virtualbox_guest_additions()
{
  if [ "$INSTALL_VIRTUALBOX_GUEST_ADDITIONS" = "1" ]; then
    if [ ! -f /usr/sbin/VBoxService ]; then
      local readonly kernel_devel="kernel-devel-`uname -r`"

      notice "Install: Virtualbox guest additions"
      notice "Please mount guest additions cd-rom (Devices > Install Guest Additions)"
      enter

      for package in $kernel_devel gcc make patch perl; do install $package; done

      mkdir -p /mnt/cdrom
      mount -r /dev/cdrom /mnt/cdrom
      sh /mnt/cdrom/VBoxLinuxAdditions.run
      umount /mnt/cdrom

      success "Installed: Virtualbox guest additions"
    else
      skip "Already installed: Virtualbox guest additions"
    fi
  fi
}

disable_firewall()
{
  for service_name in iptables ip6tables
  do
    if service $service_name status > /dev/null; then
      notice "Stop service: $service_name"

      service $service_name stop > /dev/null

      success "Stopped service: $service_name"
    else
      skip "Already stopped service: $service_name"
    fi

    if chkconfig --list $service_name | grep ':on' > /dev/null; then
      notice "Disable service: $service_name"

      chkconfig $service_name off

      success "Disabled service: $service_name"
    else
      skip "Already disabled service: $service_name"
    fi
  done
}

disable_selinux()
{
  if [ "$(getenforce)" = "Enforcing" ]; then
    notice "Stop: selinux"

    setenforce 0

    success "Stopped: selinux"
  else
    skip "Already stopped: selinux"
  fi

  if match '^SELINUX=enforcing$' /etc/selinux/config; then
    notice "Disable: selinux"

    sed -i -e "s/^SELINUX=enforcing$/SELINUX=disabled/g" /etc/selinux/config

    success "Disabled: selinux"
  else
    skip "Already disabled: selinux"
  fi
}

add_user_of_administrator()
{
  if [ ! -d /home/$USERNAME ]; then
    notice "Add user: $USERNAME"

    useradd $USERNAME
    echo $USERNAME | passwd --stdin $USERNAME

    success "Added user: $USERNAME"
  else
    skip "Already exists: $USERNAME"
  fi
}

add_root_alias()
{
  if ! match "^root:.\+$USERNAME" /etc/aliases; then
    notice "Add alias: root > $USERNAME"

    echo "root: $USERNAME" >> /etc/aliases
    newaliases

    success "Added alias: root > $USERNAME"
  else
    skip "Already alias: root > $USERNAME"
  fi
}

create_wheel_group_sudoers()
{
  local readonly sudoers_dir="/etc/sudoers.d"
  local readonly sudoers_wheel_file="$sudoers_dir/10_wheel_group"

  if [ ! -f $sudoers_wheel_file ]; then
    notice "Create file: $sudoers_wheel_file"

    mkdir -p $sudoers_dir
    chmod 750 $sudoers_dir
    cat >> $sudoers_wheel_file <<__END__
%wheel ALL=(ALL) NOPASSWD: ALL
__END__
    chmod 440 $sudoers_wheel_file

    success "Created file: $sudoers_wheel_file"
  else
    skip "Already exists: $sudoers_wheel_file"
  fi
}

add_users_to_wheel_group()
{
  for user in root $USERNAME
  do
    if ! match "^wheel:.\+$user" /etc/group; then
      notice "Add to wheel group: $user"

      gpasswd -a $user wheel

      success "Added to wheel group: $user"
    else
      skip "Already added to wheel group: $user"
    fi
  done
}

add_hostname_to_hosts()
{
  if ! match "$HOST_ADDRESS" /etc/hosts; then
    notice "Add hosts: $(uname -n) ($HOST_ADDRESS)"

    cat >> /etc/hosts <<__END__
$HOST_ADDRESS	`uname -n`
__END__

    success "Added hosts: $(uname -n) ($HOST_ADDRESS)"
  else
    skip "Already added: $(uname -n) ($HOST_ADDRESS)"
  fi
}

add_repositories()
{
  if [ ! -f /etc/yum.repos.d/epel.repo ]; then
    notice "Add repository: epel"

    yum install -y -q $EPEL_RPM_URL
    sed -i -e "s/enabled\(\s*\)=\(\s*\)1/enabled\1=\20/g" /etc/yum.repos.d/epel.repo

    success "Added repository: epel"
  else
    skip "Already added repository: epel"
  fi

  if [ ! -f /etc/yum.repos.d/rpmforge.repo ]; then
    notice "Add repository: rpmforge"

    yum install -y -q $RPMFORGE_RPM_URL
    sed -i -e "s/enabled\(\s*\)=\(\s*\)1/enabled\1=\20/g" /etc/yum.repos.d/rpmforge.repo

    success "Added repository: rpmforge"
  else
    skip "Already added repository: rpmforge"
  fi
}

add_essential_packages()
{
  # Install git 1.7.12 (with subversion 1.7.4) from rpmforge-extras
  # CentOS base repository git version is 1.7.1 (gitlab requires git 1.7.10 newer)
  install git --enablerepo=rpmforge-extras

  # Install from rpmforge
  for package in tmux tig keychain
  do
    install $package --enablerepo=rpmforge
  done

  # Install from CentOS base repository
  for package in \
    wget zsh vim-enhanced zip unzip \
    gcc gcc-c++ make autoconf automake patch \
    zlib-devel openssl-devel readline-devel sqlite-devel
  do
    install $package
  done
}

help()
{
  echo "Usage: `basename $0` [-a HOST_ADDRESS] [-u USERNAME]"
}

while getopts "u:a:v" flag; do
  case $flag in
    a) HOST_ADDRESS="$OPTARG";;
    u) USERNAME="$OPTARG";;
    v) INSTALL_VIRTUALBOX_GUEST_ADDITIONS="1";;
    *) help; exit 1;;
  esac
done

main


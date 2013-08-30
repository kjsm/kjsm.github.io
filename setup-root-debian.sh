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

  setup_network
  setup_misc
  setup_ssh
  setup_sudo
  setup_packages
}

setup_network()
{
  if not_match "$HOST_ADDRESS" /etc/network/interfaces; then
    cp /etc/network/interfaces /etc/network/interfaces.orig
    cat > "/etc/network/interfaces" <<'__END__'
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

setup_misc()
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

  # disable ipv6 network
  if [ ! -f /etc/sysctl.d/ipv6.conf ]; then
    echo "net.ipv6.conf.all.disable_ipv6 = 1" > /etc/sysctl.d/ipv6.conf
    success "disable ipv6 network"
  fi

  # disable unnecessary consoles
  if match '^[2-6]:23:' /etc/inittab; then
    sed -i.orig -e 's/^\([2-6]\):23:\(.\+\)/#\1:23:\2/g' /etc/inittab
    success "disable unnecessary consoles"
  fi

  # enable cron logging
  if match '^#cron\.\*' /etc/rsyslog.conf; then
    sed -i.orig -e 's/^#cron\.\*/cron.*/g' /etc/rsyslog.conf
    success "enable cron logging"
  fi

  # add this host
  if not_match "$HOST_ADDRESS" /etc/hosts; then
    sed -i.orig -e "1i$HOST_ADDRESS\t`uname -n`" /etc/hosts
    success "add this host"
  fi

  # disable deb-src apt-line
  if match '^deb-src ' /etc/apt/sources.list; then
    sed -i.orig -e 's/^deb-src \(.\+\)/#deb-src \1/g' /etc/apt/sources.list
    success "disable deb-src apt-line"
  fi

  # add backports to apt-line
  if not_match 'wheezy-backports' /etc/apt/sources.list; then
    cp /etc/apt/sources.list /etc/apt/sources.list.orig
    echo "\n# backports\ndeb http://ftp.debian.org/debian/ wheezy-backports main contrib non-free" >> /etc/apt/sources.list
    apt-get update
    success "add backports to apt-line"
  fi
}

setup_ssh()
{
  if not_installed ssh; then
    apt-get -qq install ssh
    success "install ssh"
  fi

  # disable ipv6 ssh
  if match '^#ListenAddress 0.0.0.0' /etc/ssh/sshd_config; then
    sed -i.orig -e 's/^#ListenAddress 0.0.0.0$/ListenAddress 0.0.0.0/' /etc/ssh/sshd_config
    /etc/init.d/ssh reload
    success "disable ipv6 ssh"
  fi
}

setup_sudo()
{
  if not_installed sudo; then
    apt-get -qq install sudo
    success "install sudo"
  fi

  if not_match "$USERNAME" /etc/sudoers; then
    chmod 600 /etc/sudoers
    cp /etc/sudoers /etc/sudoers.orig
    echo "\nroot ALL=(ALL) NOPASSWD: ALL\n$USERNAME ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
    chmod 440 /etc/sudoers
    success "setup sudo"
  fi
}

setup_packages()
{
  # purge unnecessary packages
  for package in nfs-common rpcbind at;
  do
    if installed $package; then
      apt-get -qq purge $package
      success "purge $package"
    fi
  done

  # install essential packages
  for package in curl git tig vim zsh tmux keychain zip unzip build-essential;
  do
    if not_installed $package; then
      apt-get -qq install $package
      success "install $package"
    fi
  done
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

installed()
{
  local package="$1"

  if [ -z "$package" ]; then
    error "Not given package name"
    exit 1
  fi

  if dpkg -s $package 2>&1 | grep '^Status: install' > /dev/null; then
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

success()
{
  echo "[success] $1"
}

error()
{
  echo "[error] $1"
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


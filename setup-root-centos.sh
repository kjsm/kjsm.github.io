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
  setup_misc
  setup_sudo
  setup_packages
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

setup_misc()
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

setup_sudo()
{
  if not_match "$USERNAME" /etc/sudoers; then
    chmod 600 /etc/sudoers
    echo -e "\nroot ALL=(ALL) NOPASSWD: ALL\n$USERNAME ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
    chmod 440 /etc/sudoers
    success "setup sudo"
  fi
}

setup_packages()
{
  if [ ! -f /etc/yum.repos.d/rpmforge.repo ]; then
    curl -sL http://pkgs.repoforge.org/rpmforge-release/rpmforge-release-0.5.3-1.el6.rf.i686.rpm -o rpmforge.rpm && rpm -Uv rpmforge.rpm && rm rpmforge.rpm
    sed -i -e "s/enabled = 1/enabled = 0/g" /etc/yum.repos.d/rpmforge.repo
    success "add rpmforge repository"
  fi

  if [ ! -f /etc/yum.repos.d/epel.repo ]; then
    curl -sL http://dl.fedoraproject.org/pub/epel/6/i386/epel-release-6-8.noarch.rpm -o epel.rpm && rpm -Uv epel.rpm && rm epel.rpm
    sed -i -e "s/enabled=1/enabled=0/g" /etc/yum.repos.d/epel.repo
    success "add epel repository"
  fi

  for package in wget git zsh vim zip unzip;
  do
    if not_installed $package; then
      yum -y install $package
      success "install $package"
    fi
  done

  for package in keychain tig tmux;
  do
    if not_installed $package; then
      yum -y --enablerepo=rpmforge install $package
      success "install $package"
    fi
  done

  if ask "Update packages immediately ?"; then
    yum -y update
    success "update packages"
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

  echo -n "[ask] $1 (y/n)> "
  read input

  if [ "$input" = "y" ]; then
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


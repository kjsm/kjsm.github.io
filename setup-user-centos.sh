#/bin/sh

set -e

main()
{
  local readonly install_ruby_version="2.0.0-p247"

  setup_packages
  setup_ssh_keys
  setup_dotfiles
  setup_mysql
  setup_nginx
  setup_rbenv
  setup_ruby $install_ruby_version
}

setup_packages()
{
  for package in keychain tig tmux;
  do
    if not_installed $package; then
      install $package "--enablerepo=rpmforge"
    fi
  done

  for package in wget git zsh vim-enhanced zip unzip \
    gcc gcc-c++ make autoconf automake patch \
    zlib-devel openssl-devel readline-devel mysql-devel sqlite-devel;
  do
    if not_installed $package; then
      install $package
    fi
  done
}

setup_ssh_keys()
{
  local readonly ssh_dir="$HOME/.ssh"
  local readonly private_key_path="$ssh_dir/id_rsa"
  local readonly public_key_path="$ssh_dir/id_rsa.pub"
  local readonly authorized_keys_path="$ssh_dir/authorized_keys"
  local host_os_public_key

  # generate ssh key
  if [ ! -f $private_key_path ]; then
    ssh-keygen -t rsa -f $private_key_path -N "" -C "$USER@`uname -n`"
    success "generate ssh key"
  fi

  # create authorized_keys file
  if [ ! -f $authorized_keys_path ]; then
    mkdir -p $ssh_dir
    cat $public_key_path >> $authorized_keys_path
    chmod 600 $authorized_keys_path
    success "create authorized_keys file"

    # add host os public key
    input "Input host os public key"
    read host_os_public_key

    if [ -n "$host_os_public_key" ]; then
      echo "$host_os_public_key" >> $authorized_keys_path
      success "add host os public key"
    fi
  fi
}

setup_dotfiles()
{
  local readonly dotfiles_dir="$HOME/.dotfiles"
  local dotfiles_repository

  if [ ! -d $dotfiles_dir ]; then
    notice "Please register the public key to your repository hosting site"
    echo
    cat $HOME/.ssh/id_rsa.pub
    echo
    enter

    input "Input the dotfiles repository location"
    read dotfiles_repository

    if [ -z "$dotfiles_repository" ]; then
      echo "not given dotfiles repository location"
      exit 1
    fi

    if ! git clone $dotfiles_repository $dotfiles_dir; then
      error "failed clone repository"
      exit 1
    fi

    # git submodule init and update (vim plugins)
    cd $dotfiles_dir
    git submodule init
    git submodule update
    cd
    success "setup vim plugins"

    # create symlinks for dotfiles
    $dotfiles_dir/script/dotfiles_linker.sh link
    success "create symlinks for dotfiles"

    # create .gitconfig.local
    if [ ! -f $HOME/.gitconfig.local ]; then
      cat > $HOME/.gitconfig.local <<__END__
[user]
  name = $USER
  email = $USER@`uname -n`
__END__
      success "create .gitconfig.local"
    fi

    # change shell to zsh
    if [ `basename $SHELL` != "zsh" ]; then
      sudo sed -i -e "s/^\($USER:.\+\):.\+/\1:\/bin\/zsh/" /etc/passwd
      success "change default shell to zsh"
    fi

    notice "Please login again, and check keychain, zsh, tmux, and vim"
    exit 0
  fi
}

setup_mysql()
{
  if installed mysql-server || ! ask "Install mysql ?"; then
    return 0
  fi

  if not_installed mysql-server; then
    install mysql-server

    sudo cp /etc/my.cnf /etc/my.cnf.orig
    sudo sh -c "curl http://kjsm.github.io/mysql-5.5.cnf > /etc/my.cnf"
    sudo service mysqld start
    sudo chkconfig mysqld on

    # mysql_secure_installation
    #mysqladmin -u root password $new_password
    mysql -u root -e "DELETE FROM mysql.user WHERE User='';"
    mysql -u root -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
    mysql -u root -e "DROP DATABASE test;"
    mysql -u root -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
    mysql -u root -e "FLUSH PRIVILEGES;"

    success "setup mysql"
  fi

  if [ ! -f $HOME/.my.cnf ]; then
    echo -e "[client]\nuser=root" > $HOME/.my.cnf && chmod 600 $HOME/.my.cnf
    success "setup ~/.my.cnf"
  fi
}

setup_nginx()
{
  if installed nginx || ! ask "Install nginx ?"; then
    return 0
  fi

  if not_installed nginx; then
    sudo rpm -iv http://nginx.org/packages/centos/6/noarch/RPMS/nginx-release-centos-6-0.el6.ngx.noarch.rpm
    sudo sed -i -e "s/enabled=1/enabled=0/g" /etc/yum.repos.d/nginx.repo
    sudo yum -y -q --enablerepo=nginx install nginx
    sudo service nginx start
    sudo chkconfig nginx on
    success "install nginx"
  fi
}

setup_rbenv()
{
  local readonly rbenv_dir="$HOME/.rbenv"
  local readonly rbenv_plugins_dir="$HOME/.rbenv/plugins"

  if [ -d $rbenv_dir ] || ! ask "Install rbenv ?"; then
    return 0
  fi

  if [ ! -d $rbenv_dir ]; then
    git clone git://github.com/sstephenson/rbenv.git $rbenv_dir
    mkdir $rbenv_plugins_dir
    success "install rbenv"
  fi

  if [ ! -d $rbenv_plugins_dir/ruby-build ]; then
    git clone git://github.com/sstephenson/ruby-build.git $rbenv_plugins_dir/ruby-build
    success "install ruby-build"
  fi

  if [ ! -d $rbenv_plugins_dir/rbenv-gemset ]; then
    git clone git://github.com/jamis/rbenv-gemset.git $rbenv_plugins_dir/rbenv-gemset
    success "install rbenv-gemset"
  fi
}

setup_ruby()
{
  local readonly version="$1"

  if [ -z "$version" ]; then
    error "not given ruby version"
    exit 1
  fi

  if [ -d $HOME/.rbenv/versions/$version ] || ! ask "Install ruby $version by rbenv ?"; then
    return 0
  fi

  if [ ! -d $HOME/.rbenv ]; then
    error "not installed rbenv"
    exit 1
  fi

  if [ ! -d $HOME/.rbenv/versions/$version ]; then
    export PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH"
    rbenv install $version
    rbenv rehash
    rbenv global $version
    success "install ruby $version (rbenv)"
  fi
}

install()
{
  local readonly package="$1"
  local readonly options="$2"

  if [ -z "$package" ]; then
    error "Not given package name"
    exit 1
  fi

  sudo yum -y $options install $package
  success "install $package"
}

installed()
{
  local readonly package="$1"

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

input()
{
  echo -e "\033[1;33m[input] $1:\033[0m"
}

enter()
{
  local input

  echo -e -n "\033[1;33m(Press enter to continue)\033[0m"
  read input
}

notice()
{
  echo -e "\033[1;36m[notice] $1\033[0m"
}

success()
{
  echo -e "\033[1;32m[success] $1\033[0m"
}

error()
{
  echo -e "\033[1;31m[error] $1\033[0m"
}

main


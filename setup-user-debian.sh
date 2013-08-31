#/bin/sh

set -e

main()
{
  local readonly install_node_version="0.10.17"
  local readonly install_ruby_version="2.0.0-p247"

  setup_ssh_keys
  setup_dotfiles
  setup_packages
  setup_mysql
  setup_nginx
  setup_nvm
  setup_node $install_node_version
  setup_rbenv
  setup_ruby $install_ruby_version
}

setup_ssh_keys()
{
  local readonly ssh_dir="$HOME/.ssh"
  local readonly private_key_path="$ssh_dir/id_rsa"
  local readonly public_key_path="$ssh_dir/id_rsa.pub"
  local readonly authorized_keys_path="$ssh_dir/authorized_keys"

  if [ ! -d $ssh_dir ]; then
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

      # add public key of host os
      if ask "Add public key of host os to authorized_keys ?"; then
        echo "Input public key of host os\n"

        local input
        read input

        if [ -n "$input" ]; then
          echo "$input" >> $authorized_keys_path
          success "add public key of host os"
        fi
      fi
    fi

    echo "\nregister the public key to your repository hosting site\n"
    exit 0
  fi
}

setup_dotfiles()
{
  local readonly dotfiles_dir="$HOME/.dotfiles"

  if [ ! -d $dotfiles_dir ]; then
    if [ -z "$DOTFILES_REPOSITORY" ]; then
      echo "not given DOTFILES_REPOSITORY"
      exit 1
    fi

    if ! git clone $DOTFILES_REPOSITORY $dotfiles_dir; then
      error "failed clone repository"
      exit 0
    fi

    # git submodule init and update (vim plugins)
    cd $dotfiles_dir
    git submodule init
    git submodule update
    cd

    $dotfiles_dir/script/dotfiles_linker.sh link
    success "setup dotfiles"

    if [ `basename $SHELL` != "zsh" ]; then
      sudo sed -i -e "s/^\($USER:.\+\):.\+/\1:\/usr\/bin\/zsh/" /etc/passwd
      success "change default shell to zsh"
    fi
  fi
}

setup_packages()
{
  for package in zlib1g-dev libssl-dev libreadline-dev libmysqlclient-dev libsqlite3-dev libxml2-dev libxslt1-dev;
  do
    if not_installed $package; then
      sudo apt-get -qq install $package
      success "install $package"
    fi
  done
}

setup_mysql()
{
  if not_installed mysql-server; then
    sudo DEBIAN_FRONTEND=noninteractive apt-get -qq install mysql-server
    success "install mysql"
  fi

  if [ ! -f /etc/mysql/conf.d/character-set.cnf ]; then
    sudo sh -c "cat > /etc/mysql/conf.d/character-set.cnf <<'__END__'
[mysql]
default-character-set = utf8

[mysqld]
character-set-server = utf8
__END__"
    sudo /etc/init.d/mysql restart
    success "setup mysql"
  fi

  if [ ! -f $HOME/.my.cnf ]; then
    echo "[client]\nuser=root" > $HOME/.my.cnf && chmod 600 $HOME/.my.cnf
    success "setup local .my.cnf"
  fi
}

setup_nginx()
{
  if not_installed nginx; then
    sudo apt-get -qq install nginx
    success "install nginx"
  fi

  if ! sudo /etc/init.d/nginx status > /dev/null 2>&1; then
    sudo /etc/init.d/nginx start
    success "start nginx"
  fi
}

setup_nvm()
{
  if [ ! -d $HOME/.nvm ]; then
    git clone git://github.com/creationix/nvm.git ~/.nvm
    success "setup nvm"
  fi
}

setup_node()
{
  local readonly version="$1"

  if [ ! -d $HOME/.nvm ]; then
    error "not installed nvm"
    exit 1
  fi

  if [ -z "$version" ]; then
    error "not given node version"
    exit 1
  fi

  if [ ! -d $HOME/.nvm/$version ]; then
    bash -c "source $HOME/.nvm/nvm.sh && nvm install $version && nvm use $version && nvm alias default $version"
    success "install node $version (nvm)"
  fi
}

setup_rbenv()
{
  local readonly rbenv_dir="$HOME/.rbenv"
  local readonly rbenv_plugins_dir="$HOME/.rbenv/plugins"

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

  if [ ! -d $HOME/.rbenv ]; then
    error "not installed rbenv"
    exit 1
  fi

  if [ -z "$version" ]; then
    error "not given ruby version"
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

ask()
{
  local input

  echo -n "\033[1;33m[ask] $1 (yes/no)>\033[0m "
  read input

  if [ "$input" = "yes" ]; then
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
  echo "\033[1;32m[success] $1\033[0m"
}

error()
{
  echo "\033[1;31m[error] $1\033[0m"
}

help()
{
  echo "Usage: `basename $0` [-r DOTFILES_REPOSITORY]"
}

while getopts "r:" flag; do
  case $flag in
    r) DOTFILES_REPOSITORY="$OPTARG";;
    *) help; exit 1;;
  esac
done

main


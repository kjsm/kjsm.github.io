#/bin/sh

set -e

main()
{
  if [ ! -f $HOME/.shutils ]; then
    wget -O .shutils http://kjsm.github.io/debian/shutils
  fi
  . $HOME/.shutils

  local readonly install_node_version="0.10.17"
  local readonly install_ruby_version="2.0.0-p247"

  setup_packages
  setup_ssh_keys
  setup_dotfiles
  setup_mysql
  setup_nginx
  setup_nvm
  setup_node $install_node_version
  setup_rbenv
  setup_ruby $install_ruby_version
}

setup_packages()
{
  for package in \
    curl git tig vim zsh tmux keychain zip unzip build-essential \
    zlib1g-dev libssl-dev libreadline-dev libmysqlclient-dev libsqlite3-dev libxml2-dev libxslt1-dev
  do
    installed $package || install $package
  done

  if [ "$SETUP_PACKAGES_ONLY" ]; then
    exit 0
  fi
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
    cat $public_key_path > $authorized_keys_path
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

  if [ ! -d $dotfiles_dir ]; then
    notice "Please register the public key to your repository hosting site"
    echo "\n$(cat $HOME/.ssh/id_rsa.pub)\n"
    enter

    input "Input the dotfiles repository location"
    read dotfiles_repository
    if [ -z "$dotfiles_repository" ]; then
      error "Not given dotfiles repository location"
      exit 1
    fi

    if ! git clone $dotfiles_repository $dotfiles_dir; then
      error "Failed clone repository"
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
      sudo sed -i -e "s/^\($USER:.\+\):.\+/\1:\/usr\/bin\/zsh/" /etc/passwd
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

  if ! installed mysql-server; then
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
  if installed nginx || ! ask "Install nginx ?"; then
    return 0
  fi

  if ! installed nginx; then
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
  if [ -d $HOME/.nvm ] || ! ask "Install nvm ?"; then
    return 0
  fi

  if [ ! -d $HOME/.nvm ]; then
    git clone git://github.com/creationix/nvm.git ~/.nvm
    success "setup nvm"
  fi
}

setup_node()
{
  local readonly version="$1"

  if [ -z "$version" ]; then
    error "not given node version"
    exit 1
  fi

  if [ -d $HOME/.nvm/$version ] || ! ask "Install node $version by nvm ?"; then
    return 0
  fi

  if [ ! -d $HOME/.nvm ]; then
    error "not installed nvm"
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

help()
{
  echo "Usage: `basename $0` [-p]"
}

while getopts "p" flag; do
  case $flag in
    p) SETUP_PACKAGES_ONLY=1;;
    *) help; exit 1;;
  esac
done

main


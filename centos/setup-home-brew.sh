#/bin/sh

set -e

main()
{
  if [ ! -f $HOME/.shutils ]; then
    curl -o $HOME/.shutils -O http://kjsm.github.io/centos/shutils
  fi
  . $HOME/.shutils

  install_packages
  install_brew
  install_brew_packages

  setup_ssh_keys
  setup_dotfiles
}

install_packages()
{
  for package in wget zlib-devel openssl-devel readline-devel sqlite-devel
  do
    installed $package || install $package
  done

  # Install Git 1.7.12 by rpmforge-extras (centos base repository git version is 1.7.1)
  installed git || install git --enablerepo=rpmforge-extras
  installed tig || install tig --enablerepo=rpmforge
}

install_brew()
{
  if [ ! -d $HOME/.linuxbrew ]; then
    sudo yum -y groupinstall 'Development Tools'
    success "Install Development Tools"

    for package in git m4 ruby ruby-irb texinfo bzip2-devel curl-devel expat-devel ncurses-devel zlib-devel
    do
      installed $package || install $package
    done
    success "Install linuxbrew dependency packages"

    ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/linuxbrew/go/install)"
    success "Install linuxbrew"

    export PATH="$HOME/.linuxbrew/bin:$PATH"
    brew update
    success "brew update"

    brew_installed pkg-config || brew_install pkg-config
    brew_installed ncurses || brew_install homebrew/dupes/ncurses

    if brew doctor | grep "Your system is ready to brew" > /dev/null; then
      success "Ready to brew"
    else
      error "System is not ready (brew doctor)"
      exit 1
    fi
  fi
}

install_brew_packages()
{
  export PATH="$HOME/.linuxbrew/bin:$PATH"

  brew_installed perl || brew_install perl
  brew_installed vim || brew_install vim --override-system-vi
  brew_installed tmux || brew_install tmux
  brew_installed zsh || brew_install zsh
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
  local readonly brew_dir="$HOME/.linuxbrew"
  local dotfiles_repository

  if [ ! -d $dotfiles_dir ]; then
    notice "Please register the public key to your repository hosting site"
    echo -e "\n$(cat $HOME/.ssh/id_rsa.pub)\n"
    enter

    input "Input the dotfiles repository location"
    read dotfiles_repository
    if [ -z "$dotfiles_repository" ]; then
      error "not given dotfiles repository location"
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

    # create mysql config file for user
    if [ ! -f $HOME/.my.cnf ]; then
      echo -e "[client]\nuser=root" > $HOME/.my.cnf && chmod 600 $HOME/.my.cnf
      success "setup ~/.my.cnf"
    fi

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
    if [ `basename $SHELL` != "zsh" ] && [ -x $brew_dir/bin/zsh ]; then
      sudo sed -i -e "s/^\($USER:.\+\):.\+/\1:\/home\/$USER\/.linuxbrew\/bin\/zsh/" /etc/passwd
      success "change default shell to zsh"
    fi

    notice "Please login again, and check keychain, zsh, tmux, and vim"
    exit 0
  fi
}

main


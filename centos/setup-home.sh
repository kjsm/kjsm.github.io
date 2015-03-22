#/bin/sh

set -e

main()
{
  if [ ! -f $HOME/.shutils ]; then
    curl -o $HOME/.shutils -O http://kjsm.github.io/centos/shutils
  fi
  . $HOME/.shutils

  generate_ssh_key
  create_authorized_keys

  install_brew_and_brew_packages

  setup_dotfiles
  change_default_shell_to_zsh
  create_git_config_local
  create_mysql_config
}

generate_ssh_key()
{
  local readonly private_key_path="$HOME/.ssh/id_rsa"

  if [ ! -f $private_key_path ]; then
    notice "Generate: $private_key_path"
    ssh-keygen -t rsa -f $private_key_path -N "" -C "$USER@`uname -n`"
    success
  else
    skip "Already exists: $private_key_path"
  fi
}

create_authorized_keys()
{
  local readonly ssh_dir="$HOME/.ssh"
  local readonly public_key_path="$ssh_dir/id_rsa.pub"
  local readonly authorized_keys_path="$ssh_dir/authorized_keys"

  if [ ! -f $authorized_keys_path ]; then
    notice "Create: $authorized_keys_path"
    cat $public_key_path >> $authorized_keys_path
    chmod 600 $authorized_keys_path
    success

    notice "Please paste your host public key (if you want to register to authorized_keys)"
    local register_key
    read register_key
    if [ -n "$register_key" ]; then
      echo "$register_key" >> $authorized_keys_path
      success
    else
      skip "Not do anything"
    fi
  else
    skip "Already exists: $authorized_keys_path"
  fi
}

install_brew_and_brew_packages()
{
  if [ "$INSTALL_BREW_AND_BREW_PACKAGES" != "1" ]; then
    return 0
  fi
  
  if [ ! -d $HOME/.linuxbrew ]; then
    notice "Install: linuxbrew dependency packages"
    sudo yum -y groupinstall 'Development Tools'
    for package in m4 ruby ruby-irb texinfo bzip2-devel curl-devel expat-devel ncurses-devel
    do
      install $package
    done
    success

    notice "Install: linuxbrew"
    ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/linuxbrew/go/install)"
    success

    notice "Update: linuxbrew"
    export PATH="$HOME/.linuxbrew/bin:$PATH"
    brew update
    brew_installed pkg-config || brew_install pkg-config
    if brew doctor | grep "Your system is ready to brew" > /dev/null; then
      success
    else
      error "System is not ready (by brew doctor)"
      exit 1
    fi

    brew_installed ncurses || brew_install homebrew/dupes/ncurses
    brew_installed perl || brew_install perl
    brew_installed vim || brew_install vim --override-system-vi
    brew_installed tmux || brew_install tmux
    brew_installed zsh || brew_install zsh
  else
    skip "Already installed: linuxbrew"
  fi
}

setup_dotfiles()
{
  local readonly dotfiles_dir="$HOME/.dotfiles"

  if [ ! -d $dotfiles_dir ]; then
    notice "Please register the public key to your repository hosting site"
    echo -e "\n$(cat $HOME/.ssh/id_rsa.pub)\n"
    enter

    notice "Input the dotfiles repository location"
    local dotfiles_repository
    read dotfiles_repository
    if [ -z "$dotfiles_repository" ]; then
      error "not given dotfiles repository location"
      exit 1
    fi

    notice "Clone repository: $dotfiles_repository"
    if ! git clone $dotfiles_repository $dotfiles_dir; then
      error "failed clone repository"
      exit 1
    fi
    success
  else
    skip "Already cloned repository: $dotfiles_dir"
  fi

  if [ ! -d $HOME/.zsh ]; then
    notice "Initialize and update git submodules (vim plugins)"
    cd $dotfiles_dir
    git submodule init
    git submodule update
    cd
    success

    notice "Create symbolic links to all dotfiles"
    $dotfiles_dir/script/dotfiles_linker.sh link
    success
  else
    skip "Already initialized: $dotfiles_dir"
  fi
}

change_default_shell_to_zsh()
{
  if [ "$(basename $SHELL)" != "zsh" ]; then
    notice "Change default shell: zsh"
    if [ "$INSTALL_BREW_AND_BREW_PACKAGES" = "1" ] && [ -x $brew_dir/bin/zsh ]; then
      sudo sed -i -e "s/^\($USER:.\+\):.\+/\1:\/home\/$USER\/.linuxbrew\/bin\/zsh/" /etc/passwd
    else
      sudo sed -i -e "s/^\($USER:.\+\):.\+/\1:\/bin\/zsh/" /etc/passwd
    fi
    success
  else
    skip "Already changed default shell: zsh"
  fi
}

create_git_config_local()
{
  local readonly git_config_local="$HOME/.gitconfig.local"

  if [ ! -f $git_config_local ]; then
    notice "Create: $git_config_local"
    cat > $git_config_local <<__END__
[user]
  name =
  email =
__END__
    success
  else
    skip "Already exists: $git_config_local"
  fi
}

create_mysql_config()
{
  local readonly mysql_config="$HOME/.my.cnf"

  if [ ! -f $mysql_config ]; then
    notice "Create: $mysql_config"
    cat > $mysql_config <<__END__
[client]
user = root
__END__
    chmod 600 $mysql_config
    success
  else
    skip "Already exists: $mysql_config"
  fi
}

help()
{
  echo "Usage: `basename $0` [-b]"
}

while getopts "b" flag; do
  case $flag in
    b) INSTALL_BREW_AND_BREW_PACKAGES="1";;
    *) help; exit 1;;
  esac
done

main


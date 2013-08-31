#/bin/sh

set -e

main()
{
  setup_ssh_keys
  setup_dotfiles
  setup_zsh
  setup_rbenv
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
          $input >> $authorized_keys_path
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
  fi
}

setup_zsh()
{
  if [ `basename $SHELL` != "zsh" ] && ask "Do you want to change shell to zsh ?"; then
    sudo sed -i -e "s/^\($USER:.\+\):.\+/\1:\/usr\/bin\/zsh/" /etc/passwd
    success "change default shell to zsh"
  fi
}

setup_rbenv()
{
  local readonly rbenv_dir="$HOME/.rbenv"
  local readonly rbenv_plugins_dir="$HOME/.rbenv/plugins"

  if [ ! -d $rbenv_dir ]; then
    git clone git://github.com/sstephenson/rbenv.git $rbenv_dir
    rehash
    mkdir $rbenv_plugins_dir
    success "install rbenv"
  fi

  if [ ! -d $rbenv_plugins_dir/ruby-build ]; then
    git clone git://github.com/sstephenson/ruby-build.git $rbenv_plugins_dir/ruby-build
    rehash
    success "install ruby-build"
  fi

  if [ ! -d $rbenv_plugins_dir/rbenv-gemset ]; then
    git clone git://github.com/jamis/rbenv-gemset.git $rbenv_plugins_dir/rbenv-gemset
    rehash
    success "install rbenv-gemset"
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


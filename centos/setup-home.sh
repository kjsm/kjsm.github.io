#/bin/sh

set -e

main()
{
  if [ ! -f $HOME/.shutils ]; then
    curl -o $HOME/.shutils -O http://kjsm.github.io/centos/shutils
  fi
  . $HOME/.shutils

  setup_ssh_keys
  setup_dotfiles
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

  if [ ! -d $dotfiles_dir ]; then
    notice "Please register the public key to your repository hosting site"
    echo -e "\n$(cat $HOME/.ssh/id_rsa.pub)\n"
    enter

    input "Input the dotfiles repository location"
    local dotfiles_repository
    read dotfiles_repository
    if [ -z "$dotfiles_repository" ]; then
      error "not given dotfiles repository location"
      exit 1
    fi

    if ! git clone $dotfiles_repository $dotfiles_dir; then
      error "failed clone repository"
      exit 1
    fi
  fi

  if [ ! -d $HOME/.vim ]; then
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

main


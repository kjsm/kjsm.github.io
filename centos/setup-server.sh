#/bin/sh

set -e

readonly INSTALL_RUBY_VERSION="2.1.5"

main()
{
  if [ ! -f $HOME/.shutils ]; then
    curl -o $HOME/.shutils -O http://kjsm.github.io/centos/shutils
  fi
  . $HOME/.shutils

  install_mysql
  install_nginx
  install_ruby $INSTALL_RUBY_VERSION
}

# -------------------------------------------------------------------------------------------------
# mysql
# -------------------------------------------------------------------------------------------------
install_mysql()
{
  local readonly mysql_repository_name="mysql-community"
  local readonly mysql_repository_url="http://dev.mysql.com/get/mysql-community-release-el6-5.noarch.rpm"
  local readonly mysql_repository_local_path="/etc/yum.repos.d/mysql-community.repo"

  install_repository $mysql_repository_name $mysql_repository_url $mysql_repository_local_path
  install "mysql-community-server mysql-community-devel"
  setup_mysql_config
  start_service mysqld
  enable_service mysqld
  #run_mysql_secure_installation

  success "mysql ok\n"
}

setup_mysql_config()
{
  local readonly mysql_config_path="/etc/my.cnf"
  local readonly mysql_user_config_path="/etc/my.cnf.d/my.cnf"

  if ! match '^!includedir' $mysql_config_path; then
    notice "Edit file: $mysql_config_path"
    sudo sh -c "cat >> $mysql_config_path <<'__END__'

# Include files in /etc/my.cnf.d
!includedir     /etc/my.cnf.d
__END__"
    success "Edited file: $mysql_config_path"
  else
    skip "Already edited: $mysql_config_path"
  fi

  if [ ! -f $mysql_user_config_path ]; then
    notice "Create file: $mysql_user_config_path"
    sudo sh -c "curl http://kjsm.github.io/centos/mysql-5.6.cnf > $mysql_user_config_path"
    success "Created file: $mysql_user_config_path"
  else
    skip "Already Created: $mysql_user_config_path"
  fi
}

run_mysql_secure_installation()
{
  #mysqladmin -u root password $new_password
  mysql -u root -e "DELETE FROM mysql.user WHERE User='';"
  mysql -u root -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
  mysql -u root -e "DROP DATABASE IF EXISTS test;"
  mysql -u root -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
  mysql -u root -e "FLUSH PRIVILEGES;"
}

# -------------------------------------------------------------------------------------------------
# nginx
# -------------------------------------------------------------------------------------------------
install_nginx()
{
  # nginx repository
  local readonly nginx_repository_name="nginx"
  local readonly nginx_repository_url="http://nginx.org/packages/centos/6/noarch/RPMS/nginx-release-centos-6-0.el6.ngx.noarch.rpm"
  local readonly nginx_repository_local_path="/etc/yum.repos.d/nginx.repo"

  install_repository $nginx_repository_name $nginx_repository_url $nginx_repository_local_path
  install nginx
  start_service nginx
  enable_service nginx

  success "nginx ok\n"
}

# -------------------------------------------------------------------------------------------------
# ruby
# -------------------------------------------------------------------------------------------------
install_ruby()
{
  local readonly rbenv_dir="/usr/local/rbenv"
  local readonly ruby_version="$1"

  if [ -z "$ruby_version" ]; then
    error "not given install ruby version"
    exit 1
  fi

  install_rbenv

  if [ ! -d $rbenv_dir/versions/$ruby_version ]; then
    notice "Install: ruby $ruby_version (by rbenv)"
    sudo sh -c "source /etc/profile.d/rbenv.sh && rbenv install $ruby_version && rbenv global $ruby_version"
    success "Installed: ruby $ruby_version (by rbenv)"
  else
    skip "Already installed: ruby $ruby_version"
  fi

  success "ruby ok"
}

install_rbenv()
{
  local readonly rbenv_dir="/usr/local/rbenv"
  local readonly rbenv_init_file="/etc/profile.d/rbenv.sh"
  local readonly sudo_file="/etc/sudoers.d/rbenv"
  local readonly gemrc_file="/root/.gemrc"

  if [ ! -d $rbenv_dir ]; then
    notice "Install: rbenv (by git)"
    sudo git clone -q git://github.com/sstephenson/rbenv.git $rbenv_dir
    sudo mkdir $rbenv_dir/plugins
    success "Installed: rbenv (by git)"
  else
    skip "Already installed: rbenv"
  fi

  if [ ! -f $rbenv_init_file ]; then
    notice "Create file: $rbenv_init_file"
    sudo sh -c "cat > $rbenv_init_file <<'__END__'
export RBENV_ROOT=\"$rbenv_dir\"
export PATH=\"\$RBENV_ROOT/bin:\$PATH\"
eval \"\$(rbenv init -)\"
__END__"
    success "Created file: $rbenv_init_file"
  else
    skip "Already exists: $rbenv_init_file"
  fi

  if sudo test ! -f $sudo_file; then
    notice "Create file: $sudo_file"
    sudo mkdir -p /etc/sudoers.d
    sudo chmod 750 /etc/sudoers.d
    sudo sh -c "cat > /etc/sudoers.d/rbenv <<'__END__'
Defaults     env_keep += \"RBENV_ROOT\"
Defaults     secure_path = \"/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/rbenv/bin:/usr/local/rbenv/shims\"
__END__"
    sudo chmod 440 /etc/sudoers
    success "Created file: $sudo_file"
  else
    skip "Already exists: $sudo_file"
  fi

  if sudo test ! -f $gemrc_file; then
    notice "Create file: $gemrc_file"
    sudo sh -c "echo \"gem: --no-ri --no-rdoc\" > $gemrc_file"
    success "Created file: $gemrc_file"
  else
    skip "Already exists: $gemrc_file"
  fi

  install_ruby_build
  install_rbenv_default_gems

  success "rbenv ok\n"
}

install_ruby_build()
{
  local readonly rbenv_dir="/usr/local/rbenv"

  if [ ! -d $rbenv_dir/plugins/ruby-build ]; then
    notice "Install: ruby-build (by git)"
    sudo git clone -q git://github.com/sstephenson/ruby-build.git $rbenv_dir/plugins/ruby-build
    success "Installed: ruby-build (by git)"
  else
    skip "Already installed: ruby-build"
  fi
}

install_rbenv_default_gems()
{
  local readonly rbenv_dir="/usr/local/rbenv"
  local readonly default_gems_file="$rbenv_dir/default-gems"

  if [ ! -d $rbenv_dir/plugins/rbenv-default-gems ]; then
    notice "Install: rbenv-default-gems (by git)"
    sudo git clone -q git://github.com/sstephenson/rbenv-default-gems.git $rbenv_dir/plugins/rbenv-default-gems
    success "Installed: rbenv-default-gems (by git)"
  else
    skip "Already installed: rbenv-default-gems"
  fi

  if [ ! -f $default_gems_file ]; then
    notice "Create file: $default_gems_file"
    sudo sh -c "cat > $rbenv_dir/default-gems <<'__END__'
bundler
__END__"
    success "Created file: $default_gems_file"
  else
    skip "Already exists: $default_gems_file"
  fi
}

main


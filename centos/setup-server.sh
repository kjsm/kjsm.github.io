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
  install_gitlab
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
    success
  else
    skip "Already edited: $mysql_config_path"
  fi

  if [ ! -f $mysql_user_config_path ]; then
    notice "Create file: $mysql_user_config_path"
    sudo sh -c "curl http://kjsm.github.io/centos/mysql-5.6.cnf > $mysql_user_config_path"
    success
  else
    skip "Already exists: $mysql_user_config_path"
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
    success
  else
    skip "Already installed: ruby $ruby_version"
  fi

  success "ruby ok\n"
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
    success
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
    success
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
    success
  else
    skip "Already exists: $sudo_file"
  fi

  if sudo test ! -f $gemrc_file; then
    notice "Create file: $gemrc_file"
    sudo sh -c "echo \"gem: --no-ri --no-rdoc\" > $gemrc_file"
    success
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
    success
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
    success
  else
    skip "Already installed: rbenv-default-gems"
  fi

  if [ ! -f $default_gems_file ]; then
    notice "Create file: $default_gems_file"
    sudo sh -c "cat > $rbenv_dir/default-gems <<'__END__'
bundler
__END__"
    success
  else
    skip "Already exists: $default_gems_file"
  fi
}

# -------------------------------------------------------------------------------------------------
# gitlab
# -------------------------------------------------------------------------------------------------
install_gitlab()
{
  local readonly git_home="/home/git"
  local readonly gitlab_dir="/home/git/gitlab"
  local readonly gitlab_database="gitlabhq_production"

  if [ -z "$SERVER_FQDN" ]; then
    skip "Not give server fqdn, skip gitlab installing"
    success "gitlab skipped"
    return 0
  fi

  for package in cmake libicu-devel libxml2-devel libxslt-devel
  do
    install $package
  done

  install redis --enablerepo=epel

  if ! match '^unixsocket ' /etc/redis.conf; then
    notice "Edit file: /etc/redis.conf"
    sudo cp /etc/redis.conf /etc/redis.conf.bak
    sudo sed -i -e "s/^# \(unixsocket\) .\+$/\1 \/var\/run\/redis\/redis.sock/" /etc/redis.conf
    sudo sed -i -e "s/^# \(unixsocketperm\) .\+$/\1 770/" /etc/redis.conf
    success
  else
    skip "Already edited: /etc/redis.conf"
  fi

  start_service redis
  enable_service redis

  if [ ! -d $git_home ]; then
    notice "Add user: git"
    sudo useradd -c 'GitLab' -s /bin/bash git
    sudo gpasswd -a git redis
    #sudo passwd git
    success
  else
    skip "Already added user: git"
  fi

  if mysqladmin create $gitlab_database > /dev/null 2>&1; then
    notice "Create database (with user): $gitlab_database"
    mysql -u root -e "CREATE USER 'git'@'localhost' IDENTIFIED BY 'git';"
    mysql -u root -e "GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, INDEX, ALTER ON $gitlab_database.* TO 'git'@'localhost';"
    success
  else
    skip "Already exists database: $gitlab_database"
  fi

  if sudo test ! -d $git_home/gitlab-shell; then
    notice "Install: gitlab-shell (by git)"

    sudo -u git sh -c "cd $git_home && git clone --single-branch https://github.com/gitlabhq/gitlab-shell.git -b v2.5.4"
    sudo -u git sh -c "sed -e 's/^\(gitlab_url:\).\+$/\1 \"http:\/\/$SERVER_FQDN\/\"/' $git_home/gitlab-shell/config.yml.example > $git_home/gitlab-shell/config.yml"
    sudo -u git sh -c "cd $git_home/gitlab-shell && ./bin/install"

    success
  else
    skip "Already installed: gitlab-shell (by git)"
  fi

  if sudo test ! -d $gitlab_dir; then
    notice "Install: gitlab (by git)"
    sudo -u git sh -c "cd $git_home && git clone --single-branch https://github.com/gitlabhq/gitlabhq.git gitlab -b v7.8.4"
    success
  else
    skip "Already installed: gitlab (by git)"
  fi

  if sudo test ! -f $gitlab_dir/config/gitlab.yml; then
    notice "Create file: $gitlab_dir/config/gitlab.yml"
    sudo -u git sh -c "cd $gitlab_dir && cp config/gitlab.yml.example config/gitlab.yml"
    sudo -u git sh -c "cd $gitlab_dir && sed -i -e 's/^\(\s\+host:\).\+$/\1 $SERVER_FQDN/' config/gitlab.yml"
    sudo -u git sh -c "cd $gitlab_dir && sed -i -e 's/^\(\s\+email_from:\).\+$/\1 root@localhost/' config/gitlab.yml"
    success
  else
    skip "Already exists: $gitlab_dir/config/gitlab.yml"
  fi

  if sudo test ! -f $gitlab_dir/config/unicorn.rb; then
    notice "Create file: $gitlab/config/unicorn.yml"
    sudo -u git sh -c "cd $gitlab_dir && cp config/unicorn.rb.example config/unicorn.rb"
    success
  else
    skip "Already exists: $gitlab_dir/config/unicorn.yml"
  fi

  if sudo test ! -f $gitlab_dir/config/database.yml; then
    notice "Create file: $gitlab_dir/config/database.yml"
    sudo -u git sh -c "cd $gitlab_dir && cp config/database.yml.mysql config/database.yml"
    sudo -u git sh -c "cd $gitlab_dir && sed -i -e 's/^\(\s\+username:\).\+$/\1 git/' config/database.yml"
    sudo -u git sh -c "cd $gitlab_dir && sed -i -e 's/^\(\s\+password:\).\+$/\1 git/' config/database.yml"
    success
  else
    skip "Already exists: $gitlab_dir/config/database.yml"
  fi

  if sudo test ! -d $gitlab_dir/vendor/bundle; then
    notice "Install: bundle gems"
    sudo -u git sh -c "cd $gitlab_dir && bundle install --deployment --without development test postgres --path vendor/bundle"
    sudo -u git sh -c "cd $gitlab_dir && bundle exec rake gitlab:setup RAILS_ENV=production"
    sudo -u git sh -c "cd $gitlab_dir && bundle exec rake assets:precompile RAILS_ENV=production"
    success
  else
    skip "Already installed: bundle gems"
  fi

  if [ ! -f /etc/logrotate.d/gitlab ]; then
    notice "Create file: /etc/logrotate.d/gitlab"
    sudo cp $gitlab_dir/lib/support/logrotate/gitlab /etc/logrotate.d/gitlab
    success
  else
    skip "Already exists: /etc/logrotate.d/gitlab"
  fi

  if [ ! -f /etc/init.d/gitlab ]; then
    notice "Create file: /etc/init.d/gitlab"
    sudo cp $gitlab_dir/lib/support/init.d/gitlab /etc/init.d/gitlab
    sudo cp $gitlab_dir/lib/support/init.d/gitlab.default.example /etc/default/gitlab
    sudo chkconfig --add gitlab
    success
  else
    skip "Already exists: /etc/init.d/gitlab"
  fi

  start_service gitlab
  enable_service gitlab

  if [ ! -f /etc/nginx/conf.d/gitlab.conf ]; then
    sudo cp $gitlab_dir/lib/support/nginx/gitlab /etc/nginx/conf.d/gitlab.conf
    sudo sed -i -e "s/^\(\s\+server_name\).\+$/\1 $SERVER_FQDN/" /etc/nginx/conf.d/gitlab.conf
    sudo mv /etc/nginx/conf.d/default.conf /etc/nginx/conf.d/default.conf.bak
    sudo gpasswd -a nginx git
    sudo chmod g+rx /home/git/
    sudo service nginx reload
  fi
}

help()
{
  echo "Usage: `basename $0` [-f server_fqdn]"
}

while getopts "f:" flag; do
  case $flag in
    f) SERVER_FQDN="$OPTARG";;
    *) help; exit 1;;
  esac
done

main


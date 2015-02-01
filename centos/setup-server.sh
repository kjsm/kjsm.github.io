#/bin/sh

set -e

# MySQL repository rpm
readonly MYSQL_REPOSITORY_URL="http://dev.mysql.com/get/mysql-community-release-el6-5.noarch.rpm"

# Nginx repository rpm
readonly NGINX_REPOSITORY_URL="http://nginx.org/packages/centos/6/noarch/RPMS/nginx-release-centos-6-0.el6.ngx.noarch.rpm"

# Install ruby version
readonly INSTALL_RUBY_VERSION="2.1.5"

main()
{
  if [ ! -f $HOME/.shutils ]; then
    curl -o $HOME/.shutils -O http://kjsm.github.io/centos/shutils
  fi
  . $HOME/.shutils

  setup_mysql
  setup_nginx
  setup_ruby $INSTALL_RUBY_VERSION
}

setup_mysql()
{
  if installed mysql-server || installed mysql-community-server || ! ask "Install mysql ?"; then
    return 0
  fi

  if ! installed mysql-server && ! installed mysql-community-server; then
    install $MYSQL_REPOSITORY_URL
    install mysql-community-server
    install mysql-community-devel

    sudo cp /etc/my.cnf /etc/my.cnf.orig
    sudo sh -c "curl http://kjsm.github.io/centos/mysql-5.6.cnf > /etc/my.cnf"
    sudo service mysqld start
    sudo chkconfig mysqld on

    # mysql_secure_installation
    #mysqladmin -u root password $new_password
    mysql -u root -e "DELETE FROM mysql.user WHERE User='';"
    mysql -u root -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
    mysql -u root -e "DROP DATABASE IF EXISTS test;"
    mysql -u root -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
    mysql -u root -e "FLUSH PRIVILEGES;"

    success "setup mysql"
  fi
}

setup_nginx()
{
  if installed nginx || ! ask "Install nginx ?"; then
    return 0
  fi

  if ! installed nginx; then
    install $NGINX_REPOSITORY_URL
    sudo sed -i -e "s/enabled=1/enabled=0/g" /etc/yum.repos.d/nginx.repo
    sudo yum -y -q --enablerepo=nginx install nginx
    sudo service nginx start
    sudo chkconfig nginx on

    success "install nginx"
  fi
}

setup_ruby()
{
  local readonly rbenv_dir="/opt/rbenv"
  local readonly rbenv_plugins_dir="$rbenv_dir/plugins"
  local readonly ruby_version="$1"

  if [ -z "$ruby_version" ]; then
    error "not given install ruby version"
    exit 1
  fi

  if [ -d $rbenv_dir/versions/$ruby_version ] || ! ask "Install ruby (with rbenv) ?"; then
    return 0
  fi

  if [ ! -d $rbenv_dir ]; then
    sudo git clone git://github.com/sstephenson/rbenv.git $rbenv_dir
    sudo mkdir $rbenv_plugins_dir
    success "install rbenv"
  fi

  if [ ! -d $rbenv_plugins_dir/ruby-build ]; then
    sudo git clone git://github.com/sstephenson/ruby-build.git $rbenv_plugins_dir/ruby-build
    success "install ruby-build"
  fi

  if [ ! -d $rbenv_dir/versions/$ruby_version ]; then
    sudo sh -c "cat > /etc/profile.d/rbenv.sh <<'__END__'
export RBENV_ROOT=\"/opt/rbenv\"
export PATH=\"\$RBENV_ROOT/bin:\$PATH\"
eval \"\$(rbenv init -)\"
__END__"
    sudo sh -c "source /etc/profile.d/rbenv.sh; rbenv install $ruby_version; rbenv global $ruby_version"
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


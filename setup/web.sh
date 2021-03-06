# HTTP: Turn on a web server serving static files
#################################################

source setup/functions.sh # load our functions

apt-get install software-properties-common
add-apt-repository ppa:nginx/development
apt-get update
apt_install nginx php5-fpm

STORAGE_ROOT_ESC=$(echo $STORAGE_ROOT|sed 's/[\\\/&]/\\&/g')
PUBLIC_HOSTNAME_ESC=$(echo $PUBLIC_HOSTNAME|sed 's/[\\\/&]/\\&/g')

rm /etc/nginx/sites-enabled/default

# copy in the nginx configuration file and substitute some
# variables
cat conf/nginx.conf \
	| sed "s/\$STORAGE_ROOT/$STORAGE_ROOT_ESC/g" \
	| sed "s/\$PUBLIC_HOSTNAME/$PUBLIC_HOSTNAME_ESC/g" \
	> /etc/nginx/sites-available/webmail.conf
ln -s /etc/nginx//sites-available/roundcube /etc/nginx//sites-enabled/

#fpm settings
sed -i "s/^;listen.owner = www-data/listen.owner = www-data/" /etc/php5/fpm/pool.d/www.conf
sed -i "s/^;listen.group = www-data/listen.group = www-data/" /etc/php5/fpm/pool.d/www.conf
sed -i "s/^;listen.mode = 0660/listen.mode = 0660/" /etc/php5/fpm/pool.d/www.conf

# Start services.
service nginx restart
service php5-fpm restart

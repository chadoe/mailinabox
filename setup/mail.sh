#!/bin/bash
# SMTP/IMAP: Postfix and Dovecot
################################

# The SMTP server is listening on port 25 for incoming mail (mail for us) and on
# port 587 for outgoing mail (i.e. mail you send). Port 587 uses STARTTLS (not SSL)
# and you'll authenticate with your full email address and mail password.
#
# The IMAP server is listening on port 993 and uses SSL. There is no IMAP server
# listening on port 143 because it is not encrypted on that port.

# We configure these together because postfix's configuration relies heavily on dovecot.

# Install packages.

source setup/functions.sh # load our functions
source /etc/mailinabox.conf # load global vars

apt_install \
	postfix postgrey postfix-pcre \
	dovecot-core dovecot-imapd dovecot-lmtpd dovecot-sqlite sqlite3 \
	openssl

mkdir -p $STORAGE_ROOT/mail

# POSTFIX
#########

if [ -z "$RELAY_HOST" ]; then
	echo
	echo "Enter the relay host (i.e. smtp.provider.com) or leave empty for no relay host."
	echo "Relay host must be listening on port 587."
	echo
	
	if [ -z "$DEFAULT_RELAY_HOST" ]; then
		# set a default on first run
		DEFAULT_RELAY_HOST=smtp.hostname
	fi
	
	read -e -i "$DEFAULT_RELAY_HOST" -p "Relay host: " RELAY_HOST
fi

if [ ! -z "$RELAY_HOST" ] && [ -z "$RELAY_USERNAME" ]; then
	echo
	echo "Enter the relay username or leave empty for no username."
	echo
	if [ -z "$DEFAULT_RELAY_USERNAME" ]; then
		# set a default on first run
		DEFAULT_RELAY_USERNAME=smtp.hostname
	fi
	read -e -i "$RELAY_USERNAME" -p "Relay username: " RELAY_USERNAME
fi

if [ ! -z "$RELAY_USERNAME" ] && [ -z "$RELAY_PASSWORD" ]; then
	echo
	echo "Enter the relay password or leave empty for no password."
	echo
	read -e -i "" -p "Relay password: " RELAY_PASSWORD
fi

cat >> /etc/mailinabox.conf << EOF;
RELAY_HOST=$RELAY_HOST
RELAY_USERNAME=$RELAY_USERNAME
EOF

# Have postfix listen on all network interfaces, set our name (the Debian default seems to be localhost),
# and set the name of the local machine to localhost for xxx@localhost mail (but I don't think this will have any effect because
# there is no true local mail delivery). Also set the banner (must have the hostname first, then anything).
tools/editconf.py /etc/postfix/main.cf \
	inet_interfaces=all \
	myhostname=$PUBLIC_HOSTNAME\
	smtpd_banner="\$myhostname ESMTP Hi, I'm a Mail-in-a-Box Lite (Ubuntu/Postfix; see https://github.com/chadoe/mailinabox)" \
	mydestination=localhost

# Enable the 'submission' port 587 smtpd server and tweak its settings.
# a) Require the best ciphers for incoming connections per http://baldric.net/2013/12/07/tls-ciphers-in-postfix-and-dovecot/.
#    but without affecting opportunistic TLS on incoming mail, which will allow any cipher (it's better than none).
# b) Give it a different name in syslog to distinguish it from the port 25 smtpd server.
# c) Add a new cleanup service specific to the submission service ('authclean')
#    that filters out privacy-sensitive headers on mail being sent out by
#    authenticated users.
tools/editconf.py /etc/postfix/master.cf -s -w \
	"submission=inet n       -       -       -       -       smtpd
	  -o syslog_name=postfix/submission
	  -o smtpd_tls_ciphers=high -o smtpd_tls_protocols=!SSLv2,!SSLv3
	  -o cleanup_service_name=authclean" \
	"authclean=unix  n       -       -       -       0       cleanup
	  -o header_checks=pcre:/etc/postfix/outgoing_mail_header_filters"

# Install the `outgoing_mail_header_filters` file required by the new 'authclean' service.
cp conf/postfix_outgoing_mail_header_filters /etc/postfix/outgoing_mail_header_filters

# Set relay host
if [ ! -z "$RELAY_HOST" ]; then
	tools/editconf.py /etc/postfix/main.cf \
		relayhost=[$RELAY_HOST]:submission

	if [ ! -z "$RELAY_USERNAME" ] && [ ! -z "$RELAY_PASSWORD" ]; then
		echo [$RELAY_HOST]:submission $RELAY_USERNAME:$RELAY_PASSWORD >> /etc/postfix/sasl_passwd
		postmap hash:/etc/postfix/sasl_passwd
		chmod 600 /etc/postfix/sasl_passwd /etc/postfix/sasl_passwd.db
		tools/editconf.py /etc/postfix/main.cf \
			smtp_sasl_auth_enable=yes \
			smtp_sasl_password_maps=hash:/etc/postfix/sasl_passwd \
			smtp_sasl_security_options=noanonymous \
			smtp_use_tls=yes \
			smtp_tls_CAfile=/etc/ssl/certs/ca-certificates.crt \
			smtp_sasl_tls_security_options=noanonymous
	fi
fi

# Enable TLS and require it for all user authentication.
tools/editconf.py /etc/postfix/main.cf \
	smtpd_tls_security_level=may\
	smtpd_tls_auth_only=yes \
	smtpd_tls_cert_file=$STORAGE_ROOT/ssl/ssl_certificate.pem \
	smtpd_tls_key_file=$STORAGE_ROOT/ssl/ssl_private_key.pem \
	smtpd_tls_received_header=yes

# When connecting to remote SMTP servers, prefer TLS.
tools/editconf.py /etc/postfix/main.cf \
	smtp_tls_security_level=may \
	smtp_tls_loglevel=2

# Who can send outbound mail?
# permit_sasl_authenticated: Authenticated users (i.e. on port 587).
# permit_mynetworks: Mail that originates locally.
# reject_unauth_destination: No one else. (Permits mail whose destination is local and rejects other mail.)
tools/editconf.py /etc/postfix/main.cf \
	smtpd_relay_restrictions=permit_sasl_authenticated,permit_mynetworks,reject_unauth_destination

# Who can send mail to us?
# reject_non_fqdn_sender: Reject not-nice-looking return paths.
# reject_unknown_sender_domain: Reject return paths with invalid domains.
# reject_rhsbl_sender: Reject return paths that use blacklisted domains.
# permit_sasl_authenticated: Authenticated users (i.e. on port 587).
# permit_mynetworks: Mail that originates locally.
# reject_rbl_client: Reject connections from IP addresses blacklisted in zen.spamhaus.org
# check_policy_service: Apply greylisting using postgrey.
#
# Notes:
# permit_dnswl_client can pass through mail from whitelisted IP addresses, which would be good to put before greylisting
# so these IPs get mail delivered quickly. But when an IP is not listed in the permit_dnswl_client list (i.e. it is not
# whitelisted) then postfix does a DEFER_IF_REJECT, which results in all "unknown user" sorts of messages turning into
# "450 4.7.1 Client host rejected: Service unavailable". This is a retry code, so the mail doesn't properly bounce.
tools/editconf.py /etc/postfix/main.cf \
	smtpd_sender_restrictions="reject_non_fqdn_sender,reject_unknown_sender_domain,reject_rhsbl_sender dbl.spamhaus.org" \
	smtpd_recipient_restrictions=permit_sasl_authenticated,permit_mynetworks,"reject_rbl_client zen.spamhaus.org","check_policy_service inet:127.0.0.1:10023"

# Increase the message size limit from 10MB to 128MB.
tools/editconf.py /etc/postfix/main.cf \
	message_size_limit=134217728

# Handle all local mail delivery by passing it directly to dovecot over LMTP.
tools/editconf.py /etc/postfix/main.cf virtual_transport=lmtp:unix:private/dovecot-lmtp

# Postfix will query dovecot for user authentication.
tools/editconf.py /etc/postfix/main.cf \
	smtpd_sasl_type=dovecot \
	smtpd_sasl_path=private/auth \
	smtpd_sasl_auth_enable=yes

# Use a Sqlite3 database to check whether a destination email address exists,
# and to perform any email alias rewrites.
tools/editconf.py /etc/postfix/main.cf \
	virtual_mailbox_domains=sqlite:/etc/postfix/virtual-mailbox-domains.cf \
	virtual_mailbox_maps=sqlite:/etc/postfix/virtual-mailbox-maps.cf \
	virtual_alias_maps=sqlite:/etc/postfix/virtual-alias-maps.cf \
	local_recipient_maps=\$virtual_mailbox_maps

# Here's the path to the database.
db_path=$STORAGE_ROOT/mail/users.sqlite

# SQL statement to check if we handle mail for a domain, either for users or aliases.
cat > /etc/postfix/virtual-mailbox-domains.cf << EOF;
dbpath=$db_path
query = SELECT 1 FROM users WHERE email LIKE '%%@%s' UNION SELECT 1 FROM aliases WHERE source LIKE '%%@%s'
EOF

# SQL statement to check if we handle mail for a user.
cat > /etc/postfix/virtual-mailbox-maps.cf << EOF;
dbpath=$db_path
query = SELECT 1 FROM users WHERE email='%s'
EOF

# SQL statement to rewrite an email address if an alias is present.
cat > /etc/postfix/virtual-alias-maps.cf << EOF;
dbpath=$db_path
query = SELECT destination FROM aliases WHERE source='%s'
EOF

# Create an empty database if it doesn't yet exist.
if [ ! -f $db_path ]; then
	echo Creating new user database: $db_path;
	echo "CREATE TABLE users (id INTEGER PRIMARY KEY AUTOINCREMENT, email TEXT NOT NULL UNIQUE, password TEXT NOT NULL, extra);" | sqlite3 $db_path;
	echo "CREATE TABLE aliases (id INTEGER PRIMARY KEY AUTOINCREMENT, source TEXT NOT NULL UNIQUE, destination TEXT NOT NULL);" | sqlite3 $db_path;
fi

# DOVECOT
#########

# The dovecot-imapd dovecot-lmtpd packages automatically enable IMAP and LMTP protocols.

# Set the location where we'll store user mailboxes.
tools/editconf.py /etc/dovecot/conf.d/10-mail.conf \
	mail_location=maildir:$STORAGE_ROOT/mail/mailboxes/%d/%n \
	mail_privileged_group=mail \
	first_valid_uid=0

# Require that passwords are sent over SSL only, and allow the usual IMAP authentication mechanisms.
# The LOGIN mechanism is supposedly for Microsoft products like Outlook to do SMTP login (I guess
# since we're using Dovecot to handle SMTP authentication?).
tools/editconf.py /etc/dovecot/conf.d/10-auth.conf \
	disable_plaintext_auth=yes \
	"auth_mechanisms=plain login"

# Query our Sqlite3 database, and not system users, for authentication.
sed -i "s/\(\!include auth-system.conf.ext\)/#\1/"  /etc/dovecot/conf.d/10-auth.conf
sed -i "s/#\(\!include auth-sql.conf.ext\)/\1/"  /etc/dovecot/conf.d/10-auth.conf

# Configure how to access our Sqlite3 database. Not sure what userdb is for.
cat > /etc/dovecot/conf.d/auth-sql.conf.ext << EOF;
passdb {
  driver = sql
  args = /etc/dovecot/dovecot-sql.conf.ext
}
userdb {
  driver = static
  args = uid=mail gid=mail home=$STORAGE_ROOT/mail/mailboxes/%d/%n
}
EOF

# Configure the SQL to query for a user's password.
cat > /etc/dovecot/dovecot-sql.conf.ext << EOF;
driver = sqlite
connect = $db_path
default_pass_scheme = SHA512-CRYPT
password_query = SELECT email as user, password FROM users WHERE email='%u';
EOF
chmod 0600 /etc/dovecot/dovecot-sql.conf.ext # per Dovecot instructions

# Disable in-the-clear IMAP and POP because we're paranoid (we haven't even
# enabled POP).
sed -i "s/#port = 143/port = 0/" /etc/dovecot/conf.d/10-master.conf
sed -i "s/#port = 110/port = 0/" /etc/dovecot/conf.d/10-master.conf

# Have dovecot provide authorization and LMTP (local mail delivery) services.
#
# We have dovecot listen on a Unix domain socket for these services
# in a manner that made postfix configuration above easy.
#
# We also have dovecot listen on port 10026 (localhost only) for LMTP
# in case we have other services that want to deliver local mail, namely
# spampd.
#
# Also increase the number of allowed connections per mailbox because we
# all have so many devices lately.
cat > /etc/dovecot/conf.d/99-local.conf << EOF;
service auth {
  unix_listener /var/spool/postfix/private/auth {
    mode = 0666
    user = postfix
    group = postfix
  }
}
service lmtp {
  unix_listener /var/spool/postfix/private/dovecot-lmtp {
    user = postfix
    group = postfix
  }
  inet_listener lmtp {
    address = 127.0.0.1
    port = 10026
  }
}

protocol imap {
  mail_max_userip_connections = 20
}
EOF

# postmaster_address seems to be required or LMTP won't start
tools/editconf.py /etc/dovecot/conf.d/15-lda.conf \
	postmaster_address=postmaster@$PUBLIC_HOSTNAME

# Drew Crawford sets the auth-worker process to run as the mail user, but we don't care if it runs as root.

# Enable SSL, specify the location of the SSL certificate and private key files,
# and allow only good ciphers per http://baldric.net/2013/12/07/tls-ciphers-in-postfix-and-dovecot/.
tools/editconf.py /etc/dovecot/conf.d/10-ssl.conf \
	ssl=required \
	"ssl_cert=<$STORAGE_ROOT/ssl/ssl_certificate.pem" \
	"ssl_key=<$STORAGE_ROOT/ssl/ssl_private_key.pem" \
	"ssl_cipher_list=TLSv1+HIGH !SSLv2 !RC4 !aNULL !eNULL !3DES @STRENGTH"

# Fetchmail
#########

apt_install fetchmail
tools/editconf.py /etc/default/fetchmail \
	START_DAEMON=yes
	
cat > /etc/fetchmailrc << EOF;
set daemon      180    # Poll every 3 minutes
set syslog             # log through syslog facility
set no bouncemail    
 
##########################################################################
# Hosts to poll
##########################################################################

defaults:
timeout 300
antispam -1
batchlimit 100

EOF

chmod 600 /etc/fetchmailrc
chown fetchmail /etc/fetchmailrc
	
# SSL CERTIFICATE
	
# Create a self-signed certifiate.
mkdir -p $STORAGE_ROOT/ssl
if [ ! -f $STORAGE_ROOT/ssl/ssl_certificate.pem ]; then
	# Set the umask so the key file is not world-readable.
	(umask 077; openssl genrsa -out $STORAGE_ROOT/ssl/ssl_private_key.pem 2048)
	openssl req -new -key $STORAGE_ROOT/ssl/ssl_private_key.pem -out $STORAGE_ROOT/ssl/ssl_cert_sign_req.csr \
	  -subj "/C=/ST=/L=/O=/CN=$PUBLIC_HOSTNAME"
	openssl x509 -req -days 365 \
	  -in $STORAGE_ROOT/ssl/ssl_cert_sign_req.csr -signkey $STORAGE_ROOT/ssl/ssl_private_key.pem -out $STORAGE_ROOT/ssl/ssl_certificate.pem
fi

# PERMISSIONS / RESTART SERVICES

# Ensure configuration files are owned by dovecot and not world readable.
chown -R mail:dovecot /etc/dovecot
chmod -R o-rwx /etc/dovecot

# Ensure mailbox files have a directory that exists and are owned by the mail user.
mkdir -p $STORAGE_ROOT/mail/mailboxes
chown -R mail.mail $STORAGE_ROOT/mail/mailboxes

# Restart services.
service postfix restart
service dovecot restart
service fetchmail restart


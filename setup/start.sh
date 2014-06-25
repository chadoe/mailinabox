#!/bin/bash
# This is the entry point for configuring the system.
#####################################################

# Check system setup.

if [ "`lsb_release -d | sed 's/.*:\s*//'`" != "Ubuntu 14.04 LTS" ]; then
	echo "Mail-in-a-Box only supports being installed on Ubuntu 14.04, sorry. You are running:"
	echo
	lsb_release -d | sed 's/.*:\s*//'
	echo
	echo "We can't write scripts that run on every possible setup, sorry."
	exit
fi

# Recall the last settings used if we're running this a second time.
if [ -f /etc/mailinabox.conf ]; then
	cat /etc/mailinabox.conf | sed s/^/DEFAULT_/ > /tmp/mailinabox.prev.conf
	source /tmp/mailinabox.prev.conf
fi

# Gather information from the user about the hostname and public IP
# address of this host.
if [ -z "$PUBLIC_HOSTNAME" ]; then
	echo
	echo "Enter the hostname you want to assign to this machine."
	echo "We've guessed a value. Just backspace it if it's wrong."
	echo "Should be simulare to 'domain.com'"
	echo

	if [ -z "$DEFAULT_PUBLIC_HOSTNAME" ]; then
		# set a default on first run
		DEFAULT_PUBLIC_HOSTNAME=`hostname`
	fi

	read -e -i "$DEFAULT_PUBLIC_HOSTNAME" -p "Hostname: " PUBLIC_HOSTNAME
fi

if [ -z "$PUBLIC_IP" ]; then
	echo
	echo "Enter the public IP address of this machine."
	echo "We've guessed a value, but just backspace it if it's wrong."
	echo

	if [ -z "$DEFAULT_PUBLIC_IP" ]; then
		# set a default on first run
		DEFAULT_PUBLIC_IP=`hostname -i`
	fi

	read -e -i "$DEFAULT_PUBLIC_IP" -p "Public IP: " PUBLIC_IP
fi

# Create the user named "user-data" and store all persistent user
# data (mailboxes, etc.) in that user's home directory.
if [ -z "$STORAGE_ROOT" ]; then
	STORAGE_USER=user-data
	if [ ! -d /home/$STORAGE_USER ]; then useradd -m $STORAGE_USER; fi
	STORAGE_ROOT=/home/$STORAGE_USER
	mkdir -p $STORAGE_ROOT
fi

# Save the global options in /etc/mailinabox.conf so that standalone
# tools know where to look for data.
cat > /etc/mailinabox.conf << EOF;
STORAGE_ROOT=$STORAGE_ROOT
PUBLIC_HOSTNAME=$PUBLIC_HOSTNAME
PUBLIC_IP=$PUBLIC_IP
EOF

# Start service configuration.
. setup/system.sh
. setup/mail.sh
. setup/web.sh
. setup/webmail.sh

if [ -t 0 ]; then # are we in an interactive shell?
if [ -z "`tools/mail.py user`" ]; then
	# The outut of "tools/mail.py user" is a list of mail users. If there
	# are none configured, ask the user to configure one.
	echo
	echo "Let's create your first mail user."
	read -e -i "user@$PUBLIC_HOSTNAME" -p "Email Address: " EMAIL_ADDR
	tools/mail.py user add $EMAIL_ADDR # will ask for password
	tools/mail.py alias add hostmaster@$PUBLIC_HOSTNAME $EMAIL_ADDR
	tools/mail.py alias add postmaster@$PUBLIC_HOSTNAME $EMAIL_ADDR
fi
fi


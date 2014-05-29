source scripts/functions.sh # load our functions

# Base system configuration.

apt-get -qq update
apt-get -qq -y upgrade

# Install openssh-server to ensure that the end result is consistent across all Mail-in-a-Boxes.
apt_install openssh-server

# Install basic utilities.

apt_install python3 wget curl bind9-host

# Turn on basic services:
#
#   ntp: keeps the system time correct
#
#   fail2ban: scans log files for repeated failed login attempts and blocks the remote IP at the firewall
#
# These services don't need further configuration and are started immediately after installation.

apt_install ntp fail2ban

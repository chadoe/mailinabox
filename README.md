Mail-in-a-Box Lite
=============

Mail-in-a-Box Lite is based on Mail-in-a-Box (https://github.com/JoshData/mailinabox) but intended as easy to setup internal test mail server.


The Box
-------

Mail-in-a-Box turns a fresh Ubuntu 14.04 LTS 64-bit machine into a working mail server, including:

* An SMTP server for sending/receiving mail, with STARTTLS required for authentication, and greylisting to cut down on spam (postfix, postgrey).
* An IMAP server for checking your mail, with SSL required (dovecot).
* A webmail client so you can check your email from a web browser (roundcube, nginx).
* Configuration of mailboxes and mail aliases is done using a command-line tool.
* Basic system services like intrusion protection, and setting the system clock are automatically configured (fail2ban, ntp).

Please see the initial and very barebones [Documentation](docs/index.md) for more information on how to set up a Mail-in-a-Box. But in short, it's like this:

	# do this on a fresh install of Ubuntu 14.04 only!
	sudo apt-get install -y git
	git clone https://github.com/chadoe/mailinabox
	cd mailinabox
	sudo scripts/start.sh

**Status**: This is a work in progress. It works for what it is, but it is missing such things as quotas, backup/restore, etc.

The Goals
---------

* Easy to install test mail server, not intended to be accessible from the internet as it is not secure.


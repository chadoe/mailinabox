Documentation
=============

Before You Begin
----------------

* Decide what **hostname** you'll use for your new Mail-in-a-Box. You may want to buy a domain name from your favorite registrar now. For the most flexibility, assign a subdomain to your box. For instance, my domain name is `occams.info` (my email address is something`@occams.info`), so I've assigned `box.occams.info` as the hostname for my Mail-in-a-Box.

Get a Server
------------

* Get a server. I've been a long-time customer of Rimuhosting.com which provides cheap VPS machines at several locations around the world. You could also go with Linode.com or any other cloud or VPS (virtual server) provider that provides a static IP address. Don't use Amazon Web Services though: Many of their IP addresses have a bad reputation because they've been used to send spam.

* Choose Ubuntu 14.04 amd64 as your operating system (aka a Linux distribution). You won't need much memory or disk space. 768 MB of memory (RAM) and 4G of disk space should be plenty.

* Once the machine is running, set up Reverse DNS. Each ISP handles that differently. You'll have to figure out from your ISP how to do that. Set the reverse DNS to the hostname you chose above (in my case `box.occams.info`).

* Log in with SSH. Again, your ISP will probably give you some instructions on how to do that. If your personal computer has a command line, you'll be doing something like this:

	ssh -i yourkey.pem user@10.20.30.40
	
You should see a command prompt roughly similar to:

	root@box:~# (<-- blinking cursor here)

	
All command-line instructions below assume you've logged into your machine with SSH already.

Configuring the Server
----------------------

After logging into your *new* server with SSH and becoming root, type the following in the console:

	sudo apt-get install -y git
	git clone https://github.com/joshdata/mailinabox
	cd mailinabox
	
Now you've got the Mail-in-a-Box source code stored on your server. The next command starts the automatic configuration of the server:
	
	sudo setup/start.sh
	
*(Just a reminder, do this on a fresh Ubuntu 14.04 machine only! If you're reusing an existing server, unpredictable things may happen.)*

You will be asked to enter the hostname you chose and the public IP address of the server as assigned by your ISP.

After that you'll see a lot of output as system programs are installed and configured.

At the end you'll be asked to create a mail user for the system. Enter your email address. It doesn't have to be @... the hostname you chose earlier, but if it's not then your DNS setup will be more complicated. The user's email address is also his/her IMAP/SMTP username. Then enter the user's password.

It is safe to run the start script again in case something went wrong. To add more mail users, run `tools/mail.py`.

Configuring DNS
---------------

Your server is set up as a nameserver to provide DNS information for the hostname you chose as well as the domain name in your email address. Go to your domain name registrar and tell it that `ns1.yourhostname` is your nameserver (DNS server). If it requires two, use `ns1.yourhostname` and `ns2.yourhostname`.

For instance, in my case, I could tell my domain name registrar that `ns1.box.occams.info` and `ns2.box.occams.info` are the nameservers for `occams.info`.

(In a more complex setup, you may have a different nameserver for your domain. In this case, you'll delegate DNS to your box for the box's own subdomain. In your main DNS, add a record like "box.occams.info. 3600 IN NS ns1.box.occams.info." and a second one for `ns2` (the final period may be important). This sets who is the authoritative server for the hostname. You'll then also need "ns1.box.occams.info IN A 10.20.30.40" providing the IP address of the authoritative server (and repeat for `ns2`). Then add an MX record on your main domain pointing to the hostname you chose for your server here so that you delegate mail for the domain to your new server using a record like "occams.info. 3600 IN MX 1 box.occams.info." (again the period at the end may be important). You'll also want to put an SPF record on your main domain like "occams.info IN TXT "v=spf1 a mx -all" ".)

Checking Your Mail
------------------

You can access your email at https://`hostname`/mail, where `hostname` is again the hostname you chose at the start.

If you want to set up a desktop mail client like Thunderbird, your IMAP and SMTP server is the hostname you chose at the top. For IMAP, you must choose SSL and port 993. For SMTP, you must choose STARTTLS and port 587. Your username is your complete email address. And your password you entered during server setup earlier. You're using a "self-signed certificate" for SSL connections, so you'll get security warnings when you try to read and send mail. It's safe to permanently ignore the warning the first time you see it (but not if you see the same warning later on).

Checking that it Worked
-----------------------

You can also debug your DKIM (and SPF) settings with e.g. [this tool](http://www.brandonchecketts.com/emailtest.php).
[This site](http://pingability.com/zoneinfo.jsp) will also give useful information about your DNS and mail servers.

# Mail-in-a-Box Dockerfile
# see https://www.docker.io
###########################

# To build the image:
# sudo docker.io build -t box .

# Run your container.
#  -i -t: creates an interactive console so you can poke around (CTRL+D will terminate the container)
#  -p ...: Maps container ports to host ports so that the host begins acting as a Mail-in-a-Box.
# sudo docker.io run -i -t -p 22 -p 25:25 -p 53:53/udp -p 443:443 -p 587:587 -p 993:993 box

###########################################

# We need a better starting image than docker's ubuntu image because that
# base image doesn't provide enough to run most Ubuntu services. See
# http://phusion.github.io/baseimage-docker/ for an explanation. They
# provide a better image, but their latest is for an earlier Ubuntu 
# version. When they get to Ubuntu 14.04 we'll want to use:
#
# FROM phusion/baseimage:<version-based-on-14.04>
#
# Until then, use an upgraded image provided by @pjz, based on his
# PR: https://github.com/phusion/baseimage-docker/pull/64

FROM pjzz/phusion-baseimage:0.9.10
	# based originally on ubuntu:14.04

# Dockerfile metadata.
MAINTAINER Joshua Tauberer (http://razor.occams.info)
EXPOSE 22 25 53 443 587 993

# We can't know these values ahead of time, so set them to something
# obviously local. The start.sh script will need to be run again once
# these values are known. We use the IP address here as a flag that
# the configuration is incomplete.
ENV PUBLIC_HOSTNAME box.local
ENV PUBLIC_IP 192.168.200.1

# Docker-specific Mail-in-a-Box configuration.
ENV DISABLE_FIREWALL 1
ENV NO_RESTART_SERVICES 1

# Our install will fail if SSH is installed and allows password-based authentication.
# The base image already installs openssh-server. Just edit its configuration.
RUN sed -i -e "s/^#*\s*PasswordAuthentication \(yes\|no\)/PasswordAuthentication no/g" /etc/ssh/sshd_config

# Add this repo into the image so we have the configuration scripts.
ADD setup /usr/local/mailinabox/setup
ADD conf /usr/local/mailinabox/conf
ADD tools /usr/local/mailinabox/tools

# Start the configuration.
RUN cd /usr/local/mailinabox && setup/start.sh

# Configure services for docker.
ADD containers/docker /usr/local/mailinabox/containers/docker
RUN /usr/local/mailinabox/containers/docker/setup_services.sh
RUN ln -s /usr/local/mailinabox/containers/docker/container_start.sh /etc/my_init.d/99-mailinabox.sh

# Start bash so we can poke around.
CMD ["/sbin/my_init", "--", "bash"]

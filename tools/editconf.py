#!/usr/bin/python3
#
# This is a helper tool for editing configuration files during the setup
# process. The tool is given new values for settings as command-line
# arguments. It comments-out existing setting values in the configuration
# file and adds new values either after their former location or at the
# end.
#
# The configuration file has settings that look like:
#
# NAME=VALUE
#
# If the -s option is given, then space becomes the delimiter, i.e.:
#
# NAME VALUE
#
# If the -w option is given, then setting lines continue onto following
# lines while the lines start with whitespace, e.g.:
#
# NAME VAL
#   UE 

import sys, re

# sanity check
if len(sys.argv) < 3:
	print("usage: python3 editconf.py /etc/file.conf [-s] [-w] [-t] NAME=VAL [NAME=VAL ...]")
	sys.exit(1)

# parse command line arguments
filename = sys.argv[1]
settings = sys.argv[2:]

delimiter = "="
delimiter_re = r"\s*=\s*"
folded_lines = False
testing = False
while settings[0][0] == "-" and settings[0] != "--":
	opt = settings.pop(0)
	if opt == "-s":
		# Space is the delimiter
		delimiter = " "
		delimiter_re = r"\s+"
	elif opt == "-w":
		folded_lines = True
	elif opt == "-t":
		testing = True
	else:
		print("Invalid option.")
		sys.exit(1)

# create the new config file in memory

found = set()
buf = ""
input_lines = list(open(filename))

while len(input_lines) > 0:
	line = input_lines.pop(0)

	# If this configuration file uses folded lines, append any folded lines
	# into our input buffer.
	if folded_lines and line[0] not in ("#", " ", ""):
		while len(input_lines) > 0 and input_lines[0][0] in " \t":
			line += input_lines.pop(0)

	# See if this line is for any settings passed on the command line.
	for i in range(len(settings)):
		# Check that this line contain this setting from the command-line arguments.
		name, val = settings[i].split("=", 1)
		m = re.match("\s*" + re.escape(name) + delimiter_re + "(.*?)\s*$", line, re.S)
		if not m: continue

		# If this is already the setting, do nothing.
		if m.group(1) == val:
			buf += line
			found.add(i)
			break
		
		# comment-out the existing line (also comment any folded lines)
		buf += "#" + line.rstrip().replace("\n", "\n#") + "\n"
		
		# if this option oddly appears more than once, don't add the setting again
		if i in found:
			break
		
		# add the new setting
		buf += name + delimiter + val + "\n"
		
		# note that we've applied this option
		found.add(i)
		
		break
	else:
		# If did not match any setting names, pass this line through.
		buf += line
		
# Put any settings we didn't see at the end of the file.
for i in range(len(settings)):
	if i not in found:
		name, val = settings[i].split("=", 1)
		buf += name + delimiter + val + "\n"

if not testing:
	# Write out the new file.
	with open(filename, "w") as f:
		f.write(buf)
else:
	# Just print the new file to stdout.
	print(buf)

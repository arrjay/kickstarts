#!/bin/bash

# expects OS from environment
host=$(basename ${1} .ks)

if [ -z "${OS}" ] ; then
  echo "\$OS not set" 1>&2
  exit 1
fi

if [ ! -f "${OS}.os" ] ; then
  echo "$OS unsupported .os" 1>&2
  exit 1
fi

# open destination file
if [ -w "${1}" ] ; then
  echo "${1} not writeable" 1>&2
  exit 1
fi

ksfile="${1}"

# start writing...
echo "auth --enableshadow --passalgo=sha512" > "${ksfile}"
echo "" >> "${ksfile}"

cat "${OS}.os" >> "${ksfile}"

cat << EOF >> "${ksfile}"

# text mode install
text

# enable firstboot agent but leave the EULA accepted
firstboot --enable
eula --agreed

# keyboard, language
keyboard --vckeymap=us --xlayouts='us'
lang en_US.UTF-8

# reboot when done
reboot

# root password
rootpw --iscrypted \$6\$m95xGSDD7uy.OlhR\$1fkOb4IJhARxPZtuc7Mx85tHBY0nf9eEmEE7Zw4Xweh1M4n5kUZ/Ny7xPACUHHfbKNz3dFoxbOurCWpD89YPs.

# system timezone
timezone America/Los_Angeles --isUtc

EOF

# pre
if [ -x "pre/${host}" ] ; then
  ./pre/"${host}" >> "${ksfile}"
elif [ -f "pre/${host}" ] ; then
  cat "pre/${host}" >> "${ksfile}"
fi

# disk handling - autopartition sda default else load a system-specific config
if [ -f "${host}.part" ] ; then
  cat "${host}.part" >> "${ksfile}"
fi

echo "# network" >> "${ksfile}"
# network handling - dhcp default else load a system-specific config
if [ -f "${host}.net" ] ; then
  cat "${host}.net" >> "${ksfile}"
else
  echo "network  --bootproto=dhcp --device=eth0 --onboot=on" >> "${ksfile}"
fi

echo "" >> "${ksfile}"
echo "# services" >> "${ksfile}"
# system services
if [ -x "services/${host}" ] ; then
  ./services/"${host}" >> "${ksfile}"
elif [ -f "services/${host}" ] ; then
  cat "services/${host}" >> "${ksfile}"
fi

echo "" >> "${ksfile}"
echo "# packages" >> "${ksfile}"
# packages - system, os, default
if [ -x "packages/${host}" ] ; then
  ./packages/"${host}" >> "${ksfile}"
elif [ -f "packages/${host}" ] ; then
  cat "packages/${host}" >> "${ksfile}"
fi

echo "" >> "${ksfile}"
echo "# addons" >> "${ksfile}"
# addons - system, os, default
if [ -x "addons/${host}" ] ; then
  ./addons/"${host}" >> "${ksfile}"
elif [ -f "addons/${host}" ] ; then
  cat "addons/${host}" >> "${ksfile}"
fi

# post
if [ -x "post/${host}" ] ; then
  ./pre/"${host}"
elif [ -f "post/${host}" ] ; then
  cat "post/${host}" >> "${ksfile}"
fi

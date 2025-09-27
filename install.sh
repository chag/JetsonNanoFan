#!/bin/bash -e

echo "asserting ROOT"
if [ $EUID != 0 ]; then
    sudo "$0" "$@"
    exit $?
fi

echo "copying fan.sh to /usr/local/bin/"
cp --force ./fan.sh /usr/local/bin/

echo "setting permissions"
chmod u+rx,go-wx /usr/local/bin/fan.sh

echo "copying fan.service to /lib/systemd/system/"
cp --force ./fan.service /lib/systemd/system/
chmod go-w /lib/systemd/system/fan.service

echo "copying fan.json to /etc/ (unless it already exists)"
cp --no-clobber ./fan.json /etc/
chmod go-w /etc/fan.json

echo "reloading systemctl daemon"
systemctl daemon-reload

echo "enabling fan service"
systemctl enable fan

echo "starting fan service"
systemctl start fan
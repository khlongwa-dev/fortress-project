#!/bin/bash

SERVER_DIR=/home/khlongwa/sysadmin-lab/
SERVER_USER=khlongwa
SERVER_IP=192.168.56.104
HOST_DIR=/home/khlongwa/Documents/sysadmin-lab/
PORT=5387
PING_COUNT=1

if ping -c "$PING_COUNT" "$SERVER_IP" > /dev/null 2>&1; then
	rsync -az --delete --exclude='.git' -e "ssh -p $PORT -i /home/khlongwa/.ssh/ubuntu_server_key" "$SERVER_USER@$SERVER_IP:$SERVER_DIR" "$HOST_DIR"
else
	exit 0 # I will add the logging in future when it is a greater necessity.
fi

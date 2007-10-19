#!/bin/bash
dir="/usr/local/ipop"

if ! `$dir/scripts/utils.sh check_fd`; then
  exit
fi

if [[ $1 = "start" ]]; then
  $dir/scripts/ippoll.sh &
elif [[ $1 = "stop" ]]; then
  pkill -KILL ippoll.sh
elif [[ $1 = "restart" ]]; then 
  /etc/init.d/rc_ippoll.sh stop
  /etc/init.d/rc_ippoll.sh start
fi
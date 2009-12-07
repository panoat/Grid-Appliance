#!/bin/bash

### BEGIN INIT INFO
# Provides:          grid_appliance
# Required-Start:    $local_fs $syslog
# Required-Stop:     $remote_fs $syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Begins Grid Appliance config and IPOP
# Description:       Enable Grid Appliance, Condor, IPOP
### END INIT INFO

source /etc/ipop.vpn.config
source /etc/grid_appliance.config

function stop() {
  #Stop IPOP
  /etc/init.d/groupvpn.sh stop
  #Remove DOS prevention rule
  iptables -D OUTPUT -m owner --uid-owner nobody ! -o $DEVICE -j DROP &> /dev/null

  # Kill the monitor program
  pkill -KILL monitor.sh 

  # Umount the floppy
  cat /proc/mounts | grep $CONFIG_PATH > /dev/null
  if [[ $? == 0 ]]; then
    umount $CONFIG_PATH
  fi
}

function start() {
  # Add proper hostname usage, it can be overwritten any time IPOP is updated:
  sed -i 's/USE_IPOP_HOSTNAME=$/USE_IPOP_HOSTNAME=true/g' /etc/ipop.vpn.config
  sed -i -r 's/USE_IPOP_HOSTNAME=\s+/USE_IPOP_HOSTNAME=true/g' /etc/ipop.vpn.config

  # Ensure proper loading of condor
  if [[ ! `grep condor_config.sh /etc/condor/condor_config` ]]; then
    echo "LOCAL_CONFIG_FILE  = /etc/condor/condor_config.sh|" >> /etc/condor/condor_config
  fi

  # Mount the floppy, umount first
  cat /proc/mounts | grep $CONFIG_PATH > /dev/null
  if [[ $? == 0 ]]; then
    umount $CONFIG_PATH
  fi

  # Create the path if necessary
  if ! test -d $CONFIG_PATH; then
    mkdir $CONFIG_PATH &> /dev/null
  fi

  # Determine which device and mount
  if test -e $DIR/etc/floppy.img; then
    mount -o loop $DIR/etc/floppy.img $CONFIG_PATH
  else
    modprobe floppy
    mount /dev/fd0 $CONFIG_PATH
  fi

  # If we didn't mount a floppy, no point in proceeding!
  cat /proc/mounts | grep $CONFIG_PATH > /dev/null
  if [[ $? != 0 ]]; then
    ec2
    if [[ $? == 0 ]]; then
      start
      return
    fi

    echo "No floppy.img, add a floppy.img and then restart grid_appliance."
    echo "/etc/init.d/grid_appliance.sh start"
    exit 0
  fi

  # Check to see if there is a new floppy / config
  md5old=`md5sum $DIR/var/groupvpn.zip 2> /dev/null | awk '{print $1}'`
  md5new=`md5sum $CONFIG_PATH/groupvpn.zip 2> /dev/null | awk '{print $1}'`
  if [[ "$md5old" != "$md5new" ]]; then
    rm -f $DIR/var/groupvpn.zip
    for i in groupvpn.zip group_appliance.config; do
      cp $CONFIG_PATH/$i $DIR/var/.
    done
    groupvpn_prepare.sh $DIR/var/groupvpn.zip

    if test -e $CONFIG_PATH/authorized_keys; then
      mkdir -p /root/.ssh &> /dev/null
      cp -f $CONFIG_PATH/authorized_keys /root/.ssh/authorized_keys
      chown -R root:root /root
      chmod 700 /root/.ssh
      chmod 600 /root/.ssh/*
    fi
  fi

  #Start IPOP
  /etc/init.d/groupvpn.sh start

  # Don't have duplicate rules
  iptables -D OUTPUT -m owner --uid-owner nobody ! -o $DEVICE -j DROP &> /dev/null
  #Configure IPTables to prevent DOS attacks and LAN attacks from condor jobs
  iptables -A OUTPUT -m owner --uid-owner nobody ! -o $DEVICE -j DROP &> /dev/null

  #Start the monitoring service
  $DIR/scripts/monitor.sh &> /var/log/monitor.log &
}

function ec2() {
  # Get the floppy image and prepare the system for its use
  wget http://169.254.169.254/latest/user-data -O /tmp/floppy.zip
  if [[ $? != 0 ]]; then
    return -1
  fi

  cd /tmp
  unzip floppy.zip &> /dev/null
  mv -f floppy.img $DIR/etc/floppy.img &> /dev/null

  # If the floppy exists, we've done well!
  if test -e $DIR/etc/floppy.img; then
    return 0
  fi

  return -1
}

case "$1" in
  start)
    start
    ;;
  stop)
    stop
    ;;
  restart)
    stop
    start
    ;;
  *)
    echo "usage: start, stop, restart"
  ;;
esac

exit 0

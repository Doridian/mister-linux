#!/bin/sh
modprobe pcnet32
modprobe e1000
modprobe ipv6
ifup eth0
telnetd &

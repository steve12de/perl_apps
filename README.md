# 
# Program : process_config_fr.pl
#
# Use: perl <ip address> <password file> <config file>
#
# Developed on strawberry perl v5.12.3  sing Padre IDE
#
# Programs a device from a simple text record file, via its HTTP webmin server.
# This program demonstrates the WWW:Mechanize package for automated web site access.
#
# Program takes a command line consisting of IP address, Login file and Config file. 
# It parses the config file to extract the next record with status 'ready', into an 
# array. It then initialises an ethernet connection to the device HTTP webmin server 
# using the command line <ip address>.
#
# It authenticates (from user/password in the Login file).
# It then navigates the webmin site from connman and programs hostname, dns servers, 
# ipv4 and ipv6 parameters, and saves these entries.
# It then shutsdown the device. 
# It also parses the whole config file and error checks, prints error line and exits.
#
# To install packages - In cmd window (dos)  use Cpan : Cpan Data::Validate:IP  (example)
#
# The Config file should reside on network for multiple access.
# The Config file can contain any number of records of 6 types:
# 1) IPv4 static  (no ipv6)  len 9
# 2) IPv4 dynamic (no ipv6)  len 3
# 3) IPv4 static + IPv6 static len 13
# 4) IPv4 static + IPv6 discovery len 10
# 5) IPv4 dynamic + IPv6 static len 7
# 6) IPv4 dynamic + IPv6 discovery len 4
# The end of each record is delimited by <space>
#
# The Config File records status is updated from: 
# 'ready' to  'locked' once parameters read into array.
# 'locked' to 'configured' once device programmed.
#
# Multiple instances of the program can be run (the config file should reside 
# oncan be run, each reading the next 'ready' record and programming the next device
# with this record.
#
# An Output file is written for each programmed device, its name is based on the 
# MAC address read from the webmin server. It lists the MAC addres, and parameters
# used to program the device. On error, a 'random' Error output file is written.
#
# The 6 Records can be written from a template as follows:
#
# Field        type                    example
#
# 0 Hostname   text[ A-Z,a-z,0-9 -_ ]  <hostname_1>
# 1 Status     text[ A-Z,a-z,0-9 _.]   <ready.....> <locked....> <configured>
# 2 IPmode     value                   <static>
# 3 IP         ipv4                    <10.167.111.67>
# 4 Netmask    ipv4                    <255.255.255.0>
# 5 DefGateway ipv4                    <127.0.0.1> 
# 6 DNSserver1 ipv4                    <> 
# 7 DNSserver2 ipv4                    <>
# 8 DNSserver3 ipv4                    <>
#
# 0 Hostname   text[ A-Z,a-z,0-9-_ ]   <hostname_2>
# 1 Status     text[ A-Z,a-z,0-9 _.]   <ready.....> <locked....> <configured>
# 2 IPmode     value                   <dynamic>
# <space>
# 0 Hostname   text[ A-Z,a-z,0-9-_ ]   <hostname_3>
# 1 Status     text[ A-Z,a-z,0-9 _.]   <ready.....> <locked....> <configured>
# 2 IPmode     value                   <static>
# 3 IP         ipv4                    <10.167.111.67>
# 4 Netmask    ipv4                    <255.255.255.0>
# 5 DefGateway ipv4                    <127.0.0.1> 
# 6 DNSserver1 ipv4                    <> 
# 7 DNSserver2 ipv4                    <>
# 8 DNSserver3 ipv4                    <>
# 9 IPv6 mode  value                   <static>
# 10 IPv6address ipv6                  2001:cdba:0000:0000:0000:0000:3257:9652
# 11 IPv6netmask numeric               64
# 12 IPv6gateway ipv6                  2001:cdba:290c:1291::1
#                         
# 0 Hostname   text[ A-Z,a-z,0-9-_ ]   <hostname_4>
# 1 Status     text[ A-Z,a-z,0-9 _.]   <ready.....> <locked....> <configured>
# 2 IPmode     value                   <static>
# 3 IP         ipv4                    <10.167.111.67>
# 4 Netmask    ipv4                    <255.255.255.0>
# 5 DefGateway ipv4                    <127.0.0.1> 
# 6 DNSserver1 ipv4                    <> 
# 7 DNSserver2 ipv4                    <>
# 8 DNSserver3 ipv4                    <>
# 9 IPv6 mode  value                   <discovery>
#                         
# 0 Hostname   text[ A-Z,a-z,0-9-_ ]   <hostname_5>
# 1 Status     text[ A-Z,a-z,0-9 _.]   <ready.....> <locked....> <configured>
# 2 IPmode     value                   <dynamic>
# 3 IPv6 mode  value                   <static>
# 4 IPv6address ipv6                   2001:cdba:0:0:0:0:3257:9652
# 5 IPv6netmask numeric                64
# 6 IPv6gateway ipv6                   2001:cdba:290c:1291::1
#
# 0 Hostname   text[ A-Z,a-z,0-9-_ ]   <hostname_6>
# 1 Status     text[ A-Z,a-z,0-9 _.]   <ready.....> <locked....> <configured>
# 2 IPmode     value                   <dynamic>
# 3 IPv6 mode  value                   <discovery>
#
########################################################################################

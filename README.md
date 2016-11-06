Program : process_config_fr.pl.
Use: perl <ip address> <password login file> <config file>.
Developed on strawberry perl v5.12.3.

Programs a device from a simple text record file, via its HTTP webmin server.
This program demonstrates the WWW:Mechanize package for automated web site access.

Program parses the config file and error checks, prints error lines and exits.

Program a network device from a command line consisting of an IP address, Login file and Config file.
It parses the config file to extract the next record with status 'ready', into an array. 
It then initialises a connection to the device's HTTP webmin server using the command line <ip address> 
and authenticates (from user/password in the Login file).
It then navigates the webmin site from connman and programs the hostname, dns servers, 
ipv4 and ipv6 parameters, and saves these entries. It then shuts down the device for reboot.

To install the Perl packages (in dos), use Cpan, for example: Cpan Data::Validate:IP.
The Config file should reside on the network for multiple access.
The Config file can contain any number of records of 6 types:
1) IPv4 static  (no ipv6)  len 9.
2) IPv4 dynamic (no ipv6)  len 3.
3) IPv4 static + IPv6 static len 13.
4) IPv4 static + IPv6 discovery len 10.
5) IPv4 dynamic + IPv6 static len 7.
6) IPv4 dynamic + IPv6 discovery len 4.
The end of each record is delimited by a space.

Multiple instances of the program can be run, each reading the Config File
and next 'ready' record and programming the next device with this record. 
So protection is implemented. Each record is updated:.
   'ready' to 'locked' when parameters are read into array.
   'locked' to 'configured' once the device is programmed.

An Output file is written for each programmed device, its name is based on the 
MAC address read from the webmin server and lists the MAC addres, and parameters
used to program the device. On error, a 'random' Error output file is written.

The 6 Record types are written from a template as follows.
  Field      type                    example.
Hostname   text[ A-Z,a-z,0-9 -_ ]  hostname_1.
Status     text[ A-Z,a-z,0-9 _.]   ready..... locked.... configured.
IPmode     value                   static>.
IP         ipv4                    10.167.111.67>.
Netmask    ipv4                    255.255.255.0>.
DefGateway ipv4                    127.0.0.1>.
DNSserver1 ipv4                    .
DNSserver2 ipv4                    .
DNSserver3 ipv4                    .
space.
Hostname   text[ A-Z,a-z,0-9-_ ]   hostname_2.
Status     text[ A-Z,a-z,0-9 _.]   ready..... locked.... configured.
IPmode     value                   dynamic.
space.
Hostname   text[ A-Z,a-z,0-9-_ ]   hostname_3.
Status     text[ A-Z,a-z,0-9 _.]   ready..... locked.... configured.
IPmode     value                   static.
IP         ipv4                    10.167.111.67.
Netmask    ipv4                    255.255.255.0.
DefGateway ipv4                    127.0.0.1.
DNSserver1 ipv4                    . 
DNSserver2 ipv4                    .
DNSserver3 ipv4                    .
IPv6 mode  value                   static.
IPv6address ipv6                  2001:cdba:0000:0000:0000:0000:3257:9652.
IPv6netmask numeric               64.
IPv6gateway ipv6                  2001:cdba:290c:1291::1.
space.
Hostname   text[ A-Z,a-z,0-9-_ ]   hostname_4.
Status     text[ A-Z,a-z,0-9 _.]   ready..... locked.... configured.
IPmode     value                   static.
IP         ipv4                    10.167.111.67.
Netmask    ipv4                    255.255.255.0.
DefGateway ipv4                    127.0.0.1.
DNSserver1 ipv4                    .
DNSserver2 ipv4                    .
DNSserver3 ipv4                    .
IPv6 mode  value                   discovery.
space.                  
Hostname   text[ A-Z,a-z,0-9-_ ]   hostname_5.
Status     text[ A-Z,a-z,0-9 _.]   ready..... locked.... configured.
IPmode     value                   dynamic.
IPv6 mode  value                   static.
IPv6address ipv6                   2001:cdba:0:0:0:0:3257:9652.
IPv6netmask numeric                64.
IPv6gateway ipv6                   2001:cdba:290c:1291::1.
space.
Hostname   text[ A-Z,a-z,0-9-_ ]   hostname_6.
Status     text[ A-Z,a-z,0-9 _.]   ready..... locked.... configured.
IPmode     value                   dynamic.
IPv6 mode  value                   discovery.



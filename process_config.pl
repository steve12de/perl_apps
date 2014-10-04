#!/usr/bin/perl
#
# Program : process_config_fr.pl
# Author  : Stephen Beko
# Version : 1.0
# Date    : 2014
#
# Use: perl <ip address> <password file> <config file>
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
########################################################################################
#use 5.006;
use strict;
use warnings;

use WWW::Mechanize; # main package used to automate web browsing

use HTML::TreeBuilder; # for parsing html file
use HTML::FormatText;  # for parsing html file

use HTTP::Cookies;                           # WWW::Mechanize uses this
use Fcntl qw(SEEK_SET SEEK_CUR SEEK_END);    # for seek parameters
use Data::Validate::IP qw(is_ipv4 is_ipv6);  # ip address validation
use File::Temp qw/ tempfile tempdir /;       # for random naming of error file

my $mech = WWW::Mechanize->new();
# look real
$mech->agent('User-Agent=Mozilla/5.0 (Macintosh; U; INTEL Mac OS X 10.5; en-US; rv:1.9.1.5) Gecko/20091102 Firefox/3.5.5');
# need cookies
$mech->cookie_jar(HTTP::Cookies->new);

####### Constants #########
my $FALSE = 0;
my $TRUE = 1; 

my $WEBMIN_PORT = 10000;

# Parse types used in : sub check_entry_format
my $TEXT_ENTRY = 0;
my $NUMERIC_ENTRY = 1;
my $HOSTNAME_ENTRY = 2; # RFC 1123
my $IPV4_ENTRY = 3;
my $IPV6_ENTRY = 4;
my $IPMODE_ENTRY = 5;
my $IPV6MODE_ENTRY = 6;
my $SPACE_ENTRY = 7;
my $MAX_TEXT_LEN = 40;
#
# Fields                MAINTAINANCE - ADD ADDITIONAL FIELDS HERE
my $HOSTNAME = 0;
my $STATUS   = 1;
my $IPV4_MODE = 2;
my $IPV4_ADDRESS = 3;
my $IPV4_NETMASK = 4;
my $IPV4_DEFGATEWAY = 5;
my $DNS_SERVER1 = 6;
my $DNS_SERVER2 = 7;
my $DNS_SERVER3 = 8;
my $IPV6_MODE = 9;
my $IPV6_ADDRESS = 10;
my $IPV6_NETMASK = 11;
my $IPV6_GATEWAY = 12;
my $REC_END = 13;
#
# Record states
my $SEARCH_READY = 0;
my $FOUND_READY = 1;
my $PROCESSED_READY = 2;
#
# Types of config records       MAINTAINANCE - ADD ADDITIONAL TYPES HERE
my $IPV4_STATIC_RECORD  = 1;               # static  ipv4
my $IPV4_DYNAMIC_RECORD = 2;               # dynamic ipv4
my $IPV4_STATIC_IPV6_STATIC_RECORD = 3;    # static ipv4 + static ipv6
my $IPV4_STATIC_IPV6_DISCOVER_RECORD = 4;  # static ipv4 + dynamic ipv6
my $IPV4_DYNAMIC_IPV6_STATIC_RECORD = 5;   # dynamic ipv4 + static ipv6
my $IPV4_DYNAMIC_IPV6_DISCOVER_RECORD = 6; # dynamic ipv4 + dynamic ipv6
#
# returns from : sub check_entry_format 
my $NOT_IDENTIFIED = 0;
my $IPV4_STATIC_SECTION = 10;
my $IPV4_DYNAMIC_SECTION = 11;
my $IPV6_STATIC_SECTION = 12;
my $IPV6_DISCOVER_SECTION = 13;
my $SPACE = 14;
my $READY = 15;
my $ERROR = 98;
my $SPACE_ERROR = 99;
# offset position and lengths used in parsing config file 
# MAINTAINANCE - INCREASE OFFSET/LEN FOR ADDITIONAL FIELDS HERE
# lengths include space delimiter 
my $OFFSET_DYNAMIC = 9;
my $OFFSET_IPV6 = 12;
my $OFFSET_END  = 13;
my $IPV4_STATIC_RECORD_LEN  = 10;
my $IPV4_DYNAMIC_RECORD_LEN = 4;
my $IPV4_STATIC_IPV6_STATIC_LEN = 14;
my $IPV4_STATIC_IPV6_DISCOVER_LEN = 11;
my $IPV4_DYNAMIC_IPV6_STATIC_LEN = 8;
my $IPV4_DYNAMIC_IPV6_DISCOVER_LEN = 5;

######### FILES #################
my $CONFIG_FILE = "config.txt";   # can be over-written by comamnd line args
my $LOGIN_FILE =  "login.txt";    # can be over-written by command line args
my $display_file = "out.htm";
my $error_log;
my $filename;
unless (($error_log, $filename) = tempfile(my $template, SUFFIX => '.tmp')) # open
{
  warn "Error creating error log = $filename:$!";
}
print("error_log=$filename\n");

######### DEBUG #################
my $DEBUG  = 0;
# use the following code segment to display page contents in any sub-routine
# my $display_page = $mech->content();
# open(DISPLAY_FILE, ">$display_file");
# print DISPLAY_FILE "$display_page";
# close(DISPLAY_FILE);

######## Global Vars #########
my $ip_address_connect = "10.167.111.67:10000";   #default setting for test - over-written by command line
my $temp_text = "";
my $link; # for mac address and log file
my $line_error = $FALSE;

######## Subroutines #########

sub set_error_log {
 print $error_log "CONFIGURE DEVICE LOG FILE\n\n";
 print $error_log "$temp_text\n";
 close ($error_log);
}
########

# Login to webmin
sub post_login_authentication {
 # set up IP connection
 print "Post Login Authentication ip=$_[0]\n";
 $temp_text ="$temp_text" . "Post Login Authentication ip=$_[0] username=$_[1] password=$_[2]\n";
 
 # Start at login
 unless ($mech->get("http://$_[0]/session_login.cgi"))
 {
   $temp_text ="$temp_text" . "Error: Access login Page fail\n";
   set_error_log;
   die "Error: Access login Page fail: $!\n";
 }
 # find and fill out the login form
 my $login = $mech->form_name("Login_to_webmin");
 $mech->field("user", $_[1]);
 $mech->field("pass", $_[2]);
 unless ($mech->click_button (value => "Login"))
 {
    $temp_text ="$temp_text" . "Post Login Authentication Fail\n";
    set_error_log;
    die "Error: password POST fail: $!\n";
 }
 print "Login done\n";
}
########

# Sets up link to Connection Manager
sub post_connection_manager {
 print "Access Connection Manager\n";
 $temp_text = "$temp_text" . "Access Connection Manager\n";
 # Connection Manager  eg <ip address>:10000/connman/ 
 unless ($mech->get("http://$_[0]/connman/"))
 {
   $temp_text ="$temp_text" . "Error: Access Connection Manager Fail\n";
   set_error_log;
   die "Error: Access Connection Manager Fail: $!\n";
 }
}
########

 # POSTS Hostname and DNS Client settings
sub post_hostname {
 print "Post Hostname: $_[0]\n";
 $temp_text = "$temp_text" . "Post Hostname: $_[0]\n";
 
 # "http://<ipaddress>/connman/list_dns.cgi/"
 unless ($mech->follow_link(text => "Hostname and DNS Client", n => 1))
 {
   $temp_text ="$temp_text" . "Error: Post Hostname Fail\n";
   set_error_log;
   die "Error: Post Hostname Fail: $!\n";
 }
 
 $mech->field('hostname' => $_[0]);
 if (length($_[1])) {
  $mech->field('nameserver_0' => $_[1]);
 }
 if (length($_[2])) {
  $mech->field('nameserver_1' => $_[2]);
 }
  if (length($_[3])) {
  $mech->field('nameserver_2' => $_[3]);
 }
 #$mech->click_button (value => "Save"); 
 $mech->click_button(name => "save_button"); 
}
########

# Post ipv4 network params
sub post_ipv4_network_params {
  print "Post ipv4 Network Params:";
  $temp_text = "$temp_text" . "Post ipv4 Network Params\n";
  
  # "http://<ipaddress>/connman/list_ifcs.cgi/"
  unless ($mech->follow_link(text => "Network Interfaces", n => 1))   # via connection Manager
  {
    $temp_text ="$temp_text" . "Error: Network Interface Link fail\n";
    set_error_log;
    die "Error: Network Interface Link fail $!\n";
  }
  # get the mac address and print to log file  
  $link = $mech->content(format => 'text');
  $link =~m/ethernet_/;
  $link = substr($', 0, 12);     # $' : match after, 12 characters
  if ($link) {
      $temp_text = "$temp_text" . " Device: MAC address = $link\n";
      # go to the ethernet link    
      unless ($mech->get($mech->find_link( text_regex => qr/ethernet_/i )))
      {
        $temp_text ="$temp_text" . "Error: Ethernet Link fail\n";
        set_error_log;
        die "Error: Ethernet Link fail: $!\n";
      }
      # Set ipv4 settings
      if ($_[0] eq "static") {
         $temp_text ="$temp_text" . " Static IP: $_[1]/$_[2] default gateway: $_[3]\n";
         print " $_[0]/$_[1] \n";
         #$mech->set_visible( [ radio => 'address' ] );
         $mech->set_fields('mode' =>'address');  
         $mech->field('address' =>$_[1]);
         $mech->field('netmask' =>$_[2]);
         $mech->field('gateway' =>$_[3]);
        }
      else  { # "dynamic"  
         $temp_text ="$temp_text" . " Dynamic IP\n";
         print " Dynamic\n";
         #$mech->set_visible( [ radio => 'dhcp' ] );
         $mech->set_fields('mode' =>'dhcp');     
        }     
  } # $link
 else {
     $temp_text = "$temp_text" . "Error: Unable to obtain MAC address - cannot access link\n";
     set_error_log;
     goto label_exit;
 }
}  
########
# Post ipv6 network params
sub post_ipv6_network_params {
  print "Post ipv6 Network Params:";
  $temp_text = "$temp_text" . "Post ipv6 Network Params\n";
  for ($_[0]) {
     if (m/^off$/i)  {
      printf " ipv6 off\n";
      $temp_text ="$temp_text" . " IPV6 Off\n";
      $mech->set_fields('mode6' =>'none');
     }
     elsif (m/^discovery$/i)  {
      printf " ipv6 discovery\n";
      $temp_text =" $temp_text" . " IPV6 Discovery\n";
      $mech->set_fields('mode6' =>'auto');      
     }
     elsif (m/^static$/i)  {
      printf " ipv6 static: $_[1]/$_[2]\n";
      $temp_text ="$temp_text" . " IPV6 Static: $_[1]/$_[2] gateway: $_[3]\n";
      $mech->set_fields('mode6' =>'address');      
      $mech->field('address6_0' =>$_[1]);
      $mech->field('netmask6_0' =>$_[2]);
      $mech->field('gateway6'   =>$_[3]);
     }
     else {
      printf " ipv6 invalid entry\n";
      $temp_text ="$temp_text" . " IPV6 Invalid Entry\n";
     }
  }
}
########

sub post_save {
  print "Save\n";
   unless ($mech->click_button(name => "save_button"))
   {
     $temp_text ="$temp_text" . "Error: Dave fail\n";
     set_error_log;
     die "Error: Save fail: $!\n";
   }
}
########

sub write_logfile_details {
 if ($link) {
    my $log_file_name = "logfile_" . $link . ".log";
    unless (open (LOGFILE, ">$log_file_name"))           #write mode
    {
     $temp_text ="$temp_text" . "Error: Can't open file $log_file_name \n";
     set_error_log;
     die "Error: Can't open file $log_file_name: $!\n";
    }
    flock(LOGFILE, 2); # exclusive lock for write
 
    print LOGFILE "CONFIGURE DEVICE LOG FILE\n\n";
    my $time = localtime; # scalar context
    print LOGFILE "$time\n";

    print "Get System Details\n";
    # add the MAC and address stuff we accumulated
    print LOGFILE "$temp_text\n";
    close LOGFILE;
   }
}
########

sub post_apply_shutdown {
 print "Post Apply Shutdown\n";
  
 # Bootup and shutdown e.g. <ip address>:10000/init/
 unless ($mech->get("http://$_[0]/init/shutdown.cgi?"))
 {
   $temp_text ="$temp_text" . "Error: Can't apply shutdown\n";
   set_error_log;
   die "Error: System Link Fail: $!\n";
 }
 unless ($mech->click_button(name => "confirm"))
 {
   $temp_text ="$temp_text" . "Error: Can't apply shutdown\n";
   set_error_log;
   die "Error: Can't apply shutdown $!\n";
 }
}
########

sub post_logout {
 # <ip address>:10000/session_login.cgi?logout=1/
 print "Post Logout\n";
 unless ($mech->get("http://$_[0]/session_login.cgi?logout=1"))
 {
    $temp_text ="$temp_text" . "Error: Can't apply logout\n";
    set_error_log;
    die "Error: Can't apply logout $!\n";
  }
}
########

# Set status in config file to string value
sub set_status {  
  unless (open (FILE_W, "+<$CONFIG_FILE"))
  {
    $temp_text ="$temp_text" . "Error: Can't set status\n";
    set_error_log;
    die "Error: Can't set status $!\n";  # read/write(not create)
  }
  flock(FILE_W, 2);               # exclusive lock for write
  binmode FILE_W;
  seek(FILE_W,0,SEEK_SET);
  seek(FILE_W, $_[0], SEEK_SET);
  print FILE_W $_[1];
  close(FILE_W);
}  
########

# Check_entry_format - validate config file entries
# FORMAT types
# HOSTNAME TEXT, Normal TEXT, Numeric, IPV4 address, IPV6 address
# IPV4 mode, IPV6 mode, space (delimiter)
sub check_entry_format {
 my $ret = $NOT_IDENTIFIED;
 my $len;
 for ($_[0]) {
  
     if (/$TEXT_ENTRY/)  {
      $len = length($_[1]);
      if ($len == 0 || $len > $MAX_TEXT_LEN)
        {
         print " String is an invalid length:$len";
         return $ERROR;      
        }
      else
        {
        if ($_[1] =~ m/[^a-zA-Z0-9_.]/){
            print " String contains non-alphanumeric characters";
            return $ERROR;
           }
        }
       if ($_[1] eq "ready.....")
      {
       return $READY;
      }
     }
     elsif (/$NUMERIC_ENTRY/)  {
        if ($_[1] =~ m/[^0-9]/){
            print " Invalid number";
            return $ERROR;
        }
     }
     elsif (/$HOSTNAME_ENTRY/)  {
        if ($_[1] =~ m/[^a-zA-Z0-9_-]/){
            print " Invalid hostname";
            return $ERROR;
        }
     }     
     elsif (/$IPV4_ENTRY/)  {
      $len = length($_[1]);      
      if ($len > 0) {            # an empty address is valid unless IP address
         if (!is_ipv4($_[1]))
         {
            print " Invalid IPv4 address";
            return $ERROR;
          }
       }
       else
       {
        # special case - if this is an IP address and entry is empty
        if ($_[2] eq "ip") {
            print " Missing IPv4 address";
            return $ERROR;
        }
       }
       # special case - if mode is static and next entry is empty
       $len = length($_[2]);
       if ($len == 0) {
            print " Expected IPv4 address entry ";
            return $ERROR;        
       }
      } 
     elsif (/$IPV6_ENTRY/)  {
      $len = length($_[1]);      
      if ($len > 0) {
         if (!is_ipv6($_[1]))
           {
            print " Invalid IPv6 address";
            return $ERROR;
           }
         }
      else
       {
        # special case - if this is an IP address and entry is empty
        if ($_[2] eq "ipv6address") {
            print " Missing IPv6 address";
            return $ERROR;
        }
       }
       # special case - if mode is static and next entry is empty
       $len = length($_[2]);
       if ($len == 0) {
            print " Expected IPv6 address entry";
            return $ERROR;        
        }
       }
     elsif (/$IPMODE_ENTRY/)  {                  #ipv4 mode
      unless ($_[1] =~ m/(static|dynamic)/)
        {
         print " Invalid IPv4 Mode";
         return $ERROR;
        }
      if ($_[1] eq "dynamic") {
          return $IPV4_DYNAMIC_SECTION;
        }
      else {
          return $IPV4_STATIC_SECTION;
         }
      }
     elsif (/$IPV6MODE_ENTRY/)  {                  #ipv6 mode
      # if this entry is a space, then this is an IPV4 static only 
      $len = length($_[2]);   # test title
       if ($len == 0) {
        return $SPACE;
       }
      unless ($_[1] =~ m/(static|discovery)/)
        {
         print " Invalid IPv6 Mode";
         return $ERROR;
        }
      if ($_[1] eq "discovery") {
          return $IPV6_DISCOVER_SECTION;
        }
      else {
          return $IPV6_STATIC_SECTION;
         }                     
      }
     else # /$SPACE_ENTRY/                      #space
     {
      $len = length($_[2]);   # test title
      if ($len > 0)
        {
         print " Invalid Delimiter";
         return $SPACE_ERROR;
        }
      }
 }  # for 
 return $ret;
}
######################### END Subroutines ######################

################################################################
######################## MAIN FUNCTIONALITY ####################
################################################################
# Script decodes a config file which contains Records in 
# any of 6 modes,
my $line;
my $file_check;
my $array_index = 0;
my $_i = 0;
my $line_total = 0;  
my $rec_length = 0;
my $process_record_state = $SEARCH_READY;
my $hostname = "";

# take command line parameters
my $numArgs = $#ARGV + 1;
print "Arguments:\n";
foreach my $argnum (0 .. $#ARGV) {
 if ($numArgs != 3) {
    print "\nUsage: perl process_config.pl <ip address> login.txt config.txt\n";
    exit;
   }
   print "$ARGV[$argnum]\n";
}

# extract login details
unless (open (FILE, $LOGIN_FILE))
{ 
    $temp_text ="$temp_text" . "Can't open file $LOGIN_FILE\n";
    set_error_log;
    die "Error: Can't open file $LOGIN_FILE: $!\n";
}
flock(FILE, 1);               # shared lock for reading
my @array_login = <FILE>;
foreach $line (@array_login) {
 chomp ($line);  # removes \n
 $file_check = check_entry_format($TEXT_ENTRY, $line);
 if ($file_check == $ERROR)
  {
     print "ERROR in <$LOGIN_FILE>, exiting\n";
     close(FILE);
     goto label_exit;
  }
}
close(FILE);  
print "Login File Processed OK\n";

# Check command line IP address and set port
if ($ARGV[0]) 
{
  $LOGIN_FILE  = $ARGV[1];
  $CONFIG_FILE = $ARGV[2];
  chomp $ARGV[0];
  $file_check = check_entry_format($IPV4_ENTRY, $ARGV[0], "IP");
  if ($file_check == $ERROR)
  {
     print "ERROR in Ip Address entry, exiting\n";
     close(FILE);
     goto label_exit;
  }
  $ip_address_connect = "$ARGV[0]" . ":$WEBMIN_PORT";
} 

# matches entry with type for format check
my @type_array = ($HOSTNAME_ENTRY, $TEXT_ENTRY, $IPMODE_ENTRY, $IPV4_ENTRY, $IPV4_ENTRY, $IPV4_ENTRY,
                  $IPV4_ENTRY, $IPV4_ENTRY, $IPV4_ENTRY,$IPV6MODE_ENTRY, $IPV6_ENTRY, $NUMERIC_ENTRY,
                  $IPV6_ENTRY, $SPACE_ENTRY);

# MAINTAINANCE - ADD ADDITIONAL FIELDS HERE
# initialise array to max number of elements for a record in config file - currently 13
my @device_array = ( "","","","","","","","","","","","","", );

############# PARSE CONFIG FILE ##########
# Parse each line till end of file, remove trailing and make upper case\n

my @pos = (0);           # used to tell us our line position (in bytes)
my $rec_type = 0;

my $config_status_position = 0;
unless (open (CFG_FILE, "+<$CONFIG_FILE"))
{
  $temp_text ="$temp_text" . "Error: Can't open file $CONFIG_FILE\n";
  set_error_log;
  die "Error: Can't open file $CONFIG_FILE: $!\n"; # open in read/write mode
}
flock(CFG_FILE, 2);        # exclusive lock for read/write
binmode CFG_FILE;
while (<CFG_FILE>) {
      push @pos, tell(CFG_FILE); 
}
seek(CFG_FILE,0,SEEK_SET);
my @array = <CFG_FILE>;
# process each line in the config file
foreach $line (@array) {
 	chomp ($line);  # removes \n
	# split into 2 fields
	$line = lc("$line\n");
    (my $title, my $val)=split(/\s+/,$line);
if ($DEBUG) {
	#print "$_i type =$type_array{$_i}, val=$val\n";
}	
	$file_check = check_entry_format($type_array[$_i], $val, $title);
	
	if ($file_check >= $ERROR)
        {
          $line_error = $line_total + $_i + 1;
          if ($file_check == $SPACE_ERROR){
           $line_error = $line_total + $rec_length;
           }
           print "\nERROR in <$CONFIG_FILE>, Line:$line_error, exiting";
           close(CFG_FILE);
           # set config file back to ready
           if ($config_status_position){
              #set_status($config_status_position, "ready.....");
           }
           # call function to set up log file for error
           $temp_text = "ERROR in <$CONFIG_FILE>, Line:$line_error, exiting\n";
           set_error_log;
           goto label_exit;
        }
        else  # process first 'ready' entry
        { 
         if ($_i == 0)   #hostname line
         {
           $hostname = $val;
if ($DEBUG) {  # slows read to demonstrate locking by allowing manual check of status in config file
           #sleep(1);
}           
          }
         elsif ($file_check == $READY &&  $process_record_state == $SEARCH_READY) #status line shows ready record
         {
            $process_record_state = $FOUND_READY;
            $device_array[0] = $hostname;
            $device_array[$_i] = $val;
            # use  seek  to move to the line position you want to over-write
            $config_status_position = $pos[$line_total+1] + 10;
            seek(CFG_FILE,$config_status_position,SEEK_SET);
            print CFG_FILE "locked....";
          }
          if ($process_record_state == $FOUND_READY)
          {
             $device_array[$_i] = $val;
          }
          #### FIELD PROCESSING, 
         if ($file_check == $IPV4_STATIC_SECTION){
            $rec_type = $IPV4_STATIC_RECORD;
            $type_array[$IPV4_ENTRY] = $IPV4_ENTRY;       # set position back (if required) for ipv4 params
          }
          elsif ($file_check == $IPV4_DYNAMIC_SECTION){
            $rec_type = $IPV4_DYNAMIC_RECORD;
            $type_array[$IPV4_ENTRY] = $IPV6MODE_ENTRY;   # reset position for ipv6 params
          }
          elsif ($file_check == $IPV6_STATIC_SECTION){
           if ($rec_type == $IPV4_STATIC_RECORD){
               $rec_type = $IPV4_STATIC_IPV6_STATIC_RECORD;
               $rec_length = $IPV4_STATIC_IPV6_STATIC_LEN;
             }
           else {
               $rec_type = $IPV4_DYNAMIC_IPV6_STATIC_RECORD;            
               $_i = $OFFSET_DYNAMIC;
               $rec_length = $IPV4_DYNAMIC_IPV6_STATIC_LEN;
             }
          }
          elsif ($file_check == $IPV6_DISCOVER_SECTION){
           $_i = $OFFSET_IPV6;
           if ($rec_type == $IPV4_STATIC_RECORD){
               $rec_type = $IPV4_STATIC_IPV6_DISCOVER_RECORD;            
               $rec_length = $IPV4_STATIC_IPV6_DISCOVER_LEN;
              }
           else {
               $rec_type = $IPV4_DYNAMIC_IPV6_DISCOVER_RECORD;
               $rec_length = $IPV4_DYNAMIC_IPV6_DISCOVER_LEN;
              }
          }
          elsif ($file_check == $SPACE){
           $_i = $OFFSET_END;
           if ($rec_type == $IPV4_STATIC_RECORD){
                 $rec_length = $IPV4_STATIC_RECORD_LEN;
              }  
            elsif ($rec_type == $IPV4_DYNAMIC_RECORD){
               $rec_length = $IPV4_DYNAMIC_RECORD_LEN;
            }
          }     
 	  $_i += 1;
	  if ($_i >= $IPV4_STATIC_IPV6_STATIC_LEN)
	  {
	   $_i = 0;
	   $array_index += 1;
	   $line_total += $rec_length;
	   if ($process_record_state == $FOUND_READY)
	   {
	    $process_record_state = $PROCESSED_READY;  #don't process another record, but still check the file format
	   }
	  }
	}  #else
}
close(CFG_FILE);
my $num_recs = $array_index + 1;
print "Config File Processed OK. Record Entries: $num_recs\n";
if ($process_record_state ne $PROCESSED_READY)
{
  print "No Records to process\n";
  goto label_exit;
}
############# CONFIGURE DEVICE ##########
# Process the array by:
# a) establish connection to device (IP address in command line) and login for an authorised connection
# b) write config parameters (for each config file entry) and save
# c) shutdown device

my $index =  0;
print "Params:\n";
while ($index < $IPV4_STATIC_IPV6_STATIC_LEN) {
      print "-$device_array[$index]\n";
      $index +=1;
}
#  post_login_authentication($ip_address_connect, $array_login[0], $array_login[1]);
#  post_connection_manager($ip_address_connect);
#  post_hostname($device_array[$HOSTNAME], $device_array[$DNS_SERVER1], $device_array[$DNS_SERVER2], $device_array[$DNS_SERVER3]);
#  post_ipv4_network_params($device_array[$IPV4_MODE], $device_array[$IPV4_ADDRESS], $device_array[$IPV4_NETMASK], 
#                           $device_array[$IPV4_DEFGATEWAY]);
#  if ($device_array[$IPV6_MODE]) {
#    post_ipv6_network_params($device_array[$IPV6_MODE], $device_array[$IPV6_ADDRESS], 
#                             $device_array[$IPV6_NETMASK], $device_array[$IPV6_GATEWAY]);
#  }
#  post_save;
#  write_logfile_details;
#  set_status($config_status_position, "configured");
  print "Shutting Down...\n";
#  post_apply_shutdown($ip_address_connect);

label_exit:
exit;

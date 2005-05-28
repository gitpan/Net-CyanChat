#!/usr/bin/perl -w

use strict;
use warnings;

use lib "./lib";

use Net::CyanChat::Server;

# Create the server.
our $cho = new Net::CyanChat::Server (
	host  => 'localhost',
	port  => 1812,
	debug => 1,
);

# Set welcome messages.
# $cho->setWelcome ("Welcome to Net::CyanChat::Server.", "", "testing");

# Set staff protocol (we'll do 88)
$cho->setStaffProto (88);

# Connect.
$cho->connect();

# Loop.
print "CyanChat server running at " . $cho->url . ".\n\n";
$cho->start();
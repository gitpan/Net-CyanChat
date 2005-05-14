#!/usr/bin/perl -w

use strict;
use warnings;

use lib "./lib";

our $nick = '';
until (length $nick > 0) {
	print "Login to CyanChat:\n";
	print "Nick> ";
	$nick = <STDIN>;
	chomp $nick;
	print "\n\n";
}

use Net::CyanChat;

# Create a new CC connection.
my $cyan = new Net::CyanChat (proto => 1);

# Set up handlers.
$cyan->setHandler (Connected       => \&on_connected);
$cyan->setHandler (Welcome         => \&on_welcome);
$cyan->setHandler (Message         => \&on_message);
$cyan->setHandler (Private         => \&on_private);
$cyan->setHandler (Ignored         => \&on_ignored);
$cyan->setHandler (Chat_Buddy_In   => \&on_buddy_in);
$cyan->setHandler (Chat_Buddy_Out  => \&on_buddy_out);
$cyan->setHandler (Chat_Buddy_Here => \&on_buddy_here);
$cyan->setHandler (Name_Accepted   => \&on_name_accepted);
$cyan->setHandler (Error           => \&on_error);

# Connect!
print "Connecting to CyanChat...\n";
$cyan->connect();

# Loop.
while (1) {
	$cyan->do_one_loop();
}

sub on_connected {
	my $self = shift;

	print "Connection established! Signing in as $nick\n\n";

	# Authenticate!
	$self->login ($nick);
}

sub on_welcome {
	my ($self,$msg) = @_;

	print "[ChatServer] $msg\n";
}

sub on_message {
	my ($self,$nick,$level,$addr,$msg) = @_;

	print "[$nick] $msg\n";
}

sub on_private {
	my ($self,$nick,$level,$addr,$msg) = @_;

	print "Private: [$nick] $msg\n";

	# Commands.
	if ($msg =~ /^exit/i) {
		$self->sendMessage ("g2g");
		sleep(2);
		$self->sendMessage ("Shorah!");
		sleep(1);
		$self->logout();
	}
}

sub on_ignored {
	my ($self,$ignore,$user) = @_;

	if ($ignore == 1) {
		print "[ChatClient] Now ignoring messages from $user\n";
	}
	else {
		print "[ChatClient] $user is no longer being ignored.\n";
	}
}

sub on_buddy_in {
	my ($self,$nick,$level,$addr,$msg) = @_;

	print "[$nick] $msg\n";
}

sub on_buddy_out {
	my ($self,$nick,$level,$addr,$msg) = @_;

	print "[$nick] $msg\n";
}

sub on_buddy_here {
	my ($self,$nick,$level,$addr) = @_;

	print "$nick is in the room.\n";
}

sub on_name_accepted {
	my ($self) = @_;

	print "[ChatServer] Name accepted; now logged in.\n";

	# Wait a bit and say hi.
	sleep (5);
	$self->sendMessage ("Shorah everyone!");
}

sub on_error {
	my ($self,$code,$string) = @_;

	print "[ChatServer] Error $code: $string\n";
}
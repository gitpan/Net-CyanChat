package Net::CyanChat::Server;

use strict;
use warnings;
use IO::Socket;
use IO::Select;

our $VERSION = '0.01';

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;

	my $self = {
		host       => 'localhost',
		port       => 1812,
		staffproto => undef,
		sock       => undef,
		select     => undef,
		welcome    => [
			"Welcome to Net::CyanChat::Server v. $VERSION",
			"",
			"There are only a few simple rules:",
			"    1. Be respectful to other users.",
			"    2. Keep the dialog \"G\" rated.",
			"    3. And HAVE FUN!",
			"",
			"Termination of use can happen without warning!",
		],
		conn       => {},
		who        => {},
		@_,
	};

	bless ($self,$class);
	return $self;
}

sub version {
	my ($self) = @_;
	return $VERSION;
}

sub debug {
	my ($self,$msg) = @_;

	return unless $self->{debug} == 1;
	print "Net::CyanChat::debug // $msg\n";
}

sub connect {
	my ($self) = @_;

	# Create the socket.
	$self->{sock} = IO::Socket::INET->new (
		LocalAddr => $self->{host},
		LocalPort => $self->{port},
		Listen    => 1,
		Reuse     => 1,
	) or die "Socket error: $!";

	# Create a select object.
	$self->{select} = IO::Select->new ($self->{sock});
}

sub start {
	my ($self) = @_;
	while (1) {
		$self->do_one_loop();
	}
}

sub reply {
	my ($self,$socket,$msg) = @_;

	# Send the message.
	print "S: $msg\n";
	$socket->send ("$msg\n") or do {
		# He's been disconnected.
		my $id = $socket->fileno;
		if ($self->{conn}->{$id}->{login}) {
			# Remove him.
			my $user = $self->{conn}->{$id}->{username};
			delete $self->{who}->{$user};
			delete $self->{conn}->{$id};

			# Broadcast it.
			$self->broadcast ("31|$user|^3<mistakenly used an unsafe Linking Book without a maintainer's suit *ZZZZZWHAP*>");
			$self->sendWhoList();
		}

		$self->{select}->remove ($socket);
		$socket->close();
	}
}

sub do_one_loop {
	my ($self) = @_;

	# Look for events.
	my @ready = $self->{select}->can_read(.1);
	return unless(@ready);

	# Go through each event.
	foreach my $socket (@ready) {
		# If the listening socket is ready, accept a new connection.
		if ($socket == $self->{sock}) {
			my $new = $self->{sock}->accept();
			$self->{select}->add ($new);
			print $new->fileno . ": connected\n";

			# Setup data for this connection.
			my $nid = $new->fileno;
			$self->{conn}->{$nid} = {
				level    => 0,
				announce => 0,
				nickname => undef,
				username => undef,
				login    => 0,
			};

			# Send a 35.
			my @memlist = ();
			foreach my $member (keys %{$self->{who}}) {
				my $addr = $self->{who}->{$member};
				push (@memlist,"$member,$addr");
			}
			my $mems = join ('|', @memlist);
			$self->reply ($new,"35|$mems");
		}
		else {
			# Get their ID.
			my $id = $socket->fileno;

			# Read their request.
			my $line = '';
			$socket->recv ($line, 2048);
			chomp $line;

			# Skip if this line is blank.
			next if $line eq "";

			# Go through the events.
			my ($cmd,@args) = split(/\|/, $line);

			print "C $id: $line\n";

			if ($cmd == 10) {
				# 10 = Sending their name.
				if ($self->{conn}->{$id}->{announce}) {
					my $nick = $args[0];
					if (!defined $nick) {
						# No nick defined.
						$self->reply ($socket,"21|3ChatServer|^1No nickname was defined!");
					}
					else {
						# Format their username.
						my $user = join ("", $self->{conn}->{$id}->{level}, $nick);

						# Valid nick?
						if (length $nick <= 20 && $nick !~ /\|/) {
							# See if the nick isn't already logged on.
							if (exists $self->{who}->{$user}) {
								$self->reply ($socket,"21|3ChatServer|^1The nickname is already in use.");
							}
							else {
								# Setting another name?
								if (length $self->{conn}->{$id}->{username} > 0) {
									# Remove the old.
									my $old = $self->{conn}->{$id}->{username};
									delete $self->{who}->{$old};
								}

								# Join them.
								$self->{who}->{$user} = $socket->peerhost;
								$self->{conn}->{$id}->{username} = $user;
								$self->{conn}->{$id}->{nickname} = $nick;
								$self->{conn}->{$id}->{login} = 1;
								$self->reply ($socket,"11"); # 11 = name accepted
								$self->broadcast ("31|$user|^2<links in from " . $socket->peerhost . " Age>");

								# Update the Who List.
								$self->sendWhoList();
							}
						}
						else {
							# Invalid nick.
							$self->reply ($socket,"10"); # 10 = name invalid
						}
					}
				}
			}
			elsif ($cmd == 15) {
				# 15 = Remove their name (sign out).
				if ($self->{conn}->{$id}->{login}) {
					# Exit them.
					my $nick = $self->{conn}->{$id}->{username};
					$self->{conn}->{$id}->{username} = undef;
					$self->{conn}->{$id}->{nickname} = undef;
					$self->{conn}->{$id}->{login} = 0;
					delete $self->{who}->{$nick};
					$self->broadcast ("31|$nick|^3<links safely back to their home Age>");
					$self->sendWhoList();
				}
			}
			elsif ($cmd == 20) {
				# 20 = send private message.
				if ($self->{conn}->{$id}->{login}) {
					my $to = $args[0];
					my $msg = $args[1];

					if ($to && $msg) {
						# Send to this user's socket.
						my $recipient = $self->getSocket ($to);
						$self->reply ($recipient,"21|$to|$msg");
					}
				}
			}
			elsif ($cmd == 30) {
				# 30 = send public message.
				if ($self->{conn}->{$id}->{login}) {
					$self->broadcast ("31|$self->{conn}->{$id}->{username}|$args[0]");
				}
			}
			elsif ($cmd == 40) {
				# 40 = client ready.
				my $proto = $args[0];
				$proto = 0 unless length $proto > 0;

				# Client is ready now.
				$self->{conn}->{$id}->{announce} = 1;
				my @welcome = reverse (@{$self->{welcome}});
				foreach my $send (@welcome) {
					$self->reply ($socket,"40|1$send");
				}
			}
			elsif ($cmd == 70) {
				# 70 = ignore user
				my $target = $args[0];
				if (length $target > 0) {
					# Send mutual ignore to this user's client.
					my $recipient = $self->getSocket ($target);
					$self->reply ($recipient,"70|$self->{conn}->{$id}->{username}");
				}
			}
			elsif (defined $self->{staffproto} && $cmd == $self->{staffproto}) {
				# Staff Proto = identify this connection as staff.
				$self->{conn}->{$id}->{level} = 1;
			}
			else {
				# Unknown command.
				if ($self->{conn}->{$id}->{login}) {
					$self->reply ($socket,"21|3ChatClient|^1Command not implemented.");
				}
			}
		}
	}
}

sub setWelcome {
	my ($self,@msgs) = @_;

	# Keep these messages.
	return unless @msgs;

	$self->{welcome} = [ @msgs ];

	return 1;
}

sub setStaffProto {
	my ($self,$proto) = @_;

	# Protocol number must be greater than 70.
	if ($proto > 70) {
		# Save this.
		$self->{staffproto} = $proto;
		return 1;
	}

	warn "Error: bad Staff Protocol! Must be greater than 70";
	return 0;
}

sub url {
	my ($self) = @_;

	return join (':', $self->{host}, $self->{port});
}

sub sendWhoList {
	my ($self) = @_;

	# Get the Who List.
	my @memlist = ();
	foreach my $member (keys %{$self->{who}}) {
		my $addr = $self->{who}->{$member};
		push (@memlist,"$member,$addr");
	}
	my $list = join ('|', @memlist);

	# Send the Who List to all connections.
	foreach my $socket ($self->{select}->handles) {
		next if ($socket == $self->{sock});

		# Send the 35.
		$self->reply ($socket,"35|$list");
	}

	return 1;
}

sub getSocket {
	my ($self,$handle) = @_;

	# Find this handle's socket.
	foreach my $socket ($self->{select}->handles) {
		my $id = $socket->fileno;
		if (exists $self->{conn}->{$id}->{username}) {
			if ($handle eq $self->{conn}->{$id}->{username}) {
				return $socket;
			}
		}
	}

	return undef;
}

sub broadcast {
	my ($self,$data) = @_;

	# Find this handle's socket.
	foreach my $socket ($self->{select}->handles) {
		my $id = $socket->fileno;
		if ($self->{conn}->{$id}->{login}) {
			# Send it.
			$self->reply ($socket,$data);
		}
	}
}

1;
__END__

=head1 NAME

Net::CyanChat::Server - Perl interface for running a CyanChat server.

=head1 SYNOPSIS

  use Net::CyanChat::Server;
  
  our $cho = new Net::CyanChat::Server (
          host  => 'localhost',
          port  => 1812,
          debug => 1,
  );
  
  # Start the server.
  $cho->connect();
  
  # Loop.
  $cho->start();

=head1 DESCRIPTION

Net::CyanChat::Server is a Perl interface for running your own CyanChat server (or, rather,
to run a chat server based on the CyanChat protocol that other CC clients would recognize).

=head1 METHODS

=head2 new (ARGUMENTS)

Constructor for a new CyanChat server. Pass in the host, port, and debug. All are optional.
host defaults to localhost, port defaults to 1812, debug defaults to 0. With debug on, all
the server/client conversation is printed.

Returns a CyanChat server object.

=head2 version

Returns the version number.

=head2 debug (MESSAGE)

Called by the module itself for debug messages.

=head2 connect

Connect to CyanChat's server.

=head2 start

Start a loop of do_one_loop's.

=head2 do_one_loop

Perform a single loop on the server.

=head2 setWelcome (MESSAGE_1, MESSAGE_2, ETC)

Set the Welcome Messages that are displayed when a user connects to the chat. The default messages are:

  Welcome to Net::CyanChat::Server v. <VERSION>
  
  There are only a few simple rules:
       1. Be respectful to other users.
       2. Keep the dialog "G" rated.
       3. And HAVE FUN!
  
  Termination of use can happen without warning!

=head2 setStaffProto (NUMBER)

Define a client-to-server protocol command to identify the connection as a Staff. The number must be
greater than 70. If a connecting client uses this NUMBER before signing into chat, the server will
recognize it as a staff member and, upon signin, will give it a cyan name.

=head2 url

Returns the host/port to your CyanChat server (i.e. "localhost:1812")

=head2 reply (SOCKET, DATA)

Send data to the specified SOCKET.

=head2 getSocket (USERNAME)

Get the socket of a username signed into the chat room.

=head2 broadcast (DATA)

Broadcasts commands to all logged-in users.

=head2 sendWhoList

Sends the Who List to all users. This should be called when a user joins or exits the
room.

=head1 CHANGE LOG

Version 0.01

  - Initial release.

=head1 TO DO

  - Add support for administrators ("Cyan Staff") to join the room.
  - Add support for built in profanity filters and bans.
  - Add IP encryption algorythm similar to Cyan's.
  - Display user's ISP as their home Age, rather than their IP address.

=head1 SEE ALSO

Net::CyanChat

CyanChat Protocol Documentation: http://cho.cyan.com/chat/programmers.html

=head1 AUTHOR

Cerone J. Kirsle <cjk "@" aichaos.com>

=head1 COPYRIGHT AND LICENSE

    Net::CyanChat - Perl interface to CyanChat.
    Copyright (C) 2005  Cerone J. Kirsle

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program; if not, write to the Free Software
    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

=cut

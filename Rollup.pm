package HTTP::Rollup;

require 5.005;

use strict;
use CGI::Util qw( unescape );
use vars qw($VERSION);

$VERSION = '0.2';

=head1 NAME

HTTP::Rollup - translate an HTTP query string to a hierarchal structure

=head1 SYNOPSIS

 my $hashref = HTTP::Rollup::RollupQueryString($query_string);

 my $hashref = HTTP::Rollup::RollupQueryString($query_string,
                                              { FORCE_LIST => 1 });

=head1 DESCRIPTION

Given input text of the format:

  employee.name.first=Jane
  employee.name.last=Smith
  employee.address=123%20Main%20St.
  employee.city=New%20York
  id=444
  phone=(212)123-4567
  phone=(212)555-1212
  @fax=(212)999-8877

Construct an output data structure like this:

  $hashref = {
    $employee => {
		  name => {
			   "first" => "Jane",
			   "last" => "Smith",
			  },
		  address => "123 Main St.",
		  city => "New York"
		 },
    $phone => [
	       "(212)123-4567",
	       "(212)555-1212"
	      ],
    $fax => [
	     "(212)999-8877"
	    ],
    $id => 444
  };

This is intended as a drop-in replacement for the HTTP query string
parsing implemented in CGI.pm.  CGI.pm constructs purely flat structures,
e.g. with the above example:

  $hashref = {
    "employee.name.first" => [ "Jason" ],
    "employee.name.last" => [ "Smith" ],
    "employee.name.address" => [ "123 Main St." ],
    "employee.name.city" => [ "New York" ],
    "phone" => [ "(212)123-4567", "(212)555-1212" ],
    "@fax"=> [ "(212)999-8877" ],
    "id" => [ 444 ]
  };

The FORCE_LIST switch causes CGI.pm-style behavior, as above,
for backward compatibility.

=head1 FEATURES

=over

=item *

Data nesting using dot notation

=item *

Recognizes a list if there is more than one value with the same name

=item *

Lists can be forced with a leading @-sign, to allow for lists that could
have just one element (eliminating ambiguity between scalar and single-
element list).  The @ will be stripped.

=back

=begin testing

use lib "./blib/lib";
use HTTP::Rollup;
use Data::Dumper;

my $string = <<_END_;
employee.name.first=Jane
employee.name.last=Smith
employee.address=123%20Main%20St.
employee.city=New%20York
id=444
phone=(212)123-4567
phone=(212)555-1212
\@fax=(212)999-8877
_END_

my $hashref = HTTP::Rollup::RollupQueryString($string);
ok($hashref->{employee}->{name}->{first} eq "Jane",
   "2-nested scalar");
ok($hashref->{employee}->{city} eq "New York",
   "1-nested scalar, with unescape");
ok($hashref->{id} eq "444",
   "top-level scalar");
ok($hashref->{phone}->[1] eq "(212)555-1212",
   "auto-list");
ok($hashref->{fax}->[0] eq "(212)999-8877",
   "\@-list");

my $string2 = "employee.name.first=Jane&employee.name.last=Smith&employee.address=123%20Main%20St.&employee.city=New%York&id=444&phone=(212)123-4567&phone=(212)555-1212&\@fax=(212)999-8877";

$hashref = HTTP::Rollup::RollupQueryString($string2);
ok($hashref->{employee}->{name}->{first} eq "Jane",
   "nested scalar");
ok($hashref->{id} eq "444",
   "top-level scalar");
ok($hashref->{phone}->[1] eq "(212)555-1212",
   "auto-list");
ok($hashref->{fax}->[0] eq "(212)999-8877",
   "\@-list");

my $hashref2 = HTTP::Rollup::RollupQueryString($string, { FORCE_LIST => 1 });
ok($hashref2->{'employee.name.first'}->[0] eq "Jane",
   "nested scalar");
ok($hashref2->{id}->[0] eq "444",
   "top-level scalar");
ok($hashref2->{phone}->[1] eq "(212)555-1212",
   "auto-list");
ok($hashref2->{'@fax'}->[0] eq "(212)999-8877",
   "\@-list");

=end testing

=cut

sub RollupQueryString {
    my ($input, $config) = @_;

    my $root = {};

    return $root if !$input;

    # query strings are name-value pairs delimited by & or by newline
    foreach my $nvp (split(/[\n&]/, $input)) {
	last if $nvp eq "=";	# sometimes appears as query string terminator

      PARSE:
	my ($name, $value) = split /=/, $nvp;
	my @levels = split /\./, $name;
	$value = CGI::Util::unescape($value);

	if ($config->{FORCE_LIST}) {
	    # always use a list, for CGI.pm-style behavior
	    if (ref $root->{$name}) {
		# there's already a list there
		push @{$root->{$name}}, $value;
	    } else {
		$root->{$name} = [ $value ];
	    }
	    next;
	}

      TRAVERSE:
	my $node = $root;
	my $leaf;
	for ($leaf = shift @levels;
	     scalar(@levels) >= 1;
	     $leaf = shift @levels) {
	    $node->{$leaf} = {}
	      unless defined $node->{$leaf};	# vivify
	    $node = $node->{$leaf};
	}

      SAVE:
	if (ref $node->{$leaf}) {
	    # there's already a list there
	    $leaf =~ s/^@//;
	    push @{$node->{$leaf}}, $value;
	} elsif (defined $node->{$leaf}) {
	    # scalar now, convert to a list
	    $node->{$leaf} = [ $node->{$leaf}, $value ];
	} elsif ($leaf =~ /^\@/) {
	    # leading @ forces list
	    $leaf =~ s/^@//;
	    $node->{$leaf} = [ $value ];
	} else {
	    $node->{$leaf} = $value;
	}
    }

    return $root;
}

1;

=head1 AUTHOR

Jason W. May <jmay@pobox.com>

=head1 COPYRIGHT

Copyright (C) 2002 Jason W. May.  All rights reserved.
This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut

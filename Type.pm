package Hash::Type;

use strict;
use warnings;
use Carp;

our $VERSION = "1.09";

=head1 NAME

Hash::Type - pseudo-hashes as arrays tied to a "type" (list of fields)

=head1 SYNOPSIS

  use Hash::Type;

  # create a Hash::Type
  my $personType = new Hash::Type(qw(firstname lastname city));

  # create and populate some hashes tied to $personType
  tie %wolfgang, $personType, "wolfgang amadeus", "mozart", "salzburg";
  $ludwig = new $personType ("ludwig", "van beethoven", "vienna");
  $jsb = new $personType;
  $jsb->{city} = "leipzig";
  @{$jsb}{qw(firstname lastname)} = ("johann sebastian", "bach");

  # add fields dynamically
  $personType->add("birth", "death") or die "fields not added";
  $wolfgang{birth} = 1750;

  # More complete example : read a flat file with headers on first line
  my ($headerline, @datalines) = map {chomp; $_} <F>;
  my $ht = new Hash::Type(split /\t/, $headerline);
  foreach my $line (@datalines) {
    my $data = new $ht(split /\t/, $line);
    work_with($data->{someField}, $data->{someOtherField});
  }

  # an alternative to Time::gmtime and Time::localtime
  my $timeType = new Hash::Type qw(sec min hour mday mon year wday yday);
  my $localtime = new $timeType (localtime);
  my $gmtime = new $timeType (gmtime);
  print $localtime->{hour} - $gmtime->{hour}, " hours difference to GMT";

  # comparison functions
  my $byAge = $personType->cmp("birth : -num, lastname, firstname");
  my $byNameLength = $personType->cmp(lastname => {length($b) <=> length($a)},
                                      lastname => 'alpha', 
                                      firstname => 'alpha');
  showPerson($_) foreach (sort $byAge @people);
  showPerson($_) foreach (sort $byNameLength @people);

  # special comparisons : dates
  my $US_DateCmp        = $myHashType->cmp("someDateField : m/d/y");
  my $FR_InverseDateCmp = $myHashType->cmp("someDateField : -d.m.y");

=head1 DESCRIPTION

A Hash::Type is a collection of field names.
Internally, an index is associated with each name.
Such collections are created dynamically and can be extended.
They are used to build tied hashes, either through C<tie>
or through object-oriented method calls; such tied hashes :

=over

=item * 

are 'restricted' (will only accept operations on names previously 
declared in their Hash::Type)

=item * 

are implemented internally as arrays (so they use less memory)

=item * 

can be sorted efficiently through comparison functions generated
and compiled by the class

=back

The 'pseudo-hashes' in core Perl were very similar, but they 
are deprecated starting from Perl 5.8.0. More on comparison
with other packages in section L</"SEE ALSO">

=head1 METHODS

=over

=item C<$myType = new Hash::Type(@names)> 

Creates a new object which holds a collection of names and associated indices
(technically, this is a hash reference blessed in package Hash::Type). 
This object can then be used to generate tied hashes.
The list of C<@names> is optional ; names can be added later through
method C<add>.


=item C<$h = new $myType(@vals)>

Creates a new tied hash associated to package Hash::Type and 
containing a reference to $myType (technically, this is an array 
reference, tied to package Hash::Type). 

The other way to create a tied hash is through the C<tie> syntax  :

  tie %h, $myType, @vals;

Access to C<$h{name}> is equivalent to writing 

  tied(%h)->[$myType->{name}]

C<$h{'Hash::Type'}> is a special, predefined name that  gives back the object
to which this hash is tied (you may need it for example to generate a 
comparison function, see below).

The operation C<delete $h{name}> is forbidden.
To delete a value, you have to go to the underlying array :

  delete tied(%h)->[$myType->{name}];

=cut


sub new { 
  my $class = shift;

  if (ref($class)) { # $class is an object, create a new tied hash from it
    my %h;
    tie %h, $class , @_;
    return \%h;
  }
  else { # create a new  Hash::Type object
    my $self = {};
    CORE::bless $self, $class;
    $self->add(@_);  # add indices for fields given in @_
    return $self;
  }
}


# tied hash implementation

sub TIEHASH  { CORE::bless [@_] }
sub STORE    { my $ix = $_[0]->[0]{$_[1]} or 
		 croak "can't STORE, key '$_[1]' was never added to this Hash::Type";
	       $_[0]->[$ix] = $_[2]; }

# FETCH : must be an lvalue because may be used in $h{field} =~ s/.../../;
# And since lvalues cannot use "return" (cf. L<perlsub>), we
# must write intricate ternary ifs -- not nice to read !

sub FETCH : lvalue { 
  my $ix = $_[0]->[0]{$_[1]};
  $_[1] eq 'Hash::Type' ? $_[0]->[0] 
                        : $ix ? $_[0]->[$ix]
                              : undef;
}

sub FIRSTKEY { my $a = scalar keys %{$_[0]->[0]}; each %{$_[0]->[0]} }
sub NEXTKEY  { each %{$_[0]->[0]} }
sub EXISTS   { exists $_[0]->[0]{$_[1]} }
sub DELETE   { croak "DELETE forbidden on hash tied to " . __PACKAGE__; }
sub CLEAR    { delete @{$_[0]}[1 .. $#{$_[0]}] }



=item C<$myType-E<gt>add(@newNames)>

Adds @newNames in $myType and gives them new indices. 
Does nothing for names that were already present.
Returns the number of names actually added.

You can also dynamically remove names by writing
C<delete $myType-E<gt>{name}> ; however, this merely
masks access to {name} for all hashes tied to $myType, 
so the values are still present in the underlying arrays and 
you will not gain any memory by doing this.

After deleting C<{name}>, you can again call 
C<$myType-E<gt>add('name')>, but this will allocate a new index, 
and not recover the previous one allocated to that key.


=cut

sub add {
  my $self = shift;

  # find the highed current index (cannot just take scalar(keys %$self)
  # because some keys might have been deleted in the meantime
  my $max = 0; 
  foreach (values %$self) { $max = $_ if $_ > $max; }

  my $ix = $max;
  foreach (@_) { $self->{$_} = ++$ix unless  exists $self->{$_}; }
  return $ix - $max;
}



=item C<$myType-E<gt>names>

Returns the list of defined names, in index order 
(which might be different from (keys %$myType)).

=cut

sub names { sort {$_[0]->{$a} <=> $_[0]->{$b} } keys %{$_[0]} }


=item C<$cmp = $myType-E<gt>cmp("f1 : cmp1, f2 : cmp2 , ...")>

Returns a reference to an anonymous sub which successively compares
the given field names, applying the given operators, 
and returns a positive, negative or zero value.
This sub can then be fed to C<sort>. 'f1', 'f2', etc are field names,
'cmp1', 'cmp2' are comparison operators written as :

  [+|-] [alpha|num|cmp|<=>|d.m.y|d/m/y|y-m-d|...]

The sign is '+' for ascending order, '-' for descending; default is '+'.
Operator 'alpha' is synonym to 'cmp' and 'num' is synonym to '<=>';
operators 'd.m.y', 'd/m/y', etc. are for dates in various
formats; default is 'alpha'. 

If all you want is alphabetic ascending order, 
just write the field names :

  $cmp = $personType->cmp('lastname', 'firstname');

B<Note> : C<sort> will not accept something like

  sort $personType->cmp('lastname', 'firstname') @people;

so you I<have to> store it in a variable first :

  my $cmp = $personType->cmp('lastname', 'firstname');
  sort $cmp @people;

For date comparisons, values are parsed into day/month/year, according
to the shape specified (for example 'd.m.y') will take '.' as
a separator. Day, month or year need not be several digits, 
so '1.1.1' will be interpreted as '01.01.2001'. Years of 2 or 1 digits 
are mapped to 2000 or 1900, with pivot at 33 (so 32 becomes 2032 and
33 becomes 1933).

=item C<$cmp = $myType-E<gt>cmp(f1 =E<gt> cmp1, f2 =E<gt> cmp2, ...)>

This second syntax, with pairs of field names and operators,
is a bit more verbose but gives you more flexibility, 
as you can write your own 
comparison functions using C<$a> and C<$b> :

  my $byNameLength = $personType->cmp(lastname => {length($b) <=> length($a)},
                                      lastname => 'alpha', 
                                      firstname => 'alpha');

B<Note> : the resulting closure is bound to 
special variables C<$a> and <$b>. Since those
are different in each package, you cannot
pass the comparison function to another 
package : the call to C<sort> has to be done here.



=back 

=cut

sub cmp {
  my $self = shift;

  croak "cmp : no cmp args" if not @_;

  if (@_ == 1) { # first syntax, all in one string
    my @fields = split /,/, shift;
    foreach (@fields) {
      m[^\s*(\S.*?)\s*(?::([^:]+))?$] or croak "bad cmp op : $_";
      push @_, $1, $2; # feed back to @_ as arguments to second syntax
    }
  }

  # $a and $b are different in each package, so must refer to the caller's
  my $caller = caller;
  my ($a, $b) = ("\$${caller}::a", "\$${caller}::b");

  my @cmp;        # holds code for each comparison to perform
  my @callerSub;  # references to comparison subs given by caller
                  # (must copy them from @_ into a lexical in order to 
                  #  build a proper closure)
  my $regex;      # used only for date comparisons, see below

  for (my $i = 0; $i < @_; $i += 2) {
    my $ix = $self->{$_[$i]} or croak "can't do cmp on absent field : $_[$i]";

    if (ref $_[$i+1] eq 'CODE') { # ref. to cmp function supplied by caller
      push @callerSub, $_[$i+1];
      push @cmp, "do {local ($a, $b) = (tied(%$a)->[$ix], tied(%$b)->[$ix]);".
	             "&{\$callerSub[$#callerSub]}}";
    }
    else { # builtin comparison operator
      my ($sign, $op) = ("", "cmp");
      my $str;
      if (defined $_[$i+1]) {
	($sign, $op) = ($_[$i+1] =~ /^\s*([-+]?)\s*(.+)/);
      }

      for ($op) {
	/^(alpha|cmp)\s*$/   and do {$str = "%s cmp %s"; last};
	/^(num|<=>)\s*$/     and do {$str = "%s <=> %s"; last};
	/^d(\W+)m(\W+)y\s*$/ and do {$regex=qr{(\d+)\Q$1\E(\d+)\Q$2\E(\d+)};
				     $str = "_dateCmp(\$regex, 0, 1, 2, %s, %s)";
				     last};
	/^m(\W+)d(\W+)y\s*$/ and do {$regex=qr{(\d+)\Q$1\E(\d+)\Q$2\E(\d+)};
				     $str = "_dateCmp(\$regex, 1, 0, 2, %s, %s)";
				     last};
	/^y(\W+)m(\W+)d\s*$/ and do {$regex=qr{(\d+)\Q$1\E(\d+)\Q$2\E(\d+)};
				     $str = "_dateCmp(\$regex, 2, 1, 0, %s, %s)";
				     last};
	croak "bad operator for Hash::Type::cmp : $_[$i+1]";
      }
      $str = sprintf("$sign($str)", "tied(%$a)->[$ix]", "tied(%$b)->[$ix]");
      push @cmp, $str;
    }
  }

  local $@;
  my $sub = eval "sub {" . join(" || ", @cmp) . "}"
    or croak $@;
  return $sub;
}


sub _dateCmp {
  my ($regex, $d, $m, $y, $date1, $date2) = @_;

  return 0 if not $date1 and not $date2;
  return 1 if not $date1;	# null date treated as bigger than any other
  return -1 if not $date2;

  for my $date ($date1, $date2) {
    $date =~ s[<.*?>][]g; # remove any markup
    $date =~ tr/{}[]()//d;  # remove any {}[]() chars
  }; 

  my @d1 = ($date1 =~ $regex) or croak "invalid date '$date1' for regex $regex";
  my @d2 = ($date2 =~ $regex) or croak "invalid date '$date2' for regex $regex";

  $d1[$y] += ($d1[$y] < 33) ? 2000 : 1900 if $d1[$y] < 100;
  $d2[$y] += ($d2[$y] < 33) ? 2000 : 1900 if $d2[$y] < 100;

  return ($d1[$y]<=>$d2[$y]) || ($d1[$m]<=>$d2[$m]) || ($d1[$d]<=>$d2[$d]);
}


=head1 CAVEATS

The implementation of 'each', 'keys', 'values' on tied hashes
calls corresponding operations on the Hash::Type object ; 
therefore, nested 'each' on several tied hashes won't work.

=head1 SEE ALSO

The 'pseudo-hashes' documented in L<perlref> are very similar, 
but are deprecated starting from Perl 5.8.0. 
Each pseudo-hash holds its own copy of key names in position 0 
of the underlying array, whereas hashes tied to C<Hash::Type> 
hold a reference to a shared collection of keys.

Typed references together with the C<use fields> pragma
provide support for compile-time translation of key names
to array indices; see L<fields>. This will be faster, but will
not help if field names are only known at runtime (like
in the flat file parsing example of the synopsis). 

For other ways to restrict the keys of a hash to a fixed set, see
L<Hash::Util/lock_keys>, L<Tie::Hash::FixedKeys>, L<Tie::StrictHash>.

The L<Sort::Fields> module in CPAN uses similar techniques for 
dynamically building sorting criterias according to field
positions; but it is intended for numbered fields, not
for named fields, and has no support for caller-supplied
comparison operators. The design is also a bit different :
C<fieldsort> does everything at once (splitting, comparing
and sorting), whereas C<Hash::Type::cmp> only compares, and
leaves it to the caller to do the rest.

C<Hash::Type> was primarily designed as a core element
for implementing rows of data in L<File::Tabular>.

=head1 AUTHOR

Laurent Dami, E<lt>laurent.dami AT etat  geneve  chE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2005 by Laurent Dami.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut

1;


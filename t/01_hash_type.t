use strict;
use warnings;
use Test::More;

BEGIN {use_ok("Hash::Type");}

# create a new hash type
my $personType = Hash::Type->new(qw(firstname lastname city));

isa_ok($personType, 'Hash::Type');

# there is more than one way to create tied hashes 

# 1) use the tie syntax, with initial values
my %wolfgang;
tie %wolfgang, $personType, "wolfgang amadeus", "mozart", "salzburg";

isa_ok(tied(%wolfgang), 'Hash::Type');
isa_ok(\%wolfgang, 'HASH');

is($wolfgang{firstname}, "wolfgang amadeus", "wolfgang firstname");
is($wolfgang{lastname}, "mozart", "wolfgang lastname");


# 2) use object-oriented syntax
my $ludwig = $personType->new("ludwig", "van beethoven", "vienna");

isa_ok($ludwig, 'HASH');

is($ludwig->{city}, "vienna", "ludwig city");

is(tied(%wolfgang)->[2], "mozart", "tied wolfgang 2");
is(tied(%$ludwig)->[1], "ludwig", "tied ludwig 1");


# 3) create an empty tied hash and fill the values later
my $jsb = $personType->new;
$jsb->{city} = "leipzig";
@{$jsb}{qw(firstname lastname)} = ("johann sebastian", "bach");

isa_ok($jsb, 'HASH');
ok(eq_hash($jsb, {firstname => "johann sebastian",
		  lastname => "bach",
		  city => "leipzig"}), "jsb values");

# dynamically add field names to a hash type; applies to all tied hashes
is($personType->add("lastname", "birth", "death", "birth"), 2, "2 new names");




# instanciate
my @organists = $personType->instantiate($jsb, 
                                         ["Johann Jakob", "Froberger", "Stuttgart", 1616],
                                         {firstname => 'Girolamo', lastname => 'Frescobaldi', birth => 1583});
is_deeply [map {$_->{lastname}} @organists], [qw/bach Froberger Frescobaldi/], 'instanciate';



#test the 'names' method
ok(eq_array([$personType->names],
	    [qw(firstname lastname city birth death)]), "proper method 'names'");

# keys on the tied hash
ok(eq_array([keys %wolfgang],
	    [qw(firstname lastname city birth death)]), "keys on tied hash");


# test the 'values' method
ok(eq_array([$personType->values(\%wolfgang)],
	    ["wolfgang amadeus", "mozart", "salzburg", undef, undef]),
   "values method");


# values on the tied hash
ok(eq_array([values %wolfgang],
	    ["wolfgang amadeus", "mozart", "salzburg", undef, undef]),
   "values on tied hash");

# test the 'each' method
my $iter = $personType->each(\%wolfgang);
my @list1;
while (my ($k, $v) = $iter->()) {
  no warnings 'uninitialized';
  push @list1, "$k: $v";
}
my @list2;
while (my ($k, $v) = each %wolfgang) {
  no warnings 'uninitialized';
  push @list2, "$k: $v";
}
is_deeply(\@list1, \@list2, "'each' method");


$wolfgang{birth} = 1750;
is($personType->{birth}, 4, "added field");
is($wolfgang{birth}, 1750, "wolfgang birth");

$ludwig->{birth} =  1770;
$jsb->{birth} = 1685;

# does this type have this field name ?
ok(not (exists $ludwig->{foobar}), "not exists foobar (instance)");
ok(not (exists $wolfgang{foobar}), "not exists foobar (instance2)");
ok(not (exists $personType->{foobar}), "not exists foobar (type)");
ok(exists $ludwig->{city}, "ludwig exists city");
ok(exists $wolfgang{city}, "wolfgang exists city");


# get back the Hash::Type object from which a tied hash was created
is ($ludwig->{'Hash::Type'}, $personType, "get back hash::type");

# but this is a readonly key
eval {$ludwig->{'Hash::Type'} = "foobar";};
ok($@, "setting ->{'Hash::Type'} is forbidden : $@");


# B) replace Time::gmtime and Time::localtime
my $timeType  = Hash::Type->new(qw(sec min hour mday mon year wday yday));
my $localtime = $timeType->new(localtime);
my $gmtime    = $timeType->new(gmtime);
my $diff = $localtime->{hour} - $gmtime->{hour};
ok("$diff hours difference to GMT");


# lines below break (intentionally)
eval {$jsb->{sons} = "johann-christian et al.";};
ok($@, "die on wrong fields : $@");


eval {$jsb->add('sons');};
ok($@, "die on calling 'add' on a tied hash: $@");




# comparison functions

no warnings 'uninitialized';

my @people = (\%wolfgang, $ludwig, $jsb,
	      $personType->new(qw(claudio monteverdi mantova 1567)));

my $byAge = $personType->cmp("birth : -num, lastname, firstname");

isa_ok($byAge, 'CODE', "byAge");

ok(eq_array([map {$_->{birth}} sort $byAge @people],
	    [1770, 1750, 1685, 1567]), "sort byAge");


my $byNameLength = $personType->cmp(lastname => sub {length($b) <=> length($a)},
	                            lastname => 'alpha', 
                                    firstname => 'alpha');
isa_ok($byAge, 'CODE', "byNameLength");

ok(eq_array([map {$_->{lastname}} sort $byNameLength @people],
	    ["van beethoven", "monteverdi", "mozart", "bach"]), 
   "sort byNameLength");



# test the CLEAR function
%wolfgang = ();
is(keys %wolfgang, 5, 'values cleared, keys still there');
is($wolfgang{lastname}, undef, 'wolfgang array is cleared');


# test the DELETE function
eval {delete $jsb->{city};};
ok($@, "delete forbidden on tied hash : $@");
ok(delete $personType->{city}, "delete OK on $personType");
ok((not exists $jsb->{city}), "city field was really deleted");
delete tied(%$jsb)->[$personType->{firstname}];
is($jsb->{firstname}, undef, "jsb lost his name");


# ->delete() and ->clone() functions
my $abcd_type = Hash::Type->new(qw/a b c d/);
my $clone     = $abcd_type->clone;
my @records   = ($abcd_type->new(1, 2, 3, 4), $abcd_type->new(5, 6, 7, 8));
my $mutator   = $abcd_type->delete(qw/d b d foo/);
$mutator->($_) foreach @records;
is_deeply \@records, [{a => 1, c => 3}, {a => 5, c => 7}], '->delete() operation';
is_deeply [$clone->names], [qw/a b c d/],                  '->clone() operation';

# ->reorder() function
$abcd_type = Hash::Type->new(qw/a b c d/);
@records   = ($abcd_type->new(1, 2, 3, 4), $abcd_type->new(5, 6, 7, 8));
$mutator   = $abcd_type->reorder(qw/d b/);
$mutator->($_) foreach @records;
is_deeply [$abcd_type->names], [qw/d b a c/],              'reordered names';
is_deeply [values %{$records[0]}], [4, 2, 1, 3],           'reordered values';
is_deeply \@records, [{a => 1, b => 2, c => 3, d => 4},
                      {a => 5, b => 6, c => 7, d => 8}],   'reordered hashes';

# ->rename() function
$abcd_type = Hash::Type->new(qw/a b c d/);
@records   = ($abcd_type->new(1, 2, 3, 4), $abcd_type->new(5, 6, 7, 8));
$abcd_type->rename(a => 'x', b => 'c', c => 'b');
is_deeply [$abcd_type->names], [qw/x c b d/],              'renamed cols';
is_deeply \@records, [{x => 1, c => 2, b => 3, d => 4},
                      {x => 5, c => 6, b => 7, d => 8}],   'renamed hashes';



done_testing;

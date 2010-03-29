use strict;
use warnings;
use Test::More tests => 33;

my $DRIVER = $ENV{DRIVER};
use constant USER   => $ENV{USER};
use constant PASS   => $ENV{PASS};
use constant DBNAME => $ENV{DB} || 'test';
use constant HOST   => $ENV{HOST} || ($^O eq 'cygwin') ? '127.0.0.1' : 'localhost';

use DBI;
use Tie::DBI;

######################### End of black magic.

unless ($DRIVER) {
    local($^W)=0;  # kill uninitialized variable warning
    # I like mysql best, followed by Oracle and Sybase
    my ($count) = 0;
    my (%DRIVERS) = map { ($_,$count++) } qw(Informix Pg Ingres mSQL Sybase Oracle mysql SQLite); # ExampleP doesn't work;
    ($DRIVER) = sort { $DRIVERS{$b}<=>$DRIVERS{$a} } grep {exists $DRIVERS{$_}} DBI->available_drivers(1);
}

if ($DRIVER) {
    diag("Using DBD driver $DRIVER...");
} else {
    die "Found no DBD driver to use.\n";
}

my %TABLES = (
	      'CSV' => <<END,
CREATE TABLE testTie (
produce_id       char(15),
price            real,
quantity         int,
description      char(30)
)
END
	      'mSQL' => <<END,
CREATE TABLE testTie (
produce_id       char(15),
price            real,
quantity         int,
description      char(30)
)
;
CREATE UNIQUE INDEX idx1 ON testTie (produce_id)
END
               'Pg'=><<END,
CREATE TABLE testTie (
produce_id       varchar(15) primary key,
price            real,
quantity         int,
description      varchar(30)
)
END
);

use constant DEFAULT_TABLE=><<END;
CREATE TABLE testTie (
produce_id       char(15) primary key,
price            real,
quantity         int,
description      char(30)
)
END
    ;


my @fields =   qw(produce_id     price quantity description);
my @test_data = (
		 ['strawberries',1.20,  8,      'Fresh Maine strawberries'],
		 ['apricots',    0.85,  2,      'Ripe Norwegian apricots'],
		 ['bananas',     1.30, 28,      'Sweet Alaskan bananas'],
		 ['kiwis',       1.50,  9,      'Juicy New York kiwi fruits'],
		 ['eggs',        1.00, 12,      'Farm-fresh Atlantic eggs']
		 );

sub initialize_database {
    local($^W) = 0;
    my $dsn;
    if ($DRIVER eq 'Pg') { $dsn = "dbi:$DRIVER:dbname=${\DBNAME}"; } 
                    else { $dsn = "dbi:$DRIVER:${\DBNAME}:${\HOST}";        }
    my $dbh = DBI->connect($dsn,USER,PASS,{ChopBlanks=>1}) || return undef;
    $dbh->do("DROP TABLE testTie");
    return $dbh if $DRIVER eq 'ExampleP';
    my $table = $TABLES{$DRIVER} || DEFAULT_TABLE;
    foreach (split(';',$table)) {
      $dbh->do($_) || warn $DBI::errstr;
    }
    $dbh;
}

sub insert_data {
    my $h = shift;
    my ($record,$count);
    foreach $record (@test_data) {
	my %record = map { $fields[$_]=>$record->[$_] } (0..$#fields);
	$h->{$record{produce_id}} = \%record;
	$count++;
    }
    return $count == @test_data;
}

sub chopBlanks {
  my $a = shift;
  $a=~s/\s+$//;
  $a;
}

my %h;
my $dbh = initialize_database;
{
    local($^W)=0;
    ok($dbh,"Couldn't create test table: $DBI::errstr") or die;
}
isa_ok(tie(%h,'Tie::DBI',{db=>$dbh,table=>'testTie',key=>'produce_id',CLOBBER=>3,WARN=>0}), 'Tie::DBI');

%h=() unless $DRIVER eq 'ExampleP';
is(scalar(keys %h), 0, '%h is empty');
is(insert_data(\%h), scalar @test_data, "Insert data into db");
ok(exists($h{strawberries}));
ok(defined($h{strawberries}));
is(join(" ",map {chopBlanks($_)} sort keys %h), "apricots bananas eggs kiwis strawberries");
is($h{eggs}->{quantity}, 12);
$h{eggs}->{quantity} *= 2;
is($h{eggs}->{quantity}, 24);

my $total_price = 0;
my $count = 0;
my ($key,$value);
while (($key,$value) = each %h) {
    $total_price += $value->{price} * $value->{quantity};
    $count++;
}
is($count, 5);
cmp_ok(abs($total_price - 85.2),  '<', 0.01);

$h{'cherries'} = { description=>'Vine-ripened cherries',price=>2.50,quantity=>200 };
is($h{'cherries'}{quantity}, 200);

$h{'cherries'} = { price => 2.75 };
is($h{'cherries'}{quantity}, 200);
is($h{'cherries'}{price}, 2.75);
is(join(" ",map {chopBlanks($_)} sort keys %h), "apricots bananas cherries eggs kiwis strawberries");

ok(delete $h{'cherries'});
is(exists $h{'cherries'}, '');

my $array = $h{'eggs','strawberries'};
is($array->[1]->{'description'}, 'Fresh Maine strawberries');

my $another_array = $array->[1]->{'produce_id','quantity'};
is("@{$another_array}", 'strawberries 8');

is(@fields = tied(%h)->select_where('quantity > 10'), 2);
is(join(" ",sort @fields), 'bananas eggs');

delete $h{strawberries}->{quantity};

SKIP: {
    skip "Skipping test for CSV driver...", 1 if($DRIVER eq 'CSV');
    ok(!exists ($h{strawberries}->{quantity}), 'Quantity was deleted');
}

ok($h{strawberries}->{quantity}=42);
ok($h{strawberries}->{quantity}=42);  # make sure update statement works when nothing changes
is($h{strawberries}->{quantity}, 42);

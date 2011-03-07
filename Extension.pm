package Bugzilla::Extension::AlterEgo;

use strict;
use warnings;
use Bugzilla;
use Bugzilla::Bug;
use Bugzilla::User;
use Bugzilla::Constants;
use Bugzilla::Util;

use base qw(Bugzilla::Extension);

our $VERSION = '1.0';
use constant NAME => 'AlterEgo';

sub db_schema_abstract_schema($$) {
    my ($self, $args) = @_;
    my $schema = $args->{schema};

    $schema->{alterego1} = {
        FIELDS => [
            alterego1_id => {TYPE => 'MEDIUMSERIAL', NOTNULL => 1,
                             PRIMARYKEY => 1},
            word         => {TYPE => 'TINYTEXT', NOTNULL => 1},
        ],
        INDEXES => [
            alterego1_word_idx  => {FIELDS => ['alterego1_id'],
                                     TYPE   => 'UNIQUE'},
        ],
    };

    $schema->{alterego2} = {
        FIELDS => [
            alterego2_id => {TYPE => 'MEDIUMSERIAL', NOTNULL => 1,
                             PRIMARYKEY => 1},
            word         => {TYPE => 'TINYTEXT', NOTNULL => 1},
        ],
        INDEXES => [
            alterego2_word_idx  => {FIELDS => ['alterego2_id'],
                                     TYPE   => 'UNIQUE'},
        ],
    };

    $schema->{bug_alterego_map} = {
        FIELDS => [
                   bug_id       => {TYPE => 'INT3', NOTNULL => 1,
                                    REFERENCES => {TABLE => 'bugs',
                                                   COLUMN => 'bug_id',
                                                   DELETE => 'CASCADE'}},
                   alterego1_id => {TYPE => 'INT3', NOTNULL => 1,
                                    REFERENCES => {TABLE => 'alterego1',
                                                   COLUMN => 'alterego1_id',
                                                   DELETE => 'CASCADE'}},
                   alterego2_id => {TYPE => 'INT3', NOTNULL => 1,
                                    REFERENCES => {TABLE => 'alterego2',
                                                   COLUMN => 'alterego2_id',
                                                   DELETE => 'CASCADE'}},
        ],
        INDEXES => [
            bug_alterego_map_bug_id_idx =>
                {FIELDS => [qw(bug_id alterego1_id alterego2_id)],
                 TYPE => 'UNIQUE'},
        ],
    };
}

sub update_alterego {
    my ($filename, $tablename) = @_;
    my $dbh = Bugzilla->dbh;

    # Get the currently entered words
    my $rows = $dbh->selectall_arrayref("SELECT word FROM $tablename");
    my ($row, %existing);
    foreach $row (@{$rows}) {
        $existing{$row->[0]} = 1;
    }
    print "  found " . (keys %existing) . " words in $tablename, ";

    # Use the word lists to populate the alterego word tables
    my $words = new IO::File($filename, 'r')
        || die "$filename: $!";
    my $num_new_words = 0;
    while (<$words>) {
        chomp;
        if (/./ && ! $existing{$_}) {
            $dbh->do("INSERT INTO $tablename (word) VALUES (?)", undef, $_);
            $num_new_words += 1;
        }
    }

    print "added $num_new_words new ones.\n";
}

sub install_update_db($$) {
    print STDERR "Importing AlterEgo words...\n";

    my $alterego_dir = bz_locations()->{'extensionsdir'} . "/AlterEgo";
    update_alterego("$alterego_dir/words1.txt", "alterego1");
    update_alterego("$alterego_dir/words2.txt", "alterego2");
}

sub disabled_bug_fields {
    # This is a hack. I'm monkey patching Bugzilla::Bug.
    # I'm using this hook because it is the easiest place to do it.

    no warnings 'redefine';
    sub Bugzilla::Bug::alterego {
        my $self = shift;

# need a pair of numbers, which can be algorithmically determined from an 
# arbitrary bug number. 
# dictionary: each word has a unique identifier based on its chars?
# ideally we'd be able to add to the dict without mucking up the current
# values
# also it would be nice to not have the dict be ordered
# keep it simple: import mechanism for adding new words. the data
# file contains pairs of words and their ids, which are each unique 
# numbers. import mechanism randomizes the ordering. import mechanism
# runs when bugzilla is installed.
# dict should be stored in mysql?        
        
        # get two numbers from the bug_id.
        my @nums = (1, 1);
        my $i = 0;
        my $x = $self->{'bug_id'};
        while ($x > 0) {
            if ($x % 2 == 1) {
                $x--;
                $nums[$i % 2] += 2 ** (($i - $i % 2) / 2);
            }
            $x = $x / 2;
            $i++;
        }

        # jumble up the numbers a bit
        my @jumble = (5, 3, 4, 1, 2, 0);
        $i = 0;
        foreach $x (@jumble) {
            if (($nums[0] % (2 ** $i)) == 1) {
                $nums[0] = $nums[0] - (2 ** $i) + (2 ** $x);
            }
            if (($nums[1] % (2 ** $i)) == 1) {
                $nums[1] = $nums[1] - (2 ** $i) + (2 ** $x);
            }
            $i++;
        }

        # now get the corresponding keywords
        my $dbh = Bugzilla->dbh;
        my %words;
        my $sth = $dbh->prepare(<<SQL);
SELECT ego
  FROM alterego_l
 WHERE num = $nums[0]
SQL
        my @row = $dbh->selectrow_array($sth, undef);
        my $l = lc($row[0] ? $row[0] : '???');

        $sth = $dbh->prepare(<<SQL);
SELECT ego
  FROM alterego_r
 WHERE num = $nums[1]
SQL
        @row = $dbh->selectrow_array($sth, undef);
        my $r = lc($row[0] ? $row[0] : '???');

        return "$l $r"
#        return "$l $r ($nums[0]/$nums[1])"
    }
}

__PACKAGE__->NAME;

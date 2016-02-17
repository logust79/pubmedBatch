#!/usr/bin/env perl

=header
 This is to construct the SQlite database for pubmedBatch, storing searching information.
 *id, term, result, time*
 id: primary id
 term: search term. Arranged as gene_OR_AND (e.g. USH2A_macula_ [no AND term]). Both OR and AND terms will be lower cased. Gene names will be upper cased.
 result: pID, titles, abstracts, links, pubmed scores (in JSON structure. This is what we need in the app)
 time: the time when the record is created. If longer than a period of time (2 weeks?), this record is removed and the term re-searched.
=cut

use strict;
use warnings;
use DBI;

my $dbh = DBI->connect(
    "dbi:SQLite:dbname=../db/pubmedBatch.sqlite",
    "",
    "",
    { RaiseError => 1,
      sqlite_unicode => 1,
    }
) or die $DBI::errstr;
$dbh->do("DROP TABLE IF EXISTS pubmedBatch");
$dbh->do("CREATE TABLE pubmedBatch(id INTEGER PRIMARY KEY, term TEXT, result TEXT, time INTEGER)");
$dbh->disconnect();
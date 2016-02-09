#!/bin/sh

# this is to install dependent programs/perl modules

# perl version >= 16?

ver=$(perl -v | awk '/version [0-9]+/ {print $6}' | awk '{print substr($0,0,2)}')

if [ $ver -ge 16 ] ; then
	# good. install prerequisite
	sudo apt-get -qq update
	cpan install App::cpanminus
	cpanm BioPerl
    cpanm Bio::DB::EUtilities
    cpanm Dancer2
	cpanm Template
	cpanm Try::Tiny
	cpanm File::Temp
	cpanm Starman
	cpanm JSON
    cpanm Dancer2::Plugin::ProgressStatus
    cpanm File::Path
    cpanm XML::LibXML
    cpanm Text::CSV
else
	# not good. throw an error.
	echo 'Error: Your perl version has to be at least 5.16.0. perl -v to check your perl version';
	exit 1;
fi

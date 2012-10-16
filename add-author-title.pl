#!/usr/bin/perl

# add-author-title.pl - insert author and title information into MyLibrary

# Eric Lease Morgan <emorgan@nd.edu>
# August 25, 2011 - first investigations


# configure
use constant PAMPHLETS    => '/var/www/html/sandbox/cyl/etc/cyl.marc';
use constant PDFLOCATION  => 111;
use constant PDFROOT      => 'http://dh.crc.nd.edu/sandbox/cyl/corpus/';
use constant TEXTLOCATION => 112;
use constant TEXTROOT     => 'http://dh.crc.nd.edu/sandbox/cyl/corpus/';

# require
use strict;
use MyLibrary::Core;
use MARC::Batch;

# process each MARC record
my $batch = MARC::Batch->new( 'USMARC', PAMPHLETS );
$batch->warnings_off();
$batch->strict_off();
my $count = 0;
while ( my $record = $batch->next ) {

	# increment
	$count++;
	
	# extract
	my $fkey    = $record->field( '001' )->as_string;
	my $creator = $record->author;
	my $name    = $record->title;

	# echo
	print "       count: $count\n";
	print "        fkey: $fkey\n";
	print "     creator: $creator\n";
	print "        name: $name\n";
	
	# create locations
	my $pdf_location  = PDFROOT . "$fkey.pdf";
	my $text_location = TEXTROOT . "$fkey" . "_djvu.txt";
	
	# echo
	print "         PDF: $pdf_location\n";
	print "  plain text: $text_location\n";
	
	# based on fkey, add the author	and title
	my $resource = MyLibrary::Resource->new( fkey => $fkey ); 
	if ( ! $resource ) { $resource = MyLibrary::Resource->new }
	$resource->creator( $creator );
	$resource->fkey( $fkey );
	$resource->name( $name );
	$resource->add_location( location => $pdf_location,  location_type => PDFLOCATION );
	$resource->add_location( location => $text_location, location_type => TEXTLOCATION );
	
	# save
	$resource->commit;
	my $id = $resource->id;
	
	# echo some more
	print "         id: $id\n";
	print "\n";
	
}


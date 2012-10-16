#!/usr/bin/perl

# add-size-readability.pl - update MyLibrary to include number of words and Fog, Flesch, and Kincaid scores

# Important! For better or for worse, we stuff the size, Fog, Flesch,
# and Kincaid values as integers into the format field of the
# MyLibrary database. Each value is delimited by a colon (:) --
# size:fog:flesch:kincaid:

# Eric Lease Morgan <emorgan@nd.edu>
# August 30, 2011 - first investigations


# configure
use constant TEXTLOCATION => 112;

# require
use Lingua::EN::Fathom;
use LWP;
use Math::Round;
use MyLibrary::Core;
use strict;

# get all the resources
my @resources = MyLibrary::Resource->get_resources;
my $count = 0;
foreach my $resource ( @resources ) {

	# increment
	$count++;
	
	# extract
	my $id           = $resource->id;
	my $fkey         = $resource->fkey;
	my $creator      = $resource->creator;
	my $name         = $resource->name;
	
	# get text locations
	my $text_location = '';
	foreach my $location ( $resource->resource_locations ) {
	
		if ( $location->resource_location_type == TEXTLOCATION ) { $text_location = $location->location }
		
	}

	# echo
	print "       count: $count\n";
	print "          id: $id\n";
	print "        fkey: $fkey\n";
	print "     creator: $creator\n";
	print "        name: $name\n";
	print "  plain text: $text_location\n";
	
	# get the text to analyze
	my $ua       = LWP::UserAgent->new;
	my $request  = HTTP::Request->new( GET => $text_location );
	my $response = $ua->request( $request );
	
	# check for success
	if ($response->is_success) {
	
		# analyze the text
		my $text = new Lingua::EN::Fathom;
		$text->analyse_block( $response->content );
		my $size    = $text->num_words;
		my $fog     = round( $text->fog );
		my $flesch  = round( $text->flesch );
		my $kincaid = round( $text->kincaid );
		
		# echo
		print "        size: $size\n";
		print "         Fog: $fog\n";
		print "      Flesch: $flesch\n";
		print "     Kincaid: $kincaid\n";
		
		# update
		$resource->format( "$size:$fog:$flesch:$kincaid:" );
		$resource->commit;
			
	}
	
	# error
	else { print '     ERROR: ', $response->status_line, "\n" }
	
	# echo
	print "\n";
		
}

# done
exit;

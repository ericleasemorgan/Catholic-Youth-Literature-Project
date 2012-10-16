#!/usr/bin/perl

# txt2ner.pl - create a named-entity recognition file that includes linked data uris

# Eric Lease Morgan <emorgan@nd.edu>
# May 17, 2011 - first investigations; big thanks go to the XML4Lib comunity for XPath assistance, especially Clay Redding, Neal P. Fitzgerald, Matthew Gibson, Jason Simon, Peter van Boheemen, Jason Simon, MJ Suhonos, Erik Hetzner, Kevin Clarke, and Robert Chavez
# November 11, 2011 - Started to enhance the linked data with additional metadata values

# configure 
use constant CMD      => 'cd /usr/local/ner; java -cp stanford-ner.jar edu.stanford.nlp.ie.crf.CRFClassifier -loadClassifier classifiers/ner-eng-ie.crf-3-all2008-distsim.ser.gz -textFile /tmp/input.txt -outputFormat inlineXML 2>/dev/null';
use constant TYPES    => ( 'PERSON' => 'person', 'LOCATION' => 'place', 'ORGANIZATION' => 'organisation' );
use constant LOOKUP   => 'http://lookup.dbpedia.org/api/search.asmx/KeywordSearch?QueryClass=##CLASS##&QueryString=##ENTITY##&MaxHits=##MAXHITS##';
use constant MAXHITS  => 5;
use constant TEMPLATE => 'http://dh.crc.nd.edu/sandbox/cyl/concordances/?cmd=search&id=##ID##&query=##QUERY##';

# require
use LWP;
use strict;
use XML::LibXML;
use XML::XPath;
use MyLibrary::Core;
use URI::Escape;

# sanity check
my $input = $ARGV[ 0 ];
if ( ! $input ) {

	print "Usage: $0 <filename>\n";
	exit;
	
}

binmode( STDOUT, ":utf8" );
binmode( STDERR, ":utf8" );

# get the input and save it to scratch
print STDERR "  Creating temporary file... $input\n";
my $file = &slurp( $input );
$file =~ s/&/&amp;/g;
$file =~ s/</&lt;/g;
$file =~ s/>/&gt;/g;
open TMP, ' > /tmp/input.txt ' or die "Can't open /tmp/input.txt: $!";
print TMP $file;
close TMP;

# extract the entities and clean up after myself
print STDERR "  Extracting entities...    \n";
open F, CMD . ' |';
my $ner = '';
while (<F>) { $ner = do { local $/; <F> } }
unlink '/tmp/input.txt';
close F;

# process each type of entity
print STDERR "  Tabulating entities...    \n";
my $xpath    = XML::XPath->new( xml => "<text>$ner</text>" );
my %entities = ();
my %types    = TYPES;
my $entities = '';
binmode( STDOUT, ":utf8" );
foreach my $type ( sort keys %types ) {

	# map the entity to a dbedia lookup class
	my $class = $types{ $type };

	# find all the nodes of this type; "Thanks XML4Lib!"
	foreach ( $xpath->findnodes( "//$type/text()" )->get_nodelist ) {
	
		# normalize the values
		my $entity = $_->string_value;
		$entity =~ s/&/&amp;/g;
		$entity =~ s/\n+/ /;
		$entity =~ s/ +/ /g;
	
		# tabulate
		$entities{ $entity }++
		
	}
	
	# build list of entities sorted by frequency
	foreach my $entity ( sort { $entities{ $b } <=> $entities{ $a } } keys %entities ) { 
	
		my $value  = &normalize( $entity );
		my $count  = $entities{ $entity };	
		$entities .= "<entity value='$value' type='$type' count='$count' />";
	
	}

}	

# find linked data for each entity
print STDERR "  Adding linked data...    \n";
my $ua   = LWP::UserAgent->new;
my $ner  = XML::LibXML->load_xml( string => "<entities>$entities</entities>" );
my $root = $ner->documentElement();
foreach my $entity ( $root->getChildrenByTagName( 'entity' )) {

	# extract the attribute values and map to dbpedia lookup class
	my $value   = $entity->getAttribute( 'value' );
	my $type    = $entity->getAttribute( 'type' );
	my $class   = $types{ $type };
	my $maxhits = MAXHITS;
	
	#next if ( $value ne 'Dublin' );
	
	# create and submit the lookup
	print STDERR "  Processing entity type $type. Searching for $value            \n";
	my $lookup   =  LOOKUP;
	$lookup      =~ s/##CLASS##/$class/;
	$lookup      =~ s/##ENTITY##/$value/;
	$lookup      =~ s/##MAXHITS##/$maxhits/;
	print STDERR $lookup, "\n";
	my $response =  $ua->get( $lookup );
	print STDERR "Lookup successful\n";
	
	# process successful results
	if ( $response->is_success ) {

		# create a linked data element
		my $linkeddata = XML::LibXML::Element->new( 'linkeddata' );

		# check for well-formed-ness; some of the RDF seems flakey
		eval { XML::XPath->new( xml => $response->content ); };
		if ( $@ ) {
		
			print STDERR "Error: Poorly formed XML\n"; 
			next;
			
		}
		print STDERR "Well-formednes successful\n";
		
		# parse the result
		my $xml = XML::XPath->new( xml => $response->content );
		foreach ( $xml->findnodes( '//Result')->get_nodelist ) {
					
			# flag sucess
			#$results = 1;
				
			# extract the metadata
			my $label       = $_->find( './Label')->string_value;
			my $uri         = $_->find( './URI')->string_value;
			my $description = $_->find( './Description')->string_value;
											
			# build the concordance URL
			my $fkey = $input;
			$fkey =~ s/^.*\///;
			$fkey =~ s/_djvu\.txt//;
			my $resource = MyLibrary::Resource->new( fkey => $fkey );
			my $id = $resource->id;
			my $concordance = TEMPLATE;
			$concordance =~ s/##ID##/$id/e;
		 	$concordance =~ s/##QUERY##/uri_escape( $value )/e;
			
			# create and insert a linked data item element
			my $item = XML::LibXML::Element->new( 'item' );
			$item->setAttribute( 'label', $label );
			$item->setAttribute( 'uri', $uri );
			$item->setAttribute( 'description', $description );
			$item->setAttribute( 'concordance', $concordance );

			# get the metadata
			my $detail_ua = LWP::UserAgent->new;
			$detail_ua->default_header( 'Accept' => 'application/rdf+xml' );
				
			# get the uri
			print STDERR "URI: $uri\n";
			my $request  = HTTP::Request->new( GET => $uri );
			my $response = $detail_ua->request( $request );
					
			# get elements
			my $wikipedia   = '';
			my $latitude    = '';
			my $longitude   = '';
			my $depiction   = '';
			if ( $response->is_success ) {
			
				# check for well-formed-ness; some of the RDF seems flakey
				eval { my $rdf = XML::XPath->new( xml => $response->content ); }; 
				if ( $@ ) {
				
					print STDERR "Error: Poorly formed XML, again.\n"; 
					next;
				}
				
				else {
				
					print STDERR "Well-formedness successful, again.\n";
					#print STDERR $response->content, "\n";
					
					print STDERR "Getting RDF\n";
					my $rdf       = XML::XPath->new( xml => $response->content );
					print STDERR "Getting FOAF\n";
					eval { $rdf->exists( '/rdf:RDF/rdf:Description/foaf:page') ; };
					if ( $@ ) {
					
						print STDERR "ERROR: Bad FOAF: $@\n";
						next;
					}
					if ( $rdf->exists( '/rdf:RDF/rdf:Description/foaf:page' )) { $wikipedia = $rdf->findnodes( '/rdf:RDF/rdf:Description/foaf:page' )->get_node( 1 )->getAttribute( 'rdf:resource' ) }
					print STDERR "Getting Thumbnail\n";
					if ( $rdf->exists( '/rdf:RDF/rdf:Description/dbpedia-owl:thumbnail' )) { $depiction = $rdf->findnodes( '/rdf:RDF/rdf:Description/dbpedia-owl:thumbnail' )->get_node( 1 )->getAttribute( 'rdf:resource' ) }
					print STDERR "Getting latitutde\n";
					if ( $rdf->exists( '/rdf:RDF/rdf:Description/geo:lat' )) { $latitude  = $rdf->findnodes( '/rdf:RDF/rdf:Description/geo:lat' )->get_node( 1 )->string_value }
					print STDERR "Getting longitude\n";
					if ( $rdf->exists( '/rdf:RDF/rdf:Description/geo:long' )) { $longitude  = $rdf->findnodes( '/rdf:RDF/rdf:Description/geo:long' )->get_node( 1 )->string_value }
				
				}
											
			}
			
			# echo/debug
			print STDERR  "        label: $label\n";
			print STDERR  "          uri: $uri\n";
			print STDERR  "  description: $description\n";
			print STDERR  "    wikipedia: $wikipedia\n";
			print STDERR  "    depiction: $depiction\n";
			print STDERR  "     latitude: $latitude\n";
			print STDERR  "    longitude: $longitude\n";
			print STDERR  "  concordance: $concordance\n";
			print STDERR  "\n";
					
			# update the linked data
			if ( $wikipedia ) { $item->setAttribute( 'wikipedia', $wikipedia )}
			if ( $depiction ) { $item->setAttribute( 'depiction', $depiction )}
			if ( $latitude ) { $item->setAttribute( 'latitude', $latitude )}
			if ( $longitude ) { $item->setAttribute( 'longitude', $longitude )}
			$linkeddata->appendChild( $item );

		}
							
		# append the linkeddata element to the current node
		$entity->appendChild( $linkeddata );

	}
		
}

# done
print STDERR "\n";
print $ner->toString;
exit;


sub normalize {

	my $s =  $_[ 0 ];
	$s =~ s/</&lt;/g;
	$s =~ s/>/&gt;/g;
	$s =~ s/'/&apos;/g;
	$s =~ s/"/&quot;/g;
	return $s;
	
}


sub slurp {

	# open a file named by the input and return its contents
	my $f = shift;
	my $r;
	open F, $f or die "Can't slurp: $!\n";
	$r = do { local $/; <F> };
	return $r;

}

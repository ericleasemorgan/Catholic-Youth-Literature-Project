#!/usr/bin/perl

# ner.cgi - list, display, and provide linked data for people and places (named entities)

# Eric Lease Morgan <emorgan@nd.edu>
# May 28, 2011 - based on previous scripts


# configure
use constant CORPUS => '/var/www/html/sandbox/cyl/corpus/';
use constant MAX    => 250;

# require
use CGI;
use Lingua::StopWords qw( getStopWords );
use LWP;
use strict;
use XML::XPath;

# initialize
my $cgi  = CGI->new;
my $html = '';

# get input
my $id          = $cgi->param( 'id' );
my $entity_type = $cgi->param( 'entity_type' );
my $index_type  = $cgi->param( 'index_type' );
my $value       = $cgi->param( 'value' );

# initialize according to input
my $entity_name = '';
if    ( $entity_type eq 'l' ) { $entity_name = 'LOCATION' }
elsif ( $entity_type eq 'p' ) { $entity_name = 'PERSON' }
elsif ( $entity_type eq 'o' ) { $entity_name = 'ORGANIZATION' }
else  { die }

# initialize some more
my $ner      = XML::XPath->new( filename => CORPUS . "$id.ner" );

# process a cloud request
if ( $index_type ) {

	# parse the ner file for all the entities
	my $query = '//entity[@type="' . $entity_name . '"]';
	my %entities = ();
	foreach my $entity ( $ner->findnodes( $query )->get_nodelist ) {
	
		# extract the values
		my $value = $entity->getAttribute( 'value' );
		my $count = $entity->getAttribute( 'count' );
		$entities{ $value } = $count;
			
	}
	
	# build the index/cloud
	if ( $index_type eq 'a' ) { $html = &alphabetic( \%entities, MAX ) }
	else { $html = &cloud( \%entities, MAX ) }
	$html = qq( <p class="cloud">$html</p> );

}

# display specific entities
elsif ( $value ) {

	# read all the entities
	my $query = '//entity[@value="' . $value . '"]';
	foreach my $entity ( $ner->findnodes( $query )->get_nodelist ) {
			
		# only one enities of a specific type
		if ( $entity->getAttribute( 'type' ) eq $entity_name ) {
								
			# get the metadata
			my $ua = LWP::UserAgent->new;
			$ua->default_header( 'Accept' => 'application/rdf+xml' );
	
			# process each item
			foreach my $item ( $entity->findnodes( './/item' )->get_nodelist ) {
			
				# get the uri
				my $uri      = $item->getAttribute( 'uri' );
				my $request  = HTTP::Request->new( GET => $uri );
				my $response = $ua->request( $request );
						
				if ( $response->is_success ) {
				
					# initialize
					my $rdf       = XML::XPath->new( xml => $response->content );
					my $label     = '';
					my $comment   = '';
					my $wikipedia = '';
					my $latitude  = '';
					my $longitude = '';
					my $depiction = '';
					my $context   = 'Read it in context';
								
					# get elements
					if ( $rdf->exists( '/rdf:RDF/rdf:Description/rdfs:label[@xml:lang="en"' )) { $label = $rdf->find( '/rdf:RDF/rdf:Description/rdfs:label[@xml:lang="en"' ) }
					if ( $rdf->exists( '/rdf:RDF/rdf:Description/rdfs:comment[@xml:lang="en"]' )) { $comment = $rdf->find( '/rdf:RDF/rdf:Description/rdfs:comment[@xml:lang="en"]' ) }
					if ( $rdf->exists( '/rdf:RDF/rdf:Description/foaf:page' )) { $wikipedia = $rdf->findnodes( '/rdf:RDF/rdf:Description/foaf:page' )->get_node( 1 )->getAttribute( 'rdf:resource' ) }
					if ( $rdf->exists( '/rdf:RDF/rdf:Description/dbpedia-owl:thumbnail' )) { $depiction = $rdf->findnodes( '/rdf:RDF/rdf:Description/dbpedia-owl:thumbnail' )->get_node( 1 )->getAttribute( 'rdf:resource' ) }
					if ( $rdf->exists( '/rdf:RDF/rdf:Description/geo:lat' )) { $latitude  = $rdf->findnodes( '/rdf:RDF/rdf:Description/geo:lat' )->get_node( 1 )->string_value }
					if ( $rdf->exists( '/rdf:RDF/rdf:Description/geo:long' )) { $longitude  = $rdf->findnodes( '/rdf:RDF/rdf:Description/geo:long' )->get_node( 1 )->string_value }
				
					# html-ify the extracted metadata
					if ( $depiction ) { $depiction = $cgi->img({ height => '100', src => $depiction, align => 'right' })}
					if ( $wikipedia ) { $wikipedia = '; ' . $cgi->a({ target => '_blank', href => $wikipedia }, 'Read it on Wikipedia' ) }
					if ( $latitude  ) { $latitude  = '; ' . $cgi->a({ target => '_blank', href => "http://maps.google.com/maps?q=$latitude $longitude"}, 'Map it') }
					
					# debug
					#$uri = $cgi->a({ href => $uri }, $uri );
	
					# build a list of output
					$html .= $cgi->li({ style => 'margin-bottom: 1em' }, "$depiction<strong>$label</strong> - $comment<br/>$context$wikipedia$latitude");
					
				}
				
			}
			
		}
		
	}
	
	# finish the list
	$html = $cgi->ol( $html );

}

# done
print $cgi->header( -charset => 'utf-8' );
print $html;
exit;


sub cloud {

	# get input and initialize
	my $unigrams  = $_[ 0 ];
	my $max       = $_[ 1 ];
	my $stopwords = &getStopWords( 'en' );
	my $cloud     = '';
	my $counter   = 0;
	
	foreach my $word ( sort { $$unigrams{ $b } <=> $$unigrams{ $a }} keys %$unigrams ) {
	
		# skip stopwords and punctuation
		next if ( $$stopwords{ $word } );
		next if ( $word =~ /[,.?!:;()\-]/ );
		
		# increment and check
		$counter++;
		last if ( $counter == $max );
		
		# build cloud
		#my $size = 100 / ( 75 / $$unigrams{ $word } );
		my $size = 100;
		$cloud .= "<span style='font-size: $size%'>$word</span>&nbsp; ";
		
	}

	# done
	return qq( <p>$cloud</p> );

}


sub alphabetic {

	# get input
	my $unigrams = $_[ 0 ];
	my $stopwords = &getStopWords( 'en' );
	
	# navigation
	my $navigation   = '';
	for ( my $letter = 97; $letter <= 122; $letter++ ) { $$unigrams{ chr( $letter )} = '-' }
	for ( my $letter = 97; $letter <= 122; $letter++ ) { $navigation .= '<a href="#' . chr( $letter ) . '">' . chr( $letter ) . '</a> ' }
	$navigation = "<p class='navigation'>$navigation</p>";
	
	# build the display
	my @k           = keys %$unigrams;
	my $half        = $#k / 2;
	my $leftcolumn  = "<span class='letter'><a name='a'>a</a></span>$navigation";
	my $rightcolumn = '';
	my $counter     = 0;
	foreach my $word ( sort { lc( $a ) cmp lc( $b ) } keys %$unigrams ) {
	
		# skip stopwords and punctuation
		next if ( $$stopwords{ $word } );
		next if ( $word =~ /[,.?!:;()\-]/ );
	
		# increment and branch
		$counter++;
		if ( $counter < $half ) {
		
			if ( $$unigrams{ $word } eq '-' ) { $leftcolumn .= "<a name='$word'>$navigation</a><span class='letter'>$word</span><br />" }
			else {
			
				my $link = qq (<a href='#entity' data-transition='slide' onClick="getEntity('$id', '$entity_type', '$word')">$word</a>);
				$leftcolumn .= $link . '&nbsp;(' . $$unigrams{ $word } . ')&nbsp; '
			
			}
			
		}
		
		else {
		
			if ( $$unigrams{ $word } eq '-' ) { $rightcolumn .= "<a name='$word'>$navigation</a><span class='letter'>$word</span><br />" }
			else {
			
				my $link = qq (<a href='#entity' data-transition='slide' onClick="getEntity('$id', '$entity_type', '$word')">$word</a>);
				$rightcolumn .= $link . '&nbsp;(' . $$unigrams{ $word } . ')&nbsp; '
			
			}
				
		}
			
	}
	
	# done
	return qq( <div class="left">$leftcolumn</div><div class="right">$rightcolumn</div> );

}

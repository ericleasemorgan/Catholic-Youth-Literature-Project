package CYL::Concordances;

# Concordance.pm - rudimentary text analysis tool for Catholic Youth Literature Project

# Eric Lease Morgan <emorgan@nd.edu>
# October 16, 2010 - based on Alex::Concordance
# April   11, 2011 - tweaked forms based on usability studies
# August  30, 2011 - started migrating to CYL
# January  4, 2012 - started migrating to tablet interface
# January  5, 2012 - tablet interface functions; began to add protovis
# January 24, 2012 - been tweaking the interface; no functionality changes


# define/configure
use constant MAXCOLLOCATIONS => 100;
use constant RADIUS          => 60;
use constant TEXTLOCATION    => 112;
use constant THRESHOLD       => 7;
use constant HOME            => 'http://dh.crc.nd.edu/sandbox/cyl/catalog/details/';


# require
use Apache2::Const -compile => qw( OK );
use CGI;
use Lingua::Concordance;
use Lingua::EN::Ngram;
use Lingua::StopWords qw( getStopWords );
use MyLibrary::Core;
use strict;
use LWP;

# sort of bogus
my $stopwords = &buildStopwords;

# main
sub handler {

	# initalize
	my $r    = shift;
	my $cgi  = CGI->new;
	my $id   = $cgi->param( 'id' );
	my $html = '';
	
	# display default page
	if ( ! $id ) {
	
		# set-up output
		$html = &template;
	
	}
	
	# branch according to cmd
	else {
	
		# get the id's metadata; needs error checking
		my $filename = '';
		my ( $name, $creator, $url ) = &get_metadata( $id );
				
		# get the cmd
		my $cmd = $cgi->param( 'cmd' );
		
		# no command
		if ( ! $cmd ) {
		
			# display the home page
			$html =  &template;
			$html =~ s/##CONTENT##/&home/e;
			$html =~ s/##TITLE##/$name/ge;
			$html =~ s/##FORM##/&form( $cgi )/e;
			$html =~ s/##ID##/$id/ge;
			$html =~ s/##SHOWMAP##//e;
			$html =~ s/##SHOWNETWORK##//e;
			$html =~ s/##MAP##//e;
			$html =~ s/##QUERY##//e;
			$html =~ s/##SUBFORM##//e;
			$html =~ s/##LINES##//e;
			
		}
		
		# display words starting with letter
		elsif ( $cmd eq 'letters' ) {
		
			my $i = $cgi->param( 'l' );
			
			# set up
			my $collocations = Lingua::EN::Ngram->new( text => &getText( $url ));

			my $words = $collocations->ngram( 1 );
			my $lines = '';
			foreach my $word ( sort keys %$words ) {

				my $l = substr $word, 0, 1;
				next if ( $i gt $l );
				last if ( $i lt $l );
				my $link = $cgi->a({ "data-ajax" => 'false', href => "./?cmd=search&id=$id&query=" . $word }, $word );
				$lines .= $link . ' (' . $$words{ $word } . '); &nbsp;';
	
			}

			$lines = $cgi->p( $lines );

			# set-up output
			$html =  &template;
			$html =~ s/##CONTENT##/&home/e;
			$html =~ s/##TITLE##/$name/ge;
			$html =~ s/##AUTHOR##/$creator/e;
			$html =~ s/##FORM##/&form( $cgi )/e;
			$html =~ s/##ID##/$id/ge;
			$html =~ s/##QUERY##//e;
			$html =~ s/##SHOWMAP##//e;
			$html =~ s/##SHOWNETWORK##//e;
			$html =~ s/##MAP##//e;
			$html =~ s/##SUBFORM##//e;
			$html =~ s/##LINES##/$lines/e;
				
		}
		
		# display single words
		elsif ( $cmd eq 'words' ) {
		
			# get the number of words
			my $n = $cgi->param( 'n' );
			
			# set up
			my $collocations = Lingua::EN::Ngram->new( text => &getText( $url ));
				
			# do the work
			my $words      = $collocations->ngram( 1 );
			my $index      = 0;
			my $lines      = '';
			#my $stopwords  = &getStopWords( 'en' );
			foreach ( sort { $$words{ $b } <=> $$words{ $a } } keys %$words ) {
			
				# skip stopwords and punctuation
				next if ( $$stopwords{ $_ } );
				next if ( $_ =~ /[,.?!:;()\-]/ or $_ =~ /^'/ or $_ =~ /'$/ );
		
				# limit the output
				$index++;
				last if ( $index > $n );
				
				# gather the words
				my $link = $cgi->a({ "data-ajax" => 'false', href => "./?cmd=search&id=$id&query=" . $_ }, $_ );
				$lines .= $link . ' (' . $$words{ $_ } . '); &nbsp;';
			
			}
			$lines = $cgi->p( $lines );
			
			# set-up output
			$html =  &template;
			$html =~ s/##CONTENT##/&home/e;
			$html =~ s/##TITLE##/$name/ge;
			$html =~ s/##AUTHOR##/$creator/e;
			$html =~ s/##FORM##/&form( $cgi )/e;
			$html =~ s/##ID##/$id/ge;
			$html =~ s/##QUERY##//e;
			$html =~ s/##SHOWMAP##//e;
			$html =~ s/##SHOWNETWORK##//e;
			$html =~ s/##MAP##//e;
			$html =~ s/##SUBFORM##//e;
			$html =~ s/##LINES##/$lines/e;
		
		}
		
		# display collocations
		elsif ( $cmd eq 'collocations' ) {
		
			# get the input: length of collocations
			my $n = $cgi->param( 'n' );
						
			# initalize
			my $collocations = Lingua::EN::Ngram->new( text => &getText( $url ));
			
			# count; branch according to how many
			my $bigrams = '';
			my $count   = '';
			my $tscore  = '';
			if ( $n == 2 ) { 
			
				$bigrams = $collocations->ngram( 2 );
				$count   = $collocations->tscore;
				
			}
			else { $count = $collocations->ngram( $n )}
			
			# process each count
			my $index     = 0;
			my $lines     = '';
			#my $stopwords = &getStopWords( 'en' );
			foreach my $phrase ( sort { $$count{ $b } <=> $$count{ $a } } keys %$count ) {
			
				# get the tokens of the phrase
				my @tokens = split / /, $phrase;
			
				# process each token; filter based on it's value
				my $found = 0;
				foreach ( @tokens ) {
				
					# skip stop words for bigrams
					if ( $n == 2 ) {
					
						if ( $$stopwords{ $_ }) {
						
							$found = 1;
							last;
						
						}
					
					}
					
					# skip punctuation
					if ( $_ =~ /[,.?!:;()\-]/ or $_ =~ /^'/ or $_ =~ /'$/  ) {
					
						$found = 1;
						last;
						
					}
						
					# skip punctuation
					if ( $_ =~ /^'/ ) {
					
						$found = 1;
						last;
						
					}
						
				}
				
				# loop if found an unwanted token
				next if ( $found );
		
				# limit the output
				$index++;
				last if ( $index > MAXCOLLOCATIONS );
				last if ( $$count{ $phrase } == 1 );
				
				# gather the words
				my $link = $cgi->a({ "data-ajax" => 'false', href => "./?cmd=search&id=$id&query=" . $phrase }, $phrase );
				if ( $n == 2 ) { $lines .= $link . ' (' . $$bigrams{ $phrase } . '); &nbsp;' }
				else { $lines .= $link . ' (' . $$count{ $phrase } . '); &nbsp;' }
			
			}
			$lines = $cgi->p( $lines );
			
			# set-up output
			$html =  &template;
			$html =~ s/##CONTENT##/&home/e;
			$html =~ s/##TITLE##/$name/ge;
			$html =~ s/##AUTHOR##/$creator/e;
			$html =~ s/##FORM##/&form( $cgi )/e;
			$html =~ s/##QUERY##//e;
			$html =~ s/##SHOWMAP##//e;
			$html =~ s/##SHOWNETWORK##//e;
			$html =~ s/##MAP##//e;
			$html =~ s/##SUBFORM##//e;
			$html =~ s/##ID##/$id/ge;
			$html =~ s/##LINES##/$lines/e;
		
		}
	
		# implement concordance
		elsif ( $cmd eq 'search' ) {
		
			# get the query
			my $query = $cgi->param( 'query' );
						
			# build & configure concordance
			my $concordance = Lingua::Concordance->new;
			$concordance->text( &getText( $url ));
			$concordance->radius( RADIUS );
			$concordance->query( $query );
			my $radius = $cgi->param( 'radius' ) ? $cgi->param( 'radius' ) : $concordance->radius;
			$concordance->radius( $radius );
			my $sort = $cgi->param( 'sort' ) ? $cgi->param( 'sort' ) : $concordance->radius;
			$concordance->sort( $sort );
	
			# do the work
			my $lines = '';
			my $index = 0;
			foreach my $line ( $concordance->lines ) {
			
				# build padding
				$index++;
				
				if ( $radius < 200 ) {
				
					my $spaces = '';
					if ( length( $index ) == 1 ) { $spaces = '   ' }
					if ( length( $index ) == 2 ) { $spaces = '  ' }
					if ( length( $index ) == 3 ) { $spaces = ' ' }
					
					# format line
					$lines .= "$index.$spaces$line" . $cgi->br;
				
				}
				
				else { $lines .= $cgi->p( $index . '. ' . $line ) }
			
			}
			
			# format results, some more
			my $pattern = '\w+' . $query . '\w+|' . $query . '\w+|' . $query . '|\w+' . $query ;
			$lines =~ s|($pattern)|<b style='color:red'>$1</b>|gi;
			if ( $radius < 200 ) { $lines = $cgi->pre({ style => 'text-align: center' }, $lines )}
	
			# calculate and configure map
			$concordance->scale( 10 );
			my $map = $concordance->map;
			my @keys = sort { $$map{ $b } <=> $$map{ $a }} keys %$map;
			my $greatest_value = $$map{ $keys[ 0 ]};
			@keys = sort { $a <=> $b } keys %$map;
			my $values = '';
			foreach ( @keys ) { $values .= $$map{ $_ } . ',' }
			$values = substr( $values, 0, -1 );
			my $showmap = '<a href="#map"  data-role="button" data-inline="true">Show map</a>';
			
			
			# get initial words found near the query and sort them by frequency
			my $corpus    = &getText( $url );
			#my $stopwords = &getStopWords( 'en' );
			my $threshold = THRESHOLD;
			my $words = &concordance( $corpus, $query, $radius, $stopwords );
			my @keys = sort { $$words{ $b } <=> $$words{ $a } } keys %$words;

			# process each word (key) below a particular threshold; build matrix of words
			my %matrix = ();
			for ( my $i = 0; $i < $threshold; $i++ ) {
			
				my $query = $keys[ $i ];
				my $words = &concordance( $corpus, $query, $radius, $stopwords );
				my @subkeys = ( sort { $$words{ $b } <=> $$words{ $a } } keys %$words );
				my $coocurrances = &coocurances( $subkeys[ 0 ], $words, $threshold );
				
				my @list = ();
				my $j    = 0;
				my $key  = '';
				foreach ( sort { $$coocurrances{ $b } <=> $$coocurrances{ $a } } keys %$coocurrances ) {
			
					$j++;
					if ( $j == 1 ) { $key = $_ }
					push @list, $_;
				
				}
				
				$matrix{ $key } = [ @list ];
			
			}

			# create an ordered list of the words in the matrix
			my %words = ();
			my $i     = 0;
			foreach ( keys %matrix ) {
			
				my $list = $matrix{ $_ };
				foreach my $word ( @$list ) {
				
					my $found = 0;
					foreach my $key ( keys %words ) {
					
						if ( $key eq $word ) { $found = 1 }
						
					}
					
					if ( ! $found ) {
					
						$words{ $word } = $i;
						$i++;
						
					}
					
				}
				
			}
			
			# build a list of nodes from the words for Protovis
			my $nodes = '';
			foreach ( sort { $words{ $a } <=> $words{ $b } } keys %words ) { $nodes .= qq({nodeName:"$_"},) }
			chop $nodes;
			
			# build a list of links from the words for Protovis
			my $links = '';
			foreach my $source ( keys %matrix ) {
			
				my $list = $matrix{ $source };
				foreach ( my $i = 1; $i < $threshold; $i++ ) {
				
					$links .= qq({source:$words{ $$list[ $source ] },target:$words{ $$list[ $i ] }},);
				
				}
			
			}
			chop $links;

			# build the javascript and data;
			my $javascript   = &same_breath;
			my $protovisdata = qq(<script type="text/javascript">var corpus = {nodes:[$nodes],\nlinks:[$links]};</script>\n);
			my $shownetwork  = '<a href="#network" data-role="button" data-inline="true">Show network</a>';

			# set-up output
			$html =  &template;
			$html =~ s/##CONTENT##/&home/e;
			$html =~ s/##TITLE##/$name/ge;
			$html =~ s/##AUTHOR##/$creator/e;
			$html =~ s/##FORM##/&form( $cgi )/e;
			$html =~ s/##ID##/$id/ge;
			$html =~ s/##QUERY##/$query/e;
			$html =~ s/##MAP##/&map( $greatest_value, $values )/e;
			$html =~ s/##SHOWMAP##/$showmap/e;
			$html =~ s/##SHOWNETWORK##/$shownetwork/e;
			$html =~ s/##SUBFORM##/&subform( $radius, $sort )/e;
			$html =~ s/##LINES##/$lines/e;
			$html =~ s/##PROTOVISDATA##/$protovisdata/e;
			$html =~ s/##NETWORK##/$javascript/e;
		
		}
	
	}

	# done
	$r->content_type( 'text/html' );
	$r->print( $html );
	return Apache2::Const::OK;

}


# template
sub template {
	
	return <<EOT;
<!DOCTYPE html> 
<html>
<head>
	<title>##TITLE##</title>
	<meta name="viewport" content="width=device-width, initial-scale=1">
	<link rel="stylesheet" href="//code.jquery.com/mobile/1.0/jquery.mobile-1.0.min.css" />
	<script src="http://code.jquery.com/jquery-1.6.4.min.js"></script>
	<script src="//code.jquery.com/mobile/1.0/jquery.mobile-1.0.min.js"></script>
	<script type="text/javascript" src="http://dh.crc.nd.edu/sandbox/cyl/lib/protovis.js"></script>
	##PROTOVISDATA##
	<meta name="ROBOTS" content="NOINDEX,NOFOLLOW"/>
	<style>
		.illustration {
			width:750px;
			height:500px;
			position:absolute;
			left:50%;
			top:50%;
			margin:-250px 0 0 -375px;
		}
	</style>
</head>
<body>

	<div data-role="page" id="concordance" > 
		<div data-role="header" data-theme="b"><a data-rel="back" data-icon="back">Back</a><h1>Concordance</h1></div> 
		<div data-role="content">##CONTENT##</div> 
	</div> 
	
	<div data-role="page" id="map"> 
		<div data-role="header" data-theme="b"><a data-rel="back" data-icon="back">Back</a><h1>Map</h1></div> 
		<div data-role="content"><p>##MAP##</p></div> 
	</div> 
	
	<div data-role="page" id="network"> 
		<div data-role="header" data-theme="b"><a data-rel="back" data-icon="back">Back</a><h1>Network</h1></div> 
		<div data-role="content"><p>##NETWORK##</p></div> 
	</div> 
	
</body>
</html>
EOT

}


# default
sub default {

	return <<EOT;
<h1>Concordances</h1><p>This is a set of concordances against the full text content of some Catholic youth literature. You can use the concordances to analyze and evaluate texts quickly. Here are few texts that can be used as examples:</p>
<ul>
<li><a href="./?id=110">An explanation of the Baltimore catechism of Christian doctrine</a></li>
</ul>

EOT

}


# home
sub home {
	
	return <<EOT;
<h1>##TITLE##</h1>
##FORM##
##LINES##
EOT

}


# map
sub map {

	my $g = shift;
	my $v = shift;
	my $q = shift;
	
	return <<EOT;
<!-- greatest: $g -->
<!--   values: $v -->
	<div class='illustration'><img src="http://chart.apis.google.com/chart?chxr=0,10,100|1,0,$g&chxt=x,y&chbh=a&chs=400x400&cht=bvs&chds=0,$g&chd=t:$v" width="750" height="500" alt="map" /></div>
EOT

}


# form
sub form {

	my $cgi    = shift;
	my $script = $cgi->url . '/';

	return <<EOT;
	
<div class="ui-grid-b">

	<form name='f4' action='$script' method='get' class="ui-block-a">
	<input type='hidden' name='cmd' value='letters' />
	<input type='hidden' name='id' value='##ID##' />
		<div data-role='fieldcontain'>
			<label>Words beginning with:</label>
			<select  data-inline="true" name="l" onChange='javascript:document.f4.submit()'>
				<option value="a">a</option>
				<option value="b">b</option>
				<option value="c">c</option>
				<option value="d">d</option>
				<option value="e">e</option>
				<option value="f">f</option>
				<option value="g">g</option>
				<option value="h">h</option>
				<option value="i">i</option>
				<option value="j">j</option>
				<option value="k">k</option>
				<option value="l">l</option>
				<option value="m">m</option>
				<option value="n">n</option>
				<option value="o">o</option>
				<option value="p">p</option>
				<option value="q">q</option>
				<option value="r">r</option>
				<option value="s">s</option>
				<option value="t">t</option>
				<option value="u">u</option>
				<option value="v">v</option>
				<option value="w">w</option>
				<option value="x">x</option>
				<option value="y">y</option>
				<option value="z">z</option>
			</select>
			<!-- <input data-ajax='false' data-inline="true" type='submit' value='Go' /> -->
		</div>
	</form>

	<form name='f1' action='$script' method='get' class="ui-block-b">
		<input type='hidden' name='cmd' value='words' />
		<input type='hidden' name='id' value='##ID##' />
		<div data-role='fieldcontain'>
			<label>Most frequent words:</label>
			<select data-inline="true" name="n" onChange='javascript:document.f1.submit()'>
				<option value="10">10</option>
				<option value="25">25</option>
				<option value="50" selected='selected'>50</option>
				<option value="100">100</option>
				<option value="250">250</option>
			</select>
			<!-- <input data-ajax='false' data-inline="true" type='submit' value='Go' /> -->
		</div>
	</form>

	<form name='f3' action='$script' method='get' class="ui-block-c" >
		<input type='hidden' name='cmd' value='collocations' />
		<input type='hidden' name='id' value='##ID##' />
		<div data-role='fieldcontain'>
			<label>Most frequent phrases:</label>
			<select data-inline="true" name="n" onChange='javascript:document.f3.submit()' title='Number of phrases to return'>
				<option label="2" value="2" selected='selected'>2</option>
				<option label="3" value="3">3</option>
				<option label="4" value="4">4</option>
				<option label="5" value="5">5</option>
				<option label="6" value="6">6</option>
				<option label="7" value="7">7</option>
				<option label="8" value="8">8</option>
				<option label="9" value="9">9</option>
				<option label="10" value="10">10</option>
			</select>
			<!-- <input data-ajax='false' data-inline="true" type='submit' value='Go' /> -->
		</div>
	</form>
	
</div>
	
<form name='f5' action='$script' method='get'>
<input type='hidden' name='cmd' value='search' />
<input type='hidden' name='id' value='##ID##' />
<div data-role='fieldcontain'>
	<input type='text' name='query' value='##QUERY##'/>
	<button type="submit">Search</button>
	##SUBFORM##</div>
</div>
</form>

##SHOWMAP##
##SHOWNETWORK##

EOT

}


# update subform; retain selected values
sub subform {

	my $radius = shift;
	my $sort   = shift;
	
	my $subform = <<EOF;
<select name="radius" onChange='javascript:document.f5.submit()'>
	<option value="40">40</option>
	<option value="50">50</option>
	<option value="60">60</option>
	<option value="200">200</option>
	<option value="500">500</option>
	<option value="1000">1000</option>
</select>

<select name="sort" onChange='javascript:document.f5.submit()'>
<option value="left">left</option>
<option value="right">right</option>
<option value="none">none</option>
</select>
EOF

	# brute force dynamic updating; there's got to be a better way
	if ( $radius eq '40' ) { $subform =~ s/value="40" /value="40" selected="selected" / }
	elsif ( $radius eq '50' ) { $subform =~ s/value="50" /value="50" selected="selected" / }
	elsif ( $radius eq '60' ) { $subform =~ s/value="60" /value="60" selected="selected" / }
	elsif ( $radius eq '200' ) { $subform =~ s/value="200" /value="200" selected="selected" / }
	elsif ( $radius eq '500' ) { $subform =~ s/value="500" /value="500" selected="selected" / }
	elsif ( $radius eq '1000' ) { $subform =~ s/value="1000" /value="1000" selected="selected" / }
	else  { $subform =~ s/value="30" /value="30" selected="selected" / }
	
	if    ( $sort eq 'none' )  { $subform =~ s/value="none" /value="none" checked="checked" / }
	elsif ( $sort eq 'left' )  { $subform =~ s/value="left" /value="left" checked="checked" / }
	elsif ( $sort eq 'right' ) { $subform =~ s/value="right" /value="right" checked="checked" / }
	elsif ( $sort eq 'match' ) { $subform =~ s/value="match" /value="match" checked="checked" / }
	else  { $subform =~ s/value="none" /value="none" checked="checked" / }
	
	# done
	return $subform;
	
}


# open a file named by the input and return its contents
sub slurp {

	my $f = shift;
	open ( F, $f ) or die "Can't open $f: $!\n";
	my $r = do { local $/; <F> };
	close F;
	return $r;

}


# given an id, return author, title, and url
sub get_metadata {
	
	# get input
	my $id = shift;
		
	# extract
	my $resource = MyLibrary::Resource->new( id => $id );
	my $creator  = $resource->creator;
	my $name     = $resource->name;
	my $fkey     = $resource->fkey;
	
	# get text locations
	my $url = '';
	foreach my $location ( $resource->resource_locations ) {
	
		if ( $location->resource_location_type == TEXTLOCATION ) { $url = $location->location }
		
	}
		
	# done
	return ( $name, $creator, $url, $fkey );
	
}


sub getText {

	my $url = shift;
	
	# get the text to analyze
	my $ua       = LWP::UserAgent->new;
	my $request  = HTTP::Request->new( GET => $url );
	my $response = $ua->request( $request );
	
	# check for success
	if ( $response->is_success ) { return $response->content }
	else { return 0 }
	
}


sub concordance {

	my $corpus    = shift;
	my $query     = shift;
	my $radius    = shift;
	my $stopwords = shift;
	
	my $subset = '';
	my $concordance = Lingua::Concordance->new;
	$concordance->text( $corpus );
	$concordance->query( $query );
	$concordance->radius( $radius );
	foreach ( $concordance->lines ) { $subset .= $_ . ' ' }
	if ( ! $subset ) { &notfound }
	$subset =~ tr/a-zA-Zà-ƶÀ-Ƶ'()\-,.?!;:/\n/cs;
	$subset =~ s/([,.?!:;()\-])/\n$1\n/g;
	$subset =~ s/\n+/\n/g;
	my @tokens = split /\n/, lc( $subset );
	my %words = ();
	foreach ( @tokens ) {
	
		next if ( $_ =~ /[,.?!:;()\-]/ );
		next if ( $$stopwords{ $_ } );
		next if ( length( $_ ) == 1 );
		next if ( length( $_ ) < 3 );
		$words{ $_ }++;
	
	}

	return \%words;
	
}


sub same_breath {

	return <<JAVASCRIPT;
<div class='illustration'>
	<script type="text/javascript+protovis">
	
		var w = 750,
			h = 500;
		
		var vis = new pv.Panel()
			.width(w)
			.height(h)
			.fillStyle("white")
			.event("mousedown", pv.Behavior.pan())
			.event("mousewheel", pv.Behavior.zoom());
		
		var force = vis.add(pv.Layout.Force)
			.nodes(corpus.nodes)
			.links(corpus.links)
			.springLength(50)
			.chargeConstant(-1750)
			.bound(true);
			
		force.link.add(pv.Line);
		
		force.node.add(pv.Dot)
			.size(function(d) (d.linkDegree + 175) * Math.pow(this.scale, -1.5))
			.lineWidth(.5)
			.fillStyle("pink")
			.title(function(d) d.nodeName)
			.event("mousedown", pv.Behavior.drag())
			.event("drag", force);
		
		force.label.add(pv.Label).font('14px sans-serif');
		
		vis.render();
	
	</script>
</div>
JAVASCRIPT

}

sub coocurances {

	my $query = shift;
	my $words = shift;
	my $threshold = shift;
	
	my $t = 0;
	my %coocurrances = ();
	
	foreach ( sort { $$words{ $b } <=> $$words{ $a } } keys %$words ) {
	
		$coocurrances{ $_ } = $$words{ $_ };
		$t++;
		last if ( $t == $threshold );
		
	}
	
	return \%coocurrances;

}


sub buildStopwords {

	my $stopwords  = &getStopWords( 'en' );
	
	# supplement; sort of bogus
	$$stopwords{ 'a' }++;
	$$stopwords{ 'b' }++;
	$$stopwords{ 'c' }++;
	$$stopwords{ 'd' }++;
	$$stopwords{ 'e' }++;
	$$stopwords{ 'f' }++;
	$$stopwords{ 'g' }++;
	$$stopwords{ 'h' }++;
	$$stopwords{ 'j' }++;
	$$stopwords{ 'k' }++;
	$$stopwords{ 'l' }++;
	$$stopwords{ 'm' }++;
	$$stopwords{ 'n' }++;
	$$stopwords{ 'o' }++;
	$$stopwords{ 'p' }++;
	$$stopwords{ 'q' }++;
	$$stopwords{ 'r' }++;
	$$stopwords{ 's' }++;
	$$stopwords{ 't' }++;
	$$stopwords{ 'u' }++;
	$$stopwords{ 'v' }++;
	$$stopwords{ 'w' }++;
	$$stopwords{ 'x' }++;
	$$stopwords{ 'y' }++;
	$$stopwords{ 'z' }++;
	$$stopwords{ '&apos' }++;
	
	return $stopwords;

}



# return true or die
1;

#!/usr/bin/perl

# pos-tag.pl - produce a list of words (tokens), lemmas, and parts-of-speech from a text file
# Feburary 4, 2011 - first investigations
# December 6, 2011 - moved to dh.crc.nd.edu, and escaped entities on the input

# require
use strict;
use Lingua::TreeTagger;

# sanity check
my $file = $ARGV[ 0 ];
if ( ! $file ) {

	print "Usage: $0 <filename>\n";
	exit;
	
}

# intialize, tag, and output
my $tagger = Lingua::TreeTagger->new( 'language' => 'english' );
my $text = &escape_entities( &slurp( $file ));
my $tagged_text = $tagger->tag_text( \$text );
foreach my $token ( @{ $tagged_text->sequence() } ) { print  lc( $token->original ) . "\t" . $token->lemma . "\t" . $token->tag . "\n" }

# done
exit;


sub escape_entities {

	# get the input
	my $s = shift;
	
	# escape
	$s =~ s/&/&amp;/g;
	$s =~ s/</&lt;/g;
	$s =~ s/>/&gt;/g;
	$s =~ s/"/&quot;/g;
	$s =~ s/'/&apos;/g;

	# done
	return $s;
	
}



sub slurp {

	# open a file named by the input and return its contents
	my $f = @_[0];
	my $r;
	open (F, "< $f");
	while (<F>) { $r .= $_ }
	close F;
	return $r;

}

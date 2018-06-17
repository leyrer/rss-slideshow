#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use URI::URL;
use XML::Feed;
use Image::Grab;
use HTML::TreeBuilder::XPath;
use WWW::Mechanize;
use File::Temp;
use Digest::MD5::File qw(file_md5_hex file_md5_base64);
use Data::Dumper;

my $cache_path = '';

if ( $#ARGV >= 1 ) {
	$cache_path = $ARGV[1];
	print "JO $cache_path<\n";
} else {
	$cache_path = '/home/leyrer/projects/rss-slideshow/cache';
	print "NO\n";
}

my $num_entries = 0;
my $count = 0;
my $feed = "";
my $max_pic = int(((60*2)/7));

my @skipwords;
my @overridewords;
my $url = '';

$| = 1;

printf "pqiv --slideshow-interval=7 --fullscreen --fade --lazy-load --slideshow --shuffle --hide-info-box --scale-images-up --allow-empty-window --disable-backends=archive,archive_cbx --low-memory --watch-directories \"$cache_path\" &> /dev/null &\n";

&config();

do {
	do {
		undef $feed;
		$feed = XML::Feed->parse(URI->new($url)) or die XML::Feed->errstr;
		print $feed->title, "\n", $feed->link, "\n";
	} while ( &skipfeed(\@skipwords, \@overridewords, $feed->title, $feed->link));

	for my $entry ($feed->entries) {
		my $l = $entry->link . '/.rss';
		my $c = $entry->content;
		my $b = $c->body;
		my $fn ='';
		if( $b =~ /<a href=\"([^>]+?)\">\[link\]<\/a>/mi) {
			my $t = $1;
			my $url1 = new URI::URL $t;
			
			if($url1->epath =~ /(gif|jpg|jpeg|png|avi|mp4|mov)$/gi ) {
				&fetch_image($t);
			} elsif ($t =~ /imgur\.com/i ) {
				imgur($t);
			} else {
				# print "Unknown URL $t\n";
			}
			undef $t;
			undef $url1;
		} else {
			print "Link: NONE\n";
		}
		undef $c;
		undef $b;
	}
	undef $feed;

	system("touch $cache_path");

	opendir my ($dh), $cache_path;
	my $num_entries = () = readdir($dh);
	closedir($dh);

	# print "$num_entries / $max_pic \n\n";

	if ($num_entries > $max_pic ) {
		print `date`;
		print "sleeping ...\n";
		sleep ((60*2));
		my @files = (sort{(stat $a)[9] <=> (stat $b)[9]}glob "$cache_path/*");
		my $mf = int(($#files) * 0.66);
		for( my $y=0; $y <= $mf; $y++) {
			# print "Deleting " . $files[$y] . "...\n";
			if( not unlink($files[$y]) ) {
				warn "\tNOT deleted!\n";
			}
		}
	}


} while (1);

print "Count: $count\n";
exit;

sub imgur {
	my ($url) = @_;
	my $mech=WWW::Mechanize->new(agent => 'imgur-scraper', onerror => undef);
	my $tree= HTML::TreeBuilder::XPath->new;
	$mech->get($url);
	if( $mech->success() ) {
		$tree->parse($mech->content);
		
		my @img = $tree->findnodes( '//img[@class="post-image-placeholder"]');
		foreach my $i (@img) {
			my $s = 'https:' . $i->attr('src');
			# print "\t\tLink: $s\n";
			&fetch_image($s);
		}
		undef @img;
	}
	undef $mech;
	undef $tree;
}

sub fetch_image {
	my ($img) = @_;
	my $url = new URI::URL $img;
	my $fn = '';
	my $suff = '';
	my $type = '';
	my $pic = new Image::Grab;
	$pic->url($img);
	my $erg = $pic->grab(3);
	if( not defined $pic->image ) {
		print "\tCouldn't get $url\n";
		return();
	}
	if( defined $pic->type ) {
		$pic->type =~ /^(.*?)\/(.+)$/i;
		$suff = $2;
		$type = $1;
	}
	if (not defined($suff) or $suff eq '' or $suff eq 'html') {
		$url->path =~ /([^\/]+)\.(.+)$/i;
		$suff = ".$2";
	}

	if( $type eq 'image' or $type eq 'video' or $type eq 'text' or $type eq '' ) {
		$url->path =~ /([^\/]+)\.(.+)$/i;
		$fn = "$cache_path/$1.$suff";

		if( -f $fn ) {
			my $digest = file_md5_hex($fn);
			if( $pic->md5 eq $digest) {
				return();
			} else {
				$fn = "$cache_path/" . $pic->md5 . ".$suff";
				if( -f $fn ) {
					my $x = File::Temp->new( DIR => $cache_path, SUFFIX => ".$suff" );
					$fn = $x->filename;
				}
			}
		}

		# print "\tLink: $url | " . $fn . "\n";
		open(IMAGE, ">$fn") or print "ERROR $fn: $! \n";
		binmode IMAGE;  # for MSDOS derivations.
		print IMAGE $pic->image;
		close IMAGE;
		$count++;
	} else {
		warn "$img is NO IMAGE but " . $pic->type ;
	}
	undef $pic;
}

sub skipfeed {
	my($badlist, $goodlist, $title, $url) = @_;
	my $ret = 0;
	foreach my $badword (@{$badlist}) {
		if( $title =~ /$badword/i or $url =~ /$badword/i ) {
			foreach my $goodword (@{$goodlist}) {
				# print "\tbad: $badword on $title | $url ...\n";
				if( $title =~ /$goodword/i or $url =~ /$goodword/i ) {
					# print "\t\tgood: $goodword ...\n";
					return($ret);
				}
			}
			$ret = 1;
			print "\tskipping $badword ...\n";
			open(OUT, ">>skipped.txt") or die "Can't write skipped.txt. $!\n";
			print OUT "$url\t$title\t$badword\n";
			close(OUT);
			return($ret);
		}
	}
	return($ret);
}

sub config {
	# my () = @_;
	my $file = $ARGV[0];
	open( IN, $file) or die "Error reading $file. $!\n";
	$url = <>;
	chomp $url;
	while( my $line = <>)  {   
		chomp $line;
		my @data = split(/\t/,$line);
    	if( $data[0] eq '-') {
			push(@skipwords, $data[1]);
		} else {
			push(@overridewords, $data[1]);
		}
	}
	close(IN);
}


#!usr/bin/perl
use strict;
use warnings;
use 5.010; 
use JSON;
use autodie;
use Pod::Usage qw(pod2usage);
use Getopt::Long qw(GetOptions);
use DBI;
use REST::Client;
use threads;
use Thread::Queue;

################ SQLite (for cache)  #################

my $db_cache_file = 'cache.db';
my $time_exp_cache = 900; # seconds
my $sql_create_image_details = <<'SCHEMA';
CREATE TABLE IF NOT EXISTS image_details(
	id VARCHAR(50) PRIMARY KEY,
	author VARCHAR(50),
	camera VARCHAR(50),
	tags VARCHAR(50),
	cropped_picture VARCHAR(100),
	full_picture VARCHAR(100)
);
SCHEMA

my $sql_create_token = <<'SCHEMA';
CREATE TABLE IF NOT EXISTS token(
	id INTERGER PRIMARY KEY,
	token VARCHAR(50)
);
SCHEMA

my $sql_create_cache = <<'SCHEMA';
CREATE TABLE IF NOT EXISTS cache(
	id INTERGER PRIMARY KEY,
	updated_at INTEGER(10)
);
SCHEMA

my $dbh = DBI->connect("dbi:SQLite:dbname=$db_cache_file","","", {});
$dbh->do($sql_create_image_details);
$dbh->do($sql_create_token);
$dbh->do($sql_create_cache);

################# API Config #####################
my $api_host = "http://interview.agileengine.com";
my $api_key = "23567b218376f79d9415";
my $api_client = REST::Client->new();
my $api_token = get_token($api_key, $dbh);

################# APP Config ###################

my $man = 0;
my $help = 0;
my $method = '';
my $page;
my $search_param = '';
my $url_method = '';
my $id_image;
my @get_response;


################# Arguments handler #####################

pod2usage("$0: No arguments were provided!") if ((@ARGV == 0) && (-t STDIN));

GetOptions('help|?' => \$help, 
			 'man' => \$man,
			 'method=s' => \$method,
			 'page=i' => \$page,
			 'search_param=s' => \$search_param,
			 'id_image=s' => \$id_image) or pod2usage(2);

pod2usage(1) if $help;
pod2usage(-verbose => 2) if $man;

if ($method eq '') { 
	#die "Please provide a method";
}

################### Starting APP ######################

#update cache if necessary
check_cache($time_exp_cache, $dbh);

#Routing depending on options
if ($method eq 'get_images') {
	if ($page) {
		$url_method = '/images?page=' . $page;
	}
	else {
		$url_method = '/images';
	}
	@get_response = get_request($api_host,$url_method, $api_token, $api_client);
	if (auth_status(\@get_response)){
		print_image_list(\@get_response);
	}
	else{
		say "Requesting new token. Please try again.";
		api_auth($api_key, $dbh);
	}
	
}
elsif ($method eq 'image_details') {
	if (!$id_image){
		die "Missing -id_image parameter \n"
	}
	$url_method = '/images/' . $id_image;
	@get_response = get_request($api_host,$url_method, $api_token, $api_client);
	if (auth_status(\@get_response)){
		print_image_details(\@get_response);
	}
	else{
		say "Requesting new token. Please try again.";
		api_auth($api_key, $dbh);
	}
}
elsif ($method eq 'search') {
	if ($search_param eq ''){
		die "Missing -search_param parameter \n";
	}
	my @result = search($search_param, $dbh);
	print_image_details(\@result, "SEARCH RESULTS \nfor: $search_param");
}
elsif($method eq 'auth') {
	say "Requesting new token...";
	api_auth($api_key, $dbh);
}
elsif ($method eq 'cache') {
	say "Reloading cache...";
	cache_full_data($api_host, $api_token, $api_client,$dbh);
}
else {
	die "Method not found \n";
}
sub auth_status {
	my ($r) = @_;
	my @r = @{$r};
	if (defined($r[0]->{'status'}) && $r[0]->{'status'} eq 'Unauthorized') {
		return 0;
	}
	else{
		return 1;
	}
}
sub check_cache{
	my ($time_exp_cache, $dbh) = @_;
	my $time = time();
	my $sth = $dbh->prepare("SELECT updated_at FROM cache WHERE id = 1;");
	$sth->execute();
	my $updated_at = $sth->fetchrow_array;
	if (!defined($updated_at)) {
		say "Caching image data..";
		cache_full_data($api_host, $api_token, $api_client,$dbh);
		$dbh->do ("INSERT INTO cache VALUES (1, ".time().");");
		return;
	}
	elsif(($time-$updated_at)>$time_exp_cache){
		say "Caching image data...";
		cache_full_data($api_host, $api_token, $api_client,$dbh);
		$dbh->do ("UPDATE cache SET updated_at = ".time()." WHERE id = 1;");
		return;
	}
	
}
sub cache_full_data {
	# Fetching all the data to save into database cache. Multithreads used to improve performance
	my ($api_host, $api_token, $api_client,$dbh) = @_;
	my $q = Thread::Queue->new();
	
	my $sql = "INSERT INTO image_details VALUES ";
 	my @url_list;
	my @url_list_details;
	
	my @d = get_request($api_host,'/images/', $api_token, $api_client);
	my $total_pages = $d[0]->{'pageCount'};
	for my $i (1..$total_pages){
		push @url_list, $api_host . '/images?page=' . $i;
	}
	my @thr_list = map {
		threads->create(sub {
			my @responses = ();
			while (defined (my $url_list = $q->dequeue())) {
				$api_client->GET($url_list, {"Content-Type"=> "application/json","Authorization" => "Bearer $api_token"});
				push @responses, decode_json($api_client->responseContent())  ;
			}
			return @responses;
		});
	} 1..$total_pages;
	$q->enqueue($_) for @url_list;
	$q->enqueue(undef) for 1..$total_pages;

	foreach (@thr_list) {
		my @responses_thread = $_->join();
		for (@responses_thread){
			push @url_list_details, map {$api_host . '/images/' . $_->{'id'}} @{$_->{'pictures'}};
		};
	}
	my @thr = map {
		threads->create(sub {
			my @responses = ();
			while (defined (my $url = $q->dequeue())) {
				$api_client->GET($url, {"Content-Type"=> "application/json","Authorization" => "Bearer $api_token"});
				push @responses, decode_json($api_client->responseContent())  ;
			}
			return @responses;
		});
	} 1..10;
	$q->enqueue($_) for @url_list_details;
	$q->enqueue(undef) for 1..10;

	foreach (@thr) {
		my @responses_of_this_thread = $_->join();
		for (@responses_of_this_thread){
			my $id = (defined($_->{'id'})) ? $_->{'id'} : "";
			my $author = (defined($_->{'author'})) ? $_->{'author'} : "";
			my $camera = (defined($_->{'camera'})) ? $_->{'camera'} : "";
			my $tags = (defined($_->{'tags'})) ? $_->{'tags'} : "";
			my $cropped_picture = (defined($_->{'cropped_picture'})) ? $_->{'cropped_picture'} : "";
			my $full_picture = (defined($_->{'full_picture'})) ? $_->{'full_picture'} : "";
			$sql .= "(\'$id\',\'$author\',\'$camera\',\'$tags\',\'$cropped_picture\',\'$full_picture\'),";
		};
	}
	#Remove last coma
	$sql = substr $sql, 0, -1;
	$sql = $sql . ';';
	
	# Before insert data, truncate table
	$dbh->do("DELETE FROM image_details;");
	$dbh->do($sql);
	
}

sub search {
	my ($param, $dbh) = @_;
	my @res;
	my $sql = "SELECT * FROM image_details WHERE 
				\"id\" LIKE '%".$param."%' 
				OR \"author\" LIKE '%".$param."%' 
				OR \"camera\" LIKE '%".$param."%' 
				OR \"tags\" LIKE '%".$param."%' 
				OR \"cropped_picture\" LIKE '%".$param."%' 
				OR \"full_picture\" LIKE '%".$param."%';";
	my $sth = $dbh->prepare($sql);
	$sth->execute();
	while (my $row = $sth->fetchrow_hashref) {
		push @res , $row; 
	}
	return @res;
}

sub print_image_details {
	my ($data, $title) = @_;
	$title //= "\nIMAGE DETAIL";
	say "\n\t$title";
	for (@{$data}){
		say "\nID: \t\t $_->{'id'}";
		say "Author: \t $_->{'author'}";
		say "Camera: \t $_->{'camera'}";
		say "Tags: \t\t $_->{'tags'}";
		say "Cropped Picture: $_->{'cropped_picture'}";
		say "Full Picture: \t $_->{'full_picture'} \n";
	}
}

sub get_token{
	my ($api_key, $dbh) = @_;
	my $sql = "SELECT token FROM token;";
	my $sth = $dbh->prepare($sql);
	$sth->execute();
	my $row = $sth->fetchrow_array;
	if (!defined($row)){
		return api_auth($api_key, $dbh);
	}
	return $row;
}

sub api_auth {
	my ($api_key, $dbh) = @_;
	my $sql;
	$api_client->POST($api_host . "/auth", '{"apiKey":"'.$api_key.'"}', {"Content-Type"=> "application/json","Authorization" => "Bearer $api_key"});
	my $decoded_response = decode_json($api_client->responseContent());
	
	if( $decoded_response->{'auth'}){
		save_token($decoded_response->{'token'}, $dbh);
		return $decoded_response->{'token'}
	}
	die "Couldn't get token \n";
}

sub save_token{
	my ($token, $dbh) = @_;
	my $sql;
	my $sth = $dbh->prepare("SELECT token FROM token;");
	$sth->execute();
	my $row = $sth->fetchrow_array;
	if (!defined($row)){
		$sql = "INSERT INTO token VALUES (1, \'$token\');";
	}
	else {
		$sql = "UPDATE token SET token = \'$token\' WHERE id = 1"; 

	}
	$dbh->do($sql);
}


sub get_request {
	my ($api_host,$url_method, $api_token, $obj) = @_;
	$obj->GET($api_host . $url_method, {"Content-Type"=> "application/json","Authorization" => "Bearer $api_token"});
	return decode_json($api_client->responseContent());
	
}

sub print_image_list {
	my ($data) = @_; # array
	my @d = @{$data};
	say "";
	say "\t\tIMAGES LIST";
	say "\t ID \t\t\t\t CROPPED PICTURE";
	for my $key (keys @{$d[0]->{'pictures'}}){
		my $val = @{$d[0]->{'pictures'}}[$key];
		say $val->{'id'}, "\t\t", $val->{'cropped_picture'};
	}
	say "\n Current page: $d[0]->{'page'} \t Page Count: $d[0]->{'pageCount'}";
	if ($d[0]->{'hasMore'}) { say "More results in the next page. Use: -method=get_images -page=n"; }
	
}



#########################  POD SECTION ##############################

__END__
=head1 NAME

Image Gallery Search - Solution in Perl.

=head1 SYNOPSIS

perl image_gallery_serach [-help|-man] -method [-page|-search_param]

=head1 OPTIONS

=over 4

=item B<-help, --help>

Prints a brief help message and exits.

=item B<-man, --man>

Prints the manual page and exits.

=item B<-method> -> REQUIRED

Method to execute

=item B<-search_param> ->

Search parameters

=item B<-page>

The numbe of page to fetch

=item B<-auth>

Request new token

=back
    
=head1 DESCRIPTION

Image Gallery Search script allows you to search stored images based on attribute fields. It provides a bunch of methods to get the data that you need in a fastest way. Also, it uses a cache to speed up the searches.

=head1 AUTHOR

Juan Alexis Rodiz. 2020

=cut
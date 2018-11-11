#!/usr/bin/env perl
use Mojolicious::Lite;
use Path::Tiny;
use Capture::Tiny ':all';
use Mojo::IOLoop::Subprocess;
use Mojo::Util qw(dumper);
    
get '/' => sub {
  my $c = shift;
  $c->render(template => 'index');
};

post '/' => sub {
    my $c = shift;
    my $qx = qx/ps -A/;

    my $params = $c->req->params->to_hash;
    app->log->info(dumper $params);
    
    my @ps = grep { /scanimage/ } split /\n/, qx/ps -A/;
    app->log->info(@ps);

    if (@ps) {
	return $c->render(json => { message => 'scanner busy' });
    } else {

	my $folder = path('/srv/samba-share/scans/');
	my @children = map { $_->basename } grep { $_->basename =~ /^scan(\d{4,4}).jpg$/ } sort $folder->children;

	my ($n) = map { /scan(\d+)\.jpg/; 0 + $1; } reverse sort @children;
	my $scanner = 'hpaio:/net/HP_LaserJet_200_colorMFP_M276n?ip=192.168.1.201';
	my $res = $c->param('resolution');
	my $out = sprintf '%s/scan%04d.jpg', $folder, ++$n;
	my ($qx);
	if ($c->param('source') eq 'plate') {
	    $qx = "scanimage -v --source Flatbed -d $scanner --mode Color --resolution $res --format jpeg -x 215.9 -y 296.9 > $out";
	} elsif ($c->param('source') eq 'feeder') {
	    my $options = '--batch-print --mode Color --source ADF --format jpeg';
	    $qx = "scanimage -v --batch=$folder/scan%04d.jpg --batch-start=$n -d $scanner --resolution $res $options -x 215.9 -y 296.9";
	}
	app->log->info("Scanning with command\n" . $qx);
	my $subprocess = Mojo::IOLoop::Subprocess->new;
	$subprocess->run(
			 sub {
			     my $subprocess = shift;
			     my ($stdout, $stderr, $exit) = capture { system( $qx ) };
			     return split /\n/, $stderr;
			 },
			 sub {
			     my ($subprocess, $err, @results) = @_;
			     if ($params->{print} eq 'yes') {
				 if ($params->{source} eq 'plate') {
				     @results = ($out);
				 } else {
				     @results =
					 map { sprintf '%s/scan%04d.jpg', $folder, $_ }
					 map { /(\d{4,4})/; $1 }
					 grep { /^scanned/i }
					 @results;
				 }
				 for (@results) {
				     app->log->info("printing $_");
				     qx/lp $_/;
				 }
			     }
			 }
			);
	
	$c->render(json => { number => $n,
			     message => 'scanning started',
			     source => $c->param('source'),
			     command => $qx,
			     file => $out });
    }
};

get '/status' => sub {
    my $c = shift;
    my @ps = split /\n/, qx|ps -A|;
    my $busy = grep { /\bscanimage\b/} @ps;
    $c->render(json => { busy => $busy });
};

get '/scans' => [format => ['json'] ] => sub {
    my $c = shift;
    my $folder = path('/srv/samba-share/scans/');
    $c->render(json => { scans => [ (
				     map { $_->[0] }
				     sort { $b->[1] <=> $a->[1] } 				     
				     map { [ $_->basename, $_->stat->mtime ] }
				     grep { /\.jpg$/ } $folder->children
				    ) ] });
};

get '/scans';

app->start;
__DATA__

@@ fii.html.ep
% layout 'default';
% title 'Welcome';
<style>
  body { background-color: Gainsboro }
  * { font-family: 'Lato', sans-serif }
  .button, .form {
      padding: 30px; margin: 15px; font-size: 6vw
  }
  .button { color: white; background-color: RoyalBlue; text-align: center }
  h4:first-child { margin-top: 0px; }
  h4 {
      margin-left: -30px; margin-right: -30px; margin-bottom: 24px; margin-top: 24px;
      padding-top: 6px; padding-bottom: 6px;
      color: white; background-color: DarkGray; text-align: center; 
  }
  label { min-width: 4em; display:inline-block }
</style>
<div class="form"><form id="settings">
    <h4>Resolution</h4>

    % my @res = qw(150 300 600);
% for (qw/low medium high/) {
    <div>
      <input type="radio" id="<%= $_ %>_res" name="resolution" value="<%= $res[0] %>">
      <label for="<%= $_ %>_res"><%= $_ %> (<%= shift @res %> dpi)</label>
    </div>
    % }
    <h4>Source</h4>
    <div>
    % for (qw/plate feeder/) {
      <input type="radio" id="<%= $_ %>_src" name="source" value="<%= $_ %>">
      <label for="<%= $_ %>_src"><%= $_ %></label>
    % }
    </div>
    <h4>Print scans</h4>
    <div>
    % for (qw/yes no/) {
      <input type="radio" id="<%= $_ %>_print" name="print" value="<%= $_ %>">
      <label for="<%= $_ %>_print"><%= $_ %></label>
    % }
    </div>
  </form>
</div>
<div class="button" id="scan">scan</div>
<script>
    $(function(){
	    /mobile/i.test(navigator.userAgent) && setTimeout(function () {
		window.scrollTo(0, 1);
	    }, 1000);
	$('#medium_res, #feeder_src, #no_print').prop('checked', true);
	$('.button').click(function(e){
	    // console.log($(e.target).attr('id'));
	    // console.log($('form').serialize());
	    $.post("<%= url_for('/') %>" + '?' + $('form').serialize(),
		   function(d){
		       console.log(d);
		   })
	})
    })
</script>

@@ layouts/default.html.ep
<!DOCTYPE html>
<html>
  <head><title><%= title %></title>
    <meta name="mobile-web-app-capable" content="yes">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <link href="https://fonts.googleapis.com/css?family=Lato" rel="stylesheet"> 
    <script
      src="https://code.jquery.com/jquery-3.3.1.min.js"
      integrity="sha256-FgpCb/KJQlLNfOu91ta32o/NMZxltwRo8QtmkMRdAu8="
      crossorigin="anonymous"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/zingtouch/1.0.6/zingtouch.min.js"></script>
  </head>
  <body><%= content %></body>
</html>
@@ style.html.ep
<style>
  body { background-color: Gainsboro }
  * { font-family: 'Lato', sans-serif }
  .button, .form {
      padding: 30px; margin: 15px; font-size: 6vw
  }
  .scans {
      padding: 10px; margin: 5px; font-size: 6vw
  }
  img.scan { width: 100% }
  .button { color: white; background-color: RoyalBlue; text-align: center }
  h4:first-child { margin-top: 0px; }
  h4 {
      margin-left: -30px; margin-right: -30px; margin-bottom: 24px; margin-top: 24px;
      padding-top: 6px; padding-bottom: 6px;
      color: white; background-color: DarkGray; text-align: center; 
  }
  label { min-width: 4em; display:inline-block }
    .nav { display: inline-block; height: 2em; width: 2em; text-align: center; background-color: RoyalBlue; font-size: 8vw; color: white }
</style>
@@ index.html.ep
% layout 'default';
% title 'scan';
%= include 'style';
<div class="form"><form id="settings">
    <h4>Resolution</h4>
    <div>
      <input type="radio" id="low_res" name="resolution" value="150">
      <label for="low_res">low (150 dpi)</label>
    </div>
    <div>
      <input type="radio" id="medium_res" name="resolution" value="300" checked>
      <label for="medium_res">medium (300 dpi)</label>
    </div>
    <div>
      <input type="radio" id="high_res" name="resolution" value="600">
      <label for="high_res">high (600 dpi)</label>
    </div>
    <h4>Source</h4>
    <div>
      <input type="radio" id="feeder_src" name="source" value="feeder" checked>
      <label for="feeder_src">feeder</label>
      <input type="radio" id="plate_src" name="source" value="plate">
      <label for="plate_src">plate</label>
    </div>
    <h4>Print scans</h4>
    <div>
      <input type="radio" id="yes_print" name="print" value="yes">
      <label for="yes_print">yes</label>
      <input type="radio" id="no_print" name="print" value="no" checked>
      <label for="no_print">no</label>
    </div>
  </form>
</div>
<div class="button" id="scan">scan</div>
<script>
    $(function(){
	$('.button').click(function(e){
	    $.post("<%= url_for('/') %>" + '?' + $('form').serialize(),
		   function(d){ console.log(d) }
		  )
	})
    })
</script>
@@ scans.html.ep
% layout 'default';
% title 'scan';
%= include 'style';
<div class="scans" id="scans">
<img id="scan" class="scan" src="http://192.168.1.144/scans/scan2040.jpg">
<div class="nav" id="p">&laquo;</div>
<div class="nav" id="n">&raquo;</div>
</div>
<script>
    $(function(){
	var scans = [];
	var i = 0;
	var containerElement = document.getElementById('scans');	
	$.get("<%= url_for('/scans') . '.json' %>",
	      function(d){
		  scans = d.scans;
		  console.log(scans);
		  $('#scan').attr('src', 'http://192.168.1.144/scans/' +  scans[i])
	      }
	     )
	$('#p').click(function(){
	    console.log(i);
	    console.log(scans.length);	    
	    if (i < scans.length) {
		i++;
		console.log(scans[i])
		$('#scan').attr('src', 'http://192.168.1.144/scans/' +  scans[i])
	    }
	})
	$('#n').click(function(){
	    if (i > 0) {
		i--;
		$('#scan').attr('src', 'http://192.168.1.144/scans/' +  scans[i])
	    }
	})
    })
</script>

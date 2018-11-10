#!/usr/bin/env perl
use Mojolicious::Lite;
use Path::Tiny;

get '/' => sub {
  my $c = shift;
  $c->render(template => 'index');
};

post '/' => sub {
    my $c = shift;
    my $qx = qx/ps -A/;
    
    my @ps = grep { /scanimage/ } split /\n/, qx/ps -A/;
    app->log->info(@ps);
    if (@ps) {
	$c->render(json => { message => 'scanner busy' });
    } else {

	my $folder = path('/srv/samba-share/scans/');
	my @children = map { $_->basename } grep { $_->basename =~ /^scan(\d{4,4}).jpg$/ } sort $folder->children;

	my ($n) = map { /scan(\d+)\.jpg/; 0 + $1; } reverse sort @children;
	my $scanner = 'hpaio:/net/HP_LaserJet_200_colorMFP_M276n?ip=192.168.1.201';
	my $res = $c->param('resolution');

	my $out = sprintf '%s/scan%04d.jpg', $folder, ++$n;
	if ($c->param('source') eq 'plate') {
	    my $qx = "scanimage --source Flatbed -d $scanner --mode Color --resolution $res --format jpeg -x 215.9 -y 296.9 > $out";
	    app->log->info($qx);
	    qx|$qx &|
	} elsif ($c->param('source') eq 'feeder') {
	    my $qx = "scanimage --batch=scan%04d.jpg --batch-start=$n --batch-print -d $scanner --mode Color --source ADF --resolution $res --format jpeg -x 215.9 -y 296.9";
	    app->log->info($qx);
	    qx|$qx &|
	}
	$c->render(json => { number => $n, message => 'scanning started', source => $c->param('source'), file => $out });
    }
};

get '/status' => sub {
    my $c = shift;
    my @ps = split /\n/, qx|ps -A|;
    my $busy = grep { /\bscanimage\b/} @ps;
    $c->render(json => { busy => $busy });
};

app->start;
__DATA__

@@ index.html.ep
% layout 'default';
% title 'Welcome';
<style>
  body { background-color: Gainsboro }
  * { font-family: 'Lato', sans-serif }
  .button, .form {
      padding: 30px; margin: 15px; font-size: 6vw
  }
  .button {
      color: white; background-color: RoyalBlue; text-align: center; 
  }
  h4:first-child {
      margin-top: 0px;
  }
  h4 {
      margin-left: -30px; margin-right: -30px; margin-bottom: 24px; margin-top: 24px;
      padding-top: 6px; padding-bottom: 6px;
      color: white; background-color: DarkGray; text-align: center; 
  }
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
% for (qw/plate feeder/) {
    <div>
  <input type="radio" id="<%= $_ %>_src" name="source" value="<%= $_ %>">
  <label for="<%= $_ %>_src"><%= $_ %></label>
  </div>
    % }
  </form>
</div>
<div class="button" id="scan">scan</div>
<script>
    $(function(){
	$('#medium_res, #feeder_src').prop('checked', true);
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
  <head><title><%= title %></title></head>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <link href="https://fonts.googleapis.com/css?family=Lato" rel="stylesheet"> 
    <script
      src="https://code.jquery.com/jquery-3.3.1.min.js"
      integrity="sha256-FgpCb/KJQlLNfOu91ta32o/NMZxltwRo8QtmkMRdAu8="
      crossorigin="anonymous"></script>  <body><%= content %></body>
</html>

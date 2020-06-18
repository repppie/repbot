use API::Discord;
use Cro::HTTP::Client;
use Cro::HTTP::Header;

my \TOKEN = (|EVALFILE "keys.p6").first;

my \TWITTER_PAT = /'http' 's'? '://twitter.com/' [<-[/]> && \H]+ '/status/'
     \d+/;
my \GIF_PAT = /'http' 's'? '://' \S+ '/' [ \S+ '.gif' ]/;
my \TENOR_PAT = /'http' 's'? '://tenor.com/view/' \S+/;
my \TWITTER_EMBED = 'https://publish.twitter.com/oembed?url=';

my %last-twitter;
my %last-gif;
my %replies;

my $http = Cro::HTTP::Client.new: http => 1.1;

sub get-tenor-gif($chan, $url) {
	my $body = try {
		my $resp = await $http.get($url);
		my $body = await $resp.body;
		my $gif = $body ~~ m/'content="' ('https://' <-[/]>+
		    '.tenor.com/' \S+ 'tenor.gif' <-[\"]>*) '">'/;
		%last-gif{$chan.id} = $gif[0].Str;
		CATCH { default { .Str.say }}
	}
}

sub speed-up-gif($chan, $msg) {
	my $url = $msg ~~ GIF_PAT;

	my $body = try {
		my $resp = await $http.head($url.Str);
		die "too big {$resp.header('content-length').Int}" if
		    $resp.header('content-length').Int >= 8 +< 20;
		$resp = await $http.get($url.Str);
		CATCH { default { .Str.say }}
		await $resp.body
	}
	return unless $body;

	note "{DateTime.now} speeding up {$url}";

	try {
		my $in-gif = open "in.gif", :w, :bin;
		$in-gif.write($body);

		my $exit_code = run './speed-up-gif', 'in.gif', 'out.gif';
		return if $exit_code != 0;
		LEAVE {
			$in-gif.close;
			unlink 'in.gif';
			unlink 'out.gif';
		}
		CATCH { default { .Str.say }}

		$chan.send-message(:embed(image => url =>
		    "attachment://out.gif"), :file("out.gif"))
	}
}

sub twitter($msg) {
	my $urls = $msg.content.match(TWITTER_PAT, :global);
	my $chan = await $msg.channel;

	return without $msg;

	for $urls.list -> $u {
		my $resp = await $http.get(TWITTER_EMBED  ~ $u.Str);
		my $body = await $resp.body;
		CATCH {
			default {
				.Str.say;
				for .backtrace {
					next if .file.starts-with('SETTING::');
					next unless .subname;
					$*ERR.say: "in {.subname} at {.file} line {.line}";
				}
			}
		}
		my $html = $body<html>;
		my $im;
		if $html ~~ m:g/'href="' (<-[\"]>*) '"'/.grep({ $_ !~~
		    /'twitter.com'/}).first -> $m {
			my $resp = await $http.head($m[0]):!follow;
			if $resp.status == 301 {
				$im = $_ unless /'twitter.com' .*
				    ('/photo/' | '/hashtag/')/ given
				    $resp.header('location');
			}
		}
		$im = 'False' when !$im && rand < 0.25;
		%replies{$msg.id} = $chan.send-message($im) if $im;
	}
}

sub MAIN() {
	my $discord = API::Discord.new(:token(TOKEN));
	$discord.connect.then({ say "connected!" });

	react {
		whenever $discord.messages -> $m {
			my $chan = await $m.channel;
			when $m.content ~~ TWITTER_PAT {
				when ($m.content ~~ m:i/'embed'/) {
					twitter($m);
				}
				%last-twitter{$chan.id} = $m;
			}
			when $m.content ~~ m:i/^embed \s+ that/ {
				twitter(%last-twitter{$chan.id}:delete) if
				    %last-twitter{$chan.id}:exists;
			}

			when $m.content ~~ GIF_PAT {
				%last-gif{$chan.id} = $m.content;
			}
			when $m.content ~~ TENOR_PAT {
				get-tenor-gif($chan, $m.content);
			}
			when $m.content ~~ m:i/^speed \s+ that \s+ up/ {
				%replies{$m.id} = speed-up-gif($chan,
				    %last-gif{$chan.id}:delete) if
				    %last-gif{$chan.id}:exists;
			}

			for $m.attachments {
				%last-gif{$chan.id} = .url if .url ~~ GIF_PAT;
			}
		}

		whenever $discord.events -> $e {
			(await %replies{$e<d><id>}).delete when $e<t> eq
			    'MESSAGE_DELETE' and %replies{$e<d><id>}:exists;
		}
	}
}

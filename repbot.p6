use API::Discord;
use Cro::HTTP::Client;
use Cro::HTTP::Header;

my \TOKEN = (|EVALFILE "keys.p6").first;

my \TWITTER_PAT = /'http' 's'? '://twitter.com/' [<-[/]> && \H]+ '/status/'
     \d+/;
my \GIF_PAT = /'http' 's'? '://' \S+ '/' [ \S+ '.gif' ]/;

my %last-twitter;
my %last-gif;

sub speed-up-gif($msg) {
	my $chan = await $msg.channel;
	my $url = $msg.content ~~ GIF_PAT;
	my $http = Cro::HTTP::Client.new: http => 1.1;

	my $body = try {
		my $resp = await $http.head($url.Str);
		die "too big {$resp.header('content-length').Int}" if
		    $resp.header('content-length').Int >= 10 +< 20;
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

		$chan.send-message(:embed(image => url =>
		    "attachment://out.gif"), :file("out.gif"));

		LEAVE {
			$in-gif.close;
			unlink 'in.gif';
			unlink 'out.gif';
		}
	}

	%last-gif{$chan.id}:delete;
}

sub twitter($msg, :$embed? = False) {
	my $urls = $msg.content.match(TWITTER_PAT, :global);
	my $chan = await $msg.channel;
	my $http = Cro::HTTP::Client.new: http => 1.1;

	if !$msg.defined {
		return;
	}

	for $urls.list -> $u {
		my $resp = await $http.get($u.Str);
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

		my $im;
		if ($embed)  {
			my $em = $body ~~ m/'data-expanded-url="' (<-[\"]>*)
			    '"'/;
			$im = $em[0].Str;
		} else {
			my $imgs = $body ~~ m:g/'<meta' \s+
			    'property="og:image"' \s+ 'content="'
			    (<-[\"]>*) '">'/;
			$im = $imgs[1..*].map(*[0]).join("\n");
		}
		if ($im) {
			$chan.send-message($im); 
		}
	}
	%last-twitter{$chan.id}:delete;
}

sub MAIN() {
	my $discord = API::Discord.new(:token(TOKEN));
	$discord.connect.then({ say "connected!" });

	react {
		whenever $discord.messages -> $m {
			if $m.content ~~ TWITTER_PAT {
				my $chan = await $m.channel;
				%last-twitter{$chan.id} = $m;
				if ($m.content ~~ m:i/'album'/) {
					twitter($m);
				} elsif ($m.content ~~ m:i/'embed'/) {
					twitter($m, :embed(True));
				}
			} elsif $m.content ~~ m:i/^album \s+ that/ {
				my $chan = await $m.channel;
				if %last-twitter{$chan.id}:exists {
					twitter(%last-twitter{$chan.id});
				}
			} elsif $m.content ~~ m:i/^embed \s+ that/ {
				my $chan = await $m.channel;
				if %last-twitter{$chan.id}:exists {
					twitter(%last-twitter{$chan.id},
					    :embed(True));
				}
			} elsif $m.content ~~ GIF_PAT {
				my $chan = await $m.channel;
				%last-gif{$chan.id} = $m;
			} elsif $m.content ~~ m:i/^speed \s+ that|this \s+ up/ {
				my $chan = await $m.channel;
				if %last-gif{$chan.id}:exists {
					speed-up-gif(%last-gif{$chan.id});
				}
			}
			if $m.content ~~ m:i/feet|foot/ {
				if rand < 0.05 {
					note "adding feet {DateTime.now}!";
					await $m.add-reaction(
					    <feet2:598371454811111445>);
				}
			}
		}

		whenever $discord.events -> $e {
		}
	}
}

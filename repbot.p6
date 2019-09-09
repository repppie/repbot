use API::Discord;
use Cro::HTTP::Client;
use Cro::HTTP::Header;

my \TOKEN = (|EVALFILE "keys.p6").first;

my \TWITTER_PAT = /'http' 's'? '://twitter.com/' [<-[/]> && \H]+ '/status/'
     \d+/;

my $http = Cro::HTTP::Client.new: http => 1.1;

sub twitter($msg) {
	my $urls = $msg.content.match(TWITTER_PAT, :global);

	if !($msg.content ~~ m:g/'album'/) {
		return;
	}

	for $urls.list -> $u {
		my $resp = await $http.get($u.Str);
		my $body = await $resp.body;
		CATCH {
			when X::Cro::HTTP::Error {
				say "error code {.response.status}"
			}
			default {
				.Str.say;
				for .backtrace.reverse {
					next if .file.starts-with('SETTING::');
					next unless .subname;
					say "error at {.file}:{.line}";
				}
			}
		}

		my $imgs = $body ~~ m:g/'<meta' \s+ 'property="og:image"'
		    \s+ 'content="' (<-[\"]>*) '">'/;
		my @msgs;
		for $imgs[1..*] -> $match {
			my $chan = await $msg.channel;
			my $new = $chan.send-message($match[0].Str);
		}
	}
}

sub MAIN() {
	my $discord = API::Discord.new(:token(TOKEN));
	$discord.connect.then({ say "connected!" });

	react {
		whenever $discord.messages -> $m {
			if $m.content ~~ TWITTER_PAT {
				twitter($m);
			}
			#if $m.content ~~ m:i/feet|foot/ {
				#await $m.add-reaction(
				    #<feet2:598371454811111445>);
			#}
		}

		whenever $discord.events -> $e {
		}
	}
}

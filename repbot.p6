use API::Discord;
use Cro::HTTP::Client;
use Cro::HTTP::Header;

my \TOKEN = (|EVALFILE "keys.p6").first;

my \TWITTER_PAT = /'http' 's'? '://twitter.com/' [<-[/]> && \H]+ '/status/'
     \d+/;

my $http = Cro::HTTP::Client.new: http => 1.1;

my %last-twitter;

sub twitter($msg, :$last? = False) {
	my $urls = $msg.content.match(TWITTER_PAT, :global);
	my $chan = await $msg.channel;

	if !$msg.defined {
		return;
	}

	%last-twitter{$chan.id} = $msg;
	if !$last && !($msg.content ~~ m:g:i/'album'/) {
		return;
	}

	for $urls.list -> $u {
		my $resp = await $http.get($u.Str);
		my $body = await $resp.body;
		CATCH {
			default { .Str.say; }
		}

		my $imgs = $body ~~ m:g/'<meta' \s+ 'property="og:image"'
		    \s+ 'content="' (<-[\"]>*) '">'/;
		my $im = $imgs[1..*].map(*[0]).join("\n");
		$chan.send-message($im); 
	}
	%last-twitter{$chan.id}:delete;
}

sub MAIN() {
	my $discord = API::Discord.new(:token(TOKEN));
	$discord.connect.then({ say "connected!" });

	react {
		whenever $discord.messages -> $m {
			if $m.content ~~ TWITTER_PAT {
				twitter($m);
			} elsif $m.content ~~ m:i/^album \s+ that/ {
				my $chan = await $m.channel;
				if %last-twitter{$chan.id}:exists {
					twitter(%last-twitter{$chan.id},
					    :last(True));
				}
			}
			if $m.content ~~ m:i/feet|foot/ {
				if rand < 0.02 {
					await $m.add-reaction(
					    <feet2:598371454811111445>);
				}
			}
		}

		whenever $discord.events -> $e {
		}
	}
}

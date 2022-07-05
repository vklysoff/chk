#!/usr/bin/perl
#
# Проверяем доступность мониторингов 
#

use strict;                     # Good practice
use warnings;                   # Good practice

use FindBin;
use lib "$FindBin::Bin/";

use Log::Any '$log';
use Log::Any::Adapter ('Stdout');
use LWP;
use HTTP::Request::Common;
use File::Basename;
use DBI;
use utf8;
use Parallel::ForkManager;
use experimental 'smartmatch';
use POSIX qw(strftime);
#use Data::Dumper;

binmode(STDOUT,':utf8');

my $datestring = strftime "%Y-%m-%e %H:%M:%S", localtime;
my @time = localtime();
my $script_name = $0;
$script_name =~ s|.*/||;
my $db_name = "chk.db";

my $debug=0;
my $max_forks = 10;
my $timeout_default=10;
my $try_count_default=3;
my $WorkDir = dirname($0);
my $Mon = { do "$WorkDir/config_all_monks.pl" };
my $db = "$WorkDir/persistent/$db_name";

$db = DBI->connect("dbi:SQLite:dbname=$db","","");
$db->do("CREATE TABLE IF NOT EXISTS urls (url char(256), down time NOT NULL DEFAULT CURRENT_TIMESTAMP, up time);");

my $qsel = $db->prepare('SELECT strftime("%s","now") - strftime("%s",down) AS delta FROM urls WHERE url = ?');
my $qdel = $db->prepare('DELETE FROM urls WHERE url = ?');
my $qins = $db->prepare('INSERT INTO urls (url) VALUES(?)');

my $fork = new Parallel::ForkManager($max_forks);

while (42) {
	foreach my $p ( keys %{$Mon} ) {
		next if not $Mon->{$p}{'enabled'};
		print "$p\n" if $debug;
		print "\tМониторинг:\n" if $debug;
		foreach my $Monk ( @{ $Mon->{$p}{'web'}{'monitors'}{'list'} }, @{ $Mon->{$p}{'web'}{'check'}{'list'} } ) {
			next if not $Monk->{enabled};
			my @codes_ok = [ 200 ];
			@codes_ok = @{ $Monk->{codes}{ok} } if exists $Monk->{codes};
			$ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0 if exists $Monk->{insecure} and $Monk->{insecure};
			my $timeout = exists $Monk->{timeout} ? $Monk->{timeout} : $timeout_default;
			my $try_count = exists $Monk->{try} ? $Monk->{try} : $try_count_default;
			$fork->start and next;
			print "\t\t$p $Monk->{url} [timeout=$timeout; try=$try_count]: " if $debug;
			$log->info("$p $Monk->{url} [timeout=$timeout; try=$try_count]");
			my $ua = LWP::UserAgent->new;
			$ua->timeout( $timeout );
			my $req;
			if ( exists $Monk->{'user'} and exists $Monk->{'pass'} ) {
				exit if $Monk->{type} eq 'icinga2';
				$req = POST( $Monk->{'url'} );
				$req->authorization_basic($Monk->{'user'}, $Monk->{'pass'});
			} elsif ( exists $Monk->{headers} ) {
				$req = HTTP::Request->new(GET => $Monk->{'url'} );
				$req->header(@$_) for $Monk->{headers};
			} else {
				$req = GET( $Monk->{'url'} );
			};
			my $count=1;
			my $response;
			do {
				$log->warn("$p $Monk->{url} try #$count") if $count > 1;
				$response = $ua->request( $req );
				$count++;
				sleep(5);
			} until ( $response->{_rc} ~~ @codes_ok or $count > $try_count );
			#} until ( $response->{_rc} eq '200' or $count > $try_count );
			my $msg = $response->{_msg};
			$msg =~ s|'||g;
			$log->info("$p $Monk->{url} $response->{_rc} $response->{_msg}");
			print "$response->{_rc} $response->{_msg}\n" if $debug;
			$qsel->execute($Monk->{url}) or die($db->errstr);
			my $row = $qsel->fetchrow_hashref();
            if ( defined $row and $time[1] = 0 ) {
                if ( int($row->{delta}/60+1) > 60 ) {
                    print "Страница длительное время имеет проблемы с доступом $p: $Monk->{url}\n" if $debug;
                    tg_send("%F0%9F%92%80 Длительное время недоступна страница проекта: <b>$Mon->{$p}{info}</b> [$p]: <a href=\"$Monk->{url}\">$Monk->{info}</a>. Недоступно в течении ".int($row->{delta}/60+1)." минут.\nНаблюдатель: $ENV{VIEWER}\n$datestring");
                    $log->error("Длительное время недоступна страница проекта: $p $Monk->{url}".int($row->{delta}/60+1)." минут");
                }
            }
			if ( $response->{_rc} ~~ @codes_ok and defined $row ) {
				print "Страница восстановлена $p: $response->{_rc} $response->{_msg}\n" if $debug;
				$log->warn("$p $Monk->{url} $response->{_rc} $response->{_msg}");
				$qdel->execute($Monk->{url}) or die($db->errstr);
				tg_send("%F0%9F%92%A6 Доступна страница проекта: <b>$Mon->{$p}{info}</b> [$p]: <a href=\"$Monk->{url}\">$Monk->{info}</a> ($response->{_rc} $msg). Было недоступно около ".int($row->{delta}/60+1)." минут.\nНаблюдатель: $ENV{VIEWER}\n$datestring");
			} elsif ( not $response->{_rc} ~~ @codes_ok and not defined $row ) {
				print "Страница пропала $p: $response->{_rc} $response->{_msg}\n" if $debug;
				$log->error("$p $Monk->{url} $response->{_rc} $response->{_msg}");
				$qins->execute($Monk->{url}) or die($db->errstr);
				tg_send("%F0%9F%94%A5 Недоступна страница проекта <b>$Mon->{$p}{info}</b> [$p]: <a href=\"$Monk->{url}\">$Monk->{info}</a> ($response->{_rc} $msg)\nНаблюдатель: $ENV{VIEWER}\n$datestring");
			}
			$fork->finish;
		}
	};
	sleep 60;
}
$db->disconnect;

sub tg_send {
	my $TG_chat_id = $ENV{TG_CHAT_ID};
	my $TG_token = $ENV{TG_TOKEN};

	open(my $send_fh, "-|","curl -X  POST https://api.telegram.org/$TG_token/sendMessage --data chat_id=\'$TG_chat_id\' --data parse_mode=\'HTML\' --data disable_web_page_preview=1 --data text=\'@_\'");
	$log->info(<$send_fh>);
}


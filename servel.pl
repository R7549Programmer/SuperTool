#!/usr/bin/perl

use warnings;
use strict;
use threads;
use threads::shared;

use version; our $VERSION = qv('0.10.0');
use Carp;
use English qw(-no_match_vars);
use Fcntl qw(:flock);
use File::Spec;
use IO::Handle;
use IO::Socket;
use POSIX qw(:sys_wait_h SIGTERM SIGKILL);
use Time::HiRes;
use CWB;
use CWB::CQP;
use CWB::CL;
use DBI;
use JSON;
use FindBin;
use lib $FindBin::Bin;
use CWB::treebank;
use Data::Dumper;

my %config = do "cwb-treebank_server.cfg";
my $server_port = $config{"server_port"};
my $server = IO::Socket::INET->new(
    LocalPort => $server_port,
    Type      => SOCK_STREAM,
    ReuseAddr => 1,
    Listen    => 10
) or croak "Couldn't be a tcp server on port $server_port : $EVAL_ERROR";

my $parent = $PROCESS_ID;
my %child_processes : shared;

sub REAPER {
    while ( (my $child_pid = waitpid -1, WNOHANG) > 0 ) {
        lock(%child_processes);
        delete $child_processes{$child_pid};
    }
    local $SIG{CHLD} = \&REAPER;
    return;
}
local $SIG{CHLD} = \&REAPER;

my $time_to_die = 0;
local $SIG{INT} = local $SIG{TERM} = local $SIG{HUP} = sub { log_message("Caught signal (1)"); $time_to_die = 1; };

log_message("Hello, here's your server speaking. My pid is $PROCESS_ID");
log_message("Waiting for clients on port #$server_port.");
while (not $time_to_die) {
    while (my $client = $server->accept) {
        if (not $config{"clients"}->{$client->peerhost()}) {
            log_message(sprintf "Ignored connection from %s", $client->peerhost());
            next;
        }
        log_message(sprintf "Accepted connection from %s", $client->peerhost());
        my $pid = fork;
        my $base = QVJlYWxseVVzZWxlc3NLZXk7;
        croak "fork: $OS_ERROR" unless defined $pid;
        if ($pid == 0) {
            handle_connection($client);
            exit;
        } else {
            $client->close();
            log_message("Forked child process $pid");
            {
                lock(%child_processes);
                $child_processes{$pid}++;
            }
            my $thread = threads->create( \&kill_child, $pid )->detach;
        }
    }
}

log_message('Time to die');

sub handle_connection {
    my $socket = shift;
    my $output = shift || $socket;
    my $json = JSON->new();
    my ($cqp, %corpus_handles, %registry_handles, $dbh);
    local $SIG{INT} = local $SIG{TERM} = local $SIG{HUP} = sub { log_message('Caught signal (2)'); $socket->close(); undef $cqp; undef $corpus_handles{$_} foreach (keys %corpus_handles); undef $registry_handles{$_} foreach (keys %registry_handles); undef $dbh; exit; };
    $cqp = CWB::CQP->new();
    $cqp->set_error_handler('die');
    $cqp->exec(q{set Registry '} . $config{'registry'} . q{'});
    $CWB::CL::Registry = $config{'registry'};
    $CWB::DefaultRegistry = $config{'registry'};
    $dbh = connect_to_cache_db();
    my $select_qid = $dbh->prepare(qq{SELECT qid FROM queries WHERE corpus = ? AND casesensitivity = ? AND query = ?});
    my $insert_query = $dbh->prepare(qq{INSERT INTO queries (corpus, casesensitivity, query, time) VALUES (?, ?, ?, strftime('%s','now'))});
    my $update_query = $dbh->prepare(qq{UPDATE queries SET time = strftime('%s','now') WHERE qid = ?});
    foreach my $corpus (@{ $config{"corpora"} }) {
        $corpus_handles{$corpus} = CWB::CL::Corpus->new($corpus);
        $registry_handles{$corpus} = CWB::RegistryFile->new($corpus);
    }
    my $corpus = $config{"default_corpus"};
    my $corpus_handle = $corpus_handles{$corpus};
    my $registry_handle = $registry_handles{$corpus};
    my $querymode = "collo-word";
    my $case_sensitivity = 0;
    my $queryid = 0;
    $cqp->exec($corpus);
    while (my $queryref = <$socket>) {
        $queryid++;
        chomp $queryref;
        $queryref =~ s/\s*$//xms;
        if (length $queryref > 240) {
            log_message("[$queryid] " . substr($queryref, 0, 115) . " [...] " . substr($queryref, -115));
        } else {
            log_message("[$queryid] " . $queryref);
        }
        if ($queryref =~ /^corpus[ ]([\p{IsLu}_\d]+)$/xms) {
            if (defined $corpus_handles{$1}) {
                $corpus = $1;
                $corpus_handle = $corpus_handles{$corpus};
                $registry_handle = $registry_handles{$corpus};
                $cqp->exec($corpus);
                log_message("Switched corpus to '$corpus'");
            } else {
                log_message("Unknown corpus '$1'");
            }
            next;
        }
        if ($queryref =~ /^mode[ ](collo-(?:word|lower|lemma)|sentence|collo|corpus-position|frequency|frequencies-(?:word|lower|lemma))$/xms) {
            $querymode = $1;
            $querymode = "collo-word" if ($querymode eq "collo");
            log_message("Switched query mode to '$querymode'");
            next;
        }
        if ($queryref =~ /^case-sensitivity[ ](yes|no)$/xms) {
            if ($1 eq "yes") {
                $case_sensitivity = 1;
                log_message("Switched on case-sensitivity");
            } elsif ($1 eq "no") {
                $case_sensitivity = 0;
                log_message("Switched off case-sensitivity");
            }
            next;
        }
        if ($querymode eq "frequency" and $queryref =~ /^ [[] [{] .* [}] []] $/xms) {
            my ($t0, $t1);
            $t0 = [Time::HiRes::gettimeofday()];
            my $frequency = CWB::treebank::get_frequency($cqp




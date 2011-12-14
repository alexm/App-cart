package App::cart::Collector;

use strict;
use warnings;

use Net::Twitter;
use AnyEvent::Twitter::Stream;

use App::cart::Buffer;

sub new {
    my ($class, $conf) = @_;

    my $self = bless {
        buffer   => App::cart::Buffer->new($conf),
        keywords => $conf->{keywords},
    }, $class;

    my $filter = $self->filter($conf);
    $self->{follow} = $filter->{follow};

    $self->{stream} = AnyEvent::Twitter::Stream->new(
        consumer_key    => $conf->{oauth}->{consumer_key},
        consumer_secret => $conf->{oauth}->{consumer_secret},
        token           => $conf->{oauth}->{access_token},
        token_secret    => $conf->{oauth}->{access_token_secret},
        on_tweet        => sub { $self->on_tweet(shift); },
        on_error        => sub {
            print STDERR "Got error: " . join("\n", @_) . "\n";
            die;
        },
        %$filter,
    );

    return $self;
}

sub init {
    my ($self) = @_;
    $self->{buffer}->init;
}

sub filter {
    my ($self, $conf) = @_;

    # Get user id's to follow from config
    my @ids;
    push @ids, @{$conf->{user_ids}} if ($conf->{user_ids});
    
    # Resolve the user id's from usernames given in config
    if ($conf->{user_names}) {
        my $nt  = Net::Twitter->new( traits => ['API::REST'] );
        push @ids, map {
            $nt->show_user({screen_name => $_})->{id}
        } @{$conf->{user_names}};
    }

    my $filter = { method => 'filter' };
    $filter->{follow} = join(',', @ids)   if @ids;

    return $filter;
}

# Event Handlers
sub on_tweet {
    my ($self, $tweet) = @_;

    print STDERR "got tweet " . $self->{buffer}->count . "\n";
    if (defined $tweet->{text}) {
        my $user = $tweet->{user}->{screen_name};
        my $text = $tweet->{text};
        print STDERR "$user: $text\n" if defined $tweet->{text};
        if ($self->is_valid($tweet)) {
            $self->{buffer}->bpush($tweet);
            print STDERR "Buffered!\n";
        } else {
            print STDERR "Not buffered\n";
        }
    }
}

sub is_valid {
    my ($self, $tweet) = @_;

    # This is one of our users' tweet. Check if it's a RT
    return 0 if $tweet->{retweeted};

    # Check if this is one of our user's tweet
    my $user = $tweet->{user}->{id};
    return 0 unless $self->{follow} =~ /$user/;

    # Search for at least one of our keywords
    my @kw = @{ $self->{keywords} };
    foreach (@kw) {
        if ($tweet->{text} =~ /$_/) {
            print STDERR "Got a match with $_\n";
            return 1;
        }
    }

    return 0;
}

1;
package WWW::CPANGrep::Slab::Writer;
use Moose;
use namespace::autoclean;

use File::Slurp;
use JSON;

use constant SLAB_SEPERATOR => "\n\0\1\2\x{e}\x{0}\x{f}\2\1\0\n";

my $COUNTER = 0;

has dir => (
  is => 'ro',
  isa => 'Str',
  required => 1,
);

has redis => (
  is => 'ro',
  isa => 'AnyEvent::Redis',
  required => 1,
);

has zset_name => (
  is => 'ro',
  isa => 'Str',
  default => sub { "slab:zset:process:$$-" . ++$COUNTER },
);

has rotate_size => (
  is => 'ro',
  isa => 'Int',
  default => sub { 10 * 1024 * 1024 }, # 10mb
);

has file_name => (
  is => 'ro',
  isa => 'Str',
  default => sub {
    my($self) = @_;
    "$$-" . time . "-" . ++$COUNTER;
  },
);

has _size => (
  is => 'rw',
  isa => 'Int',
  default => 0,
);

has _fh => (
  is => 'ro',
  isa => 'GlobRef',
  default => sub {
    my($self) = @_;
    open my $fh, ">", $self->dir . "/" . $self->file_name or die $!;
    binmode $fh;
    $fh;
  },
);

sub BUILDARGS {
  my($self, %args) = @_;

  # For speed avoid using the tied interface
  $args{redis} = tied %{$args{redis}};

  return \%args;
}

sub index {
  my($self, $dist, $file) = @_;

  my $content = read_file($file);
  if($content =~ /^.*\0/) { # first line contains NUL => probably binary
    warn "Ignoring probable binary file $file (in $dist)";
    return;
  }

  print {$self->_fh} $content, SLAB_SEPERATOR;

  $self->redis->zadd($self->zset_name, $self->_size, encode_json {
      size => length($content),
      dist => $dist,
      file => $file
  })->recv;

  $self->_size($self->_size + length($content) + length SLAB_SEPERATOR);
}

sub full {
  my($self) = @_;
  return $self->_size >= $self->rotate_size;
}

__PACKAGE__->meta->make_immutable;

1;
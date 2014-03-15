use 5.008;    # utf8
use strict;
use warnings;
use utf8;

package App::cpanm::meta::checker::State;

# ABSTRACT: Shared state for a single test run

# AUTHORITY

use Moo qw(has);
use CPAN::Meta;
use CPAN::Meta::Check qw(verify_dependencies);
use App::cpanm::meta::checker::State::Duplicates;
use Path::Tiny qw(path);

has 'tests' => (
    is       => ro =>,
    lazy     => 1,
    required => 1,
);

has 'list_fd' => (
    is      => ro =>,
    lazy    => 1,
    builder => sub {
        \*STDERR;
    }
);

has '_duplicates' => (
    is      => ro =>,
    lazy    => 1,
    builder => sub {
        return App::cpanm::meta::checker::State::Duplicates->new();
    },
);

sub _output {
    my ( $self, $prefix, $message ) = @_;
    return $self->list_fd->printf( qq[%s: %s\n], $prefix, $message );
}

sub x_test_list {
    my ( $self, $path, ) = @_;
    return $self->_output( 'list', path($path)->basename );
}

sub x_test_list_nonempty {
    my ( $self, $path ) = @_;
    return unless path($path)->children;
    return $self->_output( 'list_nonempty', path($path)->basename );
}

sub x_test_list_empty {
    my ( $self, $path ) = @_;
    return if path($path)->children;
    return $self->_output( 'list_empty', path($path)->basename );
}

sub x_test_list_duplicates {
    my ( $self, $path ) = @_;
    my $basename = path($path)->basename;
    my ( $dist, $version ) = $basename =~ /\A(.*)-([^-]+(?:-TRIAL)?)\z/;

    $self->_duplicates->seen_dist_version( $dist, $version );

    return unless $self->_duplicates->has_duplicates($dist);

    my $fmt = "list_duplicates:%s-%s\n";

    if ( $self->_duplicates->reported_duplicates($dist) ) {
        $self->_output( $label, sprintf $fmt, $dist, $version );
        return;
    }

    $self->_output( $label, sprintf $fmt, $dist, $_ )
      for $self->_duplicates->duplicate_versions($dist);

    $self->_duplicates->reported_duplicates( $dist, 1 );

    return;
}

sub _cache_cpan_meta {
    my ( undef, $path, $state ) = @_;
    return $state->{cpan_meta} if defined $state->{cpan_meta};
    return ( $state->{cpan_meta} =
          CPAN::Meta->load_file( path($path)->child('MYMETA.json') ) );
}

sub _cpan_meta_check_phase_type {
    my ( $self, %args ) = @_;
    my $meta = $self->_cache_cpan_meta( $args{path}, $args{state} );
    for my $dep ( verify_dependencies( $meta, $args{phase}, $args{type} ) ) {
        $self->_output( $args{label},
            ( sprintf '%s: %s', path( $args{path} )->basename, $dep ) );
    }
    return;
}

for my $phase (qw( runtime configure build develop test )) {
    for my $rel (qw( requires suggests conflicts recommends )) {
        my $method = 'x_test_check_' . $phase . '_' . $rel;

        my $code = sub {
            my ( $self, $path, $state ) = @_;
            return $self->_cpan_meta_check_phase_type(
                path  => $path,
                state => $state,
                label => ( 'check_' . $phase . '_' . $rel ),
                phase => $phase,
                type  => $rel,
            );
        };
        {
            ## no critic (TestingAndDebugging::ProhibitNoStrict)
            no strict 'refs';
            *{$method} = $code;
        }
    }
}

=method C<check_path>

    ->check_path('./foo/bar/baz');

Read the content from C<./foo/bar/baz> and check its consistency.

=cut

sub check_path {
    my ( $self, $path ) = @_;
    my $state = {};
    for my $test ( @{ $self->tests } ) {
        my $method = 'x_test_' . $test;
        if ( not $self->can($method) ) {
            die "no method $method for test $test";
        }
        $self->$method( $path, $state );
    }
}

no Moo;

1;


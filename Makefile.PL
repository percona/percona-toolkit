use ExtUtils::MakeMaker;
use ExtUtils::MY;

sub MY::postamble {
    return <<'MAKE_GOTOOLS';
gotools:
	cd src/go && $(MAKE) build

MAKE_GOTOOLS
}

WriteMakefile(
    NAME      => 'Percona::Toolkit',
    VERSION   => '3.7.1',
    EXE_FILES => [ <bin/*> ],
    MAN1PODS  => {
      'docs/percona-toolkit.pod' => 'blib/man1/percona-toolkit.1p',
      map {
         (my $name = $_) =~ s/^bin.//;
         my $file_name = $_;
if ( $file_name =~ m/(mongo|pg|galera|k8s|secure)/ ) {
            # We have to put empty line here to avoid the MAN1PODS hash corruption
            '' => '',
         }
         else {
             $_ => "blib/man1/$name.1p";
         }
      } <bin/*>
    },
    MAN3PODS     => {}, # man(3) pages are for C libs
    depend => {manifypods => gotools},
    PREREQ_PM    => {
        DBI           => 1.46,
        DBD::mysql    => 3.0000_0,
    },
);

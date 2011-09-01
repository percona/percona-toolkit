use ExtUtils::MakeMaker;

WriteMakefile(
    NAME      => 'percona-toolkit',
    VERSION   => '1.0.1',
    EXE_FILES => [ <bin/*> ],
    MAN1PODS  => {
      'docs/percona-toolkit.pod' => 'blib/man1/percona-toolkit.1',
      map {
         (my $name = $_) =~ s/^bin.//;
         $_ => "blib/man1/$name.1";
      } <bin/*>
    },
    MAN3PODS     => {}, # man(3) pages are for C libs
    PREREQ_PM    => {
        DBI           => 1.46,
        DBD::mysql    => 3.0000_0,
    },
);

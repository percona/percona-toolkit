use ExtUtils::MakeMaker;

WriteMakefile(
    NAME      => 'Percona::Toolkit',
    VERSION   => '3.5.0',
    EXE_FILES => [ <bin/*> ],
    MAN1PODS  => {
      'docs/percona-toolkit.pod' => 'blib/man1/percona-toolkit.1p',
      map {
         (my $name = $_) =~ s/^bin.//;
         my $file_name = $_;
         if ( ( $file_name !~ m/mongo/ ) || ( $file_name !~ m/pg/ ) ) {
             $_ => "blib/man1/$name.1p";
         }
      } <bin/*>
    },
    MAN3PODS     => {}, # man(3) pages are for C libs
    PREREQ_PM    => {
        DBI           => 1.46,
        DBD::mysql    => 3.0000_0,
    },
);

Name:           maatkit
Version:        @DISTRIB@
Release:        1%{?dist}
Summary:        Essential command-line utilities for MySQL

Group:          Applications/Databases
License:        GPL
URL:            http://code.google.com/p/maatkit/
Source0:        http://maatkit.googlecode.com/files/%{name}-%{version}.tar.gz
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)

BuildArch:      noarch
Requires:       perl(DBI) >= 1.13, perl(DBD::mysql) >= 1.0, perl(Term::ReadKey) >= 2.10
# perl-DBI is required by perl-DBD-MySQL anyway

%description
This toolkit contains essential command-line utilities for MySQL, such as a 
table checksum tool and query profiler. It provides missing features such as 
checking slaves for data consistency, with emphasis on quality and 
scriptability.


%prep
%setup -q


%build
%{__perl} Makefile.PL INSTALLDIRS=vendor < /dev/null
make %{?_smp_mflags}


%install
rm -rf $RPM_BUILD_ROOT
make pure_install PERL_INSTALL_ROOT=$RPM_BUILD_ROOT
find $RPM_BUILD_ROOT -type f -name .packlist -exec rm -f {} ';'
find $RPM_BUILD_ROOT -type d -depth -exec rmdir {} 2>/dev/null ';'
find $RPM_BUILD_ROOT -type f -name maatkit.pod -exec rm -f {} ';'
chmod -R u+w $RPM_BUILD_ROOT/*


%clean
rm -rf $RPM_BUILD_ROOT


%files
%defattr(-,root,root,-)
%doc COPYING INSTALL Changelog*
%{_bindir}/*
%{_mandir}/man1/*.1*


%changelog
* Fri Aug 14 2009 Robin Bowes <robin@robinbowes.com> - 3
Use perl Requires, rather than rpm packages

* Fri Sep 19 2008 Jeremy Cole <baron@percona.com> - 2
- lowercased the MySQL in requires perl-DBD-mysql

* Tue Jun 12 2007 Sven Edge <sven@curverider.co.uk> - 547-1
- initial packaging attempt

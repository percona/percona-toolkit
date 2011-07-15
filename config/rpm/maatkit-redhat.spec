Summary: Maatkit is a collection of essential command-line utilities for MySQL
Name: maatkit
Version: @DISTRIB@
Release: 1%{?dist}
Source: %{name}-%{version}.tar.gz
License: GPL
Group: Development/Tools
URL: http://code.google.com/p/maatkit/
BuildRoot: %{_tmppath}/%{name}-root
Requires: perl(DBD::mysql)
BuildArch: noarch

%description
Maatkit is a collection of essential command-line utilities for MySQL. Each is completely stand-alone, without dependencies other than core Perl and the DBI drivers needed to connect to MySQL, and doesn't need to be "installed" - you can just execute the scripts. This makes the tools easy to use on systems where you can't install anything extra, such as customer sites or ISPs.

%prep
%setup -q

%build

%install
rm -rf $RPM_BUILD_ROOT
%{__perl} Makefile.PL PREFIX=$RPM_BUILD_ROOT%{_prefix}
make install
find $RPM_BUILD_ROOT -type f -name .packlist -exec rm -f {} ';'
find $RPM_BUILD_ROOT -type f -name perllocal.pod -exec rm -f {} ';'

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,root,root)
%doc Changelog COPYING MANIFEST README
%{_bindir}/*
%{_mandir}/man1/*
%{_mandir}/man3/*
%{perl_sitelib}/*

%changelog
* Thu Sep 18 2008 Robin Bowes <robin@robinbowes.com> - 2
- Added BuildArch: noarch

* Wed Aug 13 2008 Baron Schwartz <baron.schwartz@gmail.com> - 1
- Contributed by Spil Games

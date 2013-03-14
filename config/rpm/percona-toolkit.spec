Name:      percona-toolkit
Summary:   Advanced MySQL and system command-line tools
Version:   %{version}
Release:   %{release}
Group:     Applications/Databases
License:   GPL
Vendor:    Percona
URL:       http://www.percona.com/software/percona-toolkit/
Source:    percona-toolkit-%{version}.tar.gz
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-root
BuildArch: noarch
Requires:  perl(DBI) >= 1.13, perl(DBD::mysql) >= 1.0, perl(Time::HiRes), perl(IO::Socket::SSL)
AutoReq:   no

%description
Percona Toolkit is a collection of advanced command-line tools used by
Percona (http://www.percona.com/) support staff to perform a variety of
MySQL and system tasks that are too difficult or complex to perform manually.

These tools are ideal alternatives to private or "one-off" scripts because
they are professionally developed, formally tested, and fully documented.
They are also fully self-contained, so installation is quick and easy and
no libraries are installed. 

Percona Toolkit is developed and supported by Percona.  For more
information and other free, open-source software developed by Percona,
visit http://www.percona.com/software/.

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
find $RPM_BUILD_ROOT -type f -name 'percona-toolkit.pod' -exec rm -f {} ';'
chmod -R u+w $RPM_BUILD_ROOT/*

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,root,root,-)
%doc COPYING INSTALL README Changelog
%{_bindir}/*
%{_mandir}/man1/*.1*

%changelog
* Mon Jul 18 2011 Daniel Nichter
- Initial implementation

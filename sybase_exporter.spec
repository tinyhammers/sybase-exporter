Name:           sybase_exporter
Version:        1.0.0
Release:        1%{?dist}
Summary:        Prometheus exporter for Sybase ASE metrics

License:        MIT
URL:            https://github.com/yourusername/sybase_exporter
Source0:        %{name}-%{version}.tar.gz

BuildArch:      noarch
Requires:       bash
Requires:       nc

%description
A Prometheus exporter for Sybase ASE metrics. This exporter collects various
metrics from Sybase ASE databases and exposes them in Prometheus format via
a simple HTTP server.

%prep
%setup -q -n %{name}-%{version}

%build
# Nothing to build

%install
mkdir -p %{buildroot}/usr/local/bin
mkdir -p %{buildroot}%{_sysconfdir}
mkdir -p %{buildroot}%{_unitdir}

install -m 755 sybase_exporter.sh %{buildroot}/usr/local/bin/sybase_exporter
install -m 644 sybase_exporter.conf %{buildroot}%{_sysconfdir}/sybase_exporter.conf
install -m 644 sybase_exporter.service %{buildroot}%{_unitdir}/sybase_exporter.service

%files
/usr/local/bin/sybase_exporter
%config(noreplace) %{_sysconfdir}/sybase_exporter.conf
%{_unitdir}/sybase_exporter.service

%post
%systemd_post sybase_exporter.service

%preun
%systemd_preun sybase_exporter.service

%postun
%systemd_postun_with_restart sybase_exporter.service

%changelog
* Wed Jun 11 2025 Your Name <your.email@example.com> - 1.0.0-1
- Initial release

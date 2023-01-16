#!/bin/bash -xe

#input the SCHEDULER_HOSTNAME which is also the LDAP server host name
SCHEDULER_HOSTNAME=

# Default LDAP base
LDAP_BASE="DC=soca,DC=local"

OPENLDAP_SERVER_PKGS=(
    compat-openldap
    cyrus-sasl
    cyrus-sasl-devel
    openldap
    openldap-clients
    openldap-devel
    openldap-servers
    unixODBC
    unixODBC-devel
)

SSSD_PKGS=(
    avahi-libs
    bind-libs
    bind-libs-lite
    bind-license
    bind-utils
    c-ares
    cups-libs
    cyrus-sasl-gssapi
    http-parser
    libdhash
    libipa_hbac
    libldb
    libsmbclient
    libsss_autofs
    libsss_certmap
    libsss_idmap
    libsss_nss_idmap
    libsss_sudo
    libtalloc
    libtdb
    libtevent
    libwbclient
    python-sssdconfig
    samba-client-libs
    samba-common
    samba-common-libs
    sssd
    sssd-ad
    sssd-client
    sssd-common
    sssd-common-pac
    sssd-ipa
    sssd-krb5
    sssd-krb5-common
    sssd-ldap
    sssd-proxy
)


# Disable SELINUX
sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config

# Configure Host
SERVER_IP=$(hostname -I)
SERVER_HOSTNAME=$(hostname)
SERVER_HOSTNAME_ALT=$(echo $SERVER_HOSTNAME | cut -d. -f1)
echo $SERVER_IP $SERVER_HOSTNAME $SERVER_HOSTNAME_ALT >> /etc/hosts

yum install -y $(echo ${OPENLDAP_SERVER_PKGS[*]})
yum install -y $(echo ${SSSD_PKGS[*]})

# Configure Ldap
echo "URI ldap://$SCHEDULER_HOSTNAME" >> /etc/openldap/ldap.conf
echo "BASE $LDAP_BASE" >> /etc/openldap/ldap.conf

echo -e "[domain/default]
enumerate = True
autofs_provider = ldap
cache_credentials = True
ldap_search_base = $LDAP_BASE
id_provider = ldap
auth_provider = ldap
chpass_provider = ldap
sudo_provider = ldap
ldap_sudo_search_base = ou=Sudoers,$LDAP_BASE
ldap_uri = ldap://$SCHEDULER_HOSTNAME
ldap_id_use_start_tls = True
use_fully_qualified_names = False
ldap_tls_cacertdir = /etc/openldap/cacerts
[sssd]
services = nss, pam, autofs, sudo
full_name_format = %2\$s\%1\$s
domains = default
[nss]
homedir_substring = /data/home
[pam]
[sudo]
ldap_sudo_full_refresh_interval=86400
ldap_sudo_smart_refresh_interval=3600
[autofs]
[ssh]
[pac]
[ifp]
[secrets]" > /etc/sssd/sssd.conf


chmod 600 /etc/sssd/sssd.conf
service sssd enable 
service sssd  restart 

echo | openssl s_client -connect $SCHEDULER_HOSTNAME:389 -starttls ldap > /root/open_ssl_ldap
mkdir /etc/openldap/cacerts/
cat /root/open_ssl_ldap | openssl x509 > /etc/openldap/cacerts/openldap-server.pem

#centOS6 openssl not work , so add a copy content
#copy /etc/openldap/cacerts/  from other soca host to this host

authconfig --disablesssd --disablesssdauth --disableldap --disableldapauth --disablekrb5 --disablekrb5kdcdns --disablekrb5realmdns --disablewinbind --disablewinbindauth --disableldaptls --disablerfc2307bis --updateall
sss_cache -E
authconfig --enablesssd --enablesssdauth --enableldap --enableldaptls --enableldapauth --ldapserver=ldap://$SCHEDULER_HOSTNAME --ldapbasedn=$LDAP_BASE --enablelocauthorize --enablemkhomedir --enablecachecreds --updateall

echo "sudoers: files sss" >> /etc/nsswitch.conf

# Disable SELINUX & firewalld
sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config


# Disable StrictHostKeyChecking
echo "StrictHostKeyChecking no" >> /etc/ssh/ssh_config
echo "UserKnownHostsFile /dev/null" >> /etc/ssh/ssh_config

sudo reboot



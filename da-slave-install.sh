#!/bin/sh

if [ -z "$1" ]; then
 echo "useage <username> <userpass> <master ip>";
 exit 0;
fi
if [ -z "$2" ]; then
 echo "useage <username> <userpass> <master ip>";
 exit 0;
fi
if [ -z "$3" ]; then
 echo "useage <username> <userpass> <master ip>";
 exit 0;
fi
echo "Saving most outputs to /root/install.log";

echo "doing updates and installs"
yum update -y > /root/install.log
yum install epel-release -y >> /root/install.log
yum install bind wget -y >> /root/install.log

systemctl start named >> /root/install.log
systemctl stop named >> /root/install.log

echo "creating user "$1" and adding to wheel"
useradd -G wheel $1 > /root/install.log
echo $2 |passwd $1 --stdin  >> /root/install.log
echo "disable root access to ssh"
sed -i '/PermitRootLogin/ c\PermitRootLogin no' /etc/ssh/sshd_config
systemctl restart sshd  >> /root/install.log

echo "installing and configurating directslave"
cd ~
wget -q https://directslave.com/download/directslave-3.2-advanced-all.tar.gz  >> /root/install.log
tar -xf directslave-3.2-advanced-all.tar.gz
mv directslave /usr/local/
cd /usr/local/directslave/bin
mv directslave-linux-amd64 directslave
cd /usr/local/directslave

chown named:named -R /usr/local/directslave
cat > /usr/local/directslave/etc/directslave.conf <<EOF
background	1

host            *

port            2222
ssl             off

cookie_sess_id  DS_SESSID
cookie_auth_key Change_this_line_to_something_long_&_secure

debug           0
uid             25
gid             25

pid             /usr/local/directslave/run/directslave.pid
access_log	/usr/local/directslave/log/access.log
error_log	/usr/local/directslave/log/error.log
action_log	/usr/local/directslave/log/action.log

named_workdir   /etc/namedb/secondary
named_conf	/etc/namedb/directslave.inc
retry_time	1200
rndc_path	/usr/sbin/rndc
named_format    text

authfile        /usr/local/directslave/etc/passwd

# `allow` directive removed, please, use your local firewall.
EOF

#mkdir /etc/namedb
mkdir -p /etc/namedb/secondary
touch /etc/namedb/secondary/named.conf
touch /etc/namedb/directslave.inc
chown named:named -R /etc/namedb
echo "preparing named for jail2ban"
mkdir /var/log/named
touch /var/log/named/security.log
chmod a+w -R /var/log/named

cat > /etc/named.comf <<EOF
//
// named.conf
//
// Provided by Red Hat bind package to configure the ISC BIND named(8) DNS
// server as a caching only nameserver (as a localhost DNS resolver only).
//
// See /usr/share/doc/bind*/sample/ for example named configuration files.
//

options {
        listen-on port 53 { any; };
        listen-on-v6 port 53 { any; };
        directory       \"/var/named\";
        dump-file       \"/var/named/data/cache_dump.db\";
        statistics-file \"/var/named/data/named_stats.txt\";
        memstatistics-file \"/var/named/data/named_mem_stats.txt\";
        allow-query     { any; };
        allow-recursion { none; };
		allow-notify	{ "$3"; };
		allow-transfer	{ none; };
        dnssec-enable yes;
        dnssec-validation yes;

        /* Path to ISC DLV key */
        bindkeys-file \"/etc/named.iscdlv.key\";

        managed-keys-directory \"/var/named/dynamic\";
};



logging {
		channel security_file {
			file \"/var/log/named/security.log\" versions 3 size 30m;
			severity dynamic;
			print-time yes;
		};
		category security {
			security_file;
		};
        channel default_debug {
                file \"data/named.run\";
                severity dynamic;
        };
};

zone \".\" IN {
        type hint;
        file \"named.ca\";
};

include \"/etc/named.rfc1912.zones\";
include \"/etc/named.root.key\";

include \"/etc/namedb/directslave.inc\";
EOF

/usr/local/directslave/bin/directslave --password $1:$2
/usr/local/directslave/bin/directslave --check  >> /root/install.log
rm /usr/local/directslave/run/directslave.pid

cat > /etc/systemd/system/directslave.service <<EOL
[Unit]
Description=DirectSlave for DirectAdmin
After=network.target

[Service]
Type=simple
User=named
ExecStart=/usr/local/directslave/bin/directslave --run
Restart=always

[Install]
WantedBy=multi-user.target
EOL

echo "setting enabled and starting up"
chown root:root /etc/systemd/system/directslave.service
chmod 755 /etc/systemd/system/directslave.service
systemctl daemon-reload
systemctl enabled named >> /root/install.log
systemctl enabled directslave >> /root/install.log
systemctl restart named >> /root/install.log
systemctl restart directslave >> /root/install.log

echo "all done!"
exit 0;

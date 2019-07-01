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
yum install bind fail2ban wget -y >> /root/install.log
yum groupinstall 'Development Tools' -y >> /root/install.log

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
cp /usr/local/directslave/etc/directslave.conf.sample /usr/local/directslave/etc/directslave.conf.copy

sed -i '/background/ c\background      1' /usr/local/directslave/etc/directslave.conf
sed -i '/uid/ c\uid             named' /usr/local/directslave/etc/directslave.conf
sed -i '/gid/ c\gid             named' /usr/local/directslave/etc/directslave.conf
sed -i '/ssl/ c\ssl             off' /usr/local/directslave/etc/directslave.conf
sed -i '/debug/ c\debug           0' /usr/local/directslave/etc/directslave.conf

#mkdir /etc/namedb
mkdir -p /etc/namedb/secondary
touch /etc/namedb/secondary/named.conf
touch /etc/namedb/directslave.ini
chown named:named -R /etc/namedb
echo "preparing named for jail2ban"
mkdir /var/log/named
touch /var/log/named/security.log
chmod a+w -R /var/log/named

echo "
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

include \"/etc/namedb/directslave.conf\";

" > /etc/named.conf

/usr/local/directslave/bin/pass $1 $2
/usr/local/directslave/bin/directslave --check  >> /root/install.log
rm /usr/local/directslave/run/directslave.pid


echo "install and configure fail2ban"
cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
sed -i '/^\[sshd\]/ a enabled = true' /etc/fail2ban/jail.local
sed -i '/\[sshd-ddos\]/ a enabled = true' /etc/fail2ban/jail.local
sed -i '/\[selinux-ssh\]/ a enabled = true' /etc/fail2ban/jail.local
sed -i '/\[named-refused\]/ a enabled = true' /etc/fail2ban/jail.local
sed -i '/\[directadmin\]/ a enabled = true' /etc/fail2ban/jail.local
sed -i '/logpath = \/var\/log\/directadmin\/login.log/ c\logpath = /usr/local/directslave/log/access.log' /etc/fail2ban/jail.local


echo "building directslave service"
echo "
#!/bin/sh

# directslave daemon            Start/Stop/Status/Restart

# chkconfig: 2345 80 20
# description: Allow you to use DirectAdmin Multi-Server function \
#              without need to have a DirectAdmin license, \
#              for manage external DNS Server.
# processname: directslave
# config: /usr/local/directslave/etc/directslave.conf
# pidfile: /usr/local/directslave/run/directslave.pid

# Source function library
. /etc/rc.d/init.d/functions

PROGBIN=\"/usr/local/directslave/bin/directslave --run\"
PROGLOCK=/var/lock/subsys/directslave
PROGNAME=directslave

#check the command line for actions

start() {
        echo -n \"Starting DirectSlave: \"
        daemon \$PROGBIN
        echo
        touch \$PROGLOCK
}

stop() {
        echo -n \"Stopping DirectSlave: \"
        killproc \$PROGNAME
        echo
        rm -f \$PROGLOCK
}

reload() {
        echo -n \"Reloading DirectSlave config file: \"
        killproc \$PROGNAME -HUP
        echo
}
case \"\$1\" in
        start)
                start
                ;;
        stop)
                stop
                ;;
        status)
                status $PROGNAME
                ;;
        restart)
                stop
                start
                ;;
        reload)
                reload
                ;;
        *)
                echo \"Usage: \$1 {start|stop|status|reload|restart}\"
                exit 1
esac

exit 0
" > /etc/rc.d/init.d/directslave

echo "setting chkconfig and starting up"
chown root:root /etc/rc.d/init.d/directslave
chmod 755 /etc/rc.d/init.d/directslave
chkconfig --add directslave
chkconfig --level 2345 directslave on
chkconfig --level 345 fail2ban on
chkconfig iptables on
chkconfig --level 345 named on

systemctl start fail2ban >> /root/install.log
systemctl restart named >> /root/install.log
systemctl restart directslave >> /root/install.log

echo "all done!"
exit 0;

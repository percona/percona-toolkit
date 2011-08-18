#!/bin/bash

TESTS=4

TEST_NAME="ps-mysqld-001.txt"
cat <<EOF > $TMPDIR/expected
  Port  Data Directory             Socket
  ===== ========================== ======
   3306 /var/lib/mysql             /var/run/mysqld/mysqld.sock
  12345 /tmp/12345/data            /tmp/12345/mysql_sandbox12345.sock
  12346 /tmp/12346/data            /tmp/12346/mysql_sandbox12346.sock
EOF
parse_mysqld_instances samples/ps-mysqld-001.txt > $TMPDIR/got
no_diff $TMPDIR/got $TMPDIR/expected

TEST_NAME="ps-mysqld-002.txt"
cat <<EOF > $TMPDIR/expected
  Port  Data Directory             Socket
  ===== ========================== ======
        /var/lib/mysql             /var/lib/mysql/mysql.sock
EOF
parse_mysqld_instances samples/ps-mysqld-002.txt > $TMPDIR/got
no_diff $TMPDIR/got $TMPDIR/expected

TEST_NAME="ps-mysqld-003.txt"
#parse_mysqld_instances
cat <<EOF > $TMPDIR/expected
  Port  Data Directory             Socket
  ===== ========================== ======
   3306 /mnt/data-store/mysql/data /tmp/mysql.sock
EOF
parse_mysqld_instances samples/ps-mysqld-003.txt > $TMPDIR/got
no_diff $TMPDIR/got $TMPDIR/expected

cat <<EOF > $TMPDIR/expected
  Port  Data Directory             Socket
  ===== ========================== ======
        /var/db/mysql              
EOF

cat <<EOF > $TMPDIR/in
mysql   767  0.0  0.9  3492  1100  v0  I     3:01PM   0:00.07 /bin/sh /usr/local/bin/mysqld_safe --defaults-extra-file=/var/db/mysql/my.cnf --user=mysql --datadir=/var/db/mysql --pid-file=/var/db/mysql/freebsd.hsd1.va.comcast.net..pid
mysql   818  0.0 17.4 45292 20584  v0  I     3:01PM   0:02.28 /usr/local/libexec/mysqld --defaults-extra-file=/var/db/mysql/my.cnf --basedir=/usr/local --datadir=/var/db/mysql --user=mysql --log-error=/var/db/mysql/freebsd.hsd1.va.comcast.net..err --pid-file=/var/db/mysql/freebsd.hsd1.va.comcast.net..pid
EOF
parse_mysqld_instances $TMPDIR/in > $TMPDIR/got
no_diff $TMPDIR/got $TMPDIR/expected

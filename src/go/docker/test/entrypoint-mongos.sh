#!/bin/bash

cp /mongos.key /tmp/mongos.key
cp /mongos.pem /tmp/mongos.pem
cp /rootCA.crt /tmp/mongod-rootCA.crt
chmod 400 /tmp/mongos.key /tmp/mongos.pem /tmp/mongod-rootCA.pem

/usr/bin/mongos \
	--keyFile=/tmp/mongos.key \
	--bind_ip=127.0.0.1 \
	--sslMode=preferSSL \
	--sslCAFile=/tmp/mongod-rootCA.crt \
	--sslPEMKeyFile=/tmp/mongos.pem \
	$*

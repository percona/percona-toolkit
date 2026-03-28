FROM oraclelinux:9-slim
RUN microdnf -y update
COPY bin/* /usr/bin/

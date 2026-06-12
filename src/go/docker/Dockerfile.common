FROM registry.access.redhat.com/ubi7/ubi-minimal
RUN microdnf update && microdnf clean all

MAINTAINER Percona Development <info@percona.com>
LABEL name="Percona Backup for MongoDB" \
      vendor="Percona" \
      summary="Percona Backup for MongoDB is a distributed, low-impact solution for achieving consistent backups of MongoDB Sharded Clusters and Replica Sets." \
      description=" This is a tool for creating consistent backups across a MongoDB sharded cluster (or a single replica set), and for restoring those backups to a specific point in time. Percona Backup for MongoDB uses a distributed client/server architecture to perform backup/restore actions."

COPY LICENSE /licenses/

# kubectl needed for Percona Operator for PSMDB
ENV KUBECTL_VERSION=v1.14.1
ENV KUBECTL_MD5SUM=223668b6d47121a9011645b04f5ef349
RUN curl -o /usr/bin/kubectl \
        https://storage.googleapis.com/kubernetes-release/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl \
    && chmod +x /usr/bin/kubectl \
    && echo "${KUBECTL_MD5SUM} /usr/bin/kubectl" | md5sum -c - \
    && curl -o /licenses/LICENSE.kubectl \
        https://raw.githubusercontent.com/kubernetes/kubectl/master/LICENSE

COPY pbmctl pbm-agent pbm-coordinator /usr/local/bin/

USER nobody

CMD ["pbmctl"]

ARG GOLANG_DOCKERHUB_TAG
FROM golang:$GOLANG_DOCKERHUB_TAG

RUN wget https://repo.percona.com/apt/percona-release_0.1-7.stretch_all.deb && dpkg -i percona-release_0.1-7.stretch_all.deb
RUN apt-get update && apt-get install -y percona-server-mongodb-36-server

WORKDIR /go/src/github.com/percona/percona-backup-mongodb
COPY . .
RUN chown -R mongod.mongod /go

USER mongod
RUN make vendor
CMD make test && \
    make test-gosec && \
    make

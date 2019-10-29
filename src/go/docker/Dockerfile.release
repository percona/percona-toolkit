FROM goreleaser/goreleaser

RUN apk --no-cache add upx

WORKDIR /go/src/github.com/percona/percona-backup-mongodb
COPY . .

ENTRYPOINT ["goreleaser"]
CMD ["release"]

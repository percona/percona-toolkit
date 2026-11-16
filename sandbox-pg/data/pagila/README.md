# Pagila

Vendored copy of the [Pagila](https://github.com/devrimgunduz/pagila) sample
database, the PostgreSQL port of the Sakila database that `sandbox/sakila-db`
provides for MySQL. Pagila is made available under the PostgreSQL license.

    Upstream: https://github.com/devrimgunduz/pagila
    Tag:      pagila-v3.1.0

The files are unmodified upstream dumps. This tag is used because later
releases require the `vector` extension, which the sandbox does not install:
the sandbox runs a stock PostgreSQL with no extra extensions.

`sandbox-pg/init.sql` loads them into the sandbox at deploy time, via
`pg_sandbox cluster deploy --init-sql`.

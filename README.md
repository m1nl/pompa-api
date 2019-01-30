# pompa

Fully-featured spear-phishing toolkit - API and job queue

**NOTE:** this is only backend component for [pompa](https://github.com/m1nl/pompa) web frontend. Please use [pompa-docker](https://github.com/m1nl/pompa-docker) repository for a full deployment base and read the [wiki](https://github.com/m1nl/pompa/wiki/Getting-Started).

## Prerequisites

You will need the following things properly installed on your computer:

* [Git](https://git-scm.com/)
* [RVM](https://rvm.io/)
* [Ruby](https://www.ruby-lang.org/en/) installed using RVM (version 2.5.1 or higher)
* [Bundler](https://bundler.io/)
* [PostgreSQL](https://www.postgresql.org/) including citext, trgm and tablefunc extensions
* [Redis](https://redis.io/)

## Installation

* `git clone https://github.com/m1nl/pompa-api.git`
* `cd pompa-api`
* `echo pompa > .ruby-gemset`
* `rvm use`
* `gem install bundler`
* `bundle install`
* ``rvm wrapper `pwd`/bin/model-sync``

## Configuration

* `cd config`
* `cp database.yml.sample database.yml`
* `cp pompa.yml.sample pompa.yml`
* `cp secrets.yml.sample secrets.yml`
* `cp sidekiq.yml.sample sidekiq.yml`
* Edit the files according to your needs
* Be sure to update secrets in the production environment in secrets.yml

## Database setup

Pompa uses PostgreSQL as DB backend. No other backends are supported right now.

Steps for DB configuration (valid for Ubuntu, Debian and CentOS):

* Replace \_USER\_ with your local system user
* `sudo -u postgres psql`
* `CREATE USER _USER_;`
* `CREATE DATABASE pompa_dev OWNER <USER>;`
* `\c pompa`
* `CREATE EXTENSION citext;`
* `CREATE EXTENSION pg_trgm;`
* `CREATE EXTENSION tablefunc;`
* `\q`
* No modifications to sample database.yml should be required.

## Redis setup

When Redis is run on the same machine, usage of UNIX socket is preferred. Verify if correct path is provided in pompa.yml for Redis and if your system user has required privileges. Usually you will need to be a member of local redis group to be able to access the socket.

It is recommended to set the following option in redis.conf file:

* `maxmemory-policy volatile-lfu`

## Running / Development

Terminal 1 (API server):

* `rails db:migrate`
* `rails server`

Terminal 2 (job queue):

* `bundle exec sidekiq`

Terminal 3 (notifications from DB):

* `bin/model-sync`

Web browser:

* Visit the API at [http://localhost:3000](http://localhost:3000).

## Further Reading / Useful Links

* [pompa](https://github.com/m1nl/pompa)
* [pompa-docker](https://github.com/m1nl/pompa-docker)
* [RVM](https://rvm.io/)
* [Ruby](https://www.ruby-lang.org/en/)
* [Bundler](https://bundler.io/)
* [PostgreSQL](https://www.postgresql.org/)
* [Redis](https://redis.io/)

## License
`pompa` is released under the terms of [lgpl-3.0](LICENSE).

## Author

Mateusz Nalewajski

## Commercial support / professional services

Please contact me directly at mateusz-at-nalewajski-dot-pl

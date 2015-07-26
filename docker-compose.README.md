cAdvisor with InfluxDB and Grafana
==================================

Launch cAdvisor with InfluxDB as the storage backend and Grafana
as the dashboard UI with a simple command. Everything runs in
Docker containers, so you don't need to install anything.


How?
----

[docker-compose.yml](docker-compose.yml) describes a [Docker Compose](https://docs.docker.com/compose/)
definition that orchestrates the following containers:

- [cAdvisor](https://github.com/google/cadvisor) - Docker container monitoring system with web frontend
- [InfluxDB](https://influxdb.com/docs/v0.9/introduction/overview.html) - TSDB that cAdvisor feeds so you can query history
- [Grafana](http://grafana.org/) - Web-based graphing engine that queries InfluxDB

View [docker-compose.yml](docker-compose.yml) to see exactly how everything is
wired together.


Usage
-----

Here are some basic commands. View Docker Compose [docs](https://docs.docker.com/compose/cli/)
for more information.

Initialize the cluster, and watch the logs. Add `-d` to run in the background.

    docker-compose up

Stop the cluster:

    docker-compose stop

Start a stopped cluster:

    docker-compose start

Stop and delete the cluster, losing all data and dashboards:

    docker-compose rm


cAdvisor
--------

cAdvisor listens on [http://localhost:9090](http://localhost:9090), showing the last 1 minute of
cpu, memory and network activity for the system and each Docker container.


InfluxDB
--------

InfluxDB listens on [http://localhost:8086](http://localhost:8086) for API traffic from cAdvisor
and Grafana, and [http://localhost:8083](http://localhost:8083) for user queries via the web
front-end. Log in with root/root. Data is written to the database "cadvisor" in the series "stats".


Grafana
-------

Grafana listens on [http://localhost:3000](http://localhost:3000) for web requests, showing graphs
built from InfluxDB queries. Shared dashboards will be loaded for you, and you can create and export
your own as JSON. Log in with admin/admin.


Credit
------

This was forked from [Dale-Kurt Murray's](https://github.com/dalekurt)
[docker-monitoring](https://github.com/dalekurt/docker-monitoring) repository.


create-dashboards.sh 
====================

Wire together Grafana and InfluxDB, and create Grafana dashboards for all of your Docker containers.


Details
-------

Ensure an InfluxDB user exists, pair the "cadvisor" InfluxDB with
[Grafana](http://grafana.org/), and build Grafana dashboards for
every existing Docker container.

- assumes the "cadvisor" InfluxDB database already exists
- ensures the InfluxDB user exist
- ensures the proxied Grafana InfluxDB data store exists
- creates/updates dashboards: one for all containers, and one for each


Usage
-----

    ./create-dashboards.sh


Assumptions
-----------

The script assumes a few ports and domains, as well as the root/root login for
InfluxDB and admin/admin login for Grafana. All of these configurations are
listed at the top of the script, so just change them to suit your needs. The 
InfluxDB name, login, and password are all hard-coded to `cadvisor`.


Credit
------

This is a modified fork of [Lee Hambley's](https://github.com/leehambley) [Gist](https://gist.github.com/leehambley/9741431695da3787f6b3).
He did most of the heavy lifting.

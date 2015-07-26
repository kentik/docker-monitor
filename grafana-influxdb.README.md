grafana-influxdb.sh: Set Up and Pair Grafana 2.x with InfluxDB 0.8
==================================================================

Create an [InfluxDB](https://influxdb.com/) database, pair it with
[Grafana](http://grafana.org/), and build Grafana dashboards from
JSON files.

- ensures the InfluxDB database and DB user exist
- ensures the proxied Grafana InfluxDB data store exists
- creates/updates dashboards found with a `find` file mask


Purpose
-------

This was designed to bootstrap a development system with the help of
configuration management (CM) tools like Puppet. A shared set of team
dashboards should be stored in CM. This script then sets up the
connections between InfluxDB and Grafana, and creates or updates the
team's Grafana dashboards.


Usage
-----

    grafana-influxdb.sh <db name> <file mask to dashboard JSON files (optional)>

Example:

    grafana-influxdb.sh myproject ./dashboards/*.json

The first argument is used for the InfluxDB database, the InfluxDB user and
password, and the Grafana data source. The second is fed to a `find` command,
where each result's contents are submitted to Grafana via its HTTP API.


Dashboard JSON
--------------

Create a dashboard in the Grafana web UI, then export it as JSON. Before
submitting it to Grafana, the "id" field will be stripped, so the dashboard
will be accepted as an insert. Dashboard uniqueness is determined by its name.


Assumptions
-----------

The script assumes a few ports and domains, as well as the root/root login for
InfluxDB and admin/admin login for Grafana. All of these configurations are
listed at the top of the script, so just change them to suit your needs.


Credit
------

This is a modified fork of [Lee Hambley's](https://github.com/leehambley) [Gist](https://gist.github.com/leehambley/9741431695da3787f6b3).
He did most of the heavy lifting.



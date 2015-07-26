#!/bin/bash
#
# See README.md for details
#
# Set up and pair an InfluxDB database with Grafana
# - ensures the InfluxDB database and DB user exist
# - ensures the proxied Grafana InfluxDB data store exists
# - creates/updates dashboards found in an optional file mask
#
# The InfluxDB database, InfluxDB user, and InfluxDB password
# are set from the first command line argument. The optional
# second argument is fed into a `find` command to find Grafana
# dashboard JSON definitions, which will be loaded into Grafana.
#
# This is a modified fork of Lee Hambley's Gist:
# at https://github.com/leehambley
#
# Usage:
#
#   grafana-influxdb.sh <db name> <file mask to dashboards (optional)>
#

INFLUXDB_API_URL='http://localhost:8086/'
INFLUXDB_API_REMOTE_URL='http://influxsrv:8086/'      # url for commands proxied through Grafana
INFLUXDB_ROOT_LOGIN='root'
INFLUXDB_ROOT_PASSWORD='root'

INFLUXDB_DB_NAME=$1
INFLUXDB_DB_LOGIN=$1
INFLUXDB_DB_PASSWORD=$1

GRAFANA_URL='http://localhost:3000/'
GRAFANA_API_URL='http://localhost:3000/api/'
GRAFANA_LOGIN='admin'
GRAFANA_PASSWORD='admin'
GRAFANA_DATA_SOURCE_NAME=$1

# File mask that'll find all of the dashboards you want to load
# Example: ./dashboards/*.json
DASHBOARD_FILEMASK=$2

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

COOKIEJAR=$(mktemp)
trap 'unlink ${COOKIEJAR}' EXIT
function usage {
  echo "Usage: ${0} <database_name> <dashboards file mask (optional)>"
  echo "  example: ${0} 'myproject' './dashboards/*.json'"
  exit 1
}

function influx_has_database {
  curl --silent "${INFLUXDB_API_URL}db?u=${INFLUXDB_ROOT_LOGIN}&p=${INFLUXDB_ROOT_PASSWORD}" | grep --silent "${INFLUXDB_DB_NAME}"
}

function influx_create_database {
  curl --silent --data-binary "{\"name\":\"${INFLUXDB_DB_NAME}\"}" "${INFLUXDB_API_URL}db?u=${INFLUXDB_ROOT_PASSWORD}&p=${INFLUXDB_ROOT_PASSWORD}"
}

function influx_has_user {
  curl --silent "${INFLUXDB_API_URL}db/${INFLUXDB_DB_NAME}/users?u=${INFLUXDB_ROOT_LOGIN}&p=${INFLUXDB_ROOT_PASSWORD}" | grep --silent "${INFLUXDB_DB_LOGIN}"
}

function influx_create_user {
  curl --silent --data-binary "{\"name\":\"${INFLUXDB_DB_NAME}\",\"password\":\"${INFLUXDB_DB_PASSWORD}\"}" "${INFLUXDB_API_URL}db/$INFLUXDB_DB_NAME/users?u=${INFLUXDB_ROOT_PASSWORD}&p=${INFLUXDB_ROOT_PASSWORD}"
}

function setup_influxdb {
  if influx_has_database; then
    info "InfluxDB: Database $INFLUXDB_DB_NAME already exists"
  else
    if influx_create_database; then
      success "InfluxDB: Database $INFLUXDB_DB_NAME created"
    else
      error "InfluxDB: Database $INFLUXDB_DB_NAME could not be created"
    fi
  fi
  if influx_has_user; then
    info "InfluxDB: Database ${INFLUXDB_DB_NAME} already has the user ${INFLUXDB_DB_LOGIN}"
  else
    if influx_create_user; then
      success "InfluxDB: Database ${INFLUXDB_DB_NAME} user ${INFLUXDB_DB_LOGIN} created"
    else
      error "InfluxDB: Database ${INFLUXDB_DB_NAME} user ${INFLUXDB_DB_LOGIN} could not be created"
    fi
  fi
}

function setup_grafana_session {
  if ! curl -H 'Content-Type: application/json;charset=UTF-8' \
    --data-binary "{\"user\":\"${GRAFANA_LOGIN}\",\"email\":\"\",\"password\":\"${GRAFANA_PASSWORD}\"}" \
    --cookie-jar "$COOKIEJAR" \
    "${GRAFANA_URL}login" > /dev/null 2>&1 ; then
    echo
    error "Grafana Session: Couldn't store cookies at ${COOKIEJAR}"
  fi
}

function grafana_has_data_source {
  setup_grafana_session
  curl --silent --cookie "${COOKIEJAR}" "${GRAFANA_API_URL}datasources" \
    | grep "\"name\":\"${GRAFANA_DATA_SOURCE_NAME}\"" --silent
}

function grafana_create_data_source {
  setup_grafana_session
  curl --cookie "${COOKIEJAR}" \
       -X PUT \
       --silent \
       -H 'Content-Type: application/json;charset=UTF-8' \
       --data-binary "{\"name\":\"${GRAFANA_DATA_SOURCE_NAME}\",\"type\":\"influxdb_08\",\"url\":\"${INFLUXDB_API_REMOTE_URL}\",\"access\":\"proxy\",\"database\":\"$INFLUXDB_DB_NAME\",\"user\":\"${INFLUXDB_DB_LOGIN}\",\"password\":\"${INFLUXDB_DB_PASSWORD}\"}" \
       "${GRAFANA_API_URL}datasources" 2>&1 | grep 'Datasource added' --silent;
}

function setup_grafana {
  if grafana_has_data_source; then
    info "Grafana: Data source ${INFLUXDB_DB_NAME} already exists"
  else
    if grafana_create_data_source; then
      success "Grafana: Data source $INFLUXDB_DB_NAME created"
    else
      error "Grafana: Data source $INFLUXDB_DB_NAME could not be created"
    fi
  fi

  ensure_grafana_dashboards
}

function ensure_grafana_dashboard {
  DASHBOARD_PATH=$1
  TEMP_DIR=$(mktemp -d)
  TEMP_FILE="${TEMP_DIR}/dashboard"

  # Need to wrap the dashboard json, and make sure the dashboard's "id" is null for insert
  echo '{"dashboard":' > $TEMP_FILE
  cat $DASHBOARD_PATH | sed -E 's/^  "id": [0-9]+,$/  "id": null,/' >> $TEMP_FILE
  echo ', "overwrite": true }' >> $TEMP_FILE

  curl --cookie "${COOKIEJAR}" \
       -X POST \
       --silent \
       -H 'Content-Type: application/json;charset=UTF-8' \
       --data "@${TEMP_FILE}" \
       "${GRAFANA_API_URL}dashboards/db" # > /dev/null 2>&1
  echo
  unlink $TEMP_FILE
  rmdir $TEMP_DIR
}

function ensure_grafana_dashboards {
  if [ ! -z "${DASHBOARD_FILEMASK}" ]; then
    for DASHBOARD_FILE in `find ${DASHBOARD_FILEMASK} -type f`; do
      ensure_grafana_dashboard $DASHBOARD_FILE
    done
  fi
}

function success {
  echo "$(tput setaf 2)""$*""$(tput sgr0)"
}

function info {
  echo "$(tput setaf 3)""$*""$(tput sgr0)"
}

function error {
  echo "$(tput setaf 1)""$*""$(tput sgr0)" 1>&2
}

function setup {
  setup_influxdb
  setup_grafana
}

if [ "$#" -eq "0" ]; then
  usage
else
  setup
fi


#!/bin/bash
#
# See README.md for details
#
# Set up and pair an InfluxDB database with Grafana
# - ensures the InfluxDB database and DB user exist
# - ensures the proxied Grafana InfluxDB data store exists
# - creates/updates dashboards for each container, and one for all containers
#
# The InfluxDB database, InfluxDB user, and InfluxDB password hard-coded to 'cadvisor'
#
# This is a modified fork of Lee Hambley's Gist:
# at https://github.com/leehambley
#
# Usage:
#
#   create-dashboards.sh
#

INFLUXDB_API_URL='http://localhost:8086/'
INFLUXDB_API_REMOTE_URL='http://influxsrv:8086/'      # url for commands proxied through Grafana
INFLUXDB_ROOT_LOGIN='root'
INFLUXDB_ROOT_PASSWORD='root'

INFLUXDB_DB_NAME=cadvisor
INFLUXDB_DB_LOGIN=cadvisor
INFLUXDB_DB_PASSWORD=cadvisor

GRAFANA_URL='http://localhost:3000/'
GRAFANA_API_URL='http://localhost:3000/api/'
GRAFANA_LOGIN='admin'
GRAFANA_PASSWORD='admin'
GRAFANA_DATA_SOURCE_NAME=cadvisor

NEWLINE='
'
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

COOKIEJAR=$(mktemp)
trap 'unlink ${COOKIEJAR}' EXIT

function influx_has_user {
  curl \
    --silent \
    --data-urlencode "q=SHOW USERS" \
    "${INFLUXDB_API_URL}query?u=${INFLUXDB_ROOT_LOGIN}&p=${INFLUXDB_ROOT_PASSWORD}" \
    | grep --silent "${INFLUXDB_DB_LOGIN}"
}

function influx_create_user {
  curl \
    --silent \
    -XPOST \
    --data-urlencode "q=CREATE USER ${INFLUXDB_DB_LOGIN} WITH PASSWORD '${INFLUXDB_DB_PASSWORD}'; GRANT ALL PRIVILEGES ON ${INFLUXDB_DB_NAME} TO ${INFLUXDB_DB_LOGIN}" \
    "${INFLUXDB_API_URL}query?u=${INFLUXDB_ROOT_ADMIN}&p=${INFLUXDB_ROOT_PASSWORD}" > /dev/null 2>&1
}

function setup_influxdb {
  # Note: InfluxDB is configured with PRE_CREATE_DB=cadvisor
  if influx_has_user; then
    info "InfluxDB: Database ${INFLUXDB_DB_NAME} already has the user ${influxdb_DB_LOGIN}"
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
       -X POST \
       --silent \
       -H 'Content-Type: application/json;charset=UTF-8' \
       --data-binary "{\"name\":\"${GRAFANA_DATA_SOURCE_NAME}\",\"type\":\"influxdb\",\"url\":\"${INFLUXDB_API_REMOTE_URL}\",\"access\":\"proxy\",\"database\":\"$INFLUXDB_DB_NAME\",\"user\":\"${INFLUXDB_DB_LOGIN}\",\"password\":\"${INFLUXDB_DB_PASSWORD}\"}" \
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
}

function ensure_dashboard_from_template {
  TITLE=$1
  WHERE_CLAUSE=$2
  STACK=$3

  NET_USAGE_TITLE="Container Network Usage"
  FS_LIMIT_WHERE=""
  TOOLTIP_SHARED="true"
  if [ $STACK = "true" ]; then
    NET_USAGE_TITLE="Container Network Usage (view a single container if --net=host)"
    FS_LIMIT_WHERE="and 1=0"
    TOOLTIP_SHARED="false"
  fi

  TEMP_FILE_1=$(mktemp)
  cat "Container.json.tmpl" \
    | sed -e "s|___TITLE___|$TITLE|g" \
    | sed -e "s|___STACK___|$STACK|g" \
    | sed -e "s|___FS_LIMIT_WHERE___|$FS_LIMIT_WHERE|g" \
    | sed -e "s|___NETWORK_USAGE_TITLE___|$NET_USAGE_TITLE|g" \
    | sed -e "s|___TOOLTIP_SHARED___|$TOOLTIP_SHARED|g" \
    | sed -e "s|___CONTAINER_WHERE_CLAUSE___|$WHERE_CLAUSE|g" \
    > "${TEMP_FILE_1}"
	ensure_grafana_dashboard "${TEMP_FILE_1}"
  RET=$?
  unlink "${TEMP_FILE_1}"
  if [ "${RET}" -ne "0" ]; then
    echo "An error occurred"
    exit 1
  fi
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
       "${GRAFANA_API_URL}dashboards/db" > /dev/null 2>&1
  unlink $TEMP_FILE
  rmdir $TEMP_DIR
}

function ensure_grafana_dashboards {
	echo "Creating a dashboard for 'All Containers'"
  ensure_dashboard_from_template 'All Containers (Stacked)' 'container_name !~ /\\\\//' "true"

	echo "Creating a dashboard for each running container"
  IFS=$NEWLINE
  for x in `docker ps`; do
    CONTAINER_ID=`echo $x | awk '{print $1}'`
    CONTAINER=`echo $x | awk 'END {print $NF}'`

    # Skip the header
    if [ "${CONTAINER_ID}" = "CONTAINER" ]; then
      continue
    fi

    echo "creating a dashboard for container '${CONTAINER}'"
    ensure_dashboard_from_template "${CONTAINER}" "container_name='${CONTAINER}'" "false"
  done
  echo "Done"
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

setup_influxdb
setup_grafana
ensure_grafana_dashboards

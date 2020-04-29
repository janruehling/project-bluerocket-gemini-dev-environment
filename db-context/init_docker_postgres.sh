#!/bin/bash

# DB_SCHEMA_LOCATION="/tmp/psql_data/db_schema.sql"
DB_DUMP_LOCATION="/tmp/psql_data/db_dump.sql"

echo "*** CREATING DATABASE ***"

# psql -U doadmin defaultdb < "$DB_SCHEMA_LOCATION";
psql -U doadmin defaultdb < "$DB_DUMP_LOCATION";

echo "*** DATABASE CREATED! ***"

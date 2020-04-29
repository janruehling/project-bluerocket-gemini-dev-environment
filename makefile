db_dump:
	docker run -it --rm -e PGPASSWORD=${EXTERNAL_DB_PASSWORD} postgres /usr/bin/pg_dump -h ${EXTERNAL_DB_HOST} -p ${EXTERNAL_DB_PORT} -U ${EXTERNAL_DB_USER} ${EXTERNAL_DB_DATABASE} > db-context/db_dump.sql

db_schema:
	docker run -it --rm -e PGPASSWORD=${EXTERNAL_DB_PASSWORD} postgres /usr/bin/pg_dump -h ${EXTERNAL_DB_HOST} -p ${EXTERNAL_DB_PORT} -U ${EXTERNAL_DB_USER} -d ${EXTERNAL_DB_DATABASE} -s > db-context/db_schema.sql

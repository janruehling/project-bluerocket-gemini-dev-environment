# gemini-dev-environment

## Prerequisites

- Have Docker and Docker-Compose installed
- git clone `gemini-web-react`, `gemini-api-node` & `gemini-dev-environment` into the same folder
- Rename `.env-api-sample` to `.env-api` & `.env-web-sample` to `.env-web`
- Replace the `<Ask your fellow developers>` placeholders with real values in both .env files

## Usage

- `cd gemini-dev-environment`
- `docker-compose up` (user `docker-compose up -d` if you want to do work in the same terminal)

- http://localhost:3000 > React App
- http://localhost:9001 > React StoryBook

- http://localhost:8080/graphql > API endpoints
- http://localhost:8080/playground > GraphiQL interface
- http://localhost:8080/voyager > Voyager interface
- http://localhost:4000 > Adminer Postgres interface (User/Password: `postgres`, host: `db`). Database used inside the app is `postgres` too

## Rebuild

- run `docker-compose up --build` if you have to refresh the local containers

## Update the database dump

- get the full Digital Ocean database url from your fellow developers
- extract the variables that you need from the url. The format is like this:
  postgresql://`<USERNAME>`:`<PASSWORD>`@`<HOST>`:`<PORT>`/`<DATABASE>`
- replace the variables in this command and run it: `docker run -i -e PGPASSWORD=<PASSWORD> /usr/bin/pg_dump -h <HOST> -p <PORT> -U <USERNAME> <DATABASE> > db-context/db_backup.sql`

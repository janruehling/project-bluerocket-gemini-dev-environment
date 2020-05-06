# gemini-dev-environment

## Prerequisites

- Have Docker and Docker-Compose installed
- git clone `gemini-web-react`, `gemini-api-node` & `gemini-dev-environment` into the same folder
- Rename `.env-api-sample` to `.env-api` & `.env-web-sample` to `.env-web`
- Replace the `<Ask your fellow developers>` placeholders with real values in both .env files

## Create database dump

- get the full DigitalOcean database url from your fellow developers
- extract the variables that you need from the url. The format is like this:
  postgresql://`<USERNAME>`:`<PASSWORD>`@`<HOST>`:`<PORT>`/`<DATABASE>`
- update your .env-api file. All `EXTERNAL_DB_*` variables take one of the above values

## Usage

- `cd gemini-dev-environment`
- `make db_dump` to pull the latest data from the database. Do that regularly.
- `docker-compose down -v` or `docker-compose rm` -> Make sure that the environment is not running and delete all created volumes for this stack. The database data won't update if there is still an existing volume around.
- `docker-compose up --build` (use `docker-compose up --build -d` if you want to do work in the same terminal)

- http://localhost:3000 > React App
- http://localhost:9001 > React StoryBook

- http://localhost:8080/graphql > API endpoints
- http://localhost:8080/playground > GraphiQL interface
- http://localhost:8080/voyager > Voyager interface
- http://localhost:4000 > Adminer Postgres interface (User: `doadmin`, Password: `postgres`, host: `defaultdb`).

## Heads up

- If you run into `[nodemon] Internal watch failed: ENOSPC: System limit for number of file watchers reached, watch '/home/node/app'` then run `echo fs.inotify.max_user_watches=524288 | sudo tee -a /etc/sysctl.conf && sudo sysctl -p` to increase the number of supported watchers for nodemon
- To speed up the build steps in Docker put a `.dockerignore` file into the parent container of this folder and add `**/node_modules` and `**/.git` to it.

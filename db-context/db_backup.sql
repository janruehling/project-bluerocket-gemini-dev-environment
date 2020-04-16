--
-- PostgreSQL database dump
--

-- Dumped from database version 11.7
-- Dumped by pg_dump version 12.2 (Debian 12.2-2.pgdg100+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: hdb_catalog; Type: SCHEMA; Schema: -; Owner: doadmin
--

CREATE SCHEMA hdb_catalog;


ALTER SCHEMA hdb_catalog OWNER TO doadmin;

--
-- Name: hdb_views; Type: SCHEMA; Schema: -; Owner: doadmin
--

CREATE SCHEMA hdb_views;


ALTER SCHEMA hdb_views OWNER TO doadmin;

--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;


--
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


--
-- Name: check_violation(text); Type: FUNCTION; Schema: hdb_catalog; Owner: doadmin
--

CREATE FUNCTION hdb_catalog.check_violation(msg text) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
  BEGIN
    RAISE check_violation USING message=msg;
  END;
$$;


ALTER FUNCTION hdb_catalog.check_violation(msg text) OWNER TO doadmin;

--
-- Name: hdb_schema_update_event_notifier(); Type: FUNCTION; Schema: hdb_catalog; Owner: doadmin
--

CREATE FUNCTION hdb_catalog.hdb_schema_update_event_notifier() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
  DECLARE
    instance_id uuid;
    occurred_at timestamptz;
    invalidations json;
    curr_rec record;
  BEGIN
    instance_id = NEW.instance_id;
    occurred_at = NEW.occurred_at;
    invalidations = NEW.invalidations;
    PERFORM pg_notify('hasura_schema_update', json_build_object(
      'instance_id', instance_id,
      'occurred_at', occurred_at,
      'invalidations', invalidations
      )::text);
    RETURN curr_rec;
  END;
$$;


ALTER FUNCTION hdb_catalog.hdb_schema_update_event_notifier() OWNER TO doadmin;

--
-- Name: inject_table_defaults(text, text, text, text); Type: FUNCTION; Schema: hdb_catalog; Owner: doadmin
--

CREATE FUNCTION hdb_catalog.inject_table_defaults(view_schema text, view_name text, tab_schema text, tab_name text) RETURNS void
    LANGUAGE plpgsql
    AS $$
    DECLARE
        r RECORD;
    BEGIN
      FOR r IN SELECT column_name, column_default FROM information_schema.columns WHERE table_schema = tab_schema AND table_name = tab_name AND column_default IS NOT NULL LOOP
          EXECUTE format('ALTER VIEW %I.%I ALTER COLUMN %I SET DEFAULT %s;', view_schema, view_name, r.column_name, r.column_default);
      END LOOP;
    END;
$$;


ALTER FUNCTION hdb_catalog.inject_table_defaults(view_schema text, view_name text, tab_schema text, tab_name text) OWNER TO doadmin;

--
-- Name: insert_event_log(text, text, text, text, json); Type: FUNCTION; Schema: hdb_catalog; Owner: doadmin
--

CREATE FUNCTION hdb_catalog.insert_event_log(schema_name text, table_name text, trigger_name text, op text, row_data json) RETURNS text
    LANGUAGE plpgsql
    AS $$
  DECLARE
    id text;
    payload json;
    session_variables json;
    server_version_num int;
  BEGIN
    id := gen_random_uuid();
    server_version_num := current_setting('server_version_num');
    IF server_version_num >= 90600 THEN
      session_variables := current_setting('hasura.user', 't');
    ELSE
      BEGIN
        session_variables := current_setting('hasura.user');
      EXCEPTION WHEN OTHERS THEN
                  session_variables := NULL;
      END;
    END IF;
    payload := json_build_object(
      'op', op,
      'data', row_data,
      'session_variables', session_variables
    );
    INSERT INTO hdb_catalog.event_log
                (id, schema_name, table_name, trigger_name, payload)
    VALUES
    (id, schema_name, table_name, trigger_name, payload);
    RETURN id;
  END;
$$;


ALTER FUNCTION hdb_catalog.insert_event_log(schema_name text, table_name text, trigger_name text, op text, row_data json) OWNER TO doadmin;

--
-- Name: get_department_position_subtype_counts(uuid); Type: FUNCTION; Schema: public; Owner: doadmin
--

CREATE FUNCTION public.get_department_position_subtype_counts(dept_id uuid) RETURNS TABLE(subtype text, subtype_count integer)
    LANGUAGE plpgsql
    AS $$
BEGIN
   RETURN QUERY SELECT
      subtype,
      cast( count(*) as integer)
   FROM
      position
   WHERE
      department_id = dept_id ;
END; $$;


ALTER FUNCTION public.get_department_position_subtype_counts(dept_id uuid) OWNER TO doadmin;

--
-- Name: set_current_timestamp_updated_at(); Type: FUNCTION; Schema: public; Owner: doadmin
--

CREATE FUNCTION public.set_current_timestamp_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  _new record;
BEGIN
  _new := NEW;
  _new."updated_at" = NOW();
  RETURN _new;
END;
$$;


ALTER FUNCTION public.set_current_timestamp_updated_at() OWNER TO doadmin;

SET default_tablespace = '';

--
-- Name: event_invocation_logs; Type: TABLE; Schema: hdb_catalog; Owner: doadmin
--

CREATE TABLE hdb_catalog.event_invocation_logs (
    id text DEFAULT public.gen_random_uuid() NOT NULL,
    event_id text,
    status integer,
    request json,
    response json,
    created_at timestamp without time zone DEFAULT now()
);


ALTER TABLE hdb_catalog.event_invocation_logs OWNER TO doadmin;

--
-- Name: event_log; Type: TABLE; Schema: hdb_catalog; Owner: doadmin
--

CREATE TABLE hdb_catalog.event_log (
    id text DEFAULT public.gen_random_uuid() NOT NULL,
    schema_name text NOT NULL,
    table_name text NOT NULL,
    trigger_name text NOT NULL,
    payload jsonb NOT NULL,
    delivered boolean DEFAULT false NOT NULL,
    error boolean DEFAULT false NOT NULL,
    tries integer DEFAULT 0 NOT NULL,
    created_at timestamp without time zone DEFAULT now(),
    locked boolean DEFAULT false NOT NULL,
    next_retry_at timestamp without time zone,
    archived boolean DEFAULT false NOT NULL
);


ALTER TABLE hdb_catalog.event_log OWNER TO doadmin;

--
-- Name: event_triggers; Type: TABLE; Schema: hdb_catalog; Owner: doadmin
--

CREATE TABLE hdb_catalog.event_triggers (
    name text NOT NULL,
    type text NOT NULL,
    schema_name text NOT NULL,
    table_name text NOT NULL,
    configuration json,
    comment text
);


ALTER TABLE hdb_catalog.event_triggers OWNER TO doadmin;

--
-- Name: hdb_allowlist; Type: TABLE; Schema: hdb_catalog; Owner: doadmin
--

CREATE TABLE hdb_catalog.hdb_allowlist (
    collection_name text
);


ALTER TABLE hdb_catalog.hdb_allowlist OWNER TO doadmin;

--
-- Name: hdb_check_constraint; Type: VIEW; Schema: hdb_catalog; Owner: doadmin
--

CREATE VIEW hdb_catalog.hdb_check_constraint AS
 SELECT (n.nspname)::text AS table_schema,
    (ct.relname)::text AS table_name,
    (r.conname)::text AS constraint_name,
    pg_get_constraintdef(r.oid, true) AS "check"
   FROM ((pg_constraint r
     JOIN pg_class ct ON ((r.conrelid = ct.oid)))
     JOIN pg_namespace n ON ((ct.relnamespace = n.oid)))
  WHERE (r.contype = 'c'::"char");


ALTER TABLE hdb_catalog.hdb_check_constraint OWNER TO doadmin;

--
-- Name: hdb_computed_field; Type: TABLE; Schema: hdb_catalog; Owner: doadmin
--

CREATE TABLE hdb_catalog.hdb_computed_field (
    table_schema text NOT NULL,
    table_name text NOT NULL,
    computed_field_name text NOT NULL,
    definition jsonb NOT NULL,
    comment text
);


ALTER TABLE hdb_catalog.hdb_computed_field OWNER TO doadmin;

--
-- Name: hdb_computed_field_function; Type: VIEW; Schema: hdb_catalog; Owner: doadmin
--

CREATE VIEW hdb_catalog.hdb_computed_field_function AS
 SELECT hdb_computed_field.table_schema,
    hdb_computed_field.table_name,
    hdb_computed_field.computed_field_name,
        CASE
            WHEN (((hdb_computed_field.definition -> 'function'::text) ->> 'name'::text) IS NULL) THEN (hdb_computed_field.definition ->> 'function'::text)
            ELSE ((hdb_computed_field.definition -> 'function'::text) ->> 'name'::text)
        END AS function_name,
        CASE
            WHEN (((hdb_computed_field.definition -> 'function'::text) ->> 'schema'::text) IS NULL) THEN 'public'::text
            ELSE ((hdb_computed_field.definition -> 'function'::text) ->> 'schema'::text)
        END AS function_schema
   FROM hdb_catalog.hdb_computed_field;


ALTER TABLE hdb_catalog.hdb_computed_field_function OWNER TO doadmin;

--
-- Name: hdb_foreign_key_constraint; Type: VIEW; Schema: hdb_catalog; Owner: doadmin
--

CREATE VIEW hdb_catalog.hdb_foreign_key_constraint AS
 SELECT (q.table_schema)::text AS table_schema,
    (q.table_name)::text AS table_name,
    (q.constraint_name)::text AS constraint_name,
    (min(q.constraint_oid))::integer AS constraint_oid,
    min((q.ref_table_table_schema)::text) AS ref_table_table_schema,
    min((q.ref_table)::text) AS ref_table,
    json_object_agg(ac.attname, afc.attname) AS column_mapping,
    min((q.confupdtype)::text) AS on_update,
    min((q.confdeltype)::text) AS on_delete,
    json_agg(ac.attname) AS columns,
    json_agg(afc.attname) AS ref_columns
   FROM ((( SELECT ctn.nspname AS table_schema,
            ct.relname AS table_name,
            r.conrelid AS table_id,
            r.conname AS constraint_name,
            r.oid AS constraint_oid,
            cftn.nspname AS ref_table_table_schema,
            cft.relname AS ref_table,
            r.confrelid AS ref_table_id,
            r.confupdtype,
            r.confdeltype,
            unnest(r.conkey) AS column_id,
            unnest(r.confkey) AS ref_column_id
           FROM ((((pg_constraint r
             JOIN pg_class ct ON ((r.conrelid = ct.oid)))
             JOIN pg_namespace ctn ON ((ct.relnamespace = ctn.oid)))
             JOIN pg_class cft ON ((r.confrelid = cft.oid)))
             JOIN pg_namespace cftn ON ((cft.relnamespace = cftn.oid)))
          WHERE (r.contype = 'f'::"char")) q
     JOIN pg_attribute ac ON (((q.column_id = ac.attnum) AND (q.table_id = ac.attrelid))))
     JOIN pg_attribute afc ON (((q.ref_column_id = afc.attnum) AND (q.ref_table_id = afc.attrelid))))
  GROUP BY q.table_schema, q.table_name, q.constraint_name;


ALTER TABLE hdb_catalog.hdb_foreign_key_constraint OWNER TO doadmin;

--
-- Name: hdb_function; Type: TABLE; Schema: hdb_catalog; Owner: doadmin
--

CREATE TABLE hdb_catalog.hdb_function (
    function_schema text NOT NULL,
    function_name text NOT NULL,
    configuration jsonb DEFAULT '{}'::jsonb NOT NULL,
    is_system_defined boolean DEFAULT false
);


ALTER TABLE hdb_catalog.hdb_function OWNER TO doadmin;

--
-- Name: hdb_function_agg; Type: VIEW; Schema: hdb_catalog; Owner: doadmin
--

CREATE VIEW hdb_catalog.hdb_function_agg AS
 SELECT (p.proname)::text AS function_name,
    (pn.nspname)::text AS function_schema,
    pd.description,
        CASE
            WHEN (p.provariadic = (0)::oid) THEN false
            ELSE true
        END AS has_variadic,
        CASE
            WHEN ((p.provolatile)::text = ('i'::character(1))::text) THEN 'IMMUTABLE'::text
            WHEN ((p.provolatile)::text = ('s'::character(1))::text) THEN 'STABLE'::text
            WHEN ((p.provolatile)::text = ('v'::character(1))::text) THEN 'VOLATILE'::text
            ELSE NULL::text
        END AS function_type,
    pg_get_functiondef(p.oid) AS function_definition,
    (rtn.nspname)::text AS return_type_schema,
    (rt.typname)::text AS return_type_name,
    (rt.typtype)::text AS return_type_type,
    p.proretset AS returns_set,
    ( SELECT COALESCE(json_agg(json_build_object('schema', q.schema, 'name', q.name, 'type', q.type)), '[]'::json) AS "coalesce"
           FROM ( SELECT pt.typname AS name,
                    pns.nspname AS schema,
                    pt.typtype AS type,
                    pat.ordinality
                   FROM ((unnest(COALESCE(p.proallargtypes, (p.proargtypes)::oid[])) WITH ORDINALITY pat(oid, ordinality)
                     LEFT JOIN pg_type pt ON ((pt.oid = pat.oid)))
                     LEFT JOIN pg_namespace pns ON ((pt.typnamespace = pns.oid)))
                  ORDER BY pat.ordinality) q) AS input_arg_types,
    to_json(COALESCE(p.proargnames, ARRAY[]::text[])) AS input_arg_names,
    p.pronargdefaults AS default_args,
    (p.oid)::integer AS function_oid
   FROM ((((pg_proc p
     JOIN pg_namespace pn ON ((pn.oid = p.pronamespace)))
     JOIN pg_type rt ON ((rt.oid = p.prorettype)))
     JOIN pg_namespace rtn ON ((rtn.oid = rt.typnamespace)))
     LEFT JOIN pg_description pd ON ((p.oid = pd.objoid)))
  WHERE (((pn.nspname)::text !~~ 'pg_%'::text) AND ((pn.nspname)::text <> ALL (ARRAY['information_schema'::text, 'hdb_catalog'::text, 'hdb_views'::text])) AND (NOT (EXISTS ( SELECT 1
           FROM pg_aggregate
          WHERE ((pg_aggregate.aggfnoid)::oid = p.oid)))));


ALTER TABLE hdb_catalog.hdb_function_agg OWNER TO doadmin;

--
-- Name: hdb_function_info_agg; Type: VIEW; Schema: hdb_catalog; Owner: doadmin
--

CREATE VIEW hdb_catalog.hdb_function_info_agg AS
 SELECT hdb_function_agg.function_name,
    hdb_function_agg.function_schema,
    row_to_json(( SELECT e.*::record AS e
           FROM ( SELECT hdb_function_agg.description,
                    hdb_function_agg.has_variadic,
                    hdb_function_agg.function_type,
                    hdb_function_agg.return_type_schema,
                    hdb_function_agg.return_type_name,
                    hdb_function_agg.return_type_type,
                    hdb_function_agg.returns_set,
                    hdb_function_agg.input_arg_types,
                    hdb_function_agg.input_arg_names,
                    hdb_function_agg.default_args,
                    (EXISTS ( SELECT 1
                           FROM information_schema.tables
                          WHERE (((tables.table_schema)::text = hdb_function_agg.return_type_schema) AND ((tables.table_name)::text = hdb_function_agg.return_type_name)))) AS returns_table) e)) AS function_info
   FROM hdb_catalog.hdb_function_agg;


ALTER TABLE hdb_catalog.hdb_function_info_agg OWNER TO doadmin;

--
-- Name: hdb_permission; Type: TABLE; Schema: hdb_catalog; Owner: doadmin
--

CREATE TABLE hdb_catalog.hdb_permission (
    table_schema name NOT NULL,
    table_name name NOT NULL,
    role_name text NOT NULL,
    perm_type text NOT NULL,
    perm_def jsonb NOT NULL,
    comment text,
    is_system_defined boolean DEFAULT false,
    CONSTRAINT hdb_permission_perm_type_check CHECK ((perm_type = ANY (ARRAY['insert'::text, 'select'::text, 'update'::text, 'delete'::text])))
);


ALTER TABLE hdb_catalog.hdb_permission OWNER TO doadmin;

--
-- Name: hdb_permission_agg; Type: VIEW; Schema: hdb_catalog; Owner: doadmin
--

CREATE VIEW hdb_catalog.hdb_permission_agg AS
 SELECT hdb_permission.table_schema,
    hdb_permission.table_name,
    hdb_permission.role_name,
    json_object_agg(hdb_permission.perm_type, hdb_permission.perm_def) AS permissions
   FROM hdb_catalog.hdb_permission
  GROUP BY hdb_permission.table_schema, hdb_permission.table_name, hdb_permission.role_name;


ALTER TABLE hdb_catalog.hdb_permission_agg OWNER TO doadmin;

--
-- Name: hdb_primary_key; Type: VIEW; Schema: hdb_catalog; Owner: doadmin
--

CREATE VIEW hdb_catalog.hdb_primary_key AS
 SELECT tc.table_schema,
    tc.table_name,
    tc.constraint_name,
    json_agg(constraint_column_usage.column_name) AS columns
   FROM (information_schema.table_constraints tc
     JOIN ( SELECT x.tblschema AS table_schema,
            x.tblname AS table_name,
            x.colname AS column_name,
            x.cstrname AS constraint_name
           FROM ( SELECT DISTINCT nr.nspname,
                    r.relname,
                    a.attname,
                    c.conname
                   FROM pg_namespace nr,
                    pg_class r,
                    pg_attribute a,
                    pg_depend d,
                    pg_namespace nc,
                    pg_constraint c
                  WHERE ((nr.oid = r.relnamespace) AND (r.oid = a.attrelid) AND (d.refclassid = ('pg_class'::regclass)::oid) AND (d.refobjid = r.oid) AND (d.refobjsubid = a.attnum) AND (d.classid = ('pg_constraint'::regclass)::oid) AND (d.objid = c.oid) AND (c.connamespace = nc.oid) AND (c.contype = 'c'::"char") AND (r.relkind = ANY (ARRAY['r'::"char", 'p'::"char"])) AND (NOT a.attisdropped))
                UNION ALL
                 SELECT nr.nspname,
                    r.relname,
                    a.attname,
                    c.conname
                   FROM pg_namespace nr,
                    pg_class r,
                    pg_attribute a,
                    pg_namespace nc,
                    pg_constraint c
                  WHERE ((nr.oid = r.relnamespace) AND (r.oid = a.attrelid) AND (nc.oid = c.connamespace) AND (r.oid =
                        CASE c.contype
                            WHEN 'f'::"char" THEN c.confrelid
                            ELSE c.conrelid
                        END) AND (a.attnum = ANY (
                        CASE c.contype
                            WHEN 'f'::"char" THEN c.confkey
                            ELSE c.conkey
                        END)) AND (NOT a.attisdropped) AND (c.contype = ANY (ARRAY['p'::"char", 'u'::"char", 'f'::"char"])) AND (r.relkind = ANY (ARRAY['r'::"char", 'p'::"char"])))) x(tblschema, tblname, colname, cstrname)) constraint_column_usage ON ((((tc.constraint_name)::text = (constraint_column_usage.constraint_name)::text) AND ((tc.table_schema)::text = (constraint_column_usage.table_schema)::text) AND ((tc.table_name)::text = (constraint_column_usage.table_name)::text))))
  WHERE ((tc.constraint_type)::text = 'PRIMARY KEY'::text)
  GROUP BY tc.table_schema, tc.table_name, tc.constraint_name;


ALTER TABLE hdb_catalog.hdb_primary_key OWNER TO doadmin;

--
-- Name: hdb_query_collection; Type: TABLE; Schema: hdb_catalog; Owner: doadmin
--

CREATE TABLE hdb_catalog.hdb_query_collection (
    collection_name text NOT NULL,
    collection_defn jsonb NOT NULL,
    comment text,
    is_system_defined boolean DEFAULT false
);


ALTER TABLE hdb_catalog.hdb_query_collection OWNER TO doadmin;

--
-- Name: hdb_relationship; Type: TABLE; Schema: hdb_catalog; Owner: doadmin
--

CREATE TABLE hdb_catalog.hdb_relationship (
    table_schema name NOT NULL,
    table_name name NOT NULL,
    rel_name text NOT NULL,
    rel_type text,
    rel_def jsonb NOT NULL,
    comment text,
    is_system_defined boolean DEFAULT false,
    CONSTRAINT hdb_relationship_rel_type_check CHECK ((rel_type = ANY (ARRAY['object'::text, 'array'::text])))
);


ALTER TABLE hdb_catalog.hdb_relationship OWNER TO doadmin;

--
-- Name: hdb_schema_update_event; Type: TABLE; Schema: hdb_catalog; Owner: doadmin
--

CREATE TABLE hdb_catalog.hdb_schema_update_event (
    instance_id uuid NOT NULL,
    occurred_at timestamp with time zone DEFAULT now() NOT NULL,
    invalidations json NOT NULL
);


ALTER TABLE hdb_catalog.hdb_schema_update_event OWNER TO doadmin;

--
-- Name: hdb_table; Type: TABLE; Schema: hdb_catalog; Owner: doadmin
--

CREATE TABLE hdb_catalog.hdb_table (
    table_schema name NOT NULL,
    table_name name NOT NULL,
    configuration jsonb,
    is_system_defined boolean DEFAULT false,
    is_enum boolean DEFAULT false NOT NULL
);


ALTER TABLE hdb_catalog.hdb_table OWNER TO doadmin;

--
-- Name: hdb_table_info_agg; Type: VIEW; Schema: hdb_catalog; Owner: doadmin
--

CREATE VIEW hdb_catalog.hdb_table_info_agg AS
 SELECT schema.nspname AS table_schema,
    "table".relname AS table_name,
    jsonb_build_object('oid', ("table".oid)::integer, 'columns', COALESCE(columns.info, '[]'::jsonb), 'primary_key', primary_key.info, 'unique_constraints', COALESCE(unique_constraints.info, '[]'::jsonb), 'foreign_keys', COALESCE(foreign_key_constraints.info, '[]'::jsonb), 'view_info',
        CASE "table".relkind
            WHEN 'v'::"char" THEN jsonb_build_object('is_updatable', ((pg_relation_is_updatable(("table".oid)::regclass, true) & 4) = 4), 'is_insertable', ((pg_relation_is_updatable(("table".oid)::regclass, true) & 8) = 8), 'is_deletable', ((pg_relation_is_updatable(("table".oid)::regclass, true) & 16) = 16))
            ELSE NULL::jsonb
        END, 'description', description.description) AS info
   FROM ((((((pg_class "table"
     JOIN pg_namespace schema ON ((schema.oid = "table".relnamespace)))
     LEFT JOIN pg_description description ON (((description.classoid = ('pg_class'::regclass)::oid) AND (description.objoid = "table".oid) AND (description.objsubid = 0))))
     LEFT JOIN LATERAL ( SELECT jsonb_agg(jsonb_build_object('name', "column".attname, 'position', "column".attnum, 'type', COALESCE(base_type.typname, type.typname), 'is_nullable', (NOT "column".attnotnull), 'description', col_description("table".oid, ("column".attnum)::integer))) AS info
           FROM ((pg_attribute "column"
             LEFT JOIN pg_type type ON ((type.oid = "column".atttypid)))
             LEFT JOIN pg_type base_type ON (((type.typtype = 'd'::"char") AND (base_type.oid = type.typbasetype))))
          WHERE (("column".attrelid = "table".oid) AND ("column".attnum > 0) AND (NOT "column".attisdropped))) columns ON (true))
     LEFT JOIN LATERAL ( SELECT jsonb_build_object('constraint', jsonb_build_object('name', class.relname, 'oid', (class.oid)::integer), 'columns', COALESCE(columns_1.info, '[]'::jsonb)) AS info
           FROM ((pg_index index
             JOIN pg_class class ON ((class.oid = index.indexrelid)))
             LEFT JOIN LATERAL ( SELECT jsonb_agg("column".attname) AS info
                   FROM pg_attribute "column"
                  WHERE (("column".attrelid = "table".oid) AND ("column".attnum = ANY ((index.indkey)::smallint[])))) columns_1 ON (true))
          WHERE ((index.indrelid = "table".oid) AND index.indisprimary)) primary_key ON (true))
     LEFT JOIN LATERAL ( SELECT jsonb_agg(jsonb_build_object('name', class.relname, 'oid', (class.oid)::integer)) AS info
           FROM (pg_index index
             JOIN pg_class class ON ((class.oid = index.indexrelid)))
          WHERE ((index.indrelid = "table".oid) AND index.indisunique AND (NOT index.indisprimary))) unique_constraints ON (true))
     LEFT JOIN LATERAL ( SELECT jsonb_agg(jsonb_build_object('constraint', jsonb_build_object('name', foreign_key.constraint_name, 'oid', foreign_key.constraint_oid), 'columns', foreign_key.columns, 'foreign_table', jsonb_build_object('schema', foreign_key.ref_table_table_schema, 'name', foreign_key.ref_table), 'foreign_columns', foreign_key.ref_columns)) AS info
           FROM hdb_catalog.hdb_foreign_key_constraint foreign_key
          WHERE ((foreign_key.table_schema = (schema.nspname)::text) AND (foreign_key.table_name = ("table".relname)::text))) foreign_key_constraints ON (true))
  WHERE ("table".relkind = ANY (ARRAY['r'::"char", 't'::"char", 'v'::"char", 'm'::"char", 'f'::"char", 'p'::"char"]));


ALTER TABLE hdb_catalog.hdb_table_info_agg OWNER TO doadmin;

--
-- Name: hdb_unique_constraint; Type: VIEW; Schema: hdb_catalog; Owner: doadmin
--

CREATE VIEW hdb_catalog.hdb_unique_constraint AS
 SELECT tc.table_name,
    tc.constraint_schema AS table_schema,
    tc.constraint_name,
    json_agg(kcu.column_name) AS columns
   FROM (information_schema.table_constraints tc
     JOIN information_schema.key_column_usage kcu USING (constraint_schema, constraint_name))
  WHERE ((tc.constraint_type)::text = 'UNIQUE'::text)
  GROUP BY tc.table_name, tc.constraint_schema, tc.constraint_name;


ALTER TABLE hdb_catalog.hdb_unique_constraint OWNER TO doadmin;

--
-- Name: hdb_version; Type: TABLE; Schema: hdb_catalog; Owner: doadmin
--

CREATE TABLE hdb_catalog.hdb_version (
    hasura_uuid uuid DEFAULT public.gen_random_uuid() NOT NULL,
    version text NOT NULL,
    upgraded_on timestamp with time zone NOT NULL,
    cli_state jsonb DEFAULT '{}'::jsonb NOT NULL,
    console_state jsonb DEFAULT '{}'::jsonb NOT NULL
);


ALTER TABLE hdb_catalog.hdb_version OWNER TO doadmin;

--
-- Name: remote_schemas; Type: TABLE; Schema: hdb_catalog; Owner: doadmin
--

CREATE TABLE hdb_catalog.remote_schemas (
    id bigint NOT NULL,
    name text,
    definition json,
    comment text
);


ALTER TABLE hdb_catalog.remote_schemas OWNER TO doadmin;

--
-- Name: remote_schemas_id_seq; Type: SEQUENCE; Schema: hdb_catalog; Owner: doadmin
--

CREATE SEQUENCE hdb_catalog.remote_schemas_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE hdb_catalog.remote_schemas_id_seq OWNER TO doadmin;

--
-- Name: remote_schemas_id_seq; Type: SEQUENCE OWNED BY; Schema: hdb_catalog; Owner: doadmin
--

ALTER SEQUENCE hdb_catalog.remote_schemas_id_seq OWNED BY hdb_catalog.remote_schemas.id;


--
-- Name: address; Type: TABLE; Schema: public; Owner: doadmin
--

CREATE TABLE public.address (
    id uuid NOT NULL,
    address_1 text NOT NULL,
    address_2 text,
    address_3 text,
    city text NOT NULL,
    state text NOT NULL,
    zip text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    country text,
    phone text,
    latitude text,
    longitude text,
    customer_id uuid
);


ALTER TABLE public.address OWNER TO doadmin;

--
-- Name: broadcast; Type: TABLE; Schema: public; Owner: doadmin
--

CREATE TABLE public.broadcast (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    broadcast_type text NOT NULL,
    sender_id uuid NOT NULL,
    delivery_timestamp timestamp with time zone,
    title text NOT NULL,
    message text NOT NULL,
    organization_id uuid,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE public.broadcast OWNER TO doadmin;

--
-- Name: broadcast_recipient; Type: TABLE; Schema: public; Owner: doadmin
--

CREATE TABLE public.broadcast_recipient (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    receiver_id uuid NOT NULL,
    delivery_status text NOT NULL,
    response_location_id uuid,
    response_remote_location text,
    broadcast_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE public.broadcast_recipient OWNER TO doadmin;

--
-- Name: customer; Type: TABLE; Schema: public; Owner: doadmin
--

CREATE TABLE public.customer (
    id uuid NOT NULL,
    name text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    address_id uuid
);


ALTER TABLE public.customer OWNER TO doadmin;

--
-- Name: customer_user; Type: TABLE; Schema: public; Owner: doadmin
--

CREATE TABLE public.customer_user (
    customer_id uuid NOT NULL,
    user_id uuid NOT NULL,
    is_owner boolean DEFAULT false NOT NULL
);


ALTER TABLE public.customer_user OWNER TO doadmin;

--
-- Name: department; Type: TABLE; Schema: public; Owner: doadmin
--

CREATE TABLE public.department (
    id uuid NOT NULL,
    name text NOT NULL,
    organization_id uuid NOT NULL,
    parent_id uuid,
    avatar_url text,
    color text,
    description text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    customer_id uuid,
    hierarchy_level integer
);


ALTER TABLE public.department OWNER TO doadmin;

--
-- Name: location; Type: TABLE; Schema: public; Owner: doadmin
--

CREATE TABLE public.location (
    id uuid NOT NULL,
    name text NOT NULL,
    organization_id uuid NOT NULL,
    address_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    avatar_url text,
    customer_id uuid,
    phone text
);


ALTER TABLE public.location OWNER TO doadmin;

--
-- Name: position; Type: TABLE; Schema: public; Owner: doadmin
--

CREATE TABLE public."position" (
    id uuid NOT NULL,
    title text NOT NULL,
    subtype text NOT NULL,
    description text,
    time_type text,
    status text DEFAULT 'filled'::text NOT NULL,
    profile_id uuid,
    organization_id uuid NOT NULL,
    department_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    parent_id uuid,
    hierarchy_level integer,
    customer_id uuid NOT NULL,
    position_number text,
    location_id uuid
);


ALTER TABLE public."position" OWNER TO doadmin;

--
-- Name: worker; Type: TABLE; Schema: public; Owner: doadmin
--

CREATE TABLE public.worker (
    id uuid NOT NULL,
    first_name text NOT NULL,
    last_name text NOT NULL,
    user_id uuid,
    email text NOT NULL,
    phone text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    status text DEFAULT 'active'::text,
    address_id uuid,
    location_id uuid,
    is_remote boolean DEFAULT false NOT NULL,
    gender text NOT NULL,
    avatar_url text,
    dob date,
    hire_date date,
    customer_id uuid,
    employee_number text,
    mobile text,
    mobile_country_code text,
    work_phone text,
    work_phone_country_code text,
    work_phone_extension text
);


ALTER TABLE public.worker OWNER TO doadmin;

--
-- Name: worker_position; Type: TABLE; Schema: public; Owner: doadmin
--

CREATE TABLE public.worker_position (
    position_id uuid NOT NULL,
    worker_id uuid NOT NULL,
    start_date timestamp with time zone DEFAULT now() NOT NULL,
    end_date timestamp with time zone,
    friendly_title text,
    customer_id uuid
);


ALTER TABLE public.worker_position OWNER TO doadmin;

--
-- Name: employee_manager; Type: VIEW; Schema: public; Owner: doadmin
--

CREATE VIEW public.employee_manager AS
 SELECT p.id,
    p.title,
    p.subtype,
    p.time_type,
    ((w.first_name || ' '::text) || w.last_name) AS employee,
    w.email,
    w.phone,
    w.avatar_url,
    d.name AS department,
    l.name AS facility,
    ((aw.city || ', '::text) || aw.state) AS work,
    ((ah.city || ', '::text) || ah.state) AS home,
    sq.manager_name
   FROM (((((((public."position" p
     JOIN public.worker_position wp ON ((p.id = wp.position_id)))
     JOIN public.worker w ON ((w.id = wp.worker_id)))
     JOIN public.department d ON ((p.department_id = d.id)))
     LEFT JOIN ( SELECT p1.id,
            ((w1.first_name || ' '::text) || w1.last_name) AS manager_name
           FROM ((public."position" p1
             LEFT JOIN public.worker_position wp1 ON ((p1.id = wp1.position_id)))
             LEFT JOIN public.worker w1 ON ((w1.id = wp1.worker_id)))) sq ON ((p.parent_id = sq.id)))
     LEFT JOIN public.location l ON ((w.location_id = l.id)))
     LEFT JOIN public.address aw ON ((aw.id = l.address_id)))
     LEFT JOIN public.address ah ON ((ah.id = w.address_id)))
  WHERE (wp.end_date IS NULL)
  ORDER BY w.last_name;


ALTER TABLE public.employee_manager OWNER TO doadmin;

--
-- Name: organization; Type: TABLE; Schema: public; Owner: doadmin
--

CREATE TABLE public.organization (
    id uuid NOT NULL,
    name text DEFAULT 'customer_id'::text NOT NULL,
    customer_id uuid NOT NULL,
    plan_type text,
    is_public boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    avatar_url text
);


ALTER TABLE public.organization OWNER TO doadmin;

--
-- Name: position_status; Type: TABLE; Schema: public; Owner: doadmin
--

CREATE TABLE public.position_status (
    value text NOT NULL
);


ALTER TABLE public.position_status OWNER TO doadmin;

--
-- Name: position_subtype; Type: TABLE; Schema: public; Owner: doadmin
--

CREATE TABLE public.position_subtype (
    value text NOT NULL
);


ALTER TABLE public.position_subtype OWNER TO doadmin;

--
-- Name: position_time_type; Type: TABLE; Schema: public; Owner: doadmin
--

CREATE TABLE public.position_time_type (
    value text NOT NULL
);


ALTER TABLE public.position_time_type OWNER TO doadmin;

--
-- Name: positionsancestors; Type: TABLE; Schema: public; Owner: doadmin
--

CREATE TABLE public.positionsancestors (
    position_id uuid NOT NULL,
    ancestor_id uuid NOT NULL
);


ALTER TABLE public.positionsancestors OWNER TO doadmin;

--
-- Name: profile; Type: TABLE; Schema: public; Owner: doadmin
--

CREATE TABLE public.profile (
    id uuid NOT NULL,
    name text NOT NULL,
    job_family text,
    compensation_grade text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    customer_id uuid
);


ALTER TABLE public.profile OWNER TO doadmin;

--
-- Name: user; Type: TABLE; Schema: public; Owner: doadmin
--

CREATE TABLE public."user" (
    id uuid NOT NULL,
    auth0_user_id text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    customer_id uuid
);


ALTER TABLE public."user" OWNER TO doadmin;

--
-- Name: worker_gender; Type: TABLE; Schema: public; Owner: doadmin
--

CREATE TABLE public.worker_gender (
    value text NOT NULL
);


ALTER TABLE public.worker_gender OWNER TO doadmin;

--
-- Name: remote_schemas id; Type: DEFAULT; Schema: hdb_catalog; Owner: doadmin
--

ALTER TABLE ONLY hdb_catalog.remote_schemas ALTER COLUMN id SET DEFAULT nextval('hdb_catalog.remote_schemas_id_seq'::regclass);


--
-- Data for Name: event_invocation_logs; Type: TABLE DATA; Schema: hdb_catalog; Owner: doadmin
--

COPY hdb_catalog.event_invocation_logs (id, event_id, status, request, response, created_at) FROM stdin;
\.


--
-- Data for Name: event_log; Type: TABLE DATA; Schema: hdb_catalog; Owner: doadmin
--

COPY hdb_catalog.event_log (id, schema_name, table_name, trigger_name, payload, delivered, error, tries, created_at, locked, next_retry_at, archived) FROM stdin;
\.


--
-- Data for Name: event_triggers; Type: TABLE DATA; Schema: hdb_catalog; Owner: doadmin
--

COPY hdb_catalog.event_triggers (name, type, schema_name, table_name, configuration, comment) FROM stdin;
\.


--
-- Data for Name: hdb_allowlist; Type: TABLE DATA; Schema: hdb_catalog; Owner: doadmin
--

COPY hdb_catalog.hdb_allowlist (collection_name) FROM stdin;
\.


--
-- Data for Name: hdb_computed_field; Type: TABLE DATA; Schema: hdb_catalog; Owner: doadmin
--

COPY hdb_catalog.hdb_computed_field (table_schema, table_name, computed_field_name, definition, comment) FROM stdin;
\.


--
-- Data for Name: hdb_function; Type: TABLE DATA; Schema: hdb_catalog; Owner: doadmin
--

COPY hdb_catalog.hdb_function (function_schema, function_name, configuration, is_system_defined) FROM stdin;
\.


--
-- Data for Name: hdb_permission; Type: TABLE DATA; Schema: hdb_catalog; Owner: doadmin
--

COPY hdb_catalog.hdb_permission (table_schema, table_name, role_name, perm_type, perm_def, comment, is_system_defined) FROM stdin;
\.


--
-- Data for Name: hdb_query_collection; Type: TABLE DATA; Schema: hdb_catalog; Owner: doadmin
--

COPY hdb_catalog.hdb_query_collection (collection_name, collection_defn, comment, is_system_defined) FROM stdin;
\.


--
-- Data for Name: hdb_relationship; Type: TABLE DATA; Schema: hdb_catalog; Owner: doadmin
--

COPY hdb_catalog.hdb_relationship (table_schema, table_name, rel_name, rel_type, rel_def, comment, is_system_defined) FROM stdin;
hdb_catalog	hdb_table	detail	object	{"manual_configuration": {"remote_table": {"name": "tables", "schema": "information_schema"}, "column_mapping": {"table_name": "table_name", "table_schema": "table_schema"}}}	\N	t
hdb_catalog	hdb_table	primary_key	object	{"manual_configuration": {"remote_table": {"name": "hdb_primary_key", "schema": "hdb_catalog"}, "column_mapping": {"table_name": "table_name", "table_schema": "table_schema"}}}	\N	t
hdb_catalog	hdb_table	columns	array	{"manual_configuration": {"remote_table": {"name": "columns", "schema": "information_schema"}, "column_mapping": {"table_name": "table_name", "table_schema": "table_schema"}}}	\N	t
hdb_catalog	hdb_table	foreign_key_constraints	array	{"manual_configuration": {"remote_table": {"name": "hdb_foreign_key_constraint", "schema": "hdb_catalog"}, "column_mapping": {"table_name": "table_name", "table_schema": "table_schema"}}}	\N	t
hdb_catalog	hdb_table	relationships	array	{"manual_configuration": {"remote_table": {"name": "hdb_relationship", "schema": "hdb_catalog"}, "column_mapping": {"table_name": "table_name", "table_schema": "table_schema"}}}	\N	t
hdb_catalog	hdb_table	permissions	array	{"manual_configuration": {"remote_table": {"name": "hdb_permission_agg", "schema": "hdb_catalog"}, "column_mapping": {"table_name": "table_name", "table_schema": "table_schema"}}}	\N	t
hdb_catalog	hdb_table	computed_fields	array	{"manual_configuration": {"remote_table": {"name": "hdb_computed_field", "schema": "hdb_catalog"}, "column_mapping": {"table_name": "table_name", "table_schema": "table_schema"}}}	\N	t
hdb_catalog	hdb_table	check_constraints	array	{"manual_configuration": {"remote_table": {"name": "hdb_check_constraint", "schema": "hdb_catalog"}, "column_mapping": {"table_name": "table_name", "table_schema": "table_schema"}}}	\N	t
hdb_catalog	hdb_table	unique_constraints	array	{"manual_configuration": {"remote_table": {"name": "hdb_unique_constraint", "schema": "hdb_catalog"}, "column_mapping": {"table_name": "table_name", "table_schema": "table_schema"}}}	\N	t
hdb_catalog	event_triggers	events	array	{"manual_configuration": {"remote_table": {"name": "event_log", "schema": "hdb_catalog"}, "column_mapping": {"name": "trigger_name"}}}	\N	t
hdb_catalog	event_log	trigger	object	{"manual_configuration": {"remote_table": {"name": "event_triggers", "schema": "hdb_catalog"}, "column_mapping": {"trigger_name": "name"}}}	\N	t
hdb_catalog	event_log	logs	array	{"foreign_key_constraint_on": {"table": {"name": "event_invocation_logs", "schema": "hdb_catalog"}, "column": "event_id"}}	\N	t
hdb_catalog	event_invocation_logs	event	object	{"foreign_key_constraint_on": "event_id"}	\N	t
hdb_catalog	hdb_function_agg	return_table_info	object	{"manual_configuration": {"remote_table": {"name": "hdb_table", "schema": "hdb_catalog"}, "column_mapping": {"return_type_name": "table_name", "return_type_schema": "table_schema"}}}	\N	t
public	address	locations	array	{"foreign_key_constraint_on": {"table": {"name": "location", "schema": "public"}, "column": "address_id"}}	\N	f
public	customer	customer_users	array	{"foreign_key_constraint_on": {"table": {"name": "customer_user", "schema": "public"}, "column": "customer_id"}}	\N	f
public	customer	organizations	array	{"foreign_key_constraint_on": {"table": {"name": "organization", "schema": "public"}, "column": "customer_id"}}	\N	f
public	customer_user	customer	object	{"foreign_key_constraint_on": "customer_id"}	\N	f
public	customer_user	user	object	{"foreign_key_constraint_on": "user_id"}	\N	f
public	department	department	object	{"foreign_key_constraint_on": "parent_id"}	\N	f
public	department	organization	object	{"foreign_key_constraint_on": "organization_id"}	\N	f
public	department	departments	array	{"foreign_key_constraint_on": {"table": {"name": "department", "schema": "public"}, "column": "parent_id"}}	\N	f
public	department	positions	array	{"foreign_key_constraint_on": {"table": {"name": "position", "schema": "public"}, "column": "department_id"}}	\N	f
public	location	address	object	{"foreign_key_constraint_on": "address_id"}	\N	f
public	location	organization	object	{"foreign_key_constraint_on": "organization_id"}	\N	f
public	location	workers	array	{"foreign_key_constraint_on": {"table": {"name": "worker", "schema": "public"}, "column": "location_id"}}	\N	f
public	location	positions	array	{"foreign_key_constraint_on": {"table": {"name": "position", "schema": "public"}, "column": "location_id"}}	\N	f
public	organization	customer	object	{"foreign_key_constraint_on": "customer_id"}	\N	f
public	organization	departments	array	{"foreign_key_constraint_on": {"table": {"name": "department", "schema": "public"}, "column": "organization_id"}}	\N	f
public	organization	locations	array	{"foreign_key_constraint_on": {"table": {"name": "location", "schema": "public"}, "column": "organization_id"}}	\N	f
public	organization	positions	array	{"foreign_key_constraint_on": {"table": {"name": "position", "schema": "public"}, "column": "organization_id"}}	\N	f
public	position	department	object	{"foreign_key_constraint_on": "department_id"}	\N	f
public	position	location	object	{"foreign_key_constraint_on": "location_id"}	\N	f
public	position	organization	object	{"foreign_key_constraint_on": "organization_id"}	\N	f
public	position	position	object	{"foreign_key_constraint_on": "parent_id"}	\N	f
public	position	position_status	object	{"foreign_key_constraint_on": "status"}	\N	f
public	position	position_subtype	object	{"foreign_key_constraint_on": "subtype"}	\N	f
public	position	position_time_type	object	{"foreign_key_constraint_on": "time_type"}	\N	f
public	position	profile	object	{"foreign_key_constraint_on": "profile_id"}	\N	f
public	position	positions	array	{"foreign_key_constraint_on": {"table": {"name": "position", "schema": "public"}, "column": "parent_id"}}	\N	f
public	position	worker_positions	array	{"foreign_key_constraint_on": {"table": {"name": "worker_position", "schema": "public"}, "column": "position_id"}}	\N	f
public	position	positionsancestors	array	{"foreign_key_constraint_on": {"table": {"name": "positionsancestors", "schema": "public"}, "column": "position_id"}}	\N	f
public	position	positionsancestorsByAncestorId	array	{"foreign_key_constraint_on": {"table": {"name": "positionsancestors", "schema": "public"}, "column": "ancestor_id"}}	\N	f
public	positionsancestors	position	object	{"foreign_key_constraint_on": "position_id"}	\N	f
public	positionsancestors	positionByAncestorId	object	{"foreign_key_constraint_on": "ancestor_id"}	\N	f
public	position_status	positions	array	{"foreign_key_constraint_on": {"table": {"name": "position", "schema": "public"}, "column": "status"}}	\N	f
public	position_subtype	positions	array	{"foreign_key_constraint_on": {"table": {"name": "position", "schema": "public"}, "column": "subtype"}}	\N	f
public	position_time_type	positions	array	{"foreign_key_constraint_on": {"table": {"name": "position", "schema": "public"}, "column": "time_type"}}	\N	f
public	profile	positions	array	{"foreign_key_constraint_on": {"table": {"name": "position", "schema": "public"}, "column": "profile_id"}}	\N	f
public	user	customer_users	array	{"foreign_key_constraint_on": {"table": {"name": "customer_user", "schema": "public"}, "column": "user_id"}}	\N	f
public	user	workers	array	{"foreign_key_constraint_on": {"table": {"name": "worker", "schema": "public"}, "column": "user_id"}}	\N	f
public	worker	location	object	{"foreign_key_constraint_on": "location_id"}	\N	f
public	worker	user	object	{"foreign_key_constraint_on": "user_id"}	\N	f
public	worker	worker_gender	object	{"foreign_key_constraint_on": "gender"}	\N	f
public	worker	worker_positions	array	{"foreign_key_constraint_on": {"table": {"name": "worker_position", "schema": "public"}, "column": "worker_id"}}	\N	f
public	worker_gender	workers	array	{"foreign_key_constraint_on": {"table": {"name": "worker", "schema": "public"}, "column": "gender"}}	\N	f
public	worker_position	position	object	{"foreign_key_constraint_on": "position_id"}	\N	f
public	worker_position	worker	object	{"foreign_key_constraint_on": "worker_id"}	\N	f
\.


--
-- Data for Name: hdb_schema_update_event; Type: TABLE DATA; Schema: hdb_catalog; Owner: doadmin
--

COPY hdb_catalog.hdb_schema_update_event (instance_id, occurred_at, invalidations) FROM stdin;
15c7ed4c-1d85-442c-8b26-84c77bdf6fd4	2020-04-02 23:54:22.083084+00	{"metadata":false,"remote_schemas":[]}
\.


--
-- Data for Name: hdb_table; Type: TABLE DATA; Schema: hdb_catalog; Owner: doadmin
--

COPY hdb_catalog.hdb_table (table_schema, table_name, configuration, is_system_defined, is_enum) FROM stdin;
information_schema	tables	{"custom_root_fields": {}, "custom_column_names": {}}	t	f
information_schema	schemata	{"custom_root_fields": {}, "custom_column_names": {}}	t	f
information_schema	views	{"custom_root_fields": {}, "custom_column_names": {}}	t	f
information_schema	columns	{"custom_root_fields": {}, "custom_column_names": {}}	t	f
hdb_catalog	hdb_table	{"custom_root_fields": {}, "custom_column_names": {}}	t	f
hdb_catalog	hdb_primary_key	{"custom_root_fields": {}, "custom_column_names": {}}	t	f
hdb_catalog	hdb_foreign_key_constraint	{"custom_root_fields": {}, "custom_column_names": {}}	t	f
hdb_catalog	hdb_relationship	{"custom_root_fields": {}, "custom_column_names": {}}	t	f
hdb_catalog	hdb_permission_agg	{"custom_root_fields": {}, "custom_column_names": {}}	t	f
hdb_catalog	hdb_computed_field	{"custom_root_fields": {}, "custom_column_names": {}}	t	f
hdb_catalog	hdb_check_constraint	{"custom_root_fields": {}, "custom_column_names": {}}	t	f
hdb_catalog	hdb_unique_constraint	{"custom_root_fields": {}, "custom_column_names": {}}	t	f
hdb_catalog	event_triggers	{"custom_root_fields": {}, "custom_column_names": {}}	t	f
hdb_catalog	event_log	{"custom_root_fields": {}, "custom_column_names": {}}	t	f
hdb_catalog	event_invocation_logs	{"custom_root_fields": {}, "custom_column_names": {}}	t	f
hdb_catalog	hdb_function	{"custom_root_fields": {}, "custom_column_names": {}}	t	f
hdb_catalog	hdb_function_agg	{"custom_root_fields": {}, "custom_column_names": {}}	t	f
hdb_catalog	remote_schemas	{"custom_root_fields": {}, "custom_column_names": {}}	t	f
hdb_catalog	hdb_version	{"custom_root_fields": {}, "custom_column_names": {}}	t	f
hdb_catalog	hdb_query_collection	{"custom_root_fields": {}, "custom_column_names": {}}	t	f
hdb_catalog	hdb_allowlist	{"custom_root_fields": {}, "custom_column_names": {}}	t	f
public	address	{"custom_root_fields": {}, "custom_column_names": {}}	f	f
public	customer	{"custom_root_fields": {}, "custom_column_names": {}}	f	f
public	customer_user	{"custom_root_fields": {}, "custom_column_names": {}}	f	f
public	department	{"custom_root_fields": {}, "custom_column_names": {}}	f	f
public	employee_manager	{"custom_root_fields": {}, "custom_column_names": {}}	f	f
public	location	{"custom_root_fields": {}, "custom_column_names": {}}	f	f
public	organization	{"custom_root_fields": {}, "custom_column_names": {}}	f	f
public	position	{"custom_root_fields": {}, "custom_column_names": {}}	f	f
public	positionsancestors	{"custom_root_fields": {}, "custom_column_names": {}}	f	f
public	position_status	{"custom_root_fields": {}, "custom_column_names": {}}	f	f
public	position_subtype	{"custom_root_fields": {}, "custom_column_names": {}}	f	f
public	position_time_type	{"custom_root_fields": {}, "custom_column_names": {}}	f	f
public	profile	{"custom_root_fields": {}, "custom_column_names": {}}	f	f
public	user	{"custom_root_fields": {}, "custom_column_names": {}}	f	f
public	worker	{"custom_root_fields": {}, "custom_column_names": {}}	f	f
public	worker_gender	{"custom_root_fields": {}, "custom_column_names": {}}	f	f
public	worker_position	{"custom_root_fields": {}, "custom_column_names": {}}	f	f
\.


--
-- Data for Name: hdb_version; Type: TABLE DATA; Schema: hdb_catalog; Owner: doadmin
--

COPY hdb_catalog.hdb_version (hasura_uuid, version, upgraded_on, cli_state, console_state) FROM stdin;
6dea2f36-ece7-4412-a6ed-7a6c16f2a41d	31	2020-04-02 23:52:12.308068+00	{}	{"telemetryNotificationShown": true}
\.


--
-- Data for Name: remote_schemas; Type: TABLE DATA; Schema: hdb_catalog; Owner: doadmin
--

COPY hdb_catalog.remote_schemas (id, name, definition, comment) FROM stdin;
\.


--
-- Data for Name: address; Type: TABLE DATA; Schema: public; Owner: doadmin
--

COPY public.address (id, address_1, address_2, address_3, city, state, zip, created_at, updated_at, country, phone, latitude, longitude, customer_id) FROM stdin;
513bc68f-d3c0-4f33-b231-02eb37aa9cfd	1915 N Avenida Republica de Cuba	Suite 200	\N	Tampa	FL	33605	2020-01-15 22:11:14.358068+00	2020-03-05 18:46:05.930124+00	United States	8004452673	27.961189	-82.444141	f304e1bd-4ea5-496a-9644-76c2eb9e7483
d5e8f89d-b9ef-4a1e-aff9-e7d3f31c7fe8	300 W 6th St	#1800	\N	Austin	TX	78701	2020-01-15 22:23:52.102593+00	2020-03-05 18:46:05.930124+00	United States	5122226400	30.269100	-97.745667	f304e1bd-4ea5-496a-9644-76c2eb9e7483
69fd7e44-7483-44fe-8ca0-e9307adb4779	100 Cambridge St	10th Floor	\N	Boston	MA	02114	2020-01-15 22:29:32.3982+00	2020-03-05 18:46:05.930124+00	United States	8572927780	42.360981	-71.062624	f304e1bd-4ea5-496a-9644-76c2eb9e7483
bf261892-2541-4cca-8b9b-0c107929c021	3554 NW 21st St	\N	\N	Miami	FL	33142	2020-01-15 22:30:52.678275+00	2020-03-05 18:46:05.930124+00	United States	3058835600	25.794990	-80.255292	f304e1bd-4ea5-496a-9644-76c2eb9e7483
5d8ba8f1-1576-4cfc-84b8-f05e12553e7b	2411 Kiesel Ave	\N	\N	Ogden	UT	84401	2020-01-15 22:33:31.893078+00	2020-03-05 18:46:05.930124+00	United States	8013333700	41.222466	-111.971968	f304e1bd-4ea5-496a-9644-76c2eb9e7483
4bff9e7e-7fa4-497b-b09e-be1fc3740172	1150 S Depot Drive	Suite 280	\N	Ogden	UT	84404	2020-03-05 18:49:08.244075+00	2020-03-05 18:50:14.949982+00	United States	5124260838	41.2448426	-111.9958673	c1b769c8-dc45-4662-a408-de09ce621202
07b314e8-1805-4f16-8ea2-87b32a7e9b8e	8201 164th Ave NE	#200	\N	Redmond	WA	98052	2020-03-05 18:46:05.930124+00	2020-03-05 18:51:07.537636+00	United States	4255914924	47.6764698	-122.1240705	c1b769c8-dc45-4662-a408-de09ce621202
34dc694f-c485-47fb-9560-3c1489f99683	88 Wood Street	\N	\N	London	Greater London	EC2V 7RS	2020-04-06 16:36:02.624741+00	2020-04-06 16:36:02.624741+00	UK	2076060606	51.5167802	-0.0948991	f304e1bd-4ea5-496a-9644-76c2eb9e7483
1b8ac3e7-cca1-43fb-915d-b485bab15e4c	235 Maple Wood Plaza	\N	\N	Tottenham	London	N17 0BU	2020-04-06 16:41:47.514832+00	2020-04-06 16:44:57.744488+00	UK	\N	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
a31d20e7-a68e-4e38-bc3f-eff77ae53d92	606 Nelson Trail	\N	\N	East Dulwich	London	SE22 8DX	2020-04-06 16:47:30.791778+00	2020-04-06 16:47:30.791778+00	UK	\N	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
7a63e871-fa74-4e13-b2ed-700763bb148b	73 Homdene Ave	\N	\N	Dulwich	London	SE24 9LD	2020-04-06 16:47:30.791778+00	2020-04-06 16:47:30.791778+00	UK	\N	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
803730a8-ce18-4345-9145-ad8b9d515a70	37 Elfindale Rd	\N	\N	Herne Hill	London	SE24 9NN	2020-04-06 16:47:30.791778+00	2020-04-06 16:47:30.791778+00	UK	\N	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
e9fed9a4-f9ea-4a34-aca0-5aed767ac6da	39A Chaucer Rd	\N	\N	Brixton	London	SE24 0NY	2020-04-06 16:47:30.791778+00	2020-04-06 16:47:30.791778+00	UK	\N	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
d8ef0def-e67e-4636-b38a-6139f4926c53	39 Spense Rd	\N	\N	Briston	London	SE24 0NS	2020-04-06 16:47:30.791778+00	2020-04-06 16:47:30.791778+00	UK	\N	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
43a4e4a6-f7ce-4b9c-988f-8c3f9c2a0ccf	16 Biddestone Rd	\N	\N	London	Greater London	N7 9UD	2020-04-06 16:47:30.791778+00	2020-04-06 16:47:30.791778+00	UK	\N	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
0c6f272d-05f6-4238-be5d-9e964e22d581	87A Tabley Rd	\N	\N	London	Greater London	N7 0NB	2020-04-06 16:47:30.791778+00	2020-04-06 16:47:30.791778+00	UK	\N	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
9aca07ba-4e40-4e13-909a-7755fa4946a4	106A St George Ave	\N	\N	London	Greater London	N7 0AH	2020-04-06 16:47:30.791778+00	2020-04-06 16:47:30.791778+00	UK	\N	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
57390a98-a797-4973-975c-ddf7db613b0f	1A Mayfield Rd	\N	\N	London	Greater London	N8 9LL	2020-04-06 16:47:30.791778+00	2020-04-06 16:47:30.791778+00	UK	\N	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
32eaa2af-35b8-44cf-93a7-72d653047374	144 Wynchgate	\N	\N	London	Greater London	N21 1QU	2020-04-06 16:47:30.791778+00	2020-04-06 16:47:30.791778+00	UK	\N	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
5ab7c28b-89ff-492e-853f-5789aa1bda50	10 St Mary Grove	\N	\N	London	Greater London	N1 2NT	2020-04-06 16:47:30.791778+00	2020-04-06 16:47:30.791778+00	UK	\N	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
e74f268f-d742-439f-923f-a62781e08eb6	41A Parkholme Rd	\N	\N	Dalston	London	E8 3AG	2020-04-06 16:47:30.791778+00	2020-04-06 16:47:30.791778+00	UK	\N	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
ab24f0bc-b652-4618-bf2b-359929ecc3fc	22 Greenwood Rd	\N	\N	Hackney	London	E8 1AB	2020-04-06 16:47:30.791778+00	2020-04-06 16:47:30.791778+00	UK	\N	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
334f2b9c-0078-407e-8875-2294692e173f	18 Ormeley Rd	\N	\N	Balham	London	SW12 9QE	2020-04-06 16:47:30.791778+00	2020-04-06 16:47:30.791778+00	UK	\N	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
a7e42956-163f-497c-af11-0f0417b9ac72	59 Laitwood Rd	\N	\N	Balham	London	SW12 9QJ	2020-04-06 16:47:30.791778+00	2020-04-06 16:47:30.791778+00	UK	\N	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
8682628f-5b51-4384-aa44-42132f3fbca4	46 Pentney Rd	\N	\N	Thornton	London	SW12 0NX	2020-04-06 16:47:30.791778+00	2020-04-06 16:47:30.791778+00	UK	\N	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
5884f9c3-20ee-44ec-9c09-766c9592d469	4A Glenfield Rd	\N	\N	Thornton	London	SW12 0HG	2020-04-06 16:47:30.791778+00	2020-04-06 16:47:30.791778+00	UK	\N	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
d8694069-d30e-4e17-b485-de5d4640850f	76A Culverden Rd	\N	\N	London	Greater London	SW12 9LS	2020-04-06 16:47:30.791778+00	2020-04-06 16:47:30.791778+00	UK	\N	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
c89fa3cf-27a0-4cb9-a0c1-a7c69b24395a	54 Mitcham Ln	\N	\N	Streatham	London	SW16 6NP	2020-04-06 16:47:30.791778+00	2020-04-06 16:47:30.791778+00	UK	\N	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
230cde42-7da3-461f-8af2-90e7c8309ebb	45 Westcote Rd	\N	\N	London	Greater London	SW16 6BW	2020-04-06 16:47:30.791778+00	2020-04-06 16:47:30.791778+00	UK	\N	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
33a2c51c-53de-4130-859f-12f4f051f9ee	194 Southcroft Rd	\N	\N	London	Greater London	SW17 9TW	2020-04-06 16:47:30.791778+00	2020-04-06 16:47:30.791778+00	UK	\N	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
7dd3db57-6eda-47c0-a8dc-c31170a6f1d6	137 Fountain Rd	\N	\N	London	Greater London	SW17 0HH	2020-04-06 16:47:30.791778+00	2020-04-06 16:47:30.791778+00	UK	\N	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
fb27daef-e8ee-4a4e-adae-9d77abce64f6	24 Dudley Rd	\N	\N	Kew	Richmond	TW9 2EH	2020-04-06 16:47:30.791778+00	2020-04-06 16:47:30.791778+00	UK	\N	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
10bf2d93-ab90-44e0-96c8-0f34e8501095	73 Alexandra Rd	\N	\N	Kew	Richmond	TW9 2BT	2020-04-06 16:47:30.791778+00	2020-04-06 16:47:30.791778+00	UK	\N	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
44dfdfc7-7ef7-4098-b283-51cbbec34694	71A Townholm Cres	\N	\N	Hanwell	London	W7 2LZ	2020-04-06 16:47:30.791778+00	2020-04-06 16:47:30.791778+00	UK	\N	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
399fa495-cbfe-43b1-bab8-c3177a69ce15	1016 Country Mill Dr	\N	\N	Kaysville	UT	84037	2020-03-09 19:17:35.002606+00	2020-03-09 19:17:35.002606+00	United States	5124260838	41.0181765	-111.948802	c1b769c8-dc45-4662-a408-de09ce621202
f2bbaf89-a0ee-4879-918d-ff049ced4661	4886 Eastlawn Place	\N	\N	Seattle	WA	98105	2020-01-17 18:44:44.004154+00	2020-02-24 14:29:34.72023+00	United States	4259127090	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
688b9130-56a4-4be3-a11f-112a61839858	3259 Katie Plaza	\N	\N	Issaquah	WA	98027	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	4259060203	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
3b6fe441-b224-40bc-b595-0396cf2c4568	2865 8th Crossing	\N	\N	Kirkland	WA	98034	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	4259850525	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
a4482a1c-1936-45e1-a7bb-f6939dce2312	305 Raven Point	\N	\N	Medina	WA	98039	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	4258648881	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
3412e88c-547d-4beb-a348-06c4703c20db	1426 Elgar Court	\N	\N	Mercer Island	WA	98040	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	4259723911	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
2644803f-663b-4279-9d63-b170af15a4d7	10039 Ridgeview Hill	\N	\N	Redmond	WA	98052	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	4258064277	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
510fb161-cf02-4012-a348-0d6f45f52114	14828 Moose Terrace	\N	\N	Tacoma	WA	98403	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	4259336523	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
de6ec9bd-87b6-4aed-8855-9fc0494a4ef9	10160 Brentwood Street	\N	\N	Bellevue	WA	98004	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	4259360967	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
c22f2878-8f7e-4af8-aa57-18d54abbd4f7	12658 Fisk Road	\N	\N	Bothell	WA	98021	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	4258100800	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
5608148b-81da-4a3a-9919-cacc61a66196	9035 Forster Lane	\N	\N	Seattle	WA	98105	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	4257480955	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
d3920777-9e8b-4cc4-9ae7-2491a16a073c	6637 Twin Pines Center	\N	\N	Issaquah	WA	98027	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	4258031843	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
e55d2744-268a-44db-8516-01f3b0fa6c6f	6520 Washington Hill	\N	\N	Kirkland	WA	98034	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	4258619281	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
c1490d63-1d8b-47e6-8b48-cd55c942c7a9	13783 Rockefeller Hill	\N	\N	Medina	WA	98039	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	4259841953	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
3a2fa755-9ae7-431b-a01c-37ff86d3b264	9522 Roth Place	\N	\N	Mercer Island	WA	98040	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	4259677101	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
dc4464e5-7969-491c-b2ec-bd78476d9fc8	8062 Truax Hill	\N	\N	Redmond	WA	98052	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	4258670494	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
ee98b6a9-bce6-4a16-8fb1-e4ce729d125e	8362 Johnson Alley	\N	\N	Tacoma	WA	98403	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	4257639789	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
133825fa-5860-429e-9575-d2709e0fe999	1617 Pleasure Avenue	\N	\N	Bellevue	WA	98004	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	4259462973	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
dfad3860-11af-4c13-8a9b-8f49bf4b8ec5	7272 Hoffman Court	\N	\N	Bothell	WA	98021	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	4259402320	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
76c0aac5-b596-4c70-9759-7080a0df1de2	9627 Pennsylvania Avenue	\N	\N	Seattle	WA	98105	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	4258293194	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
4027fc5e-7af3-4db3-af8a-7f2fdbb46033	3957 Almo Pass	\N	\N	Issaquah	WA	98027	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	4258205410	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
b98e0c25-a54f-44c3-a413-365eb2721cca	14011 Ronald Regan Way	\N	\N	Kirkland	WA	98034	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	4259464830	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
10f89f7f-5ef6-4ef2-a025-307b244d2f86	9967 Stephen Lane	\N	\N	Medina	WA	98039	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	4259610165	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
a5fed248-9a7a-4ac9-878b-fd462cac3d7b	4207 Magdeline Pass	\N	\N	Mercer Island	WA	98040	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	4258666748	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
41f013e6-ee6b-44e1-ac08-216b3f3e73f6	11787 Onsgard Lane	\N	\N	Redmond	WA	98052	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	4259548477	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
3e5b82f5-de08-4efd-a002-e26c23892f5d	10775 Hauk Hill	\N	\N	Ogden	UT	84405	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8018822253	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
d8da0788-4397-405e-b36f-255a2dfc822a	13769 Red Cloud Alley	\N	\N	Tacoma	WA	98403	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	4259086710	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
826a2c15-efd5-47c8-835f-95691134f93f	8853 Laurel Road	\N	\N	Bellevue	WA	98004	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	4259813820	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
299803f3-6d8b-47d1-9955-26e904e42e7a	1275 Gerald Court	\N	\N	Bothell	WA	98021	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	4258682482	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
926d872f-e7a3-4246-88fe-c691d7c41fc3	8959 Laurel Street	\N	\N	Redmond	WA	98052	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	4257903521	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
d110e7df-9b21-41af-9053-7fc4b9a0bca5	4437 Kinsman Lane	\N	\N	Redmond	WA	98052	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	4257725527	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
35487025-e7c1-4514-b449-1a69e96a9d4c	4892 Dakota Terrace	\N	\N	Seminole	FL	33775	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8139484313	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
1edbaf02-f94c-4e13-b858-241f1531e0df	7215 Sloan Parkway	\N	\N	Largo	FL	33778	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8138577380	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
5bc57413-461a-4c90-be4e-c30642c7e7a4	11741 Pleasure Pass	\N	\N	Brandon	FL	33508	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8139065161	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
5c0e2485-af8a-40d1-ad66-137dc73d5836	10774 Cordelia Way	\N	\N	Brandon	FL	33511	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8138316583	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
eec1bbcf-502e-4873-a4d2-cd3167d22706	10404 Blue Bill Park Hill	\N	\N	Tampa	FL	33626	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8139161506	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
992165cf-6e20-4e9c-bc3c-984f6a7131a7	443 Clove Plaza	\N	\N	Oldsmar	FL	34677	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8139176481	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
8134c85c-9aaa-4ef4-8abb-47330ab259df	596 Eagle Crest Center	\N	\N	Clearwater	FL	33763	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8137435048	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
812b06e2-1dbb-4677-906b-871440254f7b	3213 Armistice Way	\N	\N	Tarpon Springs	FL	34688	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8138897162	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
bf2bdda9-dceb-4875-abdb-eb1f4d7d188f	11859 Village Alley	\N	\N	Palm Harbor	FL	34684	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8138115797	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
5cd95fae-09b6-44f8-9bba-23f446db1730	9485 Corscot Drive	\N	\N	Seminole	FL	33775	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8137706990	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
aba905b9-27b2-4f8a-9d8b-9cf0e32c636f	3188 Rieder Alley	\N	\N	Largo	FL	33778	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8138811135	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
0dc6d07c-f78a-4f16-a136-c31bc05b0bfc	12630 Ohio Point	\N	\N	Brandon	FL	33508	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8137987843	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
461f2d14-a7b2-401e-bc85-991b0619edb9	8841 Farragut Crossing	\N	\N	Brandon	FL	33511	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8138618499	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
5451c54e-e403-4144-b206-0b794fb033fb	8673 Steensland Way	\N	\N	Tampa	FL	33626	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8138209953	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
7f35a7d9-b5df-4684-ada6-06c2e3b2fd85	8980 Nancy Lane	\N	\N	Oldsmar	FL	34677	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8139668868	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
4d9a64a9-61b3-4077-a33e-0c819f1cd017	8559 Emmet Center	\N	\N	Clearwater	FL	33763	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8137581740	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
da43a02e-4d74-412e-a6b6-0ba874117172	5722 Armistice Point	\N	\N	Tarpon Springs	FL	34688	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8138662283	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
426c706c-2c2d-4859-b527-eda4dcc83850	8488 Brickson Park Park	\N	\N	Palm Harbor	FL	34684	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8138080288	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
28a4f89b-4c17-43bb-9854-476a1f2c8af1	4081 Fair Oaks Alley	\N	\N	Tampa	FL	33626	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8139430416	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
0e5e8866-0ee2-4e5e-889a-bb75cfa3067a	5886 1st Center	\N	\N	Atlanta	GA	30327	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	6788798080	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
3a93d0fd-6924-4ee9-a313-92a33302383f	1608 Loftsgordon Center	\N	\N	Austin	TX	78701	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	5127834936	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
803d7758-b1e5-42eb-8680-807cb48be90a	5283 Gina Pass	\N	\N	Austin	TX	78704	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	5127630446	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
7fdcd965-4c43-4ddc-8d1f-72e877b6e3e6	4441 Columbus Parkway	\N	\N	Cedar Creek	TX	78612	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	5127926861	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
b3553b10-13e8-472c-af63-f63e91da17d6	14130 Karstens Road	\N	\N	Kyle	TX	78640	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	5128376775	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
bb07d671-5158-45a3-ad8a-4a31c4b8ba0d	1443 Bultman Alley	\N	\N	Driftwood	TX	78619	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	5129635683	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
3fb54d6e-463e-419b-9e12-38a08b30d21d	4012 Troy Alley	\N	\N	Buda	TX	78610	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	5128372496	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
50987a02-9ae6-4d9a-9940-3f74336f2d56	8219 Redwing Crossing	\N	\N	Cedar Park	TX	78613	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	5128915337	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
85732ef9-4afa-4dd0-96c4-0abb8cbe97d7	1200 Steensland Junction	\N	\N	Austin	TX	78701	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	5128767485	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
cf96dc33-559b-434a-bc83-e5632b14a849	10196 Schlimgen Pass	\N	\N	Austin	TX	78704	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	5128940045	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
ead0776d-8efa-45f0-9fbe-be3551318f11	133 Butterfield Crossing	\N	\N	Cedar Creek	TX	78612	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	5127589109	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
37f12911-f6ee-4cc2-b4b4-f863a3168c7d	9008 John Wall Crossing	\N	\N	Kyle	TX	78640	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	5129467147	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
605ac88b-99eb-44a9-b7a1-6619f874354a	13895 Huxley Street	\N	\N	Baltimore	MD	21223	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	4107767821	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
c957bd08-6a14-4985-afdc-367da67aa3e0	11911 Bonner Way	\N	\N	Boston	MA	02112	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8578617612	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
91d3c298-256c-4c55-b444-e568fafc1a2c	11878 Sutherland Street	\N	\N	Belmont	MA	02478	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8578256195	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
931da550-248f-4fdd-bcb1-3331ae7e10d6	6717 Porter Crossing	\N	\N	Cambridge	MA	02140	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8578488397	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
6d781d71-c82d-4e5d-9742-51ea26fdfd79	5213 Logan Pass	\N	\N	Canton	MA	02021	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8579760616	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
93d90de3-906b-421e-9066-5a4895a71cf9	5515 Nelson Hill	\N	\N	Arlington	MA	02476	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8579762742	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
5a31ed63-7f88-40d6-b8a9-8073bb11adee	7205 Londonderry Parkway	\N	\N	Boston	MA	02112	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8579671773	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
a906d85c-b357-4cac-bada-c017e5fb62c8	7809 Carberry Lane	\N	\N	Belmont	MA	02478	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8579130084	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
9cd961f0-9cd6-4e53-ac09-0608678089ec	5772 Ridge Oak Alley	\N	\N	Cambridge	MA	02140	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8579354302	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
99a5c52f-fd4f-43c9-a353-c56983d4d118	5025 Autumn Leaf Circle	\N	\N	Canton	MA	02021	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8578049491	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
48ef2cb8-dba7-4c2e-ab1d-ee9a38baf668	8048 Barby Center	\N	\N	Arlington	MA	02476	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8577342920	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
c9a57608-3e15-44ec-b178-0753017145b7	3456 Vernon Circle	\N	\N	Boston	MA	02112	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8577944800	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
6117ec8c-0619-445d-a5a8-d785e0d9f105	14625 Meadow Ridge Court	\N	\N	Boston	MA	02112	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8577443274	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
a2c2d8ba-a04e-4531-a36d-f9d70a561ba4	1920 Nova Way	\N	\N	Boston	MA	02112	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8577583251	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
4c5f78f2-ad54-4d2b-b9e6-ea94884649f0	3374 Mallory Street	\N	\N	Boston	MA	02112	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8578027913	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
3d89ca62-8300-417f-ab36-9047a78097e5	7712 Eagan Place	\N	\N	Chicago	IL	60614	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	3128771188	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
eeb3e3a1-726c-4aa3-b9e9-c9022b8de7d0	639 Calypso Lane	\N	\N	Dallas	TX	75214	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	2147677727	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
40cd9aa8-73dd-4874-a139-b6bc34ce0cd7	5099 Valley Edge Alley	\N	\N	Delray Beach	FL	33483	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	3059467924	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
5976274d-329d-4870-ab01-5f7a69f8a069	11069 Crest Line Drive	\N	\N	Boca Raton	FL	33487	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	3059673232	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
770b4116-4b6b-4174-b050-145af2dedac6	5584 Hanover Circle	\N	\N	Fort Lauderdale	FL	33303	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	3058097455	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
dcaed78f-cd72-474d-931d-123984733fd9	9271 Sunbrook Hill	\N	\N	Pompano Beach	FL	33093	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	3059086730	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
d9ea79ac-4f3e-4dd9-a48d-df7a166976b4	10589 Ronald Regan Court	\N	\N	Miami Beach	FL	33119	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	3058430121	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
ffcaac2f-5e34-4a41-a117-ba6412e2f6ae	10381 5th Terrace	\N	\N	Opa Locka	FL	33055	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	3059539749	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
067548c6-4d52-45ce-8b4f-6b184fed060b	6849 Cody Circle	\N	\N	Miami	FL	33124	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	3059189799	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
b94ba442-ca4c-4bbb-b9bb-c5ba0f5c4a39	2271 Meadow Valley Crossing	\N	\N	Delray Beach	FL	33483	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	3059618058	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
3fffba8b-e322-412d-af36-63e57c9f0ce7	12722 Lindbergh Hill	\N	\N	Boca Raton	FL	33487	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	3059107906	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
704c3063-1c1c-465f-a512-93a1b44a8047	2874 Summer Ridge Crossing	\N	\N	Fort Lauderdale	FL	33303	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	3057525194	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
11ea58a0-d488-4f90-a2f2-725af8440713	11247 Gina Junction	\N	\N	Pompano Beach	FL	33093	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	3057802500	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
4b03bf3c-aad9-4a8b-92c1-a04a794c8e18	3490 Fuller Terrace	\N	\N	Miami Beach	FL	33119	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	3057993254	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
e3604def-eab3-41e8-85a4-72b36cffbdb2	11566 Dryden Way	\N	\N	Opa Locka	FL	33055	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	3057357909	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
f6f159c6-f136-454c-b2e4-863e83ba1993	6281 Swallow Crossing	\N	\N	Miami	FL	33124	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	3058841164	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
1662e504-8f25-48c7-8f46-ecbe45ab5b60	1859 Wayridge Place	\N	\N	Delray Beach	FL	33483	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	3059574306	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
71c4aa67-ab0d-471f-9387-2e0608d512e7	13597 Michigan Crossing	\N	\N	Boca Raton	FL	33487	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	3057658299	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
2c68c3a1-c68e-4b66-84c1-bb78063ead59	13320 Marcy Trail	\N	\N	Fort Lauderdale	FL	33303	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	3057889031	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
db8892e9-3051-4252-be4c-410a5aa057f2	1763 Karstens Plaza	\N	\N	Pompano Beach	FL	33093	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	3058772668	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
bc8a6699-467b-448f-991f-ca9e4001d0bc	14512 Harbort Avenue	\N	\N	Miami Beach	FL	33119	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	3059664333	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
85a35b32-a9d3-4177-a5c5-17b68a4dbd32	10791 Meadow Vale Terrace	\N	\N	Opa Locka	FL	33055	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	3057898291	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
cde0c1b3-85fc-463b-8bea-f466cd3fde7f	2573 Kings Avenue	\N	\N	Miami	FL	33124	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	3058226064	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
9697e7ab-e7f1-45e9-ac9d-6ad072316e83	3722 Garrison Lane	\N	\N	Miami	FL	33124	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	3058803512	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
64021ae0-64b9-4294-895e-b630b91e191c	4687 Continental Pass	\N	\N	Minneapolis	MN	55404	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	6122449098	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
c4adfd57-e4bb-41ff-926d-5bf1c7d0eba0	7844 Anhalt Lane	\N	\N	Bountiful	UT	84010	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8018111450	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
c093ede0-7546-4739-a55a-8e5ad443bf25	822 Di Loreto Place	\N	\N	Ogden	UT	84405	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8019750817	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
e9431c21-c402-46ee-839b-6cb22469c1de	4885 Buena Vista Alley	\N	\N	Kaysville	UT	84037	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8018164386	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
e091fbb7-dc73-424e-b6a3-f6eafa96e29f	793 Waxwing Road	\N	\N	Layton	UT	84040	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8018604289	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
f7d90977-7a58-4bc9-b6be-f3fca23f8b40	4047 Blaine Hill	\N	\N	Clearfield	UT	84016	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8017325792	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
a6a19025-5e69-4eed-bca1-2a1ac295f580	14734 Waubesa Junction	\N	\N	Huntsville	UT	84317	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8019192014	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
cdc7b509-c2cf-499d-858c-a7760bbe466a	6757 Kensington Road	\N	\N	Farmington	UT	84025	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8018643230	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
1e92bffb-fea3-4660-a97c-0aefed04e98d	8456 Mcguire Drive	\N	\N	Bountiful	UT	84010	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8019109675	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
6e06a0a6-4670-4d58-979d-5d681cefa38f	11862 Hauk Point	\N	\N	Kaysville	UT	84037	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8019065246	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
6a8ede7b-65ae-4b1f-a009-fc5c00f37c18	10936 Bunker Hill Hill	\N	\N	Layton	UT	84040	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8017347405	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
f4aefd21-e14a-47b3-a52f-dce94c5e9a99	9865 Express Parkway	\N	\N	Clearfield	UT	84016	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8017880809	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
d5f1e423-9d32-4ff9-849c-a5cbe8ccf4f5	3681 Ruskin Road	\N	\N	Huntsville	UT	84317	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8018540123	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
94170717-c3c8-448a-b607-6b3236306ad9	342 Kinsman Terrace	\N	\N	Farmington	UT	84025	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8017870204	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
586bcc2d-34cc-4587-994f-fd03113e15b7	8991 Rieder Alley	\N	\N	Bountiful	UT	84010	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8019738250	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
495f03c1-3318-43ca-9726-484e3d0f9b18	1723 Atwood Road	\N	\N	Ogden	UT	84405	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8017984165	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
e8daeb9c-2b62-41e5-a02a-0f2fcd03d955	9903 Onsgard Road	\N	\N	Kaysville	UT	84037	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8017959868	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
a02a3468-1b2c-48d9-9056-8c30af8014b5	5563 1st Place	\N	\N	Layton	UT	84040	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8017580983	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
3a3cff5e-c49c-4b16-8515-3ecdb9ae99a8	6333 Erie Park	\N	\N	Clearfield	UT	84016	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8017633275	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
20145b64-53ca-43dd-b1bc-faeb8aff7369	13752 Village Terrace	\N	\N	Huntsville	UT	84317	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8018475398	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
6a4a9fd3-b1ff-4087-80a6-d8e9988312e2	2473 Kenwood Center	\N	\N	Farmington	UT	84025	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8019711128	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
fe4c3956-42a5-482c-8db3-4a1ad0284cea	13450 Clarendon Avenue	\N	\N	Ogden	UT	84405	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8017744828	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
fab28b28-0bd1-46ef-9e12-32ee9eb5bef4	8152 Lighthouse Bay Lane	\N	\N	Ogden	UT	84405	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8019152798	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
9eed30aa-9b7d-4eba-b822-211a3fe59824	4003 Coleman Terrace	\N	\N	Ogden	UT	84405	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8019786900	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
5b8d6b26-7266-4582-a10f-e88c396d3ba2	11553 Anzinger Pass	\N	\N	Phoenix	AZ	85012	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8019525177	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
d89272d2-0bb5-41b7-b77f-9f6a9c074cc2	8270 Southridge Street	\N	\N	Portland	OR	97218	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8017982308	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
6b82b10a-e9bb-498e-9ae5-aaf2c7884843	13607 Pierstorff Place	\N	\N	San Francisco	CA	94117	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8017702367	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
a7b0b193-04f0-4c97-85a2-e65a5c9a961e	11786 Chive Alley	\N	\N	Bountiful	UT	84010	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8019359846	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
907eb7eb-2d46-4075-b0eb-66857e673d2e	13846 Farragut Trail	\N	\N	Ogden	UT	84405	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8018853959	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
43529465-4724-48cf-8b25-c452c5085c22	4081 La Follette Way	\N	\N	Kaysville	UT	84037	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8019127837	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
93e7150f-0412-4f3f-80c5-102ff374401b	3999 Commercial Terrace	\N	\N	Layton	UT	84040	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8019318832	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
976ad7b5-49d1-49dd-b19d-b6ab41f46c80	5223 Aberg Street	\N	\N	Clearfield	UT	84016	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8017610649	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
7d91c60f-8994-4ace-b5ce-8512a4fc6ae6	9436 Bartelt Road	\N	\N	Huntsville	UT	84317	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8019025940	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
b57c4212-59dc-4d85-be38-a3715bc8d560	4476 Clyde Gallagher Place	\N	\N	Farmington	UT	84025	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8019751978	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
e457f299-d3bc-4538-9573-71780eec7ffa	1151 Killdeer Drive	\N	\N	Ogden	UT	84405	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8018703585	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
9a6eb210-9710-4758-866e-4f3524f9bdcb	12164 6th Terrace	\N	\N	Ogden	UT	84405	2020-01-17 18:47:59.315743+00	2020-02-24 14:29:34.72023+00	United States	8018369342	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
129a7beb-8196-4afb-9b3e-10d8e1f89fa0	719 2nd Ave	Suite 400	\N	Seattle	WA	98104	2020-01-15 22:26:16.793983+00	2020-03-05 18:46:05.930124+00	United States	4255677000	47.603445	-122.333851	f304e1bd-4ea5-496a-9644-76c2eb9e7483
\.


--
-- Data for Name: broadcast; Type: TABLE DATA; Schema: public; Owner: doadmin
--

COPY public.broadcast (id, broadcast_type, sender_id, delivery_timestamp, title, message, organization_id, created_at, updated_at) FROM stdin;
c32d88a2-e248-417b-8337-efb0a95f6d6f	location_request	05423770-0bca-48ea-80e8-919efac8e7b3	2020-04-10 08:20:56.921522+00	OPS LOCATION REQUEST	I smell Marlboro Reds from my office window and wanted to give the employees a friendly reminder. Put it out!!!!!!!	b6f5de76-b09a-4091-add7-c4a72874c9d4	2020-04-10 14:06:35.029275+00	2020-04-10 14:08:29.308038+00
24c9d685-0408-4892-828a-195a04760268	alert	30ef7f68-a992-485f-938f-691b77056a66	2020-04-10 13:32:55.871099+00	Snow Alert	Employees commuting to the Redmond offices should be advised that DOT has reported over 30 accidents on the interstate.	b6f5de76-b09a-4091-add7-c4a72874c9d4	2020-04-10 14:06:35.029275+00	2020-04-10 14:08:29.308038+00
\.


--
-- Data for Name: broadcast_recipient; Type: TABLE DATA; Schema: public; Owner: doadmin
--

COPY public.broadcast_recipient (id, receiver_id, delivery_status, response_location_id, response_remote_location, broadcast_id, created_at, updated_at) FROM stdin;
cd363313-10be-4c17-a707-dae1448102a2	41faa9b6-4495-4329-93ca-392d26d4907c	delivered	\N	\N	24c9d685-0408-4892-828a-195a04760268	2020-04-10 17:25:21.113914+00	2020-04-10 17:25:21.113914+00
\.


--
-- Data for Name: customer; Type: TABLE DATA; Schema: public; Owner: doadmin
--

COPY public.customer (id, name, created_at, updated_at, address_id) FROM stdin;
f304e1bd-4ea5-496a-9644-76c2eb9e7483	TechCore	2020-01-15 18:34:17.588136+00	2020-01-15 21:32:10.877105+00	\N
c1b769c8-dc45-4662-a408-de09ce621202	Blue Rocket	2020-03-05 15:00:05.207421+00	2020-03-05 15:11:42.740853+00	\N
ab11c688-294f-41bd-b06b-ac1cba994443	Net Number	2020-03-05 15:01:17.025341+00	2020-03-05 15:11:42.740853+00	\N
fadb1e8d-bde5-4627-94f9-1847133288c9	iDirect	2020-03-05 15:01:42.4564+00	2020-03-05 15:11:42.740853+00	\N
\.


--
-- Data for Name: customer_user; Type: TABLE DATA; Schema: public; Owner: doadmin
--

COPY public.customer_user (customer_id, user_id, is_owner) FROM stdin;
f304e1bd-4ea5-496a-9644-76c2eb9e7483	33ceb3f3-8900-4ba1-a43a-a0379b64c89d	t
\.


--
-- Data for Name: department; Type: TABLE DATA; Schema: public; Owner: doadmin
--

COPY public.department (id, name, organization_id, parent_id, avatar_url, color, description, created_at, updated_at, customer_id, hierarchy_level) FROM stdin;
e55bba25-63f8-4650-b13a-cfe91b66c5a8	Executive	b6f5de76-b09a-4091-add7-c4a72874c9d4	\N	\N	18355E	Office of the CEO	2020-03-05 19:42:15.82678+00	2020-03-05 19:42:15.82678+00	c1b769c8-dc45-4662-a408-de09ce621202	\N
fc5d6117-dffd-4a63-a7b3-a66e2dda9a86	Sales	b6f5de76-b09a-4091-add7-c4a72874c9d4	e55bba25-63f8-4650-b13a-cfe91b66c5a8	\N	44bd32	The Blue Rocket sales team is focused on customer relationships and driving sales	2020-03-05 20:31:36.845251+00	2020-03-05 21:50:55.611547+00	c1b769c8-dc45-4662-a408-de09ce621202	\N
6b65fe3d-cdbf-4dd3-b3e0-a97be0c5dbd6	Consulting	b6f5de76-b09a-4091-add7-c4a72874c9d4	e55bba25-63f8-4650-b13a-cfe91b66c5a8	\N	8c7ae6	The Blue Rocket consulting team is a group of high powered operators that deliver daily value to our clients	2020-03-05 20:31:36.845251+00	2020-03-05 21:50:55.611547+00	c1b769c8-dc45-4662-a408-de09ce621202	\N
c68c6f7c-4163-4ccd-900f-eeedc786acf7	Product Development	b6f5de76-b09a-4091-add7-c4a72874c9d4	941176eb-0abf-498d-99fe-82626bc23cea	\N	132846	We are building the future software products of Blue Rocket	2020-03-05 20:31:36.845251+00	2020-03-05 21:50:55.611547+00	c1b769c8-dc45-4662-a408-de09ce621202	\N
941176eb-0abf-498d-99fe-82626bc23cea	Product	b6f5de76-b09a-4091-add7-c4a72874c9d4	e55bba25-63f8-4650-b13a-cfe91b66c5a8	\N	8d9db2	We are the product organization including product management, product development and mission control	2020-03-05 20:31:36.845251+00	2020-03-05 21:50:55.611547+00	c1b769c8-dc45-4662-a408-de09ce621202	\N
2e0287cc-e49a-416b-ae13-595b37f016dc	Mission Control	b6f5de76-b09a-4091-add7-c4a72874c9d4	941176eb-0abf-498d-99fe-82626bc23cea	\N	2f3640	We navigate the Blue Rocket ship and keep it full of rocket fuel	2020-03-05 20:31:36.845251+00	2020-03-05 21:50:55.611547+00	c1b769c8-dc45-4662-a408-de09ce621202	\N
9e968199-8100-46f9-96c1-b51719c0fdca	Product Management	b6f5de76-b09a-4091-add7-c4a72874c9d4	941176eb-0abf-498d-99fe-82626bc23cea	\N	ef3e3c	We listen to our customers and design products to exceed their expectations	2020-03-05 20:31:36.845251+00	2020-03-05 21:50:55.611547+00	c1b769c8-dc45-4662-a408-de09ce621202	\N
01fda583-ff6a-42f8-9d3f-5355ba00f171	Marketing	72cba849-77bc-48ff-bfb1-93e5552d538e	ffcc0eec-d476-4404-ba13-7b2434bb1aa2	\N	6c5ce7	\N	2020-04-06 19:33:37.991311+00	2020-04-06 19:42:37.795482+00	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N
f5aba46c-d433-451b-96aa-b2c355acec37	Sales	72cba849-77bc-48ff-bfb1-93e5552d538e	ffcc0eec-d476-4404-ba13-7b2434bb1aa2	\N	e84393	\N	2020-04-06 19:33:37.991311+00	2020-04-06 19:42:37.795482+00	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N
d9968ee1-7871-486a-9f49-a870cac9b577	Finance	72cba849-77bc-48ff-bfb1-93e5552d538e	ffcc0eec-d476-4404-ba13-7b2434bb1aa2	\N	74b9ff	\N	2020-04-06 19:33:37.991311+00	2020-04-06 19:42:37.795482+00	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N
ad5c66ed-8528-40c4-81f3-19f6307c732f	Legal	72cba849-77bc-48ff-bfb1-93e5552d538e	ffcc0eec-d476-4404-ba13-7b2434bb1aa2	\N	a29bfe	\N	2020-04-06 19:33:37.991311+00	2020-04-06 19:42:37.795482+00	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N
4f6c1ca9-dc2f-4d21-8d0c-79d5d5b7a1cf	Human Resource	72cba849-77bc-48ff-bfb1-93e5552d538e	ffcc0eec-d476-4404-ba13-7b2434bb1aa2	\N	0984e3	\N	2020-04-06 19:33:37.991311+00	2020-04-06 19:42:37.795482+00	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N
1c366c76-503c-45a2-960d-7a3252572b14	Technology	72cba849-77bc-48ff-bfb1-93e5552d538e	ffcc0eec-d476-4404-ba13-7b2434bb1aa2	\N	00cec9	\N	2020-04-06 19:33:37.991311+00	2020-04-06 19:42:37.795482+00	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N
2ce92c37-28e4-4dbf-98ed-6e46f73d1abc	Product	72cba849-77bc-48ff-bfb1-93e5552d538e	ffcc0eec-d476-4404-ba13-7b2434bb1aa2	\N	00b894	\N	2020-04-06 19:33:37.991311+00	2020-04-06 19:42:37.795482+00	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N
ffcc0eec-d476-4404-ba13-7b2434bb1aa2	TechCore UK	72cba849-77bc-48ff-bfb1-93e5552d538e	05fd3d9f-ce4e-4d93-afb5-e6fe0af280bc	\N	636e72	\N	2020-04-06 19:33:37.991311+00	2020-04-06 21:04:11.189975+00	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N
359ac05c-19c7-4d2c-967b-5667a3c11dae	Compensation	72cba849-77bc-48ff-bfb1-93e5552d538e	ef5288f6-b3c0-4da7-8f64-2daa9737549a	https://robohash.org/nihilremut.jpg?size=50x50&set=set1	0984e3	We tell you what you get.  Don't ask for more.	2020-01-15 22:37:09.830637+00	2020-02-28 16:28:29.721796+00	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N
e5a95bfc-e227-4d81-9559-81026310d414	Learning & Development	72cba849-77bc-48ff-bfb1-93e5552d538e	ef5288f6-b3c0-4da7-8f64-2daa9737549a	https://robohash.org/commodiperspiciatisin.png?size=50x50&set=set1	0984e3	We provide the best learning and development platforms for the TechCore employees	2020-01-15 22:40:13.232069+00	2020-02-28 16:28:29.721796+00	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N
812502b1-6ad9-460d-ab7f-beaa69a9d497	HR Administration	72cba849-77bc-48ff-bfb1-93e5552d538e	ef5288f6-b3c0-4da7-8f64-2daa9737549a	https://robohash.org/necessitatibusatet.bmp?size=50x50&set=set1	0984e3	We help employees	2020-01-15 22:38:03.023576+00	2020-02-28 16:28:29.721796+00	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N
24534a16-bda0-4ff6-a704-c552721c91d9	Recruiting	72cba849-77bc-48ff-bfb1-93e5552d538e	ef5288f6-b3c0-4da7-8f64-2daa9737549a	https://robohash.org/nondelectussuscipit.bmp?size=50x50&set=set1	0984e3	We bring the best people to TechCore	2020-01-15 22:42:14.089599+00	2020-02-28 16:28:29.721796+00	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N
dae2c97a-1f38-4834-ae40-4c33256b3b8d	Finance	72cba849-77bc-48ff-bfb1-93e5552d538e	05fd3d9f-ce4e-4d93-afb5-e6fe0af280bc	https://robohash.org/consequaturquinumquam.png?size=50x50&set=set1	74b9ff	We manage the money	2020-01-15 22:01:33.590285+00	2020-02-28 16:30:35.422427+00	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N
3ff8f1ca-f908-48bb-bdc9-23bc17c9b79b	Accounting	72cba849-77bc-48ff-bfb1-93e5552d538e	dae2c97a-1f38-4834-ae40-4c33256b3b8d	https://robohash.org/autmagnamsunt.jpg?size=50x50&set=set1	74b9ff	We prepare the financial statemens, maintain the general ledger, pay bills, bill customers, payroll and financial analysis	2020-01-15 22:21:18.745246+00	2020-02-28 16:30:35.422427+00	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N
6ea0d2fe-0d72-430f-830f-cf200f53bf50	Controllership	72cba849-77bc-48ff-bfb1-93e5552d538e	dae2c97a-1f38-4834-ae40-4c33256b3b8d	https://robohash.org/quoiurequas.bmp?size=50x50&set=set1	74b9ff	We control everything	2020-01-15 22:22:11.586104+00	2020-02-28 16:30:35.422427+00	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N
8c569e9d-9105-4552-b43c-2db52ce1cc41	Financial Systems	72cba849-77bc-48ff-bfb1-93e5552d538e	dae2c97a-1f38-4834-ae40-4c33256b3b8d	https://robohash.org/mollitiaquodaut.bmp?size=50x50&set=set1	74b9ff	We run the systems that manage the money	2020-01-15 22:25:15.282711+00	2020-02-28 16:30:35.422427+00	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N
21451c5d-0c0b-45d3-8f14-e876bb836fae	Marketing	72cba849-77bc-48ff-bfb1-93e5552d538e	05fd3d9f-ce4e-4d93-afb5-e6fe0af280bc	https://robohash.org/ametcumquemolestiae.bmp?size=50x50&set=set1	6c5ce7	We promote the TechCore products and services	2020-01-15 22:05:46.559788+00	2020-03-16 16:54:36.411001+00	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N
6ec6cb34-d4dc-4be0-9ef3-e08067d357ff	Operations Management	72cba849-77bc-48ff-bfb1-93e5552d538e	05fd3d9f-ce4e-4d93-afb5-e6fe0af280bc	https://robohash.org/possimusestaspernatur.png?size=50x50&set=set1	d63031	We procure, manage and distribute all TechCore physical products	2020-01-15 22:07:06.861105+00	2020-03-04 01:38:10.764205+00	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N
05fd3d9f-ce4e-4d93-afb5-e6fe0af280bc	Executive	72cba849-77bc-48ff-bfb1-93e5552d538e	\N	https://robohash.org/consequaturautlabore.png?size=50x50&set=set1	636e72	Executive department for TechCore	2020-01-15 21:45:15.580595+00	2020-02-24 14:29:34.72023+00	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N
d47869d8-7eae-4a27-93d5-96c750792ecb	Customer Experience	72cba849-77bc-48ff-bfb1-93e5552d538e	05fd3d9f-ce4e-4d93-afb5-e6fe0af280bc	https://robohash.org/facilisilloearum.jpg?size=50x50&set=set1	2d3436	Customer Experience ensures an awesome experience with TechCore	2020-01-15 21:59:48.771552+00	2020-02-24 14:29:34.72023+00	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N
e7b0dc35-9e86-467d-b3d1-4d49167a3a89	Legal	72cba849-77bc-48ff-bfb1-93e5552d538e	05fd3d9f-ce4e-4d93-afb5-e6fe0af280bc	https://robohash.org/dolorumquiaaliquid.bmp?size=50x50&set=set1	a29bfe	We ensure legal compliance in all TechCore does	2020-01-15 22:04:00.627951+00	2020-02-24 14:29:34.72023+00	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N
a88934bf-8ebe-4bc3-8d6a-4e70f56423c5	Product	72cba849-77bc-48ff-bfb1-93e5552d538e	05fd3d9f-ce4e-4d93-afb5-e6fe0af280bc	https://robohash.org/utipsumeveniet.jpg?size=50x50&set=set1	00b894	We make awesome products	2020-01-15 22:08:09.730328+00	2020-02-24 14:29:34.72023+00	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N
5df84a7b-1a23-4a93-87d4-1683ccc41d32	Sales	72cba849-77bc-48ff-bfb1-93e5552d538e	05fd3d9f-ce4e-4d93-afb5-e6fe0af280bc	https://robohash.org/magnamnatusnecessitatibus.jpg?size=50x50&set=set1	e84393	We sell all of the TechCore products and services	2020-01-15 22:09:20.961568+00	2020-02-24 14:29:34.72023+00	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N
949eba96-7986-4576-89a2-6c8c01ea9615	Technology	72cba849-77bc-48ff-bfb1-93e5552d538e	05fd3d9f-ce4e-4d93-afb5-e6fe0af280bc	https://robohash.org/liberoducimusest.bmp?size=50x50&set=set1	00cec9	We make TechCore run with the latest and greatest stuff	2020-01-15 22:10:52.000475+00	2020-02-24 14:29:34.72023+00	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N
ad05f631-172b-43dc-a4e4-7eadcce11f9b	Warehouse Management	72cba849-77bc-48ff-bfb1-93e5552d538e	6ec6cb34-d4dc-4be0-9ef3-e08067d357ff	https://robohash.org/ipsumnecessitatibusfuga.png?size=50x50&set=set1	d63031	We manage our global warehouses	2020-01-15 23:02:50.241772+00	2020-02-27 20:47:03.268612+00	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N
19921661-9a3f-46be-948d-093c098442a8	Business Development	72cba849-77bc-48ff-bfb1-93e5552d538e	21451c5d-0c0b-45d3-8f14-e876bb836fae	https://robohash.org/liberoconsecteturexpedita.bmp?size=50x50&set=set1	6c5ce7	We make the business better by increasing revenues, growth in terms of business expansion, increasing profitability by building strategic partnerships, etc.	2020-01-15 22:53:00.603913+00	2020-02-27 21:03:21.124537+00	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N
c795957d-0ae6-4cb4-81ce-4e913a0781c6	Hardware Platforms	72cba849-77bc-48ff-bfb1-93e5552d538e	a88934bf-8ebe-4bc3-8d6a-4e70f56423c5	https://robohash.org/utrationeiste.png?size=50x50&set=set1	00b894	We build TechCore's hardware platforms	2020-01-15 23:04:31.281094+00	2020-02-27 21:03:21.124537+00	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N
96987261-8cf5-4a3f-9349-d9e70ea6dfc0	Event Management	72cba849-77bc-48ff-bfb1-93e5552d538e	ef5288f6-b3c0-4da7-8f64-2daa9737549a	https://robohash.org/abpariaturimpedit.bmp?size=50x50&set=set1	0984e3	We host the most amazing events for TechCore employees and Cusomters	2020-01-15 22:54:04.455858+00	2020-03-16 16:55:09.707603+00	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N
ef5288f6-b3c0-4da7-8f64-2daa9737549a	Human Resource	72cba849-77bc-48ff-bfb1-93e5552d538e	05fd3d9f-ce4e-4d93-afb5-e6fe0af280bc	https://robohash.org/quiavoluptasrerum.jpg?size=50x50&set=set1	0984e3	We take care of the people at TechCore	2020-01-15 22:02:48.986174+00	2020-02-28 16:28:29.721796+00	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N
1d6daae3-4c3a-4661-b4a5-c2c8e0ae7159	Supply Chain	72cba849-77bc-48ff-bfb1-93e5552d538e	6ec6cb34-d4dc-4be0-9ef3-e08067d357ff	https://robohash.org/quidemlaboriosamamet.png?size=50x50&set=set1	d63031	We move TechCore's products around the globe	2020-01-15 23:01:57.879503+00	2020-03-03 23:58:06.923531+00	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N
d9e83b30-6eab-4260-8f04-43ad4385d3ba	Marketing Operations	72cba849-77bc-48ff-bfb1-93e5552d538e	21451c5d-0c0b-45d3-8f14-e876bb836fae	https://robohash.org/etautamet.png?size=50x50&set=set1	6c5ce7	We make sure the marketing dollars are most effective	2020-01-15 22:55:51.136194+00	2020-02-27 20:54:07.913141+00	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N
d2fcf8f8-40b6-4c8f-808f-b96e35f544a7	Product Management	72cba849-77bc-48ff-bfb1-93e5552d538e	a88934bf-8ebe-4bc3-8d6a-4e70f56423c5	https://robohash.org/expeditafugavoluptates.bmp?size=50x50&set=set1	00b894	The Product Management Team	2020-01-15 23:06:10.125279+00	2020-02-27 20:56:02.604995+00	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N
0df51c70-fc23-490e-8173-c6b869fb2911	Software Platforms	72cba849-77bc-48ff-bfb1-93e5552d538e	a88934bf-8ebe-4bc3-8d6a-4e70f56423c5	https://robohash.org/velitdolorequi.png?size=50x50&set=set1	00b894	We build world class software for TechCore	2020-01-15 23:07:35.750683+00	2020-02-27 20:56:02.604995+00	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N
bb86daa7-e1cd-420f-939f-fbe7e7c325ac	Customer Success	72cba849-77bc-48ff-bfb1-93e5552d538e	d47869d8-7eae-4a27-93d5-96c750792ecb	https://robohash.org/iureeiusab.bmp?size=50x50&set=set1	2d3436		2020-01-15 23:49:25.686904+00	2020-02-27 20:58:04.848979+00	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N
c376b0a4-41df-4cc8-bdfc-a1bd070a6251	Customer Support	72cba849-77bc-48ff-bfb1-93e5552d538e	d47869d8-7eae-4a27-93d5-96c750792ecb	https://robohash.org/estdolorecorporis.bmp?size=50x50&set=set1	2d3436	\N	2020-01-15 23:49:57.132249+00	2020-02-27 20:58:04.848979+00	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N
19b11d82-d683-4e2a-a1a8-3112b639ca67	Field Sales	72cba849-77bc-48ff-bfb1-93e5552d538e	5df84a7b-1a23-4a93-87d4-1683ccc41d32	https://robohash.org/remcommodiqui.bmp?size=50x50&set=set1	e84393	We are with the customers in the field	2020-01-15 23:09:51.970821+00	2020-02-27 20:58:04.848979+00	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N
581badcc-bed1-415e-bf4d-fda75ba6b888	Inside Sales	72cba849-77bc-48ff-bfb1-93e5552d538e	5df84a7b-1a23-4a93-87d4-1683ccc41d32	https://robohash.org/aperiamenimperspiciatis.bmp?size=50x50&set=set1	e84393	We sell the TechCore products and services	2020-01-15 23:10:45.150986+00	2020-02-27 20:58:04.848979+00	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N
0ce7d0a2-8674-4f8e-890b-2a3f206dc1c9	Technical Support	72cba849-77bc-48ff-bfb1-93e5552d538e	d47869d8-7eae-4a27-93d5-96c750792ecb	https://robohash.org/veritatiseumnon.bmp?size=50x50&set=set1	2d3436		2020-01-15 23:51:33.557233+00	2020-02-27 21:00:10.404191+00	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N
27cef2cd-183a-4515-889b-9ac8c4823ded	Public Relations	72cba849-77bc-48ff-bfb1-93e5552d538e	21451c5d-0c0b-45d3-8f14-e876bb836fae	https://robohash.org/sequiveliure.png?size=50x50&set=set1	6c5ce7	We are the public face of TechCore	2020-01-15 22:56:51.795544+00	2020-02-27 21:03:21.124537+00	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N
c605f38c-e7b1-44c5-9a17-c099fdffddc0	Engineering	72cba849-77bc-48ff-bfb1-93e5552d538e	6ec6cb34-d4dc-4be0-9ef3-e08067d357ff	https://robohash.org/voluptatemsuntqui.bmp?size=50x50&set=set1	d63031	We are Engineering	2020-01-15 22:57:50.252432+00	2020-02-27 21:03:21.124537+00	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N
01cc47f4-7f9e-459b-9c33-8f59e7fc10bb	Operations	72cba849-77bc-48ff-bfb1-93e5552d538e	6ec6cb34-d4dc-4be0-9ef3-e08067d357ff	https://robohash.org/inaliquamdignissimos.jpg?size=50x50&set=set1	d63031	We are Operations	2020-01-15 22:59:29.115505+00	2020-02-27 21:03:21.124537+00	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N
41235a74-d402-4ccd-93cd-9d87625fd24a	Info Sec	72cba849-77bc-48ff-bfb1-93e5552d538e	949eba96-7986-4576-89a2-6c8c01ea9615	https://robohash.org/velitetreiciendis.jpg?size=50x50&set=set1	00cec9	We secure and protect TechCore's data	2020-01-15 23:15:33.226148+00	2020-02-27 21:03:21.124537+00	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N
f971304f-31a2-450f-ae6c-300c86eb561b	Receiving	72cba849-77bc-48ff-bfb1-93e5552d538e	ad05f631-172b-43dc-a4e4-7eadcce11f9b	https://robohash.org/quosquaeratculpa.bmp?size=50x50&set=set1	d63031	We manage the receiving function for TechCore	2020-01-15 23:01:10.35692+00	2020-03-10 15:36:01.424079+00	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N
18992680-8854-4b42-9b0b-3e06b2755c53	Floor Operations	72cba849-77bc-48ff-bfb1-93e5552d538e	ad05f631-172b-43dc-a4e4-7eadcce11f9b	https://robohash.org/autemquinihil.png?size=50x50&set=set1	d63031	We move goods on the manufacturing floor	2020-01-15 22:58:44.800871+00	2020-03-10 15:37:40.279692+00	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N
972816d1-f849-435a-9224-cdb63fbd9604	Quality	72cba849-77bc-48ff-bfb1-93e5552d538e	01cc47f4-7f9e-459b-9c33-8f59e7fc10bb	https://robohash.org/velitrerumlaboriosam.jpg?size=50x50&set=set1	d63031	We are Quality	2020-01-15 23:00:16.546194+00	2020-03-10 16:50:19.188578+00	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N
8498910c-13d7-4428-9394-d8c82947a07b	Data Analytics	72cba849-77bc-48ff-bfb1-93e5552d538e	949eba96-7986-4576-89a2-6c8c01ea9615	https://robohash.org/etperspiciatiserror.bmp?size=50x50&set=set1	00cec9	We are the house that AI built	2020-01-15 23:14:38.719256+00	2020-02-27 21:03:21.124537+00	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N
5cc8118e-d37d-4248-a421-8689097e436a	Infrastructure	72cba849-77bc-48ff-bfb1-93e5552d538e	949eba96-7986-4576-89a2-6c8c01ea9615	https://robohash.org/laboremollitiadolorem.png?size=50x50&set=set1	00cec9	We manage the infrastructure to keep TechCore running	2020-01-15 23:16:33.409335+00	2020-02-27 21:03:21.124537+00	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N
466ed5b1-3a5d-47fe-a52b-227e0e51e061	IT Operations	72cba849-77bc-48ff-bfb1-93e5552d538e	949eba96-7986-4576-89a2-6c8c01ea9615	https://robohash.org/exenimsed.bmp?size=50x50&set=set1	00cec9	We are IT Ops	2020-01-15 23:17:37.571581+00	2020-02-27 21:03:21.124537+00	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N
e5dcf4b2-96af-4d8e-b770-cd9f76f34335	Software Development	72cba849-77bc-48ff-bfb1-93e5552d538e	949eba96-7986-4576-89a2-6c8c01ea9615	https://robohash.org/ideteaque.png?size=50x50&set=set1	00cec9	We build software to run TechCore	2020-01-15 23:18:27.464288+00	2020-02-27 21:03:21.124537+00	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N
\.


--
-- Data for Name: location; Type: TABLE DATA; Schema: public; Owner: doadmin
--

COPY public.location (id, name, organization_id, address_id, created_at, updated_at, avatar_url, customer_id, phone) FROM stdin;
80d65bb1-46bd-4b1a-b52f-3ee81a6f4ca5	Marketing Center	72cba849-77bc-48ff-bfb1-93e5552d538e	69fd7e44-7483-44fe-8ca0-e9307adb4779	2020-01-15 22:30:08.198259+00	2020-02-24 14:29:34.72023+00	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N
2d6671d9-d94c-45aa-838d-38eb89c4abd3	Miami MFG	72cba849-77bc-48ff-bfb1-93e5552d538e	bf261892-2541-4cca-8b9b-0c107929c021	2020-01-15 22:31:19.95133+00	2020-02-24 14:29:34.72023+00	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N
0aa76a1d-9516-413f-b311-fe0da3c9abf1	Ogden Development Center	72cba849-77bc-48ff-bfb1-93e5552d538e	5d8ba8f1-1576-4cfc-84b8-f05e12553e7b	2020-01-15 22:33:54.773464+00	2020-02-24 14:29:34.72023+00	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N
46aeeef7-1b5e-4962-82d7-e939582d7032	Headquarters	b6f5de76-b09a-4091-add7-c4a72874c9d4	07b314e8-1805-4f16-8ea2-87b32a7e9b8e	2020-03-05 18:54:59.488142+00	2020-03-05 18:54:59.488142+00	\N	c1b769c8-dc45-4662-a408-de09ce621202	\N
0b982233-ac65-4c19-91c7-a5db07135ad9	Ogden Development Center	b6f5de76-b09a-4091-add7-c4a72874c9d4	4bff9e7e-7fa4-497b-b09e-be1fc3740172	2020-03-05 18:56:27.203378+00	2020-03-10 01:14:35.543798+00	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/b6f5de76-b09a-4091-add7-c4a72874c9d4/location_avatars/0b982233-ac65-4c19-91c7-a5db07135ad9.jpeg	c1b769c8-dc45-4662-a408-de09ce621202	\N
c10c8cb4-e212-47ce-96e5-4c077c530abd	Customer Service Center	72cba849-77bc-48ff-bfb1-93e5552d538e	513bc68f-d3c0-4f33-b231-02eb37aa9cfd	2020-01-15 22:21:39.776251+00	2020-03-10 01:49:31.295123+00	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/location_avatars/c10c8cb4-e212-47ce-96e5-4c077c530abd.jpeg	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N
fac15c2e-cce9-48f9-b818-10a2545020f4	Headquarters	72cba849-77bc-48ff-bfb1-93e5552d538e	129a7beb-8196-4afb-9b3e-10d8e1f89fa0	2020-01-15 22:27:29.697664+00	2020-03-10 02:00:27.9645+00	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/location_avatars/fac15c2e-cce9-48f9-b818-10a2545020f4.jpeg	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N
23409dd4-7cd3-4073-971a-12b48be6885e	Engineering Center	72cba849-77bc-48ff-bfb1-93e5552d538e	d5e8f89d-b9ef-4a1e-aff9-e7d3f31c7fe8	2020-01-15 22:24:48.36189+00	2020-03-10 02:01:38.127624+00	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/location_avatars/23409dd4-7cd3-4073-971a-12b48be6885e.png	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N
81c09eca-58e2-4264-b126-929908174f1a	London HQ	72cba849-77bc-48ff-bfb1-93e5552d538e	34dc694f-c485-47fb-9560-3c1489f99683	2020-04-06 17:43:03.046799+00	2020-04-06 17:43:03.046799+00	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/location_avatars/81c09eca-58e2-4264-b126-929908174f1a.jpg	f304e1bd-4ea5-496a-9644-76c2eb9e7483	2076060606
\.


--
-- Data for Name: organization; Type: TABLE DATA; Schema: public; Owner: doadmin
--

COPY public.organization (id, name, customer_id, plan_type, is_public, created_at, updated_at, avatar_url) FROM stdin;
9981aa95-a305-4e23-a917-9415cfa18cf2	Net Number	ab11c688-294f-41bd-b06b-ac1cba994443	\N	f	2020-03-05 15:12:56.125137+00	2020-03-05 15:12:56.125137+00	\N
1cbe7651-c91a-47ae-9e82-1d4fbd0f5ee8	iDirect	fadb1e8d-bde5-4627-94f9-1847133288c9	\N	f	2020-03-05 15:12:56.125137+00	2020-03-05 15:12:56.125137+00	\N
72cba849-77bc-48ff-bfb1-93e5552d538e	TechCore	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	f	2020-01-15 20:52:12.55727+00	2020-03-06 22:05:10.5464+00	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/logos/techcore_logo.png
b6f5de76-b09a-4091-add7-c4a72874c9d4	Blue Rocket	c1b769c8-dc45-4662-a408-de09ce621202	\N	f	2020-03-05 15:12:56.125137+00	2020-03-18 01:01:20.517266+00	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/b6f5de76-b09a-4091-add7-c4a72874c9d4/logos/BlueRocket_Chevron_Avatar_White_0320.png
\.


--
-- Data for Name: position; Type: TABLE DATA; Schema: public; Owner: doadmin
--

COPY public."position" (id, title, subtype, description, time_type, status, profile_id, organization_id, department_id, created_at, updated_at, parent_id, hierarchy_level, customer_id, position_number, location_id) FROM stdin;
be071a53-2599-4065-af69-d5f4c7752728	Developer	contingent	\N	contingent	filled	\N	b6f5de76-b09a-4091-add7-c4a72874c9d4	c68c6f7c-4163-4ccd-900f-eeedc786acf7	2020-03-05 22:30:15.494202+00	2020-03-25 03:05:54.736038+00	be7c96ce-a98e-4d95-9b58-a0e67b9048dc	\N	c1b769c8-dc45-4662-a408-de09ce621202	\N	0b982233-ac65-4c19-91c7-a5db07135ad9
bfe6649b-1e76-4a9f-b418-6bc4c4a2492d	Developer	contingent	\N	contingent	filled	\N	b6f5de76-b09a-4091-add7-c4a72874c9d4	c68c6f7c-4163-4ccd-900f-eeedc786acf7	2020-03-05 22:30:15.494202+00	2020-03-25 03:05:54.736038+00	be7c96ce-a98e-4d95-9b58-a0e67b9048dc	\N	c1b769c8-dc45-4662-a408-de09ce621202	\N	0b982233-ac65-4c19-91c7-a5db07135ad9
a9a55ef5-fc28-4037-bab4-168663523c20	Accounts Receivables Analyst	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	3ff8f1ca-f908-48bb-bdc9-23bc17c9b79b	2020-01-16 00:18:12.630358+00	2020-03-25 03:05:54.736038+00	ca6405b9-0263-4f55-9efc-a744c2f1c123	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	fac15c2e-cce9-48f9-b818-10a2545020f4
d744ce6e-56c9-4585-bdae-d6a6f872e681	Data Analyst	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	8c569e9d-9105-4552-b43c-2db52ce1cc41	2020-01-16 00:22:23.502059+00	2020-03-25 03:05:54.736038+00	c64e8f33-f3ff-4e20-a92b-f8c54f808949	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	fac15c2e-cce9-48f9-b818-10a2545020f4
973200e5-a3f6-42c4-956d-b27d11a85fb0	Senior Data Analyst	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	8c569e9d-9105-4552-b43c-2db52ce1cc41	2020-01-16 00:40:51.824629+00	2020-03-25 03:05:54.736038+00	c64e8f33-f3ff-4e20-a92b-f8c54f808949	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	fac15c2e-cce9-48f9-b818-10a2545020f4
656d6161-73e9-45a0-90a0-0c8209374b9a	VP Customer Experience	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	d47869d8-7eae-4a27-93d5-96c750792ecb	2020-01-16 00:43:09.267422+00	2020-03-25 03:05:54.736038+00	71fc94e3-abe0-47dc-9011-ab49597cfd6a	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	c10c8cb4-e212-47ce-96e5-4c077c530abd
50445e70-7036-4dc2-bc1d-dbc8265caec3	Inside Sales Manager	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	581badcc-bed1-415e-bf4d-fda75ba6b888	2020-01-16 00:31:41.498478+00	2020-03-25 03:05:54.736038+00	f434ac6a-0621-4b49-a313-ae8801e54c86	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	c10c8cb4-e212-47ce-96e5-4c077c530abd
5c1c1645-806b-4383-a1bd-6b45a18e3785	Manager Support	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	c376b0a4-41df-4cc8-bdfc-a1bd070a6251	2020-01-16 00:37:39.180532+00	2020-03-25 03:05:54.736038+00	656d6161-73e9-45a0-90a0-0c8209374b9a	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	c10c8cb4-e212-47ce-96e5-4c077c530abd
c318e3f0-f4ba-4737-9075-095278f0ef9a	Analyst Technical Support	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	0ce7d0a2-8674-4f8e-890b-2a3f206dc1c9	2020-01-16 00:20:11.192065+00	2020-03-25 03:05:54.736038+00	d9317b6f-309c-47d2-aec7-373e12062ecf	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	c10c8cb4-e212-47ce-96e5-4c077c530abd
1db16227-c8f5-4329-9e48-828c4788496f	Analyst Technical Support	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	0ce7d0a2-8674-4f8e-890b-2a3f206dc1c9	2020-01-21 20:14:13.36874+00	2020-03-25 03:05:54.736038+00	d9317b6f-309c-47d2-aec7-373e12062ecf	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	c10c8cb4-e212-47ce-96e5-4c077c530abd
9266dfb0-af61-4a8a-bd3b-b87d73975602	Analyst Customer Support	contingent	\N	contingent	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	bb86daa7-e1cd-420f-939f-fbe7e7c325ac	2020-01-16 00:19:31.186207+00	2020-03-25 03:05:54.736038+00	5c1c1645-806b-4383-a1bd-6b45a18e3785	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	c10c8cb4-e212-47ce-96e5-4c077c530abd
b745c589-7453-4600-99bc-82a35e5ced21	Analyst Customer Support	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	c376b0a4-41df-4cc8-bdfc-a1bd070a6251	2020-01-22 00:04:13.123697+00	2020-03-25 03:05:54.736038+00	5c1c1645-806b-4383-a1bd-6b45a18e3785	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	c10c8cb4-e212-47ce-96e5-4c077c530abd
262d11d1-ccd8-4aa2-bbda-8406b95c9de7	Analyst Customer Success	contingent	\N	contingent	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	bb86daa7-e1cd-420f-939f-fbe7e7c325ac	2020-01-22 00:04:13.123697+00	2020-03-25 03:05:54.736038+00	79be7ad7-ef59-4695-962c-c48c52f48203	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	c10c8cb4-e212-47ce-96e5-4c077c530abd
2bf62011-9339-4377-809d-d164cbe697fa	Analyst Customer Success	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	bb86daa7-e1cd-420f-939f-fbe7e7c325ac	2020-01-22 00:04:13.123697+00	2020-03-25 03:05:54.736038+00	79be7ad7-ef59-4695-962c-c48c52f48203	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	c10c8cb4-e212-47ce-96e5-4c077c530abd
650ef93f-65fb-4148-8eff-b593c0fd185e	Analyst Customer Success	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	bb86daa7-e1cd-420f-939f-fbe7e7c325ac	2020-01-16 00:19:12.893412+00	2020-03-25 03:05:54.736038+00	79be7ad7-ef59-4695-962c-c48c52f48203	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	c10c8cb4-e212-47ce-96e5-4c077c530abd
7ea33b53-d45f-4340-971d-57aec1a41e70	Analyst Customer Success	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	bb86daa7-e1cd-420f-939f-fbe7e7c325ac	2020-01-21 20:14:13.36874+00	2020-03-25 03:05:54.736038+00	79be7ad7-ef59-4695-962c-c48c52f48203	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	c10c8cb4-e212-47ce-96e5-4c077c530abd
f434ac6a-0621-4b49-a313-ae8801e54c86	Director Sales	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	19b11d82-d683-4e2a-a1a8-3112b639ca67	2020-01-16 00:26:21.03621+00	2020-03-25 03:05:54.736038+00	6ab88b8c-743d-429a-a678-e2db9b18bcec	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N
e6f9d1cb-d759-4bf5-99bd-e258bf11bfb0	VP Product	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	a88934bf-8ebe-4bc3-8d6a-4e70f56423c5	2020-01-16 00:44:43.583871+00	2020-03-25 03:05:54.736038+00	71fc94e3-abe0-47dc-9011-ab49597cfd6a	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	23409dd4-7cd3-4073-971a-12b48be6885e
5251c1e1-fad3-443e-9079-12b8de08dbd0	Inside Sales Manager	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	581badcc-bed1-415e-bf4d-fda75ba6b888	2020-01-22 00:17:30.252588+00	2020-03-25 03:05:54.736038+00	f434ac6a-0621-4b49-a313-ae8801e54c86	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	23409dd4-7cd3-4073-971a-12b48be6885e
cc8eb71f-766d-493e-94c8-cc4877e101f6	Executive Admin	contingent	\N	contingent	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	a88934bf-8ebe-4bc3-8d6a-4e70f56423c5	2020-01-16 00:30:04.075502+00	2020-03-25 03:05:54.736038+00	e6f9d1cb-d759-4bf5-99bd-e258bf11bfb0	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	23409dd4-7cd3-4073-971a-12b48be6885e
857a696f-f757-4143-806d-9bce8b90b86b	Director Product Management	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	d2fcf8f8-40b6-4c8f-808f-b96e35f544a7	2020-01-16 00:25:48.451838+00	2020-03-25 03:05:54.736038+00	e6f9d1cb-d759-4bf5-99bd-e258bf11bfb0	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	23409dd4-7cd3-4073-971a-12b48be6885e
174776b6-91ca-4ddc-84be-a3776b6fd38f	Director Software Platforms	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	0df51c70-fc23-490e-8173-c6b869fb2911	2020-01-16 00:27:01.163754+00	2020-03-25 03:05:54.736038+00	e6f9d1cb-d759-4bf5-99bd-e258bf11bfb0	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	23409dd4-7cd3-4073-971a-12b48be6885e
30415589-e236-4f04-b995-cfcb71ca79d9	Director Hardware Platforms	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	c795957d-0ae6-4cb4-81ce-4e913a0781c6	2020-01-16 00:24:10.404983+00	2020-03-25 03:05:54.736038+00	e6f9d1cb-d759-4bf5-99bd-e258bf11bfb0	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	23409dd4-7cd3-4073-971a-12b48be6885e
6a308156-a98b-4ab2-927e-07e258844607	Mobile Product Manager	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	d2fcf8f8-40b6-4c8f-808f-b96e35f544a7	2020-01-16 00:38:36.903377+00	2020-03-25 03:05:54.736038+00	857a696f-f757-4143-806d-9bce8b90b86b	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	23409dd4-7cd3-4073-971a-12b48be6885e
30e5a298-d137-49f8-8637-62176f0d832a	Enterprise Product Manager	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	d2fcf8f8-40b6-4c8f-808f-b96e35f544a7	2020-01-16 00:28:57.205444+00	2020-03-25 03:05:54.736038+00	857a696f-f757-4143-806d-9bce8b90b86b	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	23409dd4-7cd3-4073-971a-12b48be6885e
54b7afa6-03a7-4751-8804-07f29e43ea04	Data Product Manager	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	d2fcf8f8-40b6-4c8f-808f-b96e35f544a7	2020-01-16 00:22:42.619374+00	2020-03-25 03:05:54.736038+00	857a696f-f757-4143-806d-9bce8b90b86b	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	23409dd4-7cd3-4073-971a-12b48be6885e
d4da59a0-a864-4643-8796-f09d56715025	Onboarding Product Manager	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	d2fcf8f8-40b6-4c8f-808f-b96e35f544a7	2020-01-16 00:39:11.795705+00	2020-03-25 03:05:54.736038+00	857a696f-f757-4143-806d-9bce8b90b86b	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	23409dd4-7cd3-4073-971a-12b48be6885e
53a8db3c-a8f5-41bd-bc58-b27f3bc1d5d9	Director Sales	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	19b11d82-d683-4e2a-a1a8-3112b639ca67	2020-01-22 00:04:13.123697+00	2020-03-25 03:05:54.736038+00	6ab88b8c-743d-429a-a678-e2db9b18bcec	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N
c57b5e1b-090c-466f-b655-c81c3a61a8fa	VP Marketing	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	21451c5d-0c0b-45d3-8f14-e876bb836fae	2020-01-16 00:44:13.791564+00	2020-03-25 03:05:54.736038+00	71fc94e3-abe0-47dc-9011-ab49597cfd6a	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	80d65bb1-46bd-4b1a-b52f-3ee81a6f4ca5
a7cd11fe-533d-4a73-a31a-e111e4c76a25	Director Sales	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	19b11d82-d683-4e2a-a1a8-3112b639ca67	2020-01-22 00:04:13.123697+00	2020-03-25 03:05:54.736038+00	6ab88b8c-743d-429a-a678-e2db9b18bcec	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N
13464fbc-2f34-4b23-868f-8748541a4e95	Director Public Relations	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	27cef2cd-183a-4515-889b-9ac8c4823ded	2020-01-21 20:14:13.36874+00	2020-03-25 03:05:54.736038+00	c57b5e1b-090c-466f-b655-c81c3a61a8fa	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	80d65bb1-46bd-4b1a-b52f-3ee81a6f4ca5
7c68ead2-22a9-40c9-9fc9-f07b18ba1d52	Director Marketing Operations	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	d9e83b30-6eab-4260-8f04-43ad4385d3ba	2020-01-16 00:24:48.825759+00	2020-03-25 03:05:54.736038+00	c57b5e1b-090c-466f-b655-c81c3a61a8fa	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	80d65bb1-46bd-4b1a-b52f-3ee81a6f4ca5
db85f397-a133-4c1d-8a7b-087aa2515022	Director Business Development	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	19921661-9a3f-46be-948d-093c098442a8	2020-01-16 00:23:02.551131+00	2020-03-25 03:05:54.736038+00	c57b5e1b-090c-466f-b655-c81c3a61a8fa	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	80d65bb1-46bd-4b1a-b52f-3ee81a6f4ca5
a435e446-9c5e-41a4-8e20-f6db685cc1da	Copy Editor	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	d9e83b30-6eab-4260-8f04-43ad4385d3ba	2020-01-16 00:21:45.769013+00	2020-03-25 03:05:54.736038+00	7c68ead2-22a9-40c9-9fc9-f07b18ba1d52	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	80d65bb1-46bd-4b1a-b52f-3ee81a6f4ca5
9ee199fe-5e00-44d2-b590-f528ee806421	Copywriter	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	d9e83b30-6eab-4260-8f04-43ad4385d3ba	2020-01-16 00:22:04.713777+00	2020-03-25 03:05:54.736038+00	7c68ead2-22a9-40c9-9fc9-f07b18ba1d52	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	80d65bb1-46bd-4b1a-b52f-3ee81a6f4ca5
a6bae590-9cc0-448d-9838-bfea3e3dae69	Warehouse Associate	contingent	\N	contingent	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	ad05f631-172b-43dc-a4e4-7eadcce11f9b	2020-01-16 00:45:34.977703+00	2020-03-25 03:05:54.736038+00	61916ef9-6e2a-47b0-8dcc-bbfb7da5955a	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	2d6671d9-d94c-45aa-838d-38eb89c4abd3
eb53fcb5-1dcc-4ffb-94ab-21170706299d	Warehouse Associate	employee	\N	parttime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	ad05f631-172b-43dc-a4e4-7eadcce11f9b	2020-01-21 20:14:13.36874+00	2020-03-25 03:05:54.736038+00	61916ef9-6e2a-47b0-8dcc-bbfb7da5955a	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	2d6671d9-d94c-45aa-838d-38eb89c4abd3
26100c20-1051-4c24-94a9-1b45b46d8106	Operations Associate	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	18992680-8854-4b42-9b0b-3e06b2755c53	2020-01-16 00:39:26.479708+00	2020-03-25 03:05:54.736038+00	9d6a638d-7002-49d7-b9e5-745c5b819f16	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	2d6671d9-d94c-45aa-838d-38eb89c4abd3
e7e75d71-f120-420b-83c3-8b7053072e2b	Operations Associate	contingent	\N	contingent	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	18992680-8854-4b42-9b0b-3e06b2755c53	2020-01-22 00:04:13.123697+00	2020-03-25 03:05:54.736038+00	9d6a638d-7002-49d7-b9e5-745c5b819f16	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	2d6671d9-d94c-45aa-838d-38eb89c4abd3
c99b1513-0773-4d26-b954-77195722d40b	CEO	employee	\N	fulltime	filled	\N	b6f5de76-b09a-4091-add7-c4a72874c9d4	e55bba25-63f8-4650-b13a-cfe91b66c5a8	2020-03-05 22:29:37.276617+00	2020-03-25 03:05:54.736038+00	\N	\N	c1b769c8-dc45-4662-a408-de09ce621202	\N	46aeeef7-1b5e-4962-82d7-e939582d7032
08c0b2a5-b753-43bd-b542-27f2e9fea864	Sales Leader	employee	\N	fulltime	filled	\N	b6f5de76-b09a-4091-add7-c4a72874c9d4	fc5d6117-dffd-4a63-a7b3-a66e2dda9a86	2020-03-05 22:30:15.494202+00	2020-03-25 03:05:54.736038+00	c99b1513-0773-4d26-b954-77195722d40b	\N	c1b769c8-dc45-4662-a408-de09ce621202	\N	0b982233-ac65-4c19-91c7-a5db07135ad9
3bac7106-38eb-49e7-a390-ebc4944e4940	Operator	employee	\N	fulltime	filled	\N	b6f5de76-b09a-4091-add7-c4a72874c9d4	6b65fe3d-cdbf-4dd3-b3e0-a97be0c5dbd6	2020-03-05 22:30:15.494202+00	2020-03-25 03:05:54.736038+00	c99b1513-0773-4d26-b954-77195722d40b	\N	c1b769c8-dc45-4662-a408-de09ce621202	\N	0b982233-ac65-4c19-91c7-a5db07135ad9
be7c96ce-a98e-4d95-9b58-a0e67b9048dc	Head of Engineering	employee	\N	fulltime	filled	\N	b6f5de76-b09a-4091-add7-c4a72874c9d4	c68c6f7c-4163-4ccd-900f-eeedc786acf7	2020-03-05 22:30:15.494202+00	2020-03-25 03:05:54.736038+00	d17233ee-1b3a-4c33-bf61-daad198c8d80	\N	c1b769c8-dc45-4662-a408-de09ce621202	\N	0b982233-ac65-4c19-91c7-a5db07135ad9
d17233ee-1b3a-4c33-bf61-daad198c8d80	General Manager	employee	\N	fulltime	filled	\N	b6f5de76-b09a-4091-add7-c4a72874c9d4	941176eb-0abf-498d-99fe-82626bc23cea	2020-03-05 22:30:15.494202+00	2020-03-25 03:05:54.736038+00	c99b1513-0773-4d26-b954-77195722d40b	\N	c1b769c8-dc45-4662-a408-de09ce621202	\N	0b982233-ac65-4c19-91c7-a5db07135ad9
51a518c6-c6a7-479c-aa29-0a4c4e4e604c	Designer	contingent	\N	contingent	filled	\N	b6f5de76-b09a-4091-add7-c4a72874c9d4	2e0287cc-e49a-416b-ae13-595b37f016dc	2020-03-05 22:30:15.494202+00	2020-03-25 03:05:54.736038+00	d17233ee-1b3a-4c33-bf61-daad198c8d80	\N	c1b769c8-dc45-4662-a408-de09ce621202	\N	0b982233-ac65-4c19-91c7-a5db07135ad9
9c37c99a-134f-4145-8a72-0d59845e52a6	Head of Design	employee	\N	fulltime	filled	\N	b6f5de76-b09a-4091-add7-c4a72874c9d4	9e968199-8100-46f9-96c1-b51719c0fdca	2020-03-05 22:30:15.494202+00	2020-03-25 03:05:54.736038+00	d17233ee-1b3a-4c33-bf61-daad198c8d80	\N	c1b769c8-dc45-4662-a408-de09ce621202	\N	0b982233-ac65-4c19-91c7-a5db07135ad9
6224ee22-2c17-4170-a9cd-b48ce39ccc5e	Director of Technical Programs	contingent	\N	contingent	filled	\N	b6f5de76-b09a-4091-add7-c4a72874c9d4	6b65fe3d-cdbf-4dd3-b3e0-a97be0c5dbd6	2020-03-05 22:30:15.494202+00	2020-03-25 03:05:54.736038+00	c99b1513-0773-4d26-b954-77195722d40b	\N	c1b769c8-dc45-4662-a408-de09ce621202	\N	46aeeef7-1b5e-4962-82d7-e939582d7032
0c3bbd66-30ba-41d9-9b64-7dc6fa98129d	Chief Architect	employee	\N	fulltime	filled	\N	b6f5de76-b09a-4091-add7-c4a72874c9d4	6b65fe3d-cdbf-4dd3-b3e0-a97be0c5dbd6	2020-03-05 22:30:15.494202+00	2020-03-25 03:05:54.736038+00	c99b1513-0773-4d26-b954-77195722d40b	\N	c1b769c8-dc45-4662-a408-de09ce621202	\N	46aeeef7-1b5e-4962-82d7-e939582d7032
d58e3a38-be18-46b0-b4a1-003e0ee1d3d5	Operator	contingent	\N	contingent	filled	\N	b6f5de76-b09a-4091-add7-c4a72874c9d4	6b65fe3d-cdbf-4dd3-b3e0-a97be0c5dbd6	2020-03-05 22:30:15.494202+00	2020-03-25 03:05:54.736038+00	c99b1513-0773-4d26-b954-77195722d40b	\N	c1b769c8-dc45-4662-a408-de09ce621202	\N	46aeeef7-1b5e-4962-82d7-e939582d7032
8df905d1-2708-4e51-9892-a6aac09145cb	Operator	contingent	\N	contingent	filled	\N	b6f5de76-b09a-4091-add7-c4a72874c9d4	6b65fe3d-cdbf-4dd3-b3e0-a97be0c5dbd6	2020-03-05 22:30:15.494202+00	2020-03-25 03:05:54.736038+00	c99b1513-0773-4d26-b954-77195722d40b	\N	c1b769c8-dc45-4662-a408-de09ce621202	\N	46aeeef7-1b5e-4962-82d7-e939582d7032
23cdb40f-0e8e-4f93-9c1c-45db68262954	Analyst	contingent	\N	contingent	filled	\N	b6f5de76-b09a-4091-add7-c4a72874c9d4	2e0287cc-e49a-416b-ae13-595b37f016dc	2020-03-05 22:30:15.494202+00	2020-03-25 03:05:54.736038+00	d17233ee-1b3a-4c33-bf61-daad198c8d80	\N	c1b769c8-dc45-4662-a408-de09ce621202	\N	0b982233-ac65-4c19-91c7-a5db07135ad9
88cdaf24-838b-48d3-b068-55f7982f380e	Developer	contingent	\N	contingent	filled	\N	b6f5de76-b09a-4091-add7-c4a72874c9d4	c68c6f7c-4163-4ccd-900f-eeedc786acf7	2020-03-05 22:30:15.494202+00	2020-03-25 03:05:54.736038+00	be7c96ce-a98e-4d95-9b58-a0e67b9048dc	\N	c1b769c8-dc45-4662-a408-de09ce621202	\N	0b982233-ac65-4c19-91c7-a5db07135ad9
942c2ec8-7c17-4b93-9f91-9618a52bdb5d	Marketing Lead	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	01fda583-ff6a-42f8-9d3f-5355ba00f171	2020-04-06 20:30:48.911938+00	2020-04-06 20:46:44.256831+00	09318cdb-84c6-45b9-a4b4-cdd9b98f5852	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	81c09eca-58e2-4264-b126-929908174f1a
8e2725d6-97ac-49d9-85ca-2e0bb3f8f1ec	Sales Lead	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	f5aba46c-d433-451b-96aa-b2c355acec37	2020-04-06 20:30:48.911938+00	2020-04-06 20:46:44.256831+00	09318cdb-84c6-45b9-a4b4-cdd9b98f5852	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	81c09eca-58e2-4264-b126-929908174f1a
09318cdb-84c6-45b9-a4b4-cdd9b98f5852	President	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	ffcc0eec-d476-4404-ba13-7b2434bb1aa2	2020-04-06 20:30:48.911938+00	2020-04-06 20:46:44.256831+00	71fc94e3-abe0-47dc-9011-ab49597cfd6a	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	81c09eca-58e2-4264-b126-929908174f1a
3ff3eabd-1cdf-4b12-a584-c48ffd8e6a6a	Administrative Assistant	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	ffcc0eec-d476-4404-ba13-7b2434bb1aa2	2020-04-06 20:30:48.911938+00	2020-04-06 20:46:44.256831+00	09318cdb-84c6-45b9-a4b4-cdd9b98f5852	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	81c09eca-58e2-4264-b126-929908174f1a
3f546b05-ab42-40c1-b26c-12f9fb6903c4	Director Sales	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	f5aba46c-d433-451b-96aa-b2c355acec37	2020-04-06 20:30:48.911938+00	2020-04-06 20:46:44.256831+00	8e2725d6-97ac-49d9-85ca-2e0bb3f8f1ec	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	81c09eca-58e2-4264-b126-929908174f1a
05bfb8a7-57d0-437d-8add-11431378bb3a	Senior Engineer	employee	\N	fulltime	filled	\N	b6f5de76-b09a-4091-add7-c4a72874c9d4	c68c6f7c-4163-4ccd-900f-eeedc786acf7	2020-03-05 22:30:15.494202+00	2020-04-15 15:21:15.51743+00	be7c96ce-a98e-4d95-9b58-a0e67b9048dc	\N	c1b769c8-dc45-4662-a408-de09ce621202	\N	0b982233-ac65-4c19-91c7-a5db07135ad9
b4137674-1d40-4928-8fc2-78e1ea58f2de	Controller	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	d9968ee1-7871-486a-9f49-a870cac9b577	2020-04-06 20:30:48.911938+00	2020-04-06 20:46:44.256831+00	09318cdb-84c6-45b9-a4b4-cdd9b98f5852	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	81c09eca-58e2-4264-b126-929908174f1a
42543ea9-3e8f-4e0b-984c-351c6815732e	Director Sales	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	f5aba46c-d433-451b-96aa-b2c355acec37	2020-04-06 20:30:48.911938+00	2020-04-06 20:46:44.256831+00	8e2725d6-97ac-49d9-85ca-2e0bb3f8f1ec	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	81c09eca-58e2-4264-b126-929908174f1a
1de377e1-3ed2-4f0a-b3fc-f94597116af9	Senior Counsel	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	ad5c66ed-8528-40c4-81f3-19f6307c732f	2020-04-06 20:30:48.911938+00	2020-04-06 20:46:44.256831+00	09318cdb-84c6-45b9-a4b4-cdd9b98f5852	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	81c09eca-58e2-4264-b126-929908174f1a
451afcc0-43a3-45c3-a3a6-90427c926d0a	Director Sales	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	f5aba46c-d433-451b-96aa-b2c355acec37	2020-04-06 20:30:48.911938+00	2020-04-06 20:46:44.256831+00	8e2725d6-97ac-49d9-85ca-2e0bb3f8f1ec	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	81c09eca-58e2-4264-b126-929908174f1a
0c422fc8-5d1e-4a2f-bf58-d117b4e63bd5	Director Sales	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	f5aba46c-d433-451b-96aa-b2c355acec37	2020-04-06 20:30:48.911938+00	2020-04-06 20:46:44.256831+00	8e2725d6-97ac-49d9-85ca-2e0bb3f8f1ec	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	81c09eca-58e2-4264-b126-929908174f1a
c8893918-6ab4-4f32-aed6-10dec232d352	HR Lead	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	4f6c1ca9-dc2f-4d21-8d0c-79d5d5b7a1cf	2020-04-06 20:30:48.911938+00	2020-04-06 20:46:44.256831+00	09318cdb-84c6-45b9-a4b4-cdd9b98f5852	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	81c09eca-58e2-4264-b126-929908174f1a
785e15e1-13b9-4c08-816f-6de3961a8162	Senior Recruiter	contingent	\N	contingent	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	4f6c1ca9-dc2f-4d21-8d0c-79d5d5b7a1cf	2020-04-06 20:30:48.911938+00	2020-04-06 20:46:44.256831+00	c8893918-6ab4-4f32-aed6-10dec232d352	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	81c09eca-58e2-4264-b126-929908174f1a
d03f0aed-0e1e-4e34-bb90-591f5d7bb9e2	Analyst Help Desk	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	1c366c76-503c-45a2-960d-7a3252572b14	2020-04-06 20:30:48.911938+00	2020-04-06 20:46:44.256831+00	5415c0d5-def5-4424-9b42-a79884f99237	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	81c09eca-58e2-4264-b126-929908174f1a
5415c0d5-def5-4424-9b42-a79884f99237	Technology Lead	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	1c366c76-503c-45a2-960d-7a3252572b14	2020-04-06 20:30:48.911938+00	2020-04-06 20:46:44.256831+00	09318cdb-84c6-45b9-a4b4-cdd9b98f5852	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	81c09eca-58e2-4264-b126-929908174f1a
392b7354-2d68-45b5-bcac-6a3ce6704a85	Product Lead	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	2ce92c37-28e4-4dbf-98ed-6e46f73d1abc	2020-04-06 20:30:48.911938+00	2020-04-06 20:46:44.256831+00	09318cdb-84c6-45b9-a4b4-cdd9b98f5852	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	81c09eca-58e2-4264-b126-929908174f1a
8a0bb5d7-de23-4b34-b900-772a1a755edb	Senior Engineer III	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	2ce92c37-28e4-4dbf-98ed-6e46f73d1abc	2020-04-06 20:30:48.911938+00	2020-04-06 20:46:44.256831+00	392b7354-2d68-45b5-bcac-6a3ce6704a85	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	81c09eca-58e2-4264-b126-929908174f1a
1105f7ec-1658-41ea-9ebe-53caf72e9beb	Senior Engineer II	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	2ce92c37-28e4-4dbf-98ed-6e46f73d1abc	2020-04-06 20:30:48.911938+00	2020-04-06 20:46:44.256831+00	392b7354-2d68-45b5-bcac-6a3ce6704a85	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	81c09eca-58e2-4264-b126-929908174f1a
5f24abec-7db2-4691-939f-aef1acc6350c	Senior Engineer	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	2ce92c37-28e4-4dbf-98ed-6e46f73d1abc	2020-04-06 20:30:48.911938+00	2020-04-06 20:46:44.256831+00	392b7354-2d68-45b5-bcac-6a3ce6704a85	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	81c09eca-58e2-4264-b126-929908174f1a
7ab39d6a-2658-40f6-8f83-1ffafab9eb15	Inside Sales Manager	contingent	\N	contingent	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	581badcc-bed1-415e-bf4d-fda75ba6b888	2020-01-21 20:14:13.36874+00	2020-03-25 03:05:54.736038+00	f434ac6a-0621-4b49-a313-ae8801e54c86	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	fac15c2e-cce9-48f9-b818-10a2545020f4
7e5da5e4-38da-4132-8ba5-0175e13c59ad	Inside Sales Rep	contingent	\N	contingent	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	581badcc-bed1-415e-bf4d-fda75ba6b888	2020-01-22 00:04:13.123697+00	2020-03-25 03:05:54.736038+00	50445e70-7036-4dc2-bc1d-dbc8265caec3	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	fac15c2e-cce9-48f9-b818-10a2545020f4
476d4ae3-b5fc-4f9c-a910-2d5211f23b5e	Executive Admin	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	5df84a7b-1a23-4a93-87d4-1683ccc41d32	2020-01-16 00:30:26.308936+00	2020-03-25 03:05:54.736038+00	6ab88b8c-743d-429a-a678-e2db9b18bcec	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	fac15c2e-cce9-48f9-b818-10a2545020f4
beb4235f-387e-4e23-a41c-1a519656b15d	Office Manager	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	812502b1-6ad9-460d-ab7f-beaa69a9d497	2020-01-16 00:38:53.89372+00	2020-03-25 03:05:54.736038+00	4b5b2a54-040c-415a-bda7-3e029ed003a0	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	fac15c2e-cce9-48f9-b818-10a2545020f4
d9317b6f-309c-47d2-aec7-373e12062ecf	Manager Technical Support	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	0ce7d0a2-8674-4f8e-890b-2a3f206dc1c9	2020-01-16 00:37:58.695071+00	2020-03-25 03:05:54.736038+00	656d6161-73e9-45a0-90a0-0c8209374b9a	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	c10c8cb4-e212-47ce-96e5-4c077c530abd
36f6b85e-f4f1-4b28-a184-65c2b11fc78c	Analyst Customer Support	contingent	\N	contingent	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	c376b0a4-41df-4cc8-bdfc-a1bd070a6251	2020-01-22 00:04:13.123697+00	2020-03-25 03:05:54.736038+00	5c1c1645-806b-4383-a1bd-6b45a18e3785	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	c10c8cb4-e212-47ce-96e5-4c077c530abd
78ed9f38-448c-4d6e-b2da-a94d78884d33	Analyst Customer Support	contingent	\N	contingent	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	c376b0a4-41df-4cc8-bdfc-a1bd070a6251	2020-01-22 00:04:13.123697+00	2020-03-25 03:05:54.736038+00	5c1c1645-806b-4383-a1bd-6b45a18e3785	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	c10c8cb4-e212-47ce-96e5-4c077c530abd
7547cad2-7d70-4fcf-843b-6cf76a706cc8	Senior Engineer	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	2ce92c37-28e4-4dbf-98ed-6e46f73d1abc	2020-04-06 20:30:48.911938+00	2020-04-06 20:46:44.256831+00	392b7354-2d68-45b5-bcac-6a3ce6704a85	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	81c09eca-58e2-4264-b126-929908174f1a
e3dcd06d-a10b-4a93-bf65-68b0181d96d1	Senior Engineer III	contingent	\N	contingent	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	2ce92c37-28e4-4dbf-98ed-6e46f73d1abc	2020-04-06 20:30:48.911938+00	2020-04-06 20:46:44.256831+00	392b7354-2d68-45b5-bcac-6a3ce6704a85	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	81c09eca-58e2-4264-b126-929908174f1a
6bfb4af9-d6b2-41c4-9bfd-caf2a3801de3	Senior Engineer II	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	2ce92c37-28e4-4dbf-98ed-6e46f73d1abc	2020-04-06 20:30:48.911938+00	2020-04-06 20:46:44.256831+00	392b7354-2d68-45b5-bcac-6a3ce6704a85	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	81c09eca-58e2-4264-b126-929908174f1a
4a86391c-1136-4797-b919-c183a9755171	Senior Engineer II	contingent	\N	intern	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	2ce92c37-28e4-4dbf-98ed-6e46f73d1abc	2020-04-06 20:30:48.911938+00	2020-04-06 20:46:44.256831+00	392b7354-2d68-45b5-bcac-6a3ce6704a85	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	81c09eca-58e2-4264-b126-929908174f1a
c05ed09d-9a00-44d3-943b-aad1b020570e	Senior Engineer II	contingent	\N	contingent	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	2ce92c37-28e4-4dbf-98ed-6e46f73d1abc	2020-04-06 20:30:48.911938+00	2020-04-06 20:46:44.256831+00	392b7354-2d68-45b5-bcac-6a3ce6704a85	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	81c09eca-58e2-4264-b126-929908174f1a
ccea8963-af6b-4e2a-b34e-cbde6d855f1a	Engineer I	employee	\N	parttime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	2ce92c37-28e4-4dbf-98ed-6e46f73d1abc	2020-04-06 20:30:48.911938+00	2020-04-06 20:46:44.256831+00	392b7354-2d68-45b5-bcac-6a3ce6704a85	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	81c09eca-58e2-4264-b126-929908174f1a
c6d4ac13-1013-46c4-a3d8-0cb3b5e8a47e	Engineer II	employee	\N	parttime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	2ce92c37-28e4-4dbf-98ed-6e46f73d1abc	2020-04-06 20:30:48.911938+00	2020-04-06 20:46:44.256831+00	392b7354-2d68-45b5-bcac-6a3ce6704a85	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	81c09eca-58e2-4264-b126-929908174f1a
eec75af1-269c-4d9f-b7b1-0554a7aa19c1	Engineer II	employee	\N	parttime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	2ce92c37-28e4-4dbf-98ed-6e46f73d1abc	2020-04-06 20:30:48.911938+00	2020-04-06 20:46:44.256831+00	392b7354-2d68-45b5-bcac-6a3ce6704a85	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	81c09eca-58e2-4264-b126-929908174f1a
e25ca7ad-fbdd-4691-8594-b6ce11d78f3c	Analyst Customer Support	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	c376b0a4-41df-4cc8-bdfc-a1bd070a6251	2020-01-22 00:04:13.123697+00	2020-03-25 03:05:54.736038+00	5c1c1645-806b-4383-a1bd-6b45a18e3785	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	c10c8cb4-e212-47ce-96e5-4c077c530abd
dfdad657-a67f-4471-a951-c925297df211	VP Legal	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	e7b0dc35-9e86-467d-b3d1-4d49167a3a89	2020-01-16 00:44:00.135353+00	2020-03-25 03:05:54.736038+00	71fc94e3-abe0-47dc-9011-ab49597cfd6a	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	fac15c2e-cce9-48f9-b818-10a2545020f4
4b5b2a54-040c-415a-bda7-3e029ed003a0	VP Human Resource	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	ef5288f6-b3c0-4da7-8f64-2daa9737549a	2020-01-16 00:43:41.468804+00	2020-03-25 03:05:54.736038+00	71fc94e3-abe0-47dc-9011-ab49597cfd6a	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	fac15c2e-cce9-48f9-b818-10a2545020f4
e6226278-de8c-4e77-ad8a-4dcae725e667	VP Finance	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	dae2c97a-1f38-4834-ae40-4c33256b3b8d	2020-01-16 00:43:23.251296+00	2020-03-25 03:05:54.736038+00	71fc94e3-abe0-47dc-9011-ab49597cfd6a	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	fac15c2e-cce9-48f9-b818-10a2545020f4
de9550cb-657a-422e-a922-65920c6d70d1	Inside Sales Rep	contingent	\N	contingent	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	581badcc-bed1-415e-bf4d-fda75ba6b888	2020-01-16 00:32:02.740023+00	2020-03-25 03:05:54.736038+00	50445e70-7036-4dc2-bc1d-dbc8265caec3	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	fac15c2e-cce9-48f9-b818-10a2545020f4
1c83cbfe-1ebc-4a67-ab31-3090237e4a07	Manager Recruiting	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	24534a16-bda0-4ff6-a704-c552721c91d9	2020-01-16 00:36:50.963412+00	2020-03-25 03:05:54.736038+00	4b5b2a54-040c-415a-bda7-3e029ed003a0	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	fac15c2e-cce9-48f9-b818-10a2545020f4
347a454e-8d7d-4fc6-a82a-cfe404ffc525	Executive Admin	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	05fd3d9f-ce4e-4d93-afb5-e6fe0af280bc	2020-01-16 00:29:45.815871+00	2020-03-25 03:05:54.736038+00	71fc94e3-abe0-47dc-9011-ab49597cfd6a	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	fac15c2e-cce9-48f9-b818-10a2545020f4
9a4bb6c5-9e25-42e3-ba5e-4f90b22ed003	Senior Counsel	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	e7b0dc35-9e86-467d-b3d1-4d49167a3a89	2020-01-16 00:40:33.022456+00	2020-03-25 03:05:54.736038+00	dfdad657-a67f-4471-a951-c925297df211	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	fac15c2e-cce9-48f9-b818-10a2545020f4
0c372711-789c-48bc-8304-ac9f72dc6720	Staff Attorney	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	e7b0dc35-9e86-467d-b3d1-4d49167a3a89	2020-01-16 00:42:04.820267+00	2020-03-25 03:05:54.736038+00	dfdad657-a67f-4471-a951-c925297df211	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	fac15c2e-cce9-48f9-b818-10a2545020f4
b5884ce4-7f7d-4c64-87d4-9f094417c395	Manager Learning & Development	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	e5a95bfc-e227-4d81-9559-81026310d414	2020-01-16 00:35:39.734297+00	2020-03-25 03:05:54.736038+00	4b5b2a54-040c-415a-bda7-3e029ed003a0	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	fac15c2e-cce9-48f9-b818-10a2545020f4
301c40cd-ea72-421c-88dc-11ba59e400cc	Manager Compensation	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	359ac05c-19c7-4d2c-967b-5667a3c11dae	2020-01-16 00:34:06.645419+00	2020-03-25 03:05:54.736038+00	4b5b2a54-040c-415a-bda7-3e029ed003a0	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	fac15c2e-cce9-48f9-b818-10a2545020f4
a4f1ff36-88f7-453d-ba9d-fd00fa53c7df	HR Administrator	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	812502b1-6ad9-460d-ab7f-beaa69a9d497	2020-01-16 00:31:22.698332+00	2020-03-25 03:05:54.736038+00	4b5b2a54-040c-415a-bda7-3e029ed003a0	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	fac15c2e-cce9-48f9-b818-10a2545020f4
ca6405b9-0263-4f55-9efc-a744c2f1c123	Manager Accounting	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	3ff8f1ca-f908-48bb-bdc9-23bc17c9b79b	2020-01-16 00:33:39.331999+00	2020-03-25 03:05:54.736038+00	e6226278-de8c-4e77-ad8a-4dcae725e667	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	fac15c2e-cce9-48f9-b818-10a2545020f4
c64e8f33-f3ff-4e20-a92b-f8c54f808949	Financial Systems Manager	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	8c569e9d-9105-4552-b43c-2db52ce1cc41	2020-01-16 00:30:48.613384+00	2020-03-25 03:05:54.736038+00	e6226278-de8c-4e77-ad8a-4dcae725e667	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	fac15c2e-cce9-48f9-b818-10a2545020f4
eba3fb6f-6c46-432f-a314-921b54465e8e	Senior Controller	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	6ea0d2fe-0d72-430f-830f-cf200f53bf50	2020-01-16 00:40:16.860283+00	2020-03-25 03:05:54.736038+00	e6226278-de8c-4e77-ad8a-4dcae725e667	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	fac15c2e-cce9-48f9-b818-10a2545020f4
02aba96d-7de7-46e0-b02e-952a5adb9082	Accounts Payable Analyst	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	3ff8f1ca-f908-48bb-bdc9-23bc17c9b79b	2020-01-16 00:17:43.295455+00	2020-03-25 03:05:54.736038+00	ca6405b9-0263-4f55-9efc-a744c2f1c123	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	fac15c2e-cce9-48f9-b818-10a2545020f4
2eeaa908-0d10-4676-9143-4ef93d7c1695	Inside Sales Rep	contingent	\N	contingent	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	581badcc-bed1-415e-bf4d-fda75ba6b888	2020-01-21 20:14:13.36874+00	2020-03-25 03:05:54.736038+00	50445e70-7036-4dc2-bc1d-dbc8265caec3	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	fac15c2e-cce9-48f9-b818-10a2545020f4
69ab9f74-14bd-4596-889c-23b3043c4d39	Inside Sales Rep	employee	\N	parttime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	581badcc-bed1-415e-bf4d-fda75ba6b888	2020-01-22 00:04:13.123697+00	2020-03-25 03:05:54.736038+00	50445e70-7036-4dc2-bc1d-dbc8265caec3	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	fac15c2e-cce9-48f9-b818-10a2545020f4
f5e59d47-8e50-4461-b8f1-21a180ffaf5c	Inside Sales Rep	contingent	\N	intern	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	581badcc-bed1-415e-bf4d-fda75ba6b888	2020-01-22 00:04:13.123697+00	2020-03-25 03:05:54.736038+00	50445e70-7036-4dc2-bc1d-dbc8265caec3	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	fac15c2e-cce9-48f9-b818-10a2545020f4
e6bd5e8d-0b03-4763-847e-96462f0bd610	Inside Sales Rep	contingent	\N	intern	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	581badcc-bed1-415e-bf4d-fda75ba6b888	2020-01-22 00:04:13.123697+00	2020-03-25 03:05:54.736038+00	50445e70-7036-4dc2-bc1d-dbc8265caec3	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	fac15c2e-cce9-48f9-b818-10a2545020f4
27ad46e3-3b8a-4a7d-8f5e-0355edbc7d5a	Engineer Associate	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	c605f38c-e7b1-44c5-9a17-c099fdffddc0	2020-01-21 20:14:13.36874+00	2020-03-25 03:05:54.736038+00	918762d9-e398-4851-8565-e1244a378ba7	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	2d6671d9-d94c-45aa-838d-38eb89c4abd3
fdff6f69-117d-4834-8398-0c75b506d2a4	Supply Chain Coordinator	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	1d6daae3-4c3a-4661-b4a5-c2c8e0ae7159	2020-01-21 20:14:13.36874+00	2020-03-25 03:05:54.736038+00	6e4110c2-f77a-4636-8c2e-e3b9df409ec0	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	2d6671d9-d94c-45aa-838d-38eb89c4abd3
c660b8a8-8329-466c-9bac-2461984d52d2	Supply Chain Coordinator	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	1d6daae3-4c3a-4661-b4a5-c2c8e0ae7159	2020-01-21 20:14:13.36874+00	2020-03-25 03:05:54.736038+00	6e4110c2-f77a-4636-8c2e-e3b9df409ec0	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	2d6671d9-d94c-45aa-838d-38eb89c4abd3
9308f3e6-d1a4-4c1e-bd49-e2fdacffccc4	Supply Chain Coordinator	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	1d6daae3-4c3a-4661-b4a5-c2c8e0ae7159	2020-01-16 00:42:19.334996+00	2020-03-25 03:05:54.736038+00	6e4110c2-f77a-4636-8c2e-e3b9df409ec0	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	2d6671d9-d94c-45aa-838d-38eb89c4abd3
3e731f08-f2ae-408f-93e6-5dc08dd35b77	Supply Planner	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	1d6daae3-4c3a-4661-b4a5-c2c8e0ae7159	2020-01-16 00:42:37.480461+00	2020-03-25 03:05:54.736038+00	6e4110c2-f77a-4636-8c2e-e3b9df409ec0	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	2d6671d9-d94c-45aa-838d-38eb89c4abd3
87c08caa-f1ac-4e1d-b222-c2219d78007f	Maintenance Associate	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	972816d1-f849-435a-9224-cdb63fbd9604	2020-01-16 00:33:13.08539+00	2020-03-25 03:05:54.736038+00	8146e083-8198-4f06-9ddb-592d48187f68	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	2d6671d9-d94c-45aa-838d-38eb89c4abd3
f0145f4f-655a-44ef-8cba-691d220dd6c3	Quality Analyst	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	972816d1-f849-435a-9224-cdb63fbd9604	2020-01-21 20:14:13.36874+00	2020-03-25 03:05:54.736038+00	8146e083-8198-4f06-9ddb-592d48187f68	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	2d6671d9-d94c-45aa-838d-38eb89c4abd3
34748925-89e3-4410-8a66-15b63c54e6e7	Quality Analyst	contingent	\N	contingent	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	972816d1-f849-435a-9224-cdb63fbd9604	2020-01-16 00:39:42.122795+00	2020-03-25 03:05:54.736038+00	8146e083-8198-4f06-9ddb-592d48187f68	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	2d6671d9-d94c-45aa-838d-38eb89c4abd3
3a10356c-dee9-4c80-a732-d9df5e5cbf58	Quality Analyst	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	972816d1-f849-435a-9224-cdb63fbd9604	2020-01-21 20:14:13.36874+00	2020-03-25 03:05:54.736038+00	8146e083-8198-4f06-9ddb-592d48187f68	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	2d6671d9-d94c-45aa-838d-38eb89c4abd3
bc83f56d-49cf-401a-972a-0df09b625151	Director Sales	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	19b11d82-d683-4e2a-a1a8-3112b639ca67	2020-01-21 20:14:13.36874+00	2020-03-25 03:05:54.736038+00	6ab88b8c-743d-429a-a678-e2db9b18bcec	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N
7f8aad1e-ab04-4484-99ce-06aa83ce29ce	Inside Sales Manager	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	581badcc-bed1-415e-bf4d-fda75ba6b888	2020-01-22 00:17:30.252588+00	2020-03-25 03:05:54.736038+00	f434ac6a-0621-4b49-a313-ae8801e54c86	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	0aa76a1d-9516-413f-b311-fe0da3c9abf1
e910fac6-bc3d-4cc0-a9b7-faa62d7b7dc9	VP Technology	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	949eba96-7986-4576-89a2-6c8c01ea9615	2020-01-16 00:45:21.710119+00	2020-03-25 03:05:54.736038+00	71fc94e3-abe0-47dc-9011-ab49597cfd6a	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	0aa76a1d-9516-413f-b311-fe0da3c9abf1
cbc6c58d-f062-4d22-bc19-633ff50b777a	Director Cloud Infrastructure	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	5cc8118e-d37d-4248-a421-8689097e436a	2020-01-16 00:23:22.370138+00	2020-03-25 03:05:54.736038+00	e910fac6-bc3d-4cc0-a9b7-faa62d7b7dc9	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	0aa76a1d-9516-413f-b311-fe0da3c9abf1
16daff3f-4029-4a97-98ab-7d9aa437dbb7	Director Operations	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	466ed5b1-3a5d-47fe-a52b-227e0e51e061	2020-01-16 00:25:28.106741+00	2020-03-25 03:05:54.736038+00	e910fac6-bc3d-4cc0-a9b7-faa62d7b7dc9	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	0aa76a1d-9516-413f-b311-fe0da3c9abf1
2c264fe1-ab22-4478-9d1f-608c1a53056f	Director Software Development	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	e5dcf4b2-96af-4d8e-b770-cd9f76f34335	2020-01-21 20:14:13.36874+00	2020-03-25 03:05:54.736038+00	e910fac6-bc3d-4cc0-a9b7-faa62d7b7dc9	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	0aa76a1d-9516-413f-b311-fe0da3c9abf1
e7964b66-b9e0-49c8-ae2c-94102f8d0809	Director Information Security	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	41235a74-d402-4ccd-93cd-9d87625fd24a	2020-01-16 00:24:30.534567+00	2020-03-25 03:05:54.736038+00	e910fac6-bc3d-4cc0-a9b7-faa62d7b7dc9	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	0aa76a1d-9516-413f-b311-fe0da3c9abf1
7335607b-3369-40e9-a1d6-1cebd1f6def0	Engineer	employee	\N	fulltime	open	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	41235a74-d402-4ccd-93cd-9d87625fd24a	2020-01-17 23:01:26.992434+00	2020-03-25 03:05:54.736038+00	e7964b66-b9e0-49c8-ae2c-94102f8d0809	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	0aa76a1d-9516-413f-b311-fe0da3c9abf1
1776d9b5-b2dc-426c-8faa-b4ee47b9b3d5	Engineer	employee	\N	fulltime	open	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	41235a74-d402-4ccd-93cd-9d87625fd24a	2020-01-17 23:01:28.347515+00	2020-03-25 03:05:54.736038+00	e7964b66-b9e0-49c8-ae2c-94102f8d0809	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	0aa76a1d-9516-413f-b311-fe0da3c9abf1
ba4502d0-c96f-44d5-9ef7-879f07c4a35e	Senior Engineer	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	5cc8118e-d37d-4248-a421-8689097e436a	2020-01-16 00:41:51.769313+00	2020-03-25 03:05:54.736038+00	cbc6c58d-f062-4d22-bc19-633ff50b777a	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	0aa76a1d-9516-413f-b311-fe0da3c9abf1
d5511a4d-d073-4102-906e-502f8fb1c0df	Engineer	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	5cc8118e-d37d-4248-a421-8689097e436a	2020-01-21 20:14:13.36874+00	2020-03-25 03:05:54.736038+00	cbc6c58d-f062-4d22-bc19-633ff50b777a	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	0aa76a1d-9516-413f-b311-fe0da3c9abf1
7cdeab87-16ba-44c1-a898-f9070a0a05b0	Engineer	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	5cc8118e-d37d-4248-a421-8689097e436a	2020-01-16 00:27:58.921518+00	2020-03-25 03:05:54.736038+00	cbc6c58d-f062-4d22-bc19-633ff50b777a	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	0aa76a1d-9516-413f-b311-fe0da3c9abf1
006c8302-85ea-4e11-ae58-328a157ca31c	Senior Engineer	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	5cc8118e-d37d-4248-a421-8689097e436a	2020-01-21 20:14:13.36874+00	2020-03-25 03:05:54.736038+00	cbc6c58d-f062-4d22-bc19-633ff50b777a	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	0aa76a1d-9516-413f-b311-fe0da3c9abf1
68212386-1bf1-444d-9e11-42d4cc72ee28	Software Architect	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	5cc8118e-d37d-4248-a421-8689097e436a	2020-01-16 00:41:30.620656+00	2020-03-25 03:05:54.736038+00	cbc6c58d-f062-4d22-bc19-633ff50b777a	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	0aa76a1d-9516-413f-b311-fe0da3c9abf1
0d82e8be-0bee-4c1b-8244-7640170487d7	Analyst	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	5cc8118e-d37d-4248-a421-8689097e436a	2020-01-16 00:18:36.002558+00	2020-03-25 03:05:54.736038+00	cbc6c58d-f062-4d22-bc19-633ff50b777a	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	0aa76a1d-9516-413f-b311-fe0da3c9abf1
41deb728-5b6e-4072-9adc-3656a0fe705f	Analyst Help Desk	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	466ed5b1-3a5d-47fe-a52b-227e0e51e061	2020-01-17 22:59:21.199396+00	2020-03-25 03:05:54.736038+00	2f1bd1c8-ea43-46ab-8bda-34959ce6849f	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	0aa76a1d-9516-413f-b311-fe0da3c9abf1
14e36239-be02-4e84-af2b-d4348313d313	Analyst Help Desk	contingent	\N	contingent	open	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	466ed5b1-3a5d-47fe-a52b-227e0e51e061	2020-01-17 22:59:19.395138+00	2020-03-25 03:05:54.736038+00	2f1bd1c8-ea43-46ab-8bda-34959ce6849f	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	0aa76a1d-9516-413f-b311-fe0da3c9abf1
86145a3a-5b22-4ed8-a499-d0008b2bfe07	Analyst Help Desk	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	466ed5b1-3a5d-47fe-a52b-227e0e51e061	2020-01-17 22:59:07.672768+00	2020-03-25 03:05:54.736038+00	2f1bd1c8-ea43-46ab-8bda-34959ce6849f	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	0aa76a1d-9516-413f-b311-fe0da3c9abf1
3ffaa5b1-fc16-4c0f-a7a2-9aaa67e70932	Senior Analyst	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	e5dcf4b2-96af-4d8e-b770-cd9f76f34335	2020-01-16 00:40:01.074957+00	2020-03-25 03:05:54.736038+00	2c264fe1-ab22-4478-9d1f-608c1a53056f	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	0aa76a1d-9516-413f-b311-fe0da3c9abf1
66d0b7c4-b700-43f2-882b-0188be510f56	Manager Software Development	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	e5dcf4b2-96af-4d8e-b770-cd9f76f34335	2020-01-16 00:37:06.52539+00	2020-03-25 03:05:54.736038+00	2c264fe1-ab22-4478-9d1f-608c1a53056f	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	0aa76a1d-9516-413f-b311-fe0da3c9abf1
150940dd-9a4b-4767-bf06-aac8c5829c79	Engineer	contingent	\N	contingent	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	e5dcf4b2-96af-4d8e-b770-cd9f76f34335	2020-01-21 20:14:13.36874+00	2020-03-25 03:05:54.736038+00	66d0b7c4-b700-43f2-882b-0188be510f56	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	0aa76a1d-9516-413f-b311-fe0da3c9abf1
ac3eea63-1238-4e6e-910e-8b9fde560f15	Engineer	contingent	\N	contingent	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	e5dcf4b2-96af-4d8e-b770-cd9f76f34335	2020-01-16 00:28:16.581354+00	2020-03-25 03:05:54.736038+00	66d0b7c4-b700-43f2-882b-0188be510f56	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	0aa76a1d-9516-413f-b311-fe0da3c9abf1
f643319d-654b-4a57-9995-ce113b831bba	Engineer	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	e5dcf4b2-96af-4d8e-b770-cd9f76f34335	2020-01-21 20:14:13.36874+00	2020-03-25 03:05:54.736038+00	66d0b7c4-b700-43f2-882b-0188be510f56	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	0aa76a1d-9516-413f-b311-fe0da3c9abf1
a88a793d-4a67-47bf-964c-532e642e0a42	Senior Engineer	contingent	\N	contingent	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	e5dcf4b2-96af-4d8e-b770-cd9f76f34335	2020-01-16 00:41:10.848939+00	2020-03-25 03:05:54.736038+00	2c264fe1-ab22-4478-9d1f-608c1a53056f	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	0aa76a1d-9516-413f-b311-fe0da3c9abf1
82a747c1-4e13-4ee0-803e-f66f05ad841e	Analyst Business Development	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	19921661-9a3f-46be-948d-093c098442a8	2020-01-16 00:18:55.341345+00	2020-04-09 20:12:25.997881+00	db85f397-a133-4c1d-8a7b-087aa2515022	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N
71fc94e3-abe0-47dc-9011-ab49597cfd6a	Chief Executive Officer	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	05fd3d9f-ce4e-4d93-afb5-e6fe0af280bc	2020-01-16 00:20:44.910964+00	2020-03-25 03:05:54.736038+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	fac15c2e-cce9-48f9-b818-10a2545020f4
2568cea7-c8e1-4276-8372-13e9379e65f2	Accountant	contingent	\N	contingent	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	6ea0d2fe-0d72-430f-830f-cf200f53bf50	2020-01-16 00:16:38.366592+00	2020-03-25 03:05:54.736038+00	eba3fb6f-6c46-432f-a314-921b54465e8e	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	fac15c2e-cce9-48f9-b818-10a2545020f4
79be7ad7-ef59-4695-962c-c48c52f48203	Manager Customer Success	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	bb86daa7-e1cd-420f-939f-fbe7e7c325ac	2020-01-16 00:34:23.395557+00	2020-03-25 03:05:54.736038+00	656d6161-73e9-45a0-90a0-0c8209374b9a	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	c10c8cb4-e212-47ce-96e5-4c077c530abd
c006c39a-9747-45a8-a374-dc60cf41059d	UX Manager	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	0df51c70-fc23-490e-8173-c6b869fb2911	2020-01-16 00:42:54.571839+00	2020-03-25 03:05:54.736038+00	174776b6-91ca-4ddc-84be-a3776b6fd38f	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	23409dd4-7cd3-4073-971a-12b48be6885e
bdd09c05-1dc4-4f4b-9ff0-56a59a33ac14	Manager Events	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	96987261-8cf5-4a3f-9349-d9e70ea6dfc0	2020-01-16 00:35:05.892128+00	2020-03-25 03:05:54.736038+00	4b5b2a54-040c-415a-bda7-3e029ed003a0	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	80d65bb1-46bd-4b1a-b52f-3ee81a6f4ca5
c849b002-e627-4b98-8044-6375c181d616	Graphic Designer	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	d9e83b30-6eab-4260-8f04-43ad4385d3ba	2020-01-16 00:31:04.76418+00	2020-03-25 03:05:54.736038+00	7c68ead2-22a9-40c9-9fc9-f07b18ba1d52	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	80d65bb1-46bd-4b1a-b52f-3ee81a6f4ca5
4b36b1a3-b05c-449a-a47a-bd1947ea7560	Intern Public Relations	contingent	\N	intern	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	27cef2cd-183a-4515-889b-9ac8c4823ded	2020-01-16 00:32:56.332833+00	2020-03-25 03:05:54.736038+00	13464fbc-2f34-4b23-868f-8748541a4e95	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	80d65bb1-46bd-4b1a-b52f-3ee81a6f4ca5
0572d363-57cd-4a74-aac1-a2077c4f12f5	Events Coordinator	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	96987261-8cf5-4a3f-9349-d9e70ea6dfc0	2020-01-16 00:29:15.476448+00	2020-03-25 03:05:54.736038+00	bdd09c05-1dc4-4f4b-9ff0-56a59a33ac14	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	80d65bb1-46bd-4b1a-b52f-3ee81a6f4ca5
54d6162e-bad1-482c-8ba6-69231ca94feb	Graphic Designer	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	d9e83b30-6eab-4260-8f04-43ad4385d3ba	2020-01-22 00:04:13.123697+00	2020-03-25 03:05:54.736038+00	7c68ead2-22a9-40c9-9fc9-f07b18ba1d52	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	80d65bb1-46bd-4b1a-b52f-3ee81a6f4ca5
13534b17-9116-4c69-beaa-20186db16e6b	Director Sales	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	19b11d82-d683-4e2a-a1a8-3112b639ca67	2020-01-21 20:14:13.36874+00	2020-03-25 03:05:54.736038+00	6ab88b8c-743d-429a-a678-e2db9b18bcec	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N
174edffb-c983-454a-b103-b003f8df814b	VP Operations	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	6ec6cb34-d4dc-4be0-9ef3-e08067d357ff	2020-01-16 00:44:27.962999+00	2020-03-25 03:05:54.736038+00	71fc94e3-abe0-47dc-9011-ab49597cfd6a	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	2d6671d9-d94c-45aa-838d-38eb89c4abd3
6394342f-2a41-47db-ba58-f601573b3cae	Senior Engineer	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	e5dcf4b2-96af-4d8e-b770-cd9f76f34335	2020-01-21 20:14:13.36874+00	2020-03-25 03:05:54.736038+00	2c264fe1-ab22-4478-9d1f-608c1a53056f	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	0aa76a1d-9516-413f-b311-fe0da3c9abf1
6ab88b8c-743d-429a-a678-e2db9b18bcec	VP Sales	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	5df84a7b-1a23-4a93-87d4-1683ccc41d32	2020-01-16 00:45:07.908012+00	2020-03-25 03:05:54.736038+00	71fc94e3-abe0-47dc-9011-ab49597cfd6a	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N
9494375f-ece9-4ff4-acf8-00aaee3abcde	Director Sales	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	19b11d82-d683-4e2a-a1a8-3112b639ca67	2020-01-21 20:14:13.36874+00	2020-03-25 03:05:54.736038+00	6ab88b8c-743d-429a-a678-e2db9b18bcec	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N
413bce4a-a2ee-41aa-9c3c-8f9ce7c49787	Director Sales	contingent	\N	contingent	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	19b11d82-d683-4e2a-a1a8-3112b639ca67	2020-01-21 20:14:13.36874+00	2020-03-25 03:05:54.736038+00	6ab88b8c-743d-429a-a678-e2db9b18bcec	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N
766cc64a-31a4-4a38-ba79-f9fe5c7401e0	Warehouse Associate	contingent	\N	contingent	open	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	ad05f631-172b-43dc-a4e4-7eadcce11f9b	2020-01-17 22:56:04.092578+00	2020-03-25 03:05:54.736038+00	61916ef9-6e2a-47b0-8dcc-bbfb7da5955a	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N
94b69297-a2d7-4f60-8719-7657397c015f	Analyst Help Desk	contingent	\N	contingent	open	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	466ed5b1-3a5d-47fe-a52b-227e0e51e061	2020-01-16 21:11:39.508558+00	2020-03-25 03:05:54.736038+00	2f1bd1c8-ea43-46ab-8bda-34959ce6849f	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N
5792476a-72a6-447c-9f95-f3fd602028bf	Manager Engingeering	contingent	\N	contingent	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	c605f38c-e7b1-44c5-9a17-c099fdffddc0	2020-01-21 20:10:11.39721+00	2020-03-25 03:05:54.736038+00	174edffb-c983-454a-b103-b003f8df814b	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N
9d6a638d-7002-49d7-b9e5-745c5b819f16	Manager Operations	employee	\N	fulltime	open	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	18992680-8854-4b42-9b0b-3e06b2755c53	2020-01-16 00:35:58.110681+00	2020-03-25 03:05:54.736038+00	ddc97a88-0eb4-4109-8970-925a198f433a	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N
7914b09e-7527-472a-a71b-36fb38f8c4bc	VP Product	employee	\N	fulltime	closed	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	a88934bf-8ebe-4bc3-8d6a-4e70f56423c5	2020-01-21 20:14:13.36874+00	2020-03-25 03:05:54.736038+00	71fc94e3-abe0-47dc-9011-ab49597cfd6a	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N
5538f11d-5797-4201-8a98-5ef855c02369	Engineer	employee	\N	fulltime	open	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	41235a74-d402-4ccd-93cd-9d87625fd24a	2020-01-17 23:01:29.457576+00	2020-03-25 03:05:54.736038+00	e7964b66-b9e0-49c8-ae2c-94102f8d0809	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N
54493000-ba3c-4965-9102-cd88a56125f2	Engineer Associate	contingent	\N	contingent	open	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	c605f38c-e7b1-44c5-9a17-c099fdffddc0	2020-01-16 00:28:37.388025+00	2020-03-25 03:05:54.736038+00	918762d9-e398-4851-8565-e1244a378ba7	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N
ac129cad-623a-46dc-bada-9c237e9ab88b	UX Manager	employee	\N	fulltime	closed	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	0df51c70-fc23-490e-8173-c6b869fb2911	2020-01-21 20:14:13.36874+00	2020-03-25 03:05:54.736038+00	174776b6-91ca-4ddc-84be-a3776b6fd38f	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N
ab394429-10e3-40cc-9f46-c08fdedce6f4	Analyst Help Desk	contingent	\N	contingent	open	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	41235a74-d402-4ccd-93cd-9d87625fd24a	2020-01-16 00:19:50.752025+00	2020-03-25 03:05:54.736038+00	e7964b66-b9e0-49c8-ae2c-94102f8d0809	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N
2fb79b80-539e-445b-9186-b17a78d0053f	Financial Systems Manager	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	8c569e9d-9105-4552-b43c-2db52ce1cc41	2020-01-21 20:14:13.36874+00	2020-03-25 03:05:54.736038+00	e6226278-de8c-4e77-ad8a-4dcae725e667	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N
c9fba268-4596-4c87-888f-66876213c76c	Senior Counsel	employee	\N	fulltime	closed	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	e7b0dc35-9e86-467d-b3d1-4d49167a3a89	2020-01-21 20:14:13.36874+00	2020-03-25 03:05:54.736038+00	dfdad657-a67f-4471-a951-c925297df211	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N
22ffe4c4-e139-4909-8c8c-d067db9b8dc9	Manager Supply Chain	contingent	\N	contingent	open	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	1d6daae3-4c3a-4661-b4a5-c2c8e0ae7159	2020-01-21 20:14:13.36874+00	2020-03-25 03:05:54.736038+00	174edffb-c983-454a-b103-b003f8df814b	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N
842f959a-2694-470b-a176-347b1e6fef73	Director Public Relations	employee	\N	fulltime	closed	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	27cef2cd-183a-4515-889b-9ac8c4823ded	2020-01-16 00:26:04.521613+00	2020-03-25 03:05:54.736038+00	c57b5e1b-090c-466f-b655-c81c3a61a8fa	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N
eaa9badd-a587-4319-b518-680891647bb8	Warehouse Associate	contingent	\N	intern	open	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	ad05f631-172b-43dc-a4e4-7eadcce11f9b	2020-01-17 22:56:05.981521+00	2020-03-25 03:05:54.736038+00	61916ef9-6e2a-47b0-8dcc-bbfb7da5955a	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N
2ab8dcfe-d9bf-494d-903b-3f898e152fae	HR Administrator	contingent	\N	contingent	closed	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	812502b1-6ad9-460d-ab7f-beaa69a9d497	2020-01-21 20:14:13.36874+00	2020-03-25 03:05:54.736038+00	4b5b2a54-040c-415a-bda7-3e029ed003a0	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N
6f632cfc-0353-4ec7-8c5a-869912d48f53	Inside Sales Rep	employee	\N	parttime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	581badcc-bed1-415e-bf4d-fda75ba6b888	2020-01-21 20:14:13.36874+00	2020-03-25 03:05:54.736038+00	50445e70-7036-4dc2-bc1d-dbc8265caec3	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	fac15c2e-cce9-48f9-b818-10a2545020f4
f71c1291-e153-40fc-ad48-fdb98f472535	Analyst Customer Success	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	bb86daa7-e1cd-420f-939f-fbe7e7c325ac	2020-01-22 00:04:13.123697+00	2020-03-25 03:05:54.736038+00	79be7ad7-ef59-4695-962c-c48c52f48203	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	c10c8cb4-e212-47ce-96e5-4c077c530abd
e44bf447-b407-4c5a-8e4f-1bfaff3b6284	Analyst Customer Success	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	bb86daa7-e1cd-420f-939f-fbe7e7c325ac	2020-01-22 00:04:13.123697+00	2020-03-25 03:05:54.736038+00	79be7ad7-ef59-4695-962c-c48c52f48203	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	c10c8cb4-e212-47ce-96e5-4c077c530abd
cf2e0a13-f434-4bb4-b0e1-246fa32b455b	Analyst Customer Success	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	bb86daa7-e1cd-420f-939f-fbe7e7c325ac	2020-01-21 20:14:13.36874+00	2020-03-25 03:05:54.736038+00	79be7ad7-ef59-4695-962c-c48c52f48203	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	c10c8cb4-e212-47ce-96e5-4c077c530abd
be0077ef-9c90-4d9f-b2c7-db22477b41ca	Analyst Business Development	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	19921661-9a3f-46be-948d-093c098442a8	2020-01-21 21:18:07.376581+00	2020-03-25 03:05:54.736038+00	db85f397-a133-4c1d-8a7b-087aa2515022	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	80d65bb1-46bd-4b1a-b52f-3ee81a6f4ca5
329a0c8a-1f53-4e39-a1f5-2fa47de01c27	Director Sales	contingent	\N	contingent	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	19b11d82-d683-4e2a-a1a8-3112b639ca67	2020-01-21 20:14:13.36874+00	2020-03-25 03:05:54.736038+00	6ab88b8c-743d-429a-a678-e2db9b18bcec	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N
ddc97a88-0eb4-4109-8970-925a198f433a	Director Warehouse Management	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	ad05f631-172b-43dc-a4e4-7eadcce11f9b	2020-01-16 00:27:22.337149+00	2020-03-25 03:05:54.736038+00	174edffb-c983-454a-b103-b003f8df814b	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	2d6671d9-d94c-45aa-838d-38eb89c4abd3
229e5d75-880e-4621-bbc5-f853eb488e8c	Director Operations	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	01cc47f4-7f9e-459b-9c33-8f59e7fc10bb	2020-01-16 00:25:09.26452+00	2020-03-25 03:05:54.736038+00	174edffb-c983-454a-b103-b003f8df814b	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	2d6671d9-d94c-45aa-838d-38eb89c4abd3
ac0174f0-6567-4603-aae0-3d1f180076f9	Manager Receiving	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	f971304f-31a2-450f-ae6c-300c86eb561b	2020-01-16 00:36:30.46982+00	2020-03-25 03:05:54.736038+00	ddc97a88-0eb4-4109-8970-925a198f433a	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	2d6671d9-d94c-45aa-838d-38eb89c4abd3
918762d9-e398-4851-8565-e1244a378ba7	Manager Engineering	contingent	\N	contingent	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	c605f38c-e7b1-44c5-9a17-c099fdffddc0	2020-01-16 00:34:46.248835+00	2020-03-25 03:05:54.736038+00	229e5d75-880e-4621-bbc5-f853eb488e8c	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	2d6671d9-d94c-45aa-838d-38eb89c4abd3
6e4110c2-f77a-4636-8c2e-e3b9df409ec0	Manager Supply Chain	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	1d6daae3-4c3a-4661-b4a5-c2c8e0ae7159	2020-01-16 00:37:22.625434+00	2020-03-25 03:05:54.736038+00	174edffb-c983-454a-b103-b003f8df814b	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	2d6671d9-d94c-45aa-838d-38eb89c4abd3
8146e083-8198-4f06-9ddb-592d48187f68	Manager Quality	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	972816d1-f849-435a-9224-cdb63fbd9604	2020-01-16 00:36:14.752028+00	2020-03-25 03:05:54.736038+00	229e5d75-880e-4621-bbc5-f853eb488e8c	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	2d6671d9-d94c-45aa-838d-38eb89c4abd3
7638e755-2717-4a37-90f5-be0be944cb8e	Warehouse Associate	contingent	\N	intern	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	ad05f631-172b-43dc-a4e4-7eadcce11f9b	2020-01-21 20:14:13.36874+00	2020-03-25 03:05:54.736038+00	61916ef9-6e2a-47b0-8dcc-bbfb7da5955a	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	2d6671d9-d94c-45aa-838d-38eb89c4abd3
f89b7264-48f4-4294-a54b-b6cd18666634	Warehouse Associate	contingent	\N	contingent	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	ad05f631-172b-43dc-a4e4-7eadcce11f9b	2020-01-17 22:55:48.32834+00	2020-03-25 03:05:54.736038+00	61916ef9-6e2a-47b0-8dcc-bbfb7da5955a	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	2d6671d9-d94c-45aa-838d-38eb89c4abd3
cde5c705-7cac-4b0a-b4d2-4eae660ced02	Manager Accounting	contingent	\N	contingent	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	3ff8f1ca-f908-48bb-bdc9-23bc17c9b79b	2020-01-21 20:14:13.36874+00	2020-03-25 03:05:54.736038+00	e6226278-de8c-4e77-ad8a-4dcae725e667	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N
53fb0198-61ba-4ee4-952e-1a5a379e56d2	VP Human Resource	employee	\N	fulltime	closed	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	ef5288f6-b3c0-4da7-8f64-2daa9737549a	2020-01-21 20:14:13.36874+00	2020-03-25 03:05:54.736038+00	71fc94e3-abe0-47dc-9011-ab49597cfd6a	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N
4700995e-c5ae-4f23-830f-2782211caa18	Senior Data Analyst	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	8c569e9d-9105-4552-b43c-2db52ce1cc41	2020-01-21 20:14:13.36874+00	2020-03-25 03:05:54.736038+00	c64e8f33-f3ff-4e20-a92b-f8c54f808949	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N
41a795ba-4ca8-43b3-8d20-2b6e3867753c	Warehouse Associate	employee	\N	parttime	open	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	ad05f631-172b-43dc-a4e4-7eadcce11f9b	2020-01-17 22:56:02.515311+00	2020-03-25 03:05:54.736038+00	61916ef9-6e2a-47b0-8dcc-bbfb7da5955a	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N
aa87772c-b758-492d-a83d-a83680d3c273	VP Technology	employee	\N	fulltime	closed	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	949eba96-7986-4576-89a2-6c8c01ea9615	2020-01-21 20:14:13.36874+00	2020-03-25 03:05:54.736038+00	71fc94e3-abe0-47dc-9011-ab49597cfd6a	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N
53eeb44b-9f36-44d9-8826-0b4e04a74cb8	Engineer	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	41235a74-d402-4ccd-93cd-9d87625fd24a	2020-01-22 00:04:13.123697+00	2020-03-25 03:05:54.736038+00	e7964b66-b9e0-49c8-ae2c-94102f8d0809	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N
2f1bd1c8-ea43-46ab-8bda-34959ce6849f	Manager Help Desk	employee	\N	fulltime	open	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	466ed5b1-3a5d-47fe-a52b-227e0e51e061	2020-01-16 00:35:21.873846+00	2020-03-25 03:05:54.736038+00	16daff3f-4029-4a97-98ab-7d9aa437dbb7	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N
00dd39b7-61c6-401c-996a-51311125d7b6	Warehouse Associate	employee	\N	parttime	open	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	ad05f631-172b-43dc-a4e4-7eadcce11f9b	2020-01-17 22:56:06.84073+00	2020-03-25 03:05:54.736038+00	61916ef9-6e2a-47b0-8dcc-bbfb7da5955a	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N
61916ef9-6e2a-47b0-8dcc-bbfb7da5955a	Manager Warehouse Management	employee	\N	fulltime	open	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	ad05f631-172b-43dc-a4e4-7eadcce11f9b	2020-01-16 00:38:16.685161+00	2020-03-25 03:05:54.736038+00	ddc97a88-0eb4-4109-8970-925a198f433a	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N
1d19af47-050d-4501-b77f-639c8bcd5a35	Analyst Help Desk	contingent	\N	contingent	open	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	466ed5b1-3a5d-47fe-a52b-227e0e51e061	2020-01-17 22:59:22.687602+00	2020-03-25 03:05:54.736038+00	2f1bd1c8-ea43-46ab-8bda-34959ce6849f	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N
385336fb-a4c0-4ee3-9af3-12cc3577d0d3	Warehouse Associate	contingent	\N	contingent	open	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	ad05f631-172b-43dc-a4e4-7eadcce11f9b	2020-01-17 22:56:05.086454+00	2020-03-25 03:05:54.736038+00	61916ef9-6e2a-47b0-8dcc-bbfb7da5955a	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N
a2c94ff3-211c-41d1-89f5-30a8c5234719	Senior Analyst	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	e5dcf4b2-96af-4d8e-b770-cd9f76f34335	2020-01-21 20:14:13.36874+00	2020-03-25 03:05:54.736038+00	2c264fe1-ab22-4478-9d1f-608c1a53056f	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N
e6876808-f359-49f8-bf35-7261e6ea6dd1	Director Data Analytics	employee	\N	fulltime	open	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	8498910c-13d7-4428-9394-d8c82947a07b	2020-01-17 22:51:19.739275+00	2020-03-25 03:05:54.736038+00	e910fac6-bc3d-4cc0-a9b7-faa62d7b7dc9	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N
19a24a73-4fae-4bfa-a703-bed7b7a2302f	Director Software Development	contingent	\N	contingent	closed	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	e5dcf4b2-96af-4d8e-b770-cd9f76f34335	2020-01-16 00:26:43.479858+00	2020-03-25 03:05:54.736038+00	e910fac6-bc3d-4cc0-a9b7-faa62d7b7dc9	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N
07e8e4ee-7ecd-4bd8-92ac-6199e10cb30c	Director Operations	employee	\N	fulltime	closed	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	466ed5b1-3a5d-47fe-a52b-227e0e51e061	2020-01-21 20:14:13.36874+00	2020-03-25 03:05:54.736038+00	e910fac6-bc3d-4cc0-a9b7-faa62d7b7dc9	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N
9a452cff-e095-449f-ba8c-b475fbd419ea	Manager Events	contingent	\N	contingent	closed	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	96987261-8cf5-4a3f-9349-d9e70ea6dfc0	2020-01-21 20:14:13.36874+00	2020-03-25 03:05:54.736038+00	4b5b2a54-040c-415a-bda7-3e029ed003a0	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N
02dbd1b5-84b8-45a8-b4b8-155246c6b09e	Manager Quality	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	972816d1-f849-435a-9224-cdb63fbd9604	2020-01-21 20:14:13.36874+00	2020-03-25 03:05:54.736038+00	ddc97a88-0eb4-4109-8970-925a198f433a	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N
f63a74e5-9d36-477f-9b3b-6eda0d03398c	Director Information Security	employee	\N	fulltime	closed	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	41235a74-d402-4ccd-93cd-9d87625fd24a	2020-01-21 20:14:13.36874+00	2020-03-25 03:05:54.736038+00	e910fac6-bc3d-4cc0-a9b7-faa62d7b7dc9	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N
605af5e7-ed53-48a2-9c2f-def7cea806ff	Analyst Help Desk	contingent	\N	contingent	open	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	466ed5b1-3a5d-47fe-a52b-227e0e51e061	2020-01-21 20:14:13.36874+00	2020-03-25 03:05:54.736038+00	2f1bd1c8-ea43-46ab-8bda-34959ce6849f	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N
e1338ce9-cf81-493a-b805-975d9ad43c8d	Director Cloud Infrastructure	employee	\N	fulltime	closed	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	5cc8118e-d37d-4248-a421-8689097e436a	2020-01-21 20:14:13.36874+00	2020-03-25 03:05:54.736038+00	e910fac6-bc3d-4cc0-a9b7-faa62d7b7dc9	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N
2414d0cf-38d4-464d-9aac-f43840a2d6bd	Warehouse Associate	contingent	\N	contingent	open	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	ad05f631-172b-43dc-a4e4-7eadcce11f9b	2020-01-17 22:55:59.246968+00	2020-03-25 03:05:54.736038+00	61916ef9-6e2a-47b0-8dcc-bbfb7da5955a	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N
44b732ef-168c-4a00-8589-fc374ee10d32	Director Product Management	contingent	\N	contingent	closed	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	d2fcf8f8-40b6-4c8f-808f-b96e35f544a7	2020-01-21 20:14:13.36874+00	2020-03-25 03:05:54.736038+00	e6f9d1cb-d759-4bf5-99bd-e258bf11bfb0	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N
1d0abf01-0128-40f0-82cb-14903782bd42	Copywriter	employee	\N	fulltime	filled	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	d9e83b30-6eab-4260-8f04-43ad4385d3ba	2020-01-21 20:14:13.36874+00	2020-03-25 03:05:54.736038+00	7c68ead2-22a9-40c9-9fc9-f07b18ba1d52	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N
71dc6f67-389a-4904-b672-ee921456aa50	Engineer	employee	\N	fulltime	open	\N	72cba849-77bc-48ff-bfb1-93e5552d538e	41235a74-d402-4ccd-93cd-9d87625fd24a	2020-01-16 00:27:41.056174+00	2020-03-25 03:05:54.736038+00	e7964b66-b9e0-49c8-ae2c-94102f8d0809	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N
\.


--
-- Data for Name: position_status; Type: TABLE DATA; Schema: public; Owner: doadmin
--

COPY public.position_status (value) FROM stdin;
open
closed
filled
\.


--
-- Data for Name: position_subtype; Type: TABLE DATA; Schema: public; Owner: doadmin
--

COPY public.position_subtype (value) FROM stdin;
employee
contingent
\.


--
-- Data for Name: position_time_type; Type: TABLE DATA; Schema: public; Owner: doadmin
--

COPY public.position_time_type (value) FROM stdin;
contingent
fulltime
parttime
intern
\.


--
-- Data for Name: positionsancestors; Type: TABLE DATA; Schema: public; Owner: doadmin
--

COPY public.positionsancestors (position_id, ancestor_id) FROM stdin;
\.


--
-- Data for Name: profile; Type: TABLE DATA; Schema: public; Owner: doadmin
--

COPY public.profile (id, name, job_family, compensation_grade, created_at, updated_at, customer_id) FROM stdin;
\.


--
-- Data for Name: user; Type: TABLE DATA; Schema: public; Owner: doadmin
--

COPY public."user" (id, auth0_user_id, created_at, updated_at, customer_id) FROM stdin;
ab91de1b-c164-4b11-8208-0454ed502b64	auth0|5e1786e32d35050e9f248fcb	2020-01-15 18:48:45.729815+00	2020-03-15 13:08:13.079942+00	f304e1bd-4ea5-496a-9644-76c2eb9e7483
68bf1cec-1e8c-4423-a2c2-4ceaf838ae9c	auth0|5e0e50dcc2d6b70e6960e5d1	2020-01-15 18:49:30.302545+00	2020-03-15 13:12:03.746934+00	f304e1bd-4ea5-496a-9644-76c2eb9e7483
33ceb3f3-8900-4ba1-a43a-a0379b64c89d	auth0|5e31a8dbc343950c9ac998d1	2020-01-15 18:49:15.93655+00	2020-03-15 13:19:38.396195+00	f304e1bd-4ea5-496a-9644-76c2eb9e7483
378c61b3-f562-4261-836c-f0f0409b8151	auth0|5e31ccc216a0870e7e13893b	2020-01-15 18:49:07.7714+00	2020-03-15 13:30:16.926211+00	f304e1bd-4ea5-496a-9644-76c2eb9e7483
a0b2387d-fe2e-4701-bd6a-2129de8066e0	auth0|5e4616418a409e0e620251b1	2020-03-15 13:45:30.671255+00	2020-03-15 13:45:30.671255+00	f304e1bd-4ea5-496a-9644-76c2eb9e7483
1083f326-768a-4fb1-a873-5cfdedbb30f7	auth0|5e4d6c4ec2b30f0e84a9bece	2020-03-15 13:45:30.671255+00	2020-03-15 13:45:30.671255+00	f304e1bd-4ea5-496a-9644-76c2eb9e7483
564518fd-80cc-4590-85d2-4823d6ae60f7	auth0|5e66cde3265b4d0d7f130dea	2020-03-15 13:45:30.671255+00	2020-03-15 13:45:30.671255+00	f304e1bd-4ea5-496a-9644-76c2eb9e7483
feda7213-71b7-434f-a614-5ad898f34997	auth0|5e6e4b53cfee7f0c95b02429	2020-03-15 15:38:10.23111+00	2020-03-15 15:38:10.23111+00	c1b769c8-dc45-4662-a408-de09ce621202
\.


--
-- Data for Name: worker; Type: TABLE DATA; Schema: public; Owner: doadmin
--

COPY public.worker (id, first_name, last_name, user_id, email, phone, created_at, updated_at, status, address_id, location_id, is_remote, gender, avatar_url, dob, hire_date, customer_id, employee_number, mobile, mobile_country_code, work_phone, work_phone_country_code, work_phone_extension) FROM stdin;
41faa9b6-4495-4329-93ca-392d26d4907c	Almeria	Thomas	\N	AThomas@techcore.com	4255677000	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	510fb161-cf02-4012-a348-0d6f45f52114	fac15c2e-cce9-48f9-b818-10a2545020f4	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/41faa9b6-4495-4329-93ca-392d26d4907c.png	\N	2015-03-15	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
dbabdea2-cbd8-4f47-8856-df9b49751d59	Angela	Palmer	\N	APalmer@techcore.com	8013339742	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	e091fbb7-dc73-424e-b6a3-f6eafa96e29f	0aa76a1d-9516-413f-b311-fe0da3c9abf1	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/dbabdea2-cbd8-4f47-8856-df9b49751d59.png	\N	2013-08-17	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
0e760390-f472-4d20-bf75-4d1aa335b5bd	Angie	Anderson	\N	AAnderson@techcore.com	3058835675	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	db8892e9-3051-4252-be4c-410a5aa057f2	2d6671d9-d94c-45aa-838d-38eb89c4abd3	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/0e760390-f472-4d20-bf75-4d1aa335b5bd.png	\N	2010-05-18	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
aafcc14a-cc7a-4299-a0ae-2007b9692e0a	Anthony	Butler	\N	AButler@techcore.com	4258776570	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	a4482a1c-1936-45e1-a7bb-f6939dce2312	fac15c2e-cce9-48f9-b818-10a2545020f4	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/aafcc14a-cc7a-4299-a0ae-2007b9692e0a.png	\N	2013-10-16	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
7d40d0ae-66ab-4c19-ab89-4104e43b7730	Antonietta	Gonzalez	\N	AGonzalez@techcore.com	8013333968	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	e8daeb9c-2b62-41e5-a02a-0f2fcd03d955	0aa76a1d-9516-413f-b311-fe0da3c9abf1	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/7d40d0ae-66ab-4c19-ab89-4104e43b7730.png	\N	2016-09-14	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
1d64d466-9d07-48ec-a392-e503ebc2fdb6	Arleen	Patterson	\N	alpatterson@techcore.com	5122226402	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	bb07d671-5158-45a3-ad8a-4a31c4b8ba0d	23409dd4-7cd3-4073-971a-12b48be6885e	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/1d64d466-9d07-48ec-a392-e503ebc2fdb6.png	\N	2019-07-04	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
b05bcf40-4ab7-4380-acc4-9dfe5d772d39	Bel	James	\N	BJames@techcore.com	8572927789	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	99a5c52f-fd4f-43c9-a353-c56983d4d118	80d65bb1-46bd-4b1a-b52f-3ee81a6f4ca5	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/b05bcf40-4ab7-4380-acc4-9dfe5d772d39.png	\N	2010-07-13	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
2e419ecd-a12b-4f5c-b19c-3ab50b6daf99	Brigid	Long	\N	BLong@techcore.com	8004452673	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	426c706c-2c2d-4859-b527-eda4dcc83850	c10c8cb4-e212-47ce-96e5-4c077c530abd	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/2e419ecd-a12b-4f5c-b19c-3ab50b6daf99.png	\N	2018-09-11	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
81b74550-4251-48e9-a2d6-6f7caef01c75	Damon	Ross	\N	DRoss@techcore.com	8004452673	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	4d9a64a9-61b3-4077-a33e-0c819f1cd017	c10c8cb4-e212-47ce-96e5-4c077c530abd	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/81b74550-4251-48e9-a2d6-6f7caef01c75.png	\N	2015-10-22	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
78ab6b35-536d-4943-83c4-ff2bbfa5df4b	Dave	Olson	\N	DOlson@techcore.com	4255677000	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	c22f2878-8f7e-4af8-aa57-18d54abbd4f7	fac15c2e-cce9-48f9-b818-10a2545020f4	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/78ab6b35-536d-4943-83c4-ff2bbfa5df4b.png	\N	2015-03-15	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
94f3db5a-a3c3-4bcd-8945-34baa1beac0d	Dee	Campbell	\N	DCampbell@techcore.com	3058835674	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	2c68c3a1-c68e-4b66-84c1-bb78063ead59	2d6671d9-d94c-45aa-838d-38eb89c4abd3	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/94f3db5a-a3c3-4bcd-8945-34baa1beac0d.png	\N	2013-11-26	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
d299489c-3371-4afd-8755-f2cb10db8b57	Delia	Weaver	\N	DWeaver@techcore.com	4255671601	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	f2bbaf89-a0ee-4879-918d-ff049ced4661	fac15c2e-cce9-48f9-b818-10a2545020f4	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/d299489c-3371-4afd-8755-f2cb10db8b57.png	\N	2010-03-01	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
a18dfae2-259f-4d9e-a846-3b1d44830fe7	Doralynne	Mitchell	\N	DMitchell@techcore.com	4253151016	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	299803f3-6d8b-47d1-9955-26e904e42e7a	fac15c2e-cce9-48f9-b818-10a2545020f4	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/a18dfae2-259f-4d9e-a846-3b1d44830fe7.png	\N	2011-02-08	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
66201a46-db33-473a-96a1-9aef06975180	Dorine	Perkins	\N	DPerkins@techcore.com	8138765654	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	35487025-e7c1-4514-b449-1a69e96a9d4c	c10c8cb4-e212-47ce-96e5-4c077c530abd	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/66201a46-db33-473a-96a1-9aef06975180.png	\N	2015-09-23	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
db41d0e1-c2b9-42ef-9bd3-857c16a30549	Drew	Gomez	\N	DGomez@techcore.com	4152957783	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	6b82b10a-e9bb-498e-9ae5-aaf2c7884843	\N	t	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/db41d0e1-c2b9-42ef-9bd3-857c16a30549.png	\N	2015-04-04	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
07eb6f1d-edab-4ef8-9c35-cc903bd4857a	Emily	Rea	\N	erea@techcore.uk.co	\N	2020-04-07 21:27:50.333705+00	2020-04-07 21:27:50.333705+00	active	1b8ac3e7-cca1-43fb-915d-b485bab15e4c	81c09eca-58e2-4264-b126-929908174f1a	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/07eb6f1d-edab-4ef8-9c35-cc903bd4857a.jpeg	\N	2019-03-03	f304e1bd-4ea5-496a-9644-76c2eb9e7483	85-7974238	7776790771	44	8296169500	44	103
109db868-b090-4a65-91f8-a2057af23efd	Salomé	De Maria	\N	sdemaria@techcore.uk.co	\N	2020-04-07 21:27:50.333705+00	2020-04-07 21:27:50.333705+00	active	a31d20e7-a68e-4e38-bc3f-eff77ae53d92	81c09eca-58e2-4264-b126-929908174f1a	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/109db868-b090-4a65-91f8-a2057af23efd.jpg	\N	2011-02-27	f304e1bd-4ea5-496a-9644-76c2eb9e7483	65-8734030	4778986282	44	8296169500	44	104
18c6943d-d03e-4a00-9a19-3b85d110b7be	Thomas	Rushforth	\N	trushforth@techcore.uk.co	\N	2020-04-07 21:27:50.333705+00	2020-04-07 21:27:50.333705+00	active	7a63e871-fa74-4e13-b2ed-700763bb148b	81c09eca-58e2-4264-b126-929908174f1a	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/18c6943d-d03e-4a00-9a19-3b85d110b7be.jpg	\N	2019-08-01	f304e1bd-4ea5-496a-9644-76c2eb9e7483	38-0088703	9231629111	44	8296169500	44	105
240abdea-f613-49b6-8b69-0ec0bd02fddc	Maëlla	Yuryaev	\N	myuryaev@techcore.uk.co	\N	2020-04-07 21:27:50.333705+00	2020-04-07 21:27:50.333705+00	active	803730a8-ce18-4345-9145-ad8b9d515a70	81c09eca-58e2-4264-b126-929908174f1a	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/240abdea-f613-49b6-8b69-0ec0bd02fddc.jpg	\N	2016-05-24	f304e1bd-4ea5-496a-9644-76c2eb9e7483	15-2676677	4696667703	44	8296169500	44	106
359177b3-d52c-4321-867e-2a89d2b78a56	Alfie	Weld	\N	aweld@techcore.uk.co	\N	2020-04-07 21:27:50.333705+00	2020-04-07 21:27:50.333705+00	active	e9fed9a4-f9ea-4a34-aca0-5aed767ac6da	81c09eca-58e2-4264-b126-929908174f1a	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/359177b3-d52c-4321-867e-2a89d2b78a56.jpeg	\N	2019-01-09	f304e1bd-4ea5-496a-9644-76c2eb9e7483	83-7521144	8664858577	44	8296169500	44	107
3639b340-37fa-4b82-9e22-e008658cc79d	Hélèna	Adamovitz	\N	hadamovitz@techcore.uk.co	\N	2020-04-07 21:27:50.333705+00	2020-04-07 21:27:50.333705+00	active	d8ef0def-e67e-4636-b38a-6139f4926c53	81c09eca-58e2-4264-b126-929908174f1a	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/3639b340-37fa-4b82-9e22-e008658cc79d.jpg	\N	2017-10-15	f304e1bd-4ea5-496a-9644-76c2eb9e7483	29-8346863	9698530394	44	8296169500	44	108
391d3848-defd-4aeb-a188-ada5d4ea7926	Gisèle	Kaley	\N	gkaley@techcore.uk.co	\N	2020-04-07 21:27:50.333705+00	2020-04-07 21:27:50.333705+00	active	43a4e4a6-f7ce-4b9c-988f-8c3f9c2a0ccf	81c09eca-58e2-4264-b126-929908174f1a	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/391d3848-defd-4aeb-a188-ada5d4ea7926.jpeg	\N	2020-01-15	f304e1bd-4ea5-496a-9644-76c2eb9e7483	59-8939073	8031339232	44	8296169500	44	109
4edca5e3-2937-40f0-b0dd-871e59dc04ba	Chloe	Hriinchenko	\N	chriinchenko@techcore.uk.co	\N	2020-04-07 21:27:50.333705+00	2020-04-07 21:27:50.333705+00	active	0c6f272d-05f6-4238-be5d-9e964e22d581	81c09eca-58e2-4264-b126-929908174f1a	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/4edca5e3-2937-40f0-b0dd-871e59dc04ba.jpg	\N	2011-06-09	f304e1bd-4ea5-496a-9644-76c2eb9e7483	04-2628088	2012993733	44	8296169500	44	110
082e9b3b-574a-4031-a98f-4dec17460291	Al	Patterson	\N	APatterson@techcore.com	8013337317	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	a02a3468-1b2c-48d9-9056-8c30af8014b5	0aa76a1d-9516-413f-b311-fe0da3c9abf1	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/082e9b3b-574a-4031-a98f-4dec17460291.png	\N	2016-08-22	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
5fed4868-3369-4880-adbe-6d59007a9c2c	Eda	Evans	\N	EEvans@techcore.com	8013339765	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	3e5b82f5-de08-4efd-a002-e26c23892f5d	0aa76a1d-9516-413f-b311-fe0da3c9abf1	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/5fed4868-3369-4880-adbe-6d59007a9c2c.png	\N	2015-11-14	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
6d9cfd2d-f110-429c-becd-95af311544b4	Effie	Stevens	\N	EStevens@techcore.com	8004452673	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	461f2d14-a7b2-401e-bc85-991b0619edb9	c10c8cb4-e212-47ce-96e5-4c077c530abd	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/6d9cfd2d-f110-429c-becd-95af311544b4.png	\N	2015-10-06	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
99697a6e-ecd2-4063-b235-afd698921c9e	Elsa	Snyder	\N	ESnyder@techcore.com	3058835669	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	d9ea79ac-4f3e-4dd9-a48d-df7a166976b4	2d6671d9-d94c-45aa-838d-38eb89c4abd3	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/99697a6e-ecd2-4063-b235-afd698921c9e.png	\N	2013-04-26	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
8e31c1ff-e087-4c7f-a367-feadc19fb7db	Emmalyn	Powell	\N	EPowell@techcore.com	8138765547	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	5c0e2485-af8a-40d1-ad66-137dc73d5836	c10c8cb4-e212-47ce-96e5-4c077c530abd	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/8e31c1ff-e087-4c7f-a367-feadc19fb7db.png	\N	2016-08-29	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
2f49e79f-98b0-438d-ac4b-d2c847a3027f	Erna	Perry	\N	EPerry@techcore.com	8013339013	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	f7d90977-7a58-4bc9-b6be-f3fca23f8b40	0aa76a1d-9516-413f-b311-fe0da3c9abf1	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/2f49e79f-98b0-438d-ac4b-d2c847a3027f.png	\N	2019-07-10	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
358d5760-1767-4dd0-890c-92753f4bc2e5	Fania	Barnes	\N	FBarnes@techcore.com	3058835600	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	704c3063-1c1c-465f-a512-93a1b44a8047	2d6671d9-d94c-45aa-838d-38eb89c4abd3	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/358d5760-1767-4dd0-890c-92753f4bc2e5.png	\N	2016-11-17	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
37f4c73c-20de-4438-bd20-725092240179	Ferne	Adams	\N	FAdams@techcore.com	8013335446	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	1e92bffb-fea3-4660-a97c-0aefed04e98d	0aa76a1d-9516-413f-b311-fe0da3c9abf1	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/37f4c73c-20de-4438-bd20-725092240179.png	\N	2015-03-25	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
7d7c5155-9acc-4b6a-8b77-f9926566a7bb	Frankie	Foster	\N	FFoster@techcore.com	8572927786	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	5a31ed63-7f88-40d6-b8a9-8073bb11adee	80d65bb1-46bd-4b1a-b52f-3ee81a6f4ca5	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/7d7c5155-9acc-4b6a-8b77-f9926566a7bb.png	\N	2010-12-17	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
71daca88-28ed-43b9-bfe5-48d6614d7985	Gerda	Fisher	\N	GFisher@techcore.com	3058835600	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	bc8a6699-467b-448f-991f-ca9e4001d0bc	2d6671d9-d94c-45aa-838d-38eb89c4abd3	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/71daca88-28ed-43b9-bfe5-48d6614d7985.png	\N	2014-05-30	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
3b738df3-b5c7-4598-809d-e55bb73152f0	Geri	Smith	\N	GSmith@techcore.com	8013336536	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	e9431c21-c402-46ee-839b-6cb22469c1de	0aa76a1d-9516-413f-b311-fe0da3c9abf1	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/3b738df3-b5c7-4598-809d-e55bb73152f0.png	\N	2015-04-01	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
95a6b551-549a-4268-85a2-ae48d1816852	Giralda	Black	\N	GBlack@techcore.com	8013339553	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	6a4a9fd3-b1ff-4087-80a6-d8e9988312e2	0aa76a1d-9516-413f-b311-fe0da3c9abf1	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/95a6b551-549a-4268-85a2-ae48d1816852.png	\N	2015-08-28	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
9884669c-912e-4301-8abb-fad814aa5120	Glynnis	Miller	\N	GMiller@techcore.com	8572927788	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	9cd961f0-9cd6-4e53-ac09-0608678089ec	80d65bb1-46bd-4b1a-b52f-3ee81a6f4ca5	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/9884669c-912e-4301-8abb-fad814aa5120.png	\N	2010-03-16	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
5fd8b4b2-c7a9-41c1-8dfa-31dd5ae62fda	Grethel	Harris	\N	GHarris@techcore.com	4258230511	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	d110e7df-9b21-41af-9053-7fc4b9a0bca5	fac15c2e-cce9-48f9-b818-10a2545020f4	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/5fd8b4b2-c7a9-41c1-8dfa-31dd5ae62fda.png	\N	2012-07-19	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
8339f6c2-2d0e-4a8c-8384-2a2a9f3f3c3a	Gwennie	Butler	\N	GButler@techcore.com	4255671677	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	2644803f-663b-4279-9d63-b170af15a4d7	fac15c2e-cce9-48f9-b818-10a2545020f4	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/8339f6c2-2d0e-4a8c-8384-2a2a9f3f3c3a.png	\N	2013-05-11	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
db2f994e-3fa3-4599-b55f-17585fa7f09f	Harriot	Collins	\N	HCollins@techcore.com	8572927792	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	6117ec8c-0619-445d-a5a8-d785e0d9f105	80d65bb1-46bd-4b1a-b52f-3ee81a6f4ca5	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/db2f994e-3fa3-4599-b55f-17585fa7f09f.png	\N	2018-08-30	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
35e2d654-6ac7-4ae6-88a7-c699eaf89d33	Hetty	Smith	\N	HSmith@techcore.com	8572927787	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	a906d85c-b357-4cac-bada-c017e5fb62c8	80d65bb1-46bd-4b1a-b52f-3ee81a6f4ca5	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/35e2d654-6ac7-4ae6-88a7-c699eaf89d33.png	\N	2018-08-03	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
14adc0e8-e37c-43f5-9a3e-7a6bea64514d	Idalina	Perez	\N	IPerez@techcore.com	3058835677	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	cde0c1b3-85fc-463b-8bea-f466cd3fde7f	2d6671d9-d94c-45aa-838d-38eb89c4abd3	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/14adc0e8-e37c-43f5-9a3e-7a6bea64514d.png	\N	2011-05-11	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
bc4e7385-133d-49fa-a1e0-2594cee7f858	Jacob	Smith	\N	JSmith@techcore.com	3058835673	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	71c4aa67-ab0d-471f-9387-2e0608d512e7	2d6671d9-d94c-45aa-838d-38eb89c4abd3	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/bc4e7385-133d-49fa-a1e0-2594cee7f858.png	\N	2017-05-28	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
1ca6d0d9-b599-42ab-b38f-3cc1414946f5	James	Lopez	\N	JLopez@techcore.com	3058835678	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	9697e7ab-e7f1-45e9-ac9d-6ad072316e83	2d6671d9-d94c-45aa-838d-38eb89c4abd3	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/1ca6d0d9-b599-42ab-b38f-3cc1414946f5.png	\N	2010-12-24	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
a9dbef18-3568-4243-bdd4-573f0240f79b	Javier	Daniels	\N	JDaniels@techcore.com	4255671665	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	76c0aac5-b596-4c70-9759-7080a0df1de2	fac15c2e-cce9-48f9-b818-10a2545020f4	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/a9dbef18-3568-4243-bdd4-573f0240f79b.png	\N	2013-12-28	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
8f3e7f09-414b-49de-8203-89e4331404a4	Jayson	Harper	\N	JHarper@techcore.com	5124267991	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	ead0776d-8efa-45f0-9fbe-be3551318f11	23409dd4-7cd3-4073-971a-12b48be6885e	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/8f3e7f09-414b-49de-8203-89e4331404a4.png	\N	2013-06-20	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
d2263269-9059-4507-98a1-a135958e3911	Jeanne	Wright	\N	JWright@techcore.com	8013334886	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	6a8ede7b-65ae-4b1f-a009-fc5c00f37c18	0aa76a1d-9516-413f-b311-fe0da3c9abf1	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/d2263269-9059-4507-98a1-a135958e3911.png	\N	2019-02-12	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
5dd187cf-c6d4-40ae-b323-fef8ede3213d	Mary	Henke	\N	mhenke@techcore.uk.co	\N	2020-04-07 21:27:50.333705+00	2020-04-07 21:27:50.333705+00	active	9aca07ba-4e40-4e13-909a-7755fa4946a4	81c09eca-58e2-4264-b126-929908174f1a	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/5dd187cf-c6d4-40ae-b323-fef8ede3213d.jpg	\N	2014-12-04	f304e1bd-4ea5-496a-9644-76c2eb9e7483	78-9299903	2075086229	44	8296169500	44	111
7de1e69d-d1be-45b0-a526-d0cd4d1637e2	Agata	Watkins	\N	AWatkins@techcore.com	8138765510	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	1edbaf02-f94c-4e13-b858-241f1531e0df	c10c8cb4-e212-47ce-96e5-4c077c530abd	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/7de1e69d-d1be-45b0-a526-d0cd4d1637e2.png	\N	2017-08-16	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
42495344-a2dd-4fdc-85cb-00be6f956588	Jeannie	Williams	\N	JWilliams@techcore.com	4257848833	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	ee98b6a9-bce6-4a16-8fb1-e4ce729d125e	fac15c2e-cce9-48f9-b818-10a2545020f4	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/42495344-a2dd-4fdc-85cb-00be6f956588.png	\N	2012-11-28	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
067bfb87-ad52-4dbf-8e10-d899060bb71c	Jennifer	Gomez	\N	JGomez@techcore.com	4253150827	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	826a2c15-efd5-47c8-835f-95691134f93f	fac15c2e-cce9-48f9-b818-10a2545020f4	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/067bfb87-ad52-4dbf-8e10-d899060bb71c.png	\N	2011-10-03	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
7c8050be-223e-4b5e-8b26-7e61af1928d6	Jeri	Brown	\N	JBrown@techcore.com	3058835600	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	b94ba442-ca4c-4bbb-b9bb-c5ba0f5c4a39	2d6671d9-d94c-45aa-838d-38eb89c4abd3	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/7c8050be-223e-4b5e-8b26-7e61af1928d6.png	\N	2011-01-10	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
d64bbef0-0c57-46b5-b06a-92b41c23ab90	Joceline	Stone	\N	JStone@techcore.com	8572927783	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	931da550-248f-4fdd-bcb1-3331ae7e10d6	80d65bb1-46bd-4b1a-b52f-3ee81a6f4ca5	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/d64bbef0-0c57-46b5-b06a-92b41c23ab90.png	\N	2016-12-04	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
58169734-aa36-4301-8541-1bf6729cebcd	Johna	Ortiz	\N	JOrtiz@techcore.com	8013333934	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	fab28b28-0bd1-46ef-9e12-32ee9eb5bef4	0aa76a1d-9516-413f-b311-fe0da3c9abf1	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/58169734-aa36-4301-8541-1bf6729cebcd.png	\N	2017-05-06	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
cc319918-9dd9-44e2-b431-775e854df581	Karole	Martinez	\N	KMartinez@techcore.com	4255677000	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	5608148b-81da-4a3a-9919-cacc61a66196	fac15c2e-cce9-48f9-b818-10a2545020f4	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/cc319918-9dd9-44e2-b431-775e854df581.png	\N	2015-03-15	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
d2059b84-398e-41d2-afab-f6537d2ad3a0	Kayley	Mills	\N	KMills@techcore.com	3058835668	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	dcaed78f-cd72-474d-931d-123984733fd9	2d6671d9-d94c-45aa-838d-38eb89c4abd3	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/d2059b84-398e-41d2-afab-f6537d2ad3a0.png	\N	2015-06-07	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
4d8ae02b-a6af-449d-a2ce-43e56cb12a36	Kelsey	Peters	\N	KPeters@techcore.com	3058835672	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	1662e504-8f25-48c7-8f46-ecbe45ab5b60	2d6671d9-d94c-45aa-838d-38eb89c4abd3	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/4d8ae02b-a6af-449d-a2ce-43e56cb12a36.png	\N	2016-12-21	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
6b9e2d45-2320-4060-bfd5-28634479dfc1	Keslie	Diaz	\N	KDiaz@techcore.com	8004452673	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	7f35a7d9-b5df-4684-ada6-06c2e3b2fd85	c10c8cb4-e212-47ce-96e5-4c077c530abd	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/6b9e2d45-2320-4060-bfd5-28634479dfc1.png	\N	2019-04-16	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
decadbb0-ac38-4903-a445-2732a0467915	Ketti	Martin	\N	KMartin@techcore.com	4255677677	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	133825fa-5860-429e-9575-d2709e0fe999	fac15c2e-cce9-48f9-b818-10a2545020f4	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/decadbb0-ac38-4903-a445-2732a0467915.png	\N	2018-05-17	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
dd0cbc03-be03-48ff-9f70-db7626075b6f	Laurel	Lane	\N	LLane@techcore.com	8013336953	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	fe4c3956-42a5-482c-8db3-4a1ad0284cea	0aa76a1d-9516-413f-b311-fe0da3c9abf1	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/dd0cbc03-be03-48ff-9f70-db7626075b6f.png	\N	2010-04-28	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
0021da48-8a44-48fb-b2d7-eaeb717b6241	Leann	Ramos	\N	LRamos@techcore.com	5039727765	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	d89272d2-0bb5-41b7-b77f-9f6a9c074cc2	\N	t	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/0021da48-8a44-48fb-b2d7-eaeb717b6241.png	\N	2014-09-20	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
a2ed7452-ff32-4f5b-83a3-61c892a43b18	Leonard	Allen	\N	LAllen@techcore.com	8572927791	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	c9a57608-3e15-44ec-b178-0753017145b7	80d65bb1-46bd-4b1a-b52f-3ee81a6f4ca5	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/a2ed7452-ff32-4f5b-83a3-61c892a43b18.png	\N	2019-02-18	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
8de5a622-8471-4013-9400-a59dd97c69cf	Leslie	Williams	\N	LWilliams@techcore.com	2147677727	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	eeb3e3a1-726c-4aa3-b9e9-c9022b8de7d0	\N	t	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/8de5a622-8471-4013-9400-a59dd97c69cf.png	\N	2019-02-26	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
0fd1a480-6fc4-40f3-a79d-8e4ad43cb4bf	Lin	Spencer	\N	LSpencer@techcore.com	4258230827	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	926d872f-e7a3-4246-88fe-c691d7c41fc3	fac15c2e-cce9-48f9-b818-10a2545020f4	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/0fd1a480-6fc4-40f3-a79d-8e4ad43cb4bf.png	\N	2012-05-12	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
de457c0b-63b8-489e-9475-b153f335c200	Mallory	Flores	\N	MFlores@techcore.com	8013336188	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	586bcc2d-34cc-4587-994f-fd03113e15b7	0aa76a1d-9516-413f-b311-fe0da3c9abf1	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/de457c0b-63b8-489e-9475-b153f335c200.png	\N	2017-01-25	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
24e52226-9f5b-4de0-9be0-254bb50584e2	Marco	Price	\N	MPrice@techcore.com	8013336146	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	94170717-c3c8-448a-b607-6b3236306ad9	0aa76a1d-9516-413f-b311-fe0da3c9abf1	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/24e52226-9f5b-4de0-9be0-254bb50584e2.png	\N	2019-02-13	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
672c179b-81af-4252-8317-798f37cfaeec	Marena	Snyder	\N	MSnyder@techcore.com	8013337678	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	d5f1e423-9d32-4ff9-849c-a5cbe8ccf4f5	0aa76a1d-9516-413f-b311-fe0da3c9abf1	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/672c179b-81af-4252-8317-798f37cfaeec.png	\N	2016-01-18	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
d4719f90-8ea8-4681-a445-cc58ab593450	Mary	Lee	\N	MLee@techcore.com	5124260837	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	7fdcd965-4c43-4ddc-8d1f-72e877b6e3e6	23409dd4-7cd3-4073-971a-12b48be6885e	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/d4719f90-8ea8-4681-a445-cc58ab593450.png	\N	2017-08-08	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
7c11c074-7968-44c7-88b6-cb1462d91f2f	Melvin	Jones	\N	MJones@techcore.com	5128505209	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	803d7758-b1e5-42eb-8680-807cb48be90a	23409dd4-7cd3-4073-971a-12b48be6885e	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/7c11c074-7968-44c7-88b6-cb1462d91f2f.png	\N	2017-02-10	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
0f6322aa-4f54-47e0-9f48-844e96733f86	Meriel	Robinson	\N	MRobinson@techcore.com	4255671630	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	3a2fa755-9ae7-431b-a01c-37ff86d3b264	fac15c2e-cce9-48f9-b818-10a2545020f4	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/0f6322aa-4f54-47e0-9f48-844e96733f86.png	\N	2019-07-27	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
0908b890-968b-427d-a6da-b37f67d0ee03	Merrill	Rodriguez	\N	MRodriguez@techcore.com	8004452673	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	aba905b9-27b2-4f8a-9d8b-9cf0e32c636f	c10c8cb4-e212-47ce-96e5-4c077c530abd	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/0908b890-968b-427d-a6da-b37f67d0ee03.png	\N	2018-08-13	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
5f00a5a7-c3a2-44a6-9007-b40ae36abb7b	Joshua	Serchwell	\N	jserchwell@techcore.uk.co	\N	2020-04-07 21:27:50.333705+00	2020-04-07 21:27:50.333705+00	active	57390a98-a797-4973-975c-ddf7db613b0f	81c09eca-58e2-4264-b126-929908174f1a	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/5f00a5a7-c3a2-44a6-9007-b40ae36abb7b.jpeg	\N	2015-02-15	f304e1bd-4ea5-496a-9644-76c2eb9e7483	78-3158168	2643466134	44	8296169500	44	112
9f940688-ee63-4ccf-a8fb-0cc4314b11bf	Michell	Owens	\N	MOwens@techcore.com	3058835670	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	ffcaac2f-5e34-4a41-a117-ba6412e2f6ae	2d6671d9-d94c-45aa-838d-38eb89c4abd3	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/9f940688-ee63-4ccf-a8fb-0cc4314b11bf.png	\N	2017-06-19	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
c9418845-31f6-4c50-8bbb-efc4f0e40ad6	Mitchell	Simmons	\N	MSimmons@techcore.com	4255677000	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	e55d2744-268a-44db-8516-01f3b0fa6c6f	fac15c2e-cce9-48f9-b818-10a2545020f4	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/c9418845-31f6-4c50-8bbb-efc4f0e40ad6.png	\N	2015-03-15	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
16762880-9a7e-41b9-8d3f-ef695ca6e206	Morena	Nelson	\N	MNelson@techcore.com	4255671635	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	3b6fe441-b224-40bc-b595-0396cf2c4568	fac15c2e-cce9-48f9-b818-10a2545020f4	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/16762880-9a7e-41b9-8d3f-ef695ca6e206.png	\N	2012-04-10	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
b62323b4-3312-49d7-b652-77b82f7530c9	Naomi	Lane	\N	NLane@techcore.com	3058835676	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	85a35b32-a9d3-4177-a5c5-17b68a4dbd32	2d6671d9-d94c-45aa-838d-38eb89c4abd3	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/b62323b4-3312-49d7-b652-77b82f7530c9.png	\N	2012-12-28	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
0cd35625-f147-4059-bb92-26ff5eaf3bfc	Natasha	Mathews	\N	NMathews@techcore.com	3058335667	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	770b4116-4b6b-4174-b050-145af2dedac6	2d6671d9-d94c-45aa-838d-38eb89c4abd3	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/0cd35625-f147-4059-bb92-26ff5eaf3bfc.png	\N	2010-07-06	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
cc6a17c5-fb34-49ef-96ef-e2e549ae65b0	Natassia	Gordon	\N	NGordon@techcore.com	8013337465	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	6e06a0a6-4670-4d58-979d-5d681cefa38f	0aa76a1d-9516-413f-b311-fe0da3c9abf1	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/cc6a17c5-fb34-49ef-96ef-e2e549ae65b0.png	\N	2013-08-25	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
568769e8-bfdc-4939-8d0a-7fd56142b656	Nixie	Cruz	\N	NCruz@techcore.com	8572923384	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	6d781d71-c82d-4e5d-9742-51ea26fdfd79	80d65bb1-46bd-4b1a-b52f-3ee81a6f4ca5	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/568769e8-bfdc-4939-8d0a-7fd56142b656.png	\N	2012-12-17	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
7e38837b-0b28-4d09-b12f-7debc59f8a2b	Noni	Henderson	\N	NHenderson@techcore.com	8004452673	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	0dc6d07c-f78a-4f16-a136-c31bc05b0bfc	c10c8cb4-e212-47ce-96e5-4c077c530abd	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/7e38837b-0b28-4d09-b12f-7debc59f8a2b.png	\N	2019-05-30	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
af486a23-9fe8-426d-af5d-949285e5db37	Odessa	Lane	\N	OLane@techcore.com	3058835600	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	f6f159c6-f136-454c-b2e4-863e83ba1993	2d6671d9-d94c-45aa-838d-38eb89c4abd3	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/af486a23-9fe8-426d-af5d-949285e5db37.png	\N	2011-02-08	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
2b965826-79f5-4d2c-a75c-d76938cff748	Orelle	Bennett	\N	OBennett@techcore.com	6027321163	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	5b8d6b26-7266-4582-a10f-e88c396d3ba2	\N	t	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/2b965826-79f5-4d2c-a75c-d76938cff748.png	\N	2011-04-24	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
166df220-50a6-4668-8215-2d0d45bef2fb	Paul	Perry	\N	PPerry@techcore.com	8004452673	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	5cd95fae-09b6-44f8-9bba-23f446db1730	c10c8cb4-e212-47ce-96e5-4c077c530abd	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/166df220-50a6-4668-8215-2d0d45bef2fb.png	\N	2010-04-18	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
04d6904a-f173-484e-bed4-c765d6036372	Richard	Lane	\N	RLane@techcore.com	8572927783	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	c957bd08-6a14-4985-afdc-367da67aa3e0	80d65bb1-46bd-4b1a-b52f-3ee81a6f4ca5	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/04d6904a-f173-484e-bed4-c765d6036372.png	\N	2011-10-11	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
addc86d9-d86a-4aee-a025-502a4d4990c3	Scott	Diaz	\N	SDiaz@techcore.com	4255674432	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	dfad3860-11af-4c13-8a9b-8f49bf4b8ec5	fac15c2e-cce9-48f9-b818-10a2545020f4	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/addc86d9-d86a-4aee-a025-502a4d4990c3.png	\N	2010-09-30	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
b9115495-5bce-475a-8c31-601be8c340e3	Scott	Greene	\N	SGreene@techcore.com	8013335121	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	3a3cff5e-c49c-4b16-8515-3ecdb9ae99a8	0aa76a1d-9516-413f-b311-fe0da3c9abf1	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/b9115495-5bce-475a-8c31-601be8c340e3.png	\N	2016-04-01	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
75e15e9d-50f9-4334-ac28-658793144475	Seline	Carpenter	\N	SCarpenter@techcore.com	8004452673	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	812b06e2-1dbb-4677-906b-871440254f7b	c10c8cb4-e212-47ce-96e5-4c077c530abd	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/75e15e9d-50f9-4334-ac28-658793144475.png	\N	2013-06-13	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
a1ed9a1c-90f6-4d12-9315-b885b429d919	Shawn	Stone	\N	SStone@techcore.com	5125857892	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	3a93d0fd-6924-4ee9-a313-92a33302383f	23409dd4-7cd3-4073-971a-12b48be6885e	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/a1ed9a1c-90f6-4d12-9315-b885b429d919.png	\N	2019-01-01	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
5cb03b36-f201-46b1-8989-3b0cf3bc2c80	Shawnee	Carter	\N	SCarter@techcore.com	4254547723	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	3412e88c-547d-4beb-a348-06c4703c20db	fac15c2e-cce9-48f9-b818-10a2545020f4	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/5cb03b36-f201-46b1-8989-3b0cf3bc2c80.png	\N	2012-02-15	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
c2f59945-dc1d-4abb-a706-8e5aa888baa8	Steffane	Fox	\N	SFox@techcore.com	8013336823	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	20145b64-53ca-43dd-b1bc-faeb8aff7369	0aa76a1d-9516-413f-b311-fe0da3c9abf1	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/c2f59945-dc1d-4abb-a706-8e5aa888baa8.png	\N	2014-05-05	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
48310e68-b9f5-494a-a815-efb9d6d5a7a0	Stephan	Hunt	\N	SHunt@techcore.com	4107767821	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	605ac88b-99eb-44a9-b7a1-6619f874354a	\N	t	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/48310e68-b9f5-494a-a815-efb9d6d5a7a0.png	\N	2016-03-11	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
51a3a1d1-79ec-4b4b-8729-0e19f4221a0f	Tad	Ray	\N	TRay@techcore.com	8013334719	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	9eed30aa-9b7d-4eba-b822-211a3fe59824	0aa76a1d-9516-413f-b311-fe0da3c9abf1	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/51a3a1d1-79ec-4b4b-8729-0e19f4221a0f.png	\N	2016-09-24	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
97f93a86-2e8e-4560-91e6-84df9763477c	Taylor	Webb	\N	TWebb@techcore.com	4252253328	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	d8da0788-4397-405e-b36f-255a2dfc822a	fac15c2e-cce9-48f9-b818-10a2545020f4	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/97f93a86-2e8e-4560-91e6-84df9763477c.png	\N	2010-10-15	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
d3e6e291-0f98-4af7-a560-f28e9e61c817	Tildy	Clark	\N	TClark@techcore.com	3058835600	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	11ea58a0-d488-4f90-a2f2-725af8440713	2d6671d9-d94c-45aa-838d-38eb89c4abd3	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/d3e6e291-0f98-4af7-a560-f28e9e61c817.png	\N	2016-04-03	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
5d7fa22e-fb06-457e-9d42-15131cd51068	Tim	Edwards	\N	TEdwards@techcore.com	8013338561	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	f4aefd21-e14a-47b3-a52f-dce94c5e9a99	0aa76a1d-9516-413f-b311-fe0da3c9abf1	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/5d7fa22e-fb06-457e-9d42-15131cd51068.png	\N	2010-06-27	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
563c5400-e6b4-4fa6-a708-8ed62952b882	Toby	Robertson	\N	TRobertson@techcore.com	3058835600	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	3fffba8b-e322-412d-af36-63e57c9f0ce7	2d6671d9-d94c-45aa-838d-38eb89c4abd3	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/563c5400-e6b4-4fa6-a708-8ed62952b882.png	\N	2016-01-15	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
61fbbf6b-741e-4e51-a33d-1d2de3ed377a	George	Noonan	\N	gnoonan@techcore.uk.co	\N	2020-04-07 21:27:50.333705+00	2020-04-07 21:27:50.333705+00	active	32eaa2af-35b8-44cf-93a7-72d653047374	81c09eca-58e2-4264-b126-929908174f1a	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/61fbbf6b-741e-4e51-a33d-1d2de3ed377a.jpg	\N	2019-11-10	f304e1bd-4ea5-496a-9644-76c2eb9e7483	45-4684139	6294544621	44	8296169500	44	113
1516f974-4716-4ffa-b306-c54723310e46	Adan	Rice	\N	ARice@techcore.com	3058835600	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	4b03bf3c-aad9-4a8b-92c1-a04a794c8e18	2d6671d9-d94c-45aa-838d-38eb89c4abd3	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/1516f974-4716-4ffa-b306-c54723310e46.png	\N	2015-11-03	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
02fead52-5004-4ac7-9a6f-101df7c39831	Adela	Williams	\N	AWilliams@techcore.com	8013338890	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	cdc7b509-c2cf-499d-858c-a7760bbe466a	0aa76a1d-9516-413f-b311-fe0da3c9abf1	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/02fead52-5004-4ac7-9a6f-101df7c39831.png	\N	2012-08-07	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
717f9b2e-952b-4cdb-a044-46b8324b97ff	Gary	Cowlishaw	\N	gcowlishaw@techcore.uk.co	\N	2020-04-07 21:27:50.333705+00	2020-04-07 21:27:50.333705+00	active	5ab7c28b-89ff-492e-853f-5789aa1bda50	81c09eca-58e2-4264-b126-929908174f1a	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/717f9b2e-952b-4cdb-a044-46b8324b97ff.jpeg	\N	2015-08-18	f304e1bd-4ea5-496a-9644-76c2eb9e7483	13-6316836	5609176754	44	8296169500	44	114
76146c13-ace8-4b59-8b9d-aa0c62392aac	Oliver	Iiannoni	\N	oiiannoni@techcore.uk.co	\N	2020-04-07 21:27:50.333705+00	2020-04-07 21:27:50.333705+00	active	e74f268f-d742-439f-923f-a62781e08eb6	81c09eca-58e2-4264-b126-929908174f1a	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/76146c13-ace8-4b59-8b9d-aa0c62392aac.jpg	\N	2010-12-11	f304e1bd-4ea5-496a-9644-76c2eb9e7483	66-4144881	2433070829	44	8296169500	44	115
7ed99503-14c0-44ff-a190-d017aa371c43	Mia	Grindley	\N	mgrindley@techcore.uk.co	\N	2020-04-07 21:27:50.333705+00	2020-04-07 21:27:50.333705+00	active	ab24f0bc-b652-4618-bf2b-359929ecc3fc	81c09eca-58e2-4264-b126-929908174f1a	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/7ed99503-14c0-44ff-a190-d017aa371c43.jpg	\N	2012-02-01	f304e1bd-4ea5-496a-9644-76c2eb9e7483	92-6097038	3936073939	44	8296169500	44	116
a09d3d50-c5c3-4c2d-ba87-a3e9db51f3cd	Adria	Berry	\N	ABerry@techcore.com	4255677000	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	d3920777-9e8b-4cc4-9ae7-2491a16a073c	fac15c2e-cce9-48f9-b818-10a2545020f4	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/a09d3d50-c5c3-4c2d-ba87-a3e9db51f3cd.png	\N	2015-03-15	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
2da28665-a1ba-4342-b00d-73e98d4ca9d4	Alberta	Reyes	\N	AReyes@techcore.com	8004452673	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	da43a02e-4d74-412e-a6b6-0ba874117172	c10c8cb4-e212-47ce-96e5-4c077c530abd	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/2da28665-a1ba-4342-b00d-73e98d4ca9d4.png	\N	2012-08-16	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
0168b1be-f3bd-4d8f-a5bd-a874791eb419	Alena	Turner	\N	ATurner@techcore.com	5122120997	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	50987a02-9ae6-4d9a-9940-3f74336f2d56	23409dd4-7cd3-4073-971a-12b48be6885e	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/0168b1be-f3bd-4d8f-a5bd-a874791eb419.png	\N	2019-04-24	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
8704bb52-dd21-4507-adc0-3bf4cfdf6ec4	Noah	Jeffcoat	\N	njeffcoat@techcore.uk.co	\N	2020-04-07 21:27:50.333705+00	2020-04-07 21:27:50.333705+00	active	334f2b9c-0078-407e-8875-2294692e173f	81c09eca-58e2-4264-b126-929908174f1a	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/8704bb52-dd21-4507-adc0-3bf4cfdf6ec4.png	\N	2016-01-12	f304e1bd-4ea5-496a-9644-76c2eb9e7483	31-0228852	7562167885	44	8296169500	44	117
9a250bfc-ef07-45a2-8702-56f48b9214e1	Daniel	Spuffard	\N	dspuffard@techcore.uk.co	\N	2020-04-07 21:27:50.333705+00	2020-04-07 21:27:50.333705+00	active	a7e42956-163f-497c-af11-0f0417b9ac72	81c09eca-58e2-4264-b126-929908174f1a	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/9a250bfc-ef07-45a2-8702-56f48b9214e1.jpg	\N	2013-08-15	f304e1bd-4ea5-496a-9644-76c2eb9e7483	93-5733113	6894508074	44	8296169500	44	118
a1a356c4-5bd7-438f-8939-82d9697b9058	Max	Bartlam	\N	mbartlam@techcore.uk.co	\N	2020-04-07 21:27:50.333705+00	2020-04-07 21:27:50.333705+00	active	8682628f-5b51-4384-aa44-42132f3fbca4	81c09eca-58e2-4264-b126-929908174f1a	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/a1a356c4-5bd7-438f-8939-82d9697b9058.jpeg	\N	2014-03-24	f304e1bd-4ea5-496a-9644-76c2eb9e7483	90-8217428	8575333863	44	8296169500	44	119
ad4675de-db74-4945-a79a-0d2d79934a37	Leo	Blindmann	\N	lblindmann@techcore.uk.co	\N	2020-04-07 21:27:50.333705+00	2020-04-07 21:27:50.333705+00	active	5884f9c3-20ee-44ec-9c09-766c9592d469	81c09eca-58e2-4264-b126-929908174f1a	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/ad4675de-db74-4945-a79a-0d2d79934a37.png	\N	2016-08-29	f304e1bd-4ea5-496a-9644-76c2eb9e7483	33-1347977	2226764998	44	8296169500	44	120
bac24777-48c1-4c65-a457-cca99c4688bb	Cloé	Conechie	\N	cconechie@techcore.uk.co	\N	2020-04-07 21:27:50.333705+00	2020-04-07 21:27:50.333705+00	active	d8694069-d30e-4e17-b485-de5d4640850f	81c09eca-58e2-4264-b126-929908174f1a	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/bac24777-48c1-4c65-a457-cca99c4688bb.jpg	\N	2015-07-26	f304e1bd-4ea5-496a-9644-76c2eb9e7483	06-7344866	5898492537	44	8296169500	44	121
c0830259-a620-4b98-a549-368c06fd77c0	Mark	Horwell	\N	mhorwell@techcore.uk.co	\N	2020-04-07 21:27:50.333705+00	2020-04-07 21:27:50.333705+00	active	c89fa3cf-27a0-4cb9-a0c1-a7c69b24395a	81c09eca-58e2-4264-b126-929908174f1a	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/c0830259-a620-4b98-a549-368c06fd77c0.jpg	\N	2010-11-27	f304e1bd-4ea5-496a-9644-76c2eb9e7483	47-8877560	2876570366	44	8296169500	44	122
c5ac5607-793c-4244-b7a3-bb964868b5e3	Angèle	Edison	\N	aedison@techcore.uk.co	\N	2020-04-07 21:27:50.333705+00	2020-04-07 21:27:50.333705+00	active	230cde42-7da3-461f-8af2-90e7c8309ebb	81c09eca-58e2-4264-b126-929908174f1a	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/c5ac5607-793c-4244-b7a3-bb964868b5e3.jpg	\N	2015-10-20	f304e1bd-4ea5-496a-9644-76c2eb9e7483	27-3259871	9844714399	44	8296169500	44	123
cb512953-e23d-413c-92d3-53efbad005c5	Alexander	Poleye	\N	apoleye@techcore.uk.co	\N	2020-04-07 21:27:50.333705+00	2020-04-07 21:27:50.333705+00	active	33a2c51c-53de-4130-859f-12f4f051f9ee	81c09eca-58e2-4264-b126-929908174f1a	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/cb512953-e23d-413c-92d3-53efbad005c5.jpg	\N	2011-11-24	f304e1bd-4ea5-496a-9644-76c2eb9e7483	05-0522961	3981448041	44	8296169500	44	124
d76c30cb-e2d0-49c3-bfef-3ac7184389e5	John	Allewell	\N	jallewell@techcore.uk.co	\N	2020-04-07 21:27:50.333705+00	2020-04-07 21:27:50.333705+00	active	7dd3db57-6eda-47c0-a8dc-c31170a6f1d6	81c09eca-58e2-4264-b126-929908174f1a	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/d76c30cb-e2d0-49c3-bfef-3ac7184389e5.jpg	\N	2013-04-06	f304e1bd-4ea5-496a-9644-76c2eb9e7483	44-6369260	5015134855	44	8296169500	44	125
dc88ec4c-83c9-4ffa-bd37-006fbb32a47e	Harry	Agus	\N	hagus@techcore.uk.co	\N	2020-04-07 21:27:50.333705+00	2020-04-07 21:27:50.333705+00	active	fb27daef-e8ee-4a4e-adae-9d77abce64f6	81c09eca-58e2-4264-b126-929908174f1a	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/dc88ec4c-83c9-4ffa-bd37-006fbb32a47e.jpeg	\N	2017-01-02	f304e1bd-4ea5-496a-9644-76c2eb9e7483	75-4719176	4655516532	44	8296169500	44	126
efb52ad6-4d86-450c-9ab1-cb0839ed1a36	David	Forsberg	\N	david@bluerocket.io	8013914042	2020-03-05 23:07:39.575416+00	2020-03-09 20:55:55.190581+00	active	\N	0b982233-ac65-4c19-91c7-a5db07135ad9	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/b6f5de76-b09a-4091-add7-c4a72874c9d4/user_avatars/efb52ad6-4d86-450c-9ab1-cb0839ed1a36.png	\N	\N	c1b769c8-dc45-4662-a408-de09ce621202	\N	\N	\N	\N	\N	\N
9d2da858-2513-479f-8760-a591e8bfbfda	Vaughn	Aust	\N	vaust@bluerocket.io	4252417080	2020-03-05 23:07:39.575416+00	2020-03-09 20:55:55.190581+00	active	\N	0b982233-ac65-4c19-91c7-a5db07135ad9	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/b6f5de76-b09a-4091-add7-c4a72874c9d4/user_avatars/9d2da858-2513-479f-8760-a591e8bfbfda.png	\N	\N	c1b769c8-dc45-4662-a408-de09ce621202	\N	\N	\N	\N	\N	\N
02123e56-439a-455f-80f3-932dadffa18a	Jason	Kap	feda7213-71b7-434f-a614-5ad898f34997	jason@bluerocket.io	4255914924	2020-03-05 23:07:39.575416+00	2020-03-15 15:39:21.097035+00	active	\N	46aeeef7-1b5e-4962-82d7-e939582d7032	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/b6f5de76-b09a-4091-add7-c4a72874c9d4/user_avatars/02123e56-439a-455f-80f3-932dadffa18a.png	\N	\N	c1b769c8-dc45-4662-a408-de09ce621202	\N	\N	\N	\N	\N	\N
9a830a29-5d28-4009-acac-dd5787a293cd	Brian	Masters	\N	bmasters@bluerocket.io	8016037589	2020-03-05 23:07:39.575416+00	2020-03-09 20:55:55.190581+00	active	\N	0b982233-ac65-4c19-91c7-a5db07135ad9	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/b6f5de76-b09a-4091-add7-c4a72874c9d4/user_avatars/9a830a29-5d28-4009-acac-dd5787a293cd.png	\N	\N	c1b769c8-dc45-4662-a408-de09ce621202	\N	\N	\N	\N	\N	\N
a4949214-a186-4585-8b28-e61cf2075798	Joshua	Williams	\N	jwilliams@bluerocket.io	4259857111	2020-03-05 23:07:39.575416+00	2020-03-09 20:55:55.190581+00	active	\N	46aeeef7-1b5e-4962-82d7-e939582d7032	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/b6f5de76-b09a-4091-add7-c4a72874c9d4/user_avatars/a4949214-a186-4585-8b28-e61cf2075798.png	\N	\N	c1b769c8-dc45-4662-a408-de09ce621202	\N	\N	\N	\N	\N	\N
7d8d40eb-2f23-4785-a031-18b02c289d42	Daniel	Walton	\N	dwalton@bluerocket.io	5087362112	2020-03-05 23:07:39.575416+00	2020-03-09 20:55:55.190581+00	active	\N	46aeeef7-1b5e-4962-82d7-e939582d7032	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/b6f5de76-b09a-4091-add7-c4a72874c9d4/user_avatars/7d8d40eb-2f23-4785-a031-18b02c289d42.png	\N	\N	c1b769c8-dc45-4662-a408-de09ce621202	\N	\N	\N	\N	\N	\N
d80a8eae-54cf-49d2-a5b8-ed2ad827fbdf	Rob	Beaver	\N	rbeaver@bluerocket.io	5153609541	2020-03-05 23:07:39.575416+00	2020-03-09 20:55:55.190581+00	active	\N	46aeeef7-1b5e-4962-82d7-e939582d7032	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/b6f5de76-b09a-4091-add7-c4a72874c9d4/user_avatars/d80a8eae-54cf-49d2-a5b8-ed2ad827fbdf.png	\N	\N	c1b769c8-dc45-4662-a408-de09ce621202	\N	\N	\N	\N	\N	\N
948f24c4-c8f9-4442-b487-bc77aa3389be	Jonathan	Shultz	\N	jshultz@bluerocket.io	4252418089	2020-03-05 23:07:39.575416+00	2020-03-09 20:55:55.190581+00	active	\N	46aeeef7-1b5e-4962-82d7-e939582d7032	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/b6f5de76-b09a-4091-add7-c4a72874c9d4/user_avatars/948f24c4-c8f9-4442-b487-bc77aa3389be.png	\N	\N	c1b769c8-dc45-4662-a408-de09ce621202	\N	\N	\N	\N	\N	\N
cf1b1356-1cb3-461d-b029-fcdaf8c90b67	Pam	Stevens	\N	pshupestevens@gmail.com	9294857333	2020-03-05 23:07:39.575416+00	2020-03-09 20:55:55.190581+00	active	\N	0b982233-ac65-4c19-91c7-a5db07135ad9	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/b6f5de76-b09a-4091-add7-c4a72874c9d4/user_avatars/cf1b1356-1cb3-461d-b029-fcdaf8c90b67.png	\N	\N	c1b769c8-dc45-4662-a408-de09ce621202	\N	\N	\N	\N	\N	\N
5206a77e-7609-4312-a5cb-5d15aed6f8f5	Brittni	Hawkins	\N	BHawkins@techcore.com	8572927794	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	4c5f78f2-ad54-4d2b-b9e6-ea94884649f0	80d65bb1-46bd-4b1a-b52f-3ee81a6f4ca5	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/5206a77e-7609-4312-a5cb-5d15aed6f8f5.png	\N	2016-12-28	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
30ef7f68-a992-485f-938f-691b77056a66	Josh	Ettwein	68bf1cec-1e8c-4423-a2c2-4ceaf838ae9c	jettwein@bluerocket.io	8582204676	2020-03-05 23:07:39.575416+00	2020-03-15 13:18:56.874242+00	active	\N	0b982233-ac65-4c19-91c7-a5db07135ad9	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/b6f5de76-b09a-4091-add7-c4a72874c9d4/user_avatars/30ef7f68-a992-485f-938f-691b77056a66.png	\N	\N	c1b769c8-dc45-4662-a408-de09ce621202	\N	\N	\N	\N	\N	\N
12632ce4-65af-40d4-9e85-e863203f9719	Robert	Moore	33ceb3f3-8900-4ba1-a43a-a0379b64c89d	rmoore@bluerocket.io	5124260838	2020-03-05 23:07:39.575416+00	2020-03-15 13:20:10.58874+00	active	399fa495-cbfe-43b1-bab8-c3177a69ce15	0b982233-ac65-4c19-91c7-a5db07135ad9	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/b6f5de76-b09a-4091-add7-c4a72874c9d4/user_avatars/12632ce4-65af-40d4-9e85-e863203f9719.png	1976-03-15	\N	c1b769c8-dc45-4662-a408-de09ce621202	\N	\N	\N	\N	\N	\N
0f8b9ba8-4248-44b5-b083-373b1096f490	Ian	Barkley	378c61b3-f562-4261-836c-f0f0409b8151	ibarkley@bluerocket.io	8185054044	2020-03-05 23:07:39.575416+00	2020-03-15 13:31:12.340093+00	active	\N	0b982233-ac65-4c19-91c7-a5db07135ad9	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/b6f5de76-b09a-4091-add7-c4a72874c9d4/user_avatars/0f8b9ba8-4248-44b5-b083-373b1096f490.png	\N	\N	c1b769c8-dc45-4662-a408-de09ce621202	\N	\N	\N	\N	\N	\N
77dae8b4-f53f-45c4-a2e4-9f60ddd927a7	Broderick	Murray	\N	BMurray@techcore.com	6788798080	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	0e5e8866-0ee2-4e5e-889a-bb75cfa3067a	\N	t	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/77dae8b4-f53f-45c4-a2e4-9f60ddd927a7.png	\N	2010-11-05	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
05423770-0bca-48ea-80e8-919efac8e7b3	Savidrath	By	ab91de1b-c164-4b11-8208-0454ed502b64	sby@bluerocket.io	5073043649	2020-03-05 23:07:39.575416+00	2020-04-15 15:19:47.344668+00	active	\N	0b982233-ac65-4c19-91c7-a5db07135ad9	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/b6f5de76-b09a-4091-add7-c4a72874c9d4/user_avatars/05423770-0bca-48ea-80e8-919efac8e7b3.png	\N	2020-04-01	c1b769c8-dc45-4662-a408-de09ce621202	\N	\N	\N	\N	\N	\N
a0497766-0c92-4872-8271-0d20acf0af13	Catherine	Stewart	\N	CStewart@techcore.com	4255673365	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	dc4464e5-7969-491c-b2ec-bd78476d9fc8	fac15c2e-cce9-48f9-b818-10a2545020f4	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/a0497766-0c92-4872-8271-0d20acf0af13.png	\N	2017-10-01	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
9b2b911a-1976-4047-a523-4b7e05e5374b	Charlotta	Reynolds	\N	CReynolds@techcore.com	8572927793	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	a2c2d8ba-a04e-4531-a36d-f9d70a561ba4	80d65bb1-46bd-4b1a-b52f-3ee81a6f4ca5	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/9b2b911a-1976-4047-a523-4b7e05e5374b.png	\N	2013-11-02	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
35c48330-3f39-4a92-aab6-28745ca954e3	Clara	Lee	\N	CLee@techcore.com	6122449098	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	64021ae0-64b9-4294-895e-b630b91e191c	\N	t	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/35c48330-3f39-4a92-aab6-28745ca954e3.png	\N	2010-05-17	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
8d4c489a-60bc-40dd-83cd-e1ad7a9102c3	Crista	Owens	\N	COwens@techcore.com	8572927785	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	93d90de3-906b-421e-9066-5a4895a71cf9	80d65bb1-46bd-4b1a-b52f-3ee81a6f4ca5	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/8d4c489a-60bc-40dd-83cd-e1ad7a9102c3.png	\N	2019-02-26	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
888a2a22-bb46-46bf-a0ed-fcea72fd76cb	Agney	Menon	\N	agney.menon@bigbinary.com	\N	2020-03-05 23:07:39.575416+00	2020-03-18 17:11:51.649406+00	active	\N	0b982233-ac65-4c19-91c7-a5db07135ad9	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/b6f5de76-b09a-4091-add7-c4a72874c9d4/user_avatars/888a2a22-bb46-46bf-a0ed-fcea72fd76cb.png	\N	\N	c1b769c8-dc45-4662-a408-de09ce621202	\N	\N	\N	\N	\N	\N
023c50d2-6dfc-47e1-9f1c-d01d5fa7cadc	Eswar	Tallapudi	\N	eswar.tallapudi@bigbinary.com	\N	2020-03-05 23:07:39.575416+00	2020-03-18 17:11:51.649406+00	active	\N	0b982233-ac65-4c19-91c7-a5db07135ad9	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/b6f5de76-b09a-4091-add7-c4a72874c9d4/user_avatars/023c50d2-6dfc-47e1-9f1c-d01d5fa7cadc.png	\N	\N	c1b769c8-dc45-4662-a408-de09ce621202	\N	\N	\N	\N	\N	\N
69aba4b3-79ad-4a9a-bc10-9faaad11454d	Muhsin	Keloth	\N	muhsin.k@bigbinary.com	\N	2020-03-05 23:07:39.575416+00	2020-03-18 17:23:33.453806+00	active	\N	0b982233-ac65-4c19-91c7-a5db07135ad9	f	male	\N	\N	\N	c1b769c8-dc45-4662-a408-de09ce621202	\N	\N	\N	\N	\N	\N
eb9d8432-85c7-4959-869b-2af3c99c4ae9	Charlie	Maulin	\N	cmaulin@techcore.uk.co	\N	2020-04-07 21:27:50.333705+00	2020-04-07 21:27:50.333705+00	active	10bf2d93-ab90-44e0-96c8-0f34e8501095	81c09eca-58e2-4264-b126-929908174f1a	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/eb9d8432-85c7-4959-869b-2af3c99c4ae9.jpg	\N	2017-01-06	f304e1bd-4ea5-496a-9644-76c2eb9e7483	41-4146959	6118409093	44	8296169500	44	127
fef7bbb5-29c9-4e7f-bd6e-e14cfb4177d8	Gwenaëlle	Trude	\N	gtrude@techcore.uk.co	\N	2020-04-07 21:27:50.333705+00	2020-04-07 21:27:50.333705+00	active	44dfdfc7-7ef7-4098-b283-51cbbec34694	81c09eca-58e2-4264-b126-929908174f1a	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/fef7bbb5-29c9-4e7f-bd6e-e14cfb4177d8.jpg	\N	2013-05-04	f304e1bd-4ea5-496a-9644-76c2eb9e7483	47-1872428	3801606518	44	8296169500	44	128
04f95695-c074-4305-91a2-f5ee88a38f11	Cloe	Wood	\N	CWood@techcore.com	8572927790	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	48ef2cb8-dba7-4c2e-ab1d-ee9a38baf668	80d65bb1-46bd-4b1a-b52f-3ee81a6f4ca5	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/04f95695-c074-4305-91a2-f5ee88a38f11.png	\N	2016-11-09	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
bbda5f2f-39f6-45c8-9444-f4dec3e72102	Emily	Moore	\N	EMoore@techcore.com	8138765549	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	eec1bbcf-502e-4873-a4d2-cd3167d22706	c10c8cb4-e212-47ce-96e5-4c077c530abd	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/bbda5f2f-39f6-45c8-9444-f4dec3e72102.png	\N	2016-08-04	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
ba067402-960f-49e5-827b-6740391da20d	Jamie	Roberts	\N	JRoberts@techcore.com	4255670823	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	b98e0c25-a54f-44c3-a413-365eb2721cca	fac15c2e-cce9-48f9-b818-10a2545020f4	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/ba067402-960f-49e5-827b-6740391da20d.png	\N	2011-08-05	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
00b7c3c8-eae6-44cd-8a43-f0174839543f	Jessy	Jackson	\N	JJackson@techcore.com	4255677000	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	de6ec9bd-87b6-4aed-8855-9fc0494a4ef9	fac15c2e-cce9-48f9-b818-10a2545020f4	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/00b7c3c8-eae6-44cd-8a43-f0174839543f.png	\N	2015-03-15	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
b6664603-0899-4396-80c6-59f4fb65589a	Melanie	Ruiz	\N	MRuiz@techcore.com	8004452673	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	5451c54e-e403-4144-b206-0b794fb033fb	c10c8cb4-e212-47ce-96e5-4c077c530abd	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/b6664603-0899-4396-80c6-59f4fb65589a.png	\N	2019-08-12	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
cfed498c-a31f-4c59-b15d-b533c05639dd	Meris	Robinson	\N	merisrobinson@techcore.com	4255672289	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	4027fc5e-7af3-4db3-af8a-7f2fdbb46033	fac15c2e-cce9-48f9-b818-10a2545020f4	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/cfed498c-a31f-4c59-b15d-b533c05639dd.png	\N	2016-08-27	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
37a4ca73-e691-4b3c-82c6-44d7ea03f2d0	Trenton	Turner	\N	TTurner@techcore.com	8138765542	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	5bc57413-461a-4c90-be4e-c30642c7e7a4	c10c8cb4-e212-47ce-96e5-4c077c530abd	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/37a4ca73-e691-4b3c-82c6-44d7ea03f2d0.png	\N	2015-11-06	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
8d20c463-d211-4e89-a359-6d1176cff333	Ty	Perry	\N	TPerry@techcore.com	4255677000	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	c1490d63-1d8b-47e6-8b48-cd55c942c7a9	fac15c2e-cce9-48f9-b818-10a2545020f4	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/8d20c463-d211-4e89-a359-6d1176cff333.png	\N	2015-03-15	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
ff599b72-b9d2-4f48-8572-5f4c39df52de	Val	Morgan	\N	VMorgan@techcore.com	8004452673	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	992165cf-6e20-4e9c-bc3c-984f6a7131a7	c10c8cb4-e212-47ce-96e5-4c077c530abd	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/ff599b72-b9d2-4f48-8572-5f4c39df52de.png	\N	2013-12-15	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
8c4a2b20-1d15-4de9-88c1-1730ff2d00c7	Van	Martin	\N	VMartin@techcore.com	8012926322	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	c093ede0-7546-4739-a55a-8e5ad443bf25	0aa76a1d-9516-413f-b311-fe0da3c9abf1	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/8c4a2b20-1d15-4de9-88c1-1730ff2d00c7.png	\N	2019-07-27	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
39bc7ecd-431c-4c12-b55d-9b90da94e29d	Vitia	West	\N	VWest@techcore.com	8004452673	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	8134c85c-9aaa-4ef4-8abb-47330ab259df	c10c8cb4-e212-47ce-96e5-4c077c530abd	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/39bc7ecd-431c-4c12-b55d-9b90da94e29d.png	\N	2015-06-28	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
e9f5aba8-9767-481a-9ce9-2754eed2d9ff	Angele	Miller	\N	AMiller@techcore.com	8004452673	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	28a4f89b-4c17-43bb-9854-476a1f2c8af1	c10c8cb4-e212-47ce-96e5-4c077c530abd	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/e9f5aba8-9767-481a-9ce9-2754eed2d9ff.png	\N	2015-02-28	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
e345509b-938c-423c-b9c8-a77a0cc817f5	Bekki	Price	\N	BPrice@techcore.com	8004452673	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	bf2bdda9-dceb-4875-abdb-eb1f4d7d188f	c10c8cb4-e212-47ce-96e5-4c077c530abd	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/e345509b-938c-423c-b9c8-a77a0cc817f5.png	\N	2012-08-12	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
f479438f-70c2-4082-8b93-b4eced25432e	Darb	Ross	\N	darbross@techcore.com	4256771213	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	a5fed248-9a7a-4ac9-878b-fd462cac3d7b	fac15c2e-cce9-48f9-b818-10a2545020f4	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/f479438f-70c2-4082-8b93-b4eced25432e.png	\N	2014-02-02	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
f9140927-59f5-4ceb-9542-e3d819f7264e	Delora	Arnold	\N	DArnold@techcore.com	8013335368	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	495f03c1-3318-43ca-9726-484e3d0f9b18	0aa76a1d-9516-413f-b311-fe0da3c9abf1	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/f9140927-59f5-4ceb-9542-e3d819f7264e.png	\N	2014-06-28	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
e309c3bf-5623-4bbb-96f9-b69f04f42211	Dominque	Hall	\N	DHall@techcore.com	4252251898	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	41f013e6-ee6b-44e1-ac08-216b3f3e73f6	fac15c2e-cce9-48f9-b818-10a2545020f4	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/e309c3bf-5623-4bbb-96f9-b69f04f42211.png	\N	2017-11-06	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
f4e0ece2-aa80-4843-81cb-c3a1fe68bcfe	Dory	Watson	\N	DWatson@techcore.com	5123334543	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	3fb54d6e-463e-419b-9e12-38a08b30d21d	23409dd4-7cd3-4073-971a-12b48be6885e	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/f4e0ece2-aa80-4843-81cb-c3a1fe68bcfe.png	\N	2015-10-05	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
f781c199-0db5-4632-a8f1-f92071d2f2f6	Eilis	Henderson	\N	EHenderson@techcore.com	5124260034	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	37f12911-f6ee-4cc2-b4b4-f863a3168c7d	23409dd4-7cd3-4073-971a-12b48be6885e	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/f781c199-0db5-4632-a8f1-f92071d2f2f6.png	\N	2016-07-14	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
ecda3df6-3ae1-488d-b6ad-7023f574b6a9	Elane	Griffin	\N	EGriffin@techcore.com	4255671635	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	688b9130-56a4-4be3-a11f-112a61839858	fac15c2e-cce9-48f9-b818-10a2545020f4	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/ecda3df6-3ae1-488d-b6ad-7023f574b6a9.png	\N	2017-08-27	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
f7eeab19-abdd-4c10-9422-f9105ec664cb	Janet	Ford	\N	JFord@techcore.com	3058835600	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	e3604def-eab3-41e8-85a4-72b36cffbdb2	2d6671d9-d94c-45aa-838d-38eb89c4abd3	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/f7eeab19-abdd-4c10-9422-f9105ec664cb.png	\N	2017-12-20	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
eb9e8d20-17a9-439c-a8c1-6c07983690a9	Kendrick	Austin	\N	KAustin@techcore.com	3128771188	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	3d89ca62-8300-417f-ab36-9047a78097e5	\N	t	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/eb9e8d20-17a9-439c-a8c1-6c07983690a9.png	\N	2012-05-28	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
63a9b6db-f71c-4123-b37f-07f26ba265e9	Rachelle	Torres	\N	RTorres@techcore.com	8012983171	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	c4adfd57-e4bb-41ff-926d-5bf1c7d0eba0	0aa76a1d-9516-413f-b311-fe0da3c9abf1	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/63a9b6db-f71c-4123-b37f-07f26ba265e9.png	\N	2011-07-29	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
f02e915a-d80d-4cfa-a425-840242f5b33f	Rafa	Cox	\N	RCox@techcore.com	3058335666	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	5976274d-329d-4870-ab01-5f7a69f8a069	2d6671d9-d94c-45aa-838d-38eb89c4abd3	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/f02e915a-d80d-4cfa-a425-840242f5b33f.png	\N	2010-11-19	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
0d4af5e4-73bd-43de-9026-46aaf282de35	Randy	Lawson	\N	RLawson@techcore.com	5123335539	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	cf96dc33-559b-434a-bc83-e5632b14a849	23409dd4-7cd3-4073-971a-12b48be6885e	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/0d4af5e4-73bd-43de-9026-46aaf282de35.png	\N	2012-09-11	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
b176dd8d-3e1b-488b-b92d-d7e38c9dcc27	Rane	Lopez	\N	RLopez@techcore.com	3058335665	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	40cd9aa8-73dd-4874-a139-b6bc34ce0cd7	2d6671d9-d94c-45aa-838d-38eb89c4abd3	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/b176dd8d-3e1b-488b-b92d-d7e38c9dcc27.png	\N	2019-02-13	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
c2bea9f3-2018-4de9-8d1e-e02d7c659123	Rhetta	Gardener	\N	RGardener@techcore.com	8013338138	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	a6a19025-5e69-4eed-bca1-2a1ac295f580	0aa76a1d-9516-413f-b311-fe0da3c9abf1	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/c2bea9f3-2018-4de9-8d1e-e02d7c659123.png	\N	2019-07-22	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
e0c5bc58-c3bc-475f-b97b-b7a48cdec624	Rick	Owens	\N	ROwens@techcore.com	4258779911	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	10f89f7f-5ef6-4ef2-a025-307b244d2f86	fac15c2e-cce9-48f9-b818-10a2545020f4	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/e0c5bc58-c3bc-475f-b97b-b7a48cdec624.png	\N	2015-01-10	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
ded0927f-2454-462c-9f14-804f3bba34ae	Roscoe	Henry	\N	RHenry@techcore.com	5124332525	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	b3553b10-13e8-472c-af63-f63e91da17d6	23409dd4-7cd3-4073-971a-12b48be6885e	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/ded0927f-2454-462c-9f14-804f3bba34ae.png	\N	2018-02-26	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
a9be7145-8f65-4b56-944e-215663d3a0a9	Ruthy	Hart	\N	RHart@techcore.com	3058835671	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	067548c6-4d52-45ce-8b4f-6b184fed060b	2d6671d9-d94c-45aa-838d-38eb89c4abd3	f	female	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/a9be7145-8f65-4b56-944e-215663d3a0a9.png	\N	2019-08-19	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
ce715557-0bfc-4202-a3ea-d8767d0188a0	Salome	Armstrong	\N	SArmstrong@techcore.com	8572956621	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	91d3c298-256c-4c55-b444-e568fafc1a2c	\N	t	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/ce715557-0bfc-4202-a3ea-d8767d0188a0.png	\N	2010-09-30	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
8e11a959-d891-4dcf-8d48-ca5c55c29a34	Scott	Nichols	\N	SNichols@techcore.com	5123339987	2020-01-16 01:34:57.858991+00	2020-03-18 01:20:27.020393+00	active	85732ef9-4afa-4dd0-96c4-0abb8cbe97d7	23409dd4-7cd3-4073-971a-12b48be6885e	f	male	https://gemini-cdn.sfo2.cdn.digitaloceanspaces.com/72cba849-77bc-48ff-bfb1-93e5552d538e/user_avatars/8e11a959-d891-4dcf-8d48-ca5c55c29a34.png	\N	2013-10-23	f304e1bd-4ea5-496a-9644-76c2eb9e7483	\N	\N	\N	\N	\N	\N
\.


--
-- Data for Name: worker_gender; Type: TABLE DATA; Schema: public; Owner: doadmin
--

COPY public.worker_gender (value) FROM stdin;
male
female
\.


--
-- Data for Name: worker_position; Type: TABLE DATA; Schema: public; Owner: doadmin
--

COPY public.worker_position (position_id, worker_id, start_date, end_date, friendly_title, customer_id) FROM stdin;
c99b1513-0773-4d26-b954-77195722d40b	02123e56-439a-455f-80f3-932dadffa18a	2020-03-06 00:48:58.754963+00	\N	\N	c1b769c8-dc45-4662-a408-de09ce621202
08c0b2a5-b753-43bd-b542-27f2e9fea864	efb52ad6-4d86-450c-9ab1-cb0839ed1a36	2020-03-06 00:48:58.754963+00	\N	\N	c1b769c8-dc45-4662-a408-de09ce621202
3bac7106-38eb-49e7-a390-ebc4944e4940	9d2da858-2513-479f-8760-a591e8bfbfda	2020-03-06 00:48:58.754963+00	\N	\N	c1b769c8-dc45-4662-a408-de09ce621202
be7c96ce-a98e-4d95-9b58-a0e67b9048dc	30ef7f68-a992-485f-938f-691b77056a66	2020-03-06 00:48:58.754963+00	\N	\N	c1b769c8-dc45-4662-a408-de09ce621202
d17233ee-1b3a-4c33-bf61-daad198c8d80	12632ce4-65af-40d4-9e85-e863203f9719	2020-03-06 00:48:58.754963+00	\N	\N	c1b769c8-dc45-4662-a408-de09ce621202
51a518c6-c6a7-479c-aa29-0a4c4e4e604c	9a830a29-5d28-4009-acac-dd5787a293cd	2020-03-06 00:48:58.754963+00	\N	\N	c1b769c8-dc45-4662-a408-de09ce621202
9c37c99a-134f-4145-8a72-0d59845e52a6	0f8b9ba8-4248-44b5-b083-373b1096f490	2020-03-06 00:48:58.754963+00	\N	\N	c1b769c8-dc45-4662-a408-de09ce621202
6224ee22-2c17-4170-a9cd-b48ce39ccc5e	a4949214-a186-4585-8b28-e61cf2075798	2020-03-06 00:48:58.754963+00	\N	\N	c1b769c8-dc45-4662-a408-de09ce621202
0c3bbd66-30ba-41d9-9b64-7dc6fa98129d	7d8d40eb-2f23-4785-a031-18b02c289d42	2020-03-06 00:48:58.754963+00	\N	\N	c1b769c8-dc45-4662-a408-de09ce621202
d58e3a38-be18-46b0-b4a1-003e0ee1d3d5	d80a8eae-54cf-49d2-a5b8-ed2ad827fbdf	2020-03-06 00:48:58.754963+00	\N	\N	c1b769c8-dc45-4662-a408-de09ce621202
05bfb8a7-57d0-437d-8add-11431378bb3a	05423770-0bca-48ea-80e8-919efac8e7b3	2020-03-06 00:48:58.754963+00	\N	\N	c1b769c8-dc45-4662-a408-de09ce621202
8df905d1-2708-4e51-9892-a6aac09145cb	948f24c4-c8f9-4442-b487-bc77aa3389be	2020-03-06 00:48:58.754963+00	\N	\N	c1b769c8-dc45-4662-a408-de09ce621202
23cdb40f-0e8e-4f93-9c1c-45db68262954	cf1b1356-1cb3-461d-b029-fcdaf8c90b67	2020-03-06 00:48:58.754963+00	\N	\N	c1b769c8-dc45-4662-a408-de09ce621202
88cdaf24-838b-48d3-b068-55f7982f380e	888a2a22-bb46-46bf-a0ed-fcea72fd76cb	2020-03-06 00:48:58.754963+00	\N	\N	c1b769c8-dc45-4662-a408-de09ce621202
be071a53-2599-4065-af69-d5f4c7752728	023c50d2-6dfc-47e1-9f1c-d01d5fa7cadc	2020-03-06 00:48:58.754963+00	\N	\N	c1b769c8-dc45-4662-a408-de09ce621202
bfe6649b-1e76-4a9f-b418-6bc4c4a2492d	69aba4b3-79ad-4a9a-bc10-9faaad11454d	2020-03-06 00:48:58.754963+00	\N	\N	c1b769c8-dc45-4662-a408-de09ce621202
5f24abec-7db2-4691-939f-aef1acc6350c	07eb6f1d-edab-4ef8-9c35-cc903bd4857a	2020-04-07 21:49:05.248237+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
e3dcd06d-a10b-4a93-bf65-68b0181d96d1	109db868-b090-4a65-91f8-a2057af23efd	2020-04-07 21:49:05.248237+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
5415c0d5-def5-4424-9b42-a79884f99237	18c6943d-d03e-4a00-9a19-3b85d110b7be	2020-04-07 21:49:05.248237+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
392b7354-2d68-45b5-bcac-6a3ce6704a85	240abdea-f613-49b6-8b69-0ec0bd02fddc	2020-04-07 21:49:05.248237+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
7547cad2-7d70-4fcf-843b-6cf76a706cc8	359177b3-d52c-4321-867e-2a89d2b78a56	2020-04-07 21:49:05.248237+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
ccea8963-af6b-4e2a-b34e-cbde6d855f1a	3639b340-37fa-4b82-9e22-e008658cc79d	2020-04-07 21:49:05.248237+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
3f546b05-ab42-40c1-b26c-12f9fb6903c4	391d3848-defd-4aeb-a188-ada5d4ea7926	2020-04-07 21:49:05.248237+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
8e2725d6-97ac-49d9-85ca-2e0bb3f8f1ec	4edca5e3-2937-40f0-b0dd-871e59dc04ba	2020-04-07 21:49:05.248237+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
09318cdb-84c6-45b9-a4b4-cdd9b98f5852	5dd187cf-c6d4-40ae-b323-fef8ede3213d	2020-04-07 21:49:05.248237+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
4a86391c-1136-4797-b919-c183a9755171	5f00a5a7-c3a2-44a6-9007-b40ae36abb7b	2020-04-07 21:49:05.248237+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
0c422fc8-5d1e-4a2f-bf58-d117b4e63bd5	61fbbf6b-741e-4e51-a33d-1d2de3ed377a	2020-04-07 21:49:05.248237+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
3ff3eabd-1cdf-4b12-a584-c48ffd8e6a6a	717f9b2e-952b-4cdb-a044-46b8324b97ff	2020-04-07 21:49:05.248237+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
451afcc0-43a3-45c3-a3a6-90427c926d0a	76146c13-ace8-4b59-8b9d-aa0c62392aac	2020-04-07 21:49:05.248237+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
42543ea9-3e8f-4e0b-984c-351c6815732e	7ed99503-14c0-44ff-a190-d017aa371c43	2020-04-07 21:49:05.248237+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
d03f0aed-0e1e-4e34-bb90-591f5d7bb9e2	8704bb52-dd21-4507-adc0-3bf4cfdf6ec4	2020-04-07 21:49:05.248237+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
eec75af1-269c-4d9f-b7b1-0554a7aa19c1	9a250bfc-ef07-45a2-8702-56f48b9214e1	2020-04-07 21:49:05.248237+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
c6d4ac13-1013-46c4-a3d8-0cb3b5e8a47e	a1a356c4-5bd7-438f-8939-82d9697b9058	2020-04-07 21:49:05.248237+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
1105f7ec-1658-41ea-9ebe-53caf72e9beb	ad4675de-db74-4945-a79a-0d2d79934a37	2020-04-07 21:49:05.248237+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
c8893918-6ab4-4f32-aed6-10dec232d352	bac24777-48c1-4c65-a457-cca99c4688bb	2020-04-07 21:49:05.248237+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
1de377e1-3ed2-4f0a-b3fc-f94597116af9	c0830259-a620-4b98-a549-368c06fd77c0	2020-04-07 21:49:05.248237+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
6bfb4af9-d6b2-41c4-9bfd-caf2a3801de3	c5ac5607-793c-4244-b7a3-bb964868b5e3	2020-04-07 21:49:05.248237+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
c05ed09d-9a00-44d3-943b-aad1b020570e	cb512953-e23d-413c-92d3-53efbad005c5	2020-04-07 21:49:05.248237+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
b4137674-1d40-4928-8fc2-78e1ea58f2de	d76c30cb-e2d0-49c3-bfef-3ac7184389e5	2020-04-07 21:49:05.248237+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
785e15e1-13b9-4c08-816f-6de3961a8162	dc88ec4c-83c9-4ffa-bd37-006fbb32a47e	2020-04-07 21:49:05.248237+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
8a0bb5d7-de23-4b34-b900-772a1a755edb	eb9d8432-85c7-4959-869b-2af3c99c4ae9	2020-04-07 21:49:05.248237+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
942c2ec8-7c17-4b93-9f91-9618a52bdb5d	fef7bbb5-29c9-4e7f-bd6e-e14cfb4177d8	2020-04-07 21:49:05.248237+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
71fc94e3-abe0-47dc-9011-ab49597cfd6a	d299489c-3371-4afd-8755-f2cb10db8b57	2010-03-01 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
dfdad657-a67f-4471-a951-c925297df211	ecda3df6-3ae1-488d-b6ad-7023f574b6a9	2017-08-27 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
4b5b2a54-040c-415a-bda7-3e029ed003a0	16762880-9a7e-41b9-8d3f-ef695ca6e206	2012-04-10 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
e6226278-de8c-4e77-ad8a-4dcae725e667	aafcc14a-cc7a-4299-a0ae-2007b9692e0a	2013-10-16 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
347a454e-8d7d-4fc6-a82a-cfe404ffc525	5cb03b36-f201-46b1-8989-3b0cf3bc2c80	2012-02-15 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
7ab39d6a-2658-40f6-8f83-1ffafab9eb15	8339f6c2-2d0e-4a8c-8384-2a2a9f3f3c3a	2013-05-11 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
2eeaa908-0d10-4676-9143-4ef93d7c1695	41faa9b6-4495-4329-93ca-392d26d4907c	2015-03-15 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
69ab9f74-14bd-4596-889c-23b3043c4d39	00b7c3c8-eae6-44cd-8a43-f0174839543f	2015-03-15 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
6f632cfc-0353-4ec7-8c5a-869912d48f53	78ab6b35-536d-4943-83c4-ff2bbfa5df4b	2015-03-15 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
7e5da5e4-38da-4132-8ba5-0175e13c59ad	cc319918-9dd9-44e2-b431-775e854df581	2015-03-15 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
de9550cb-657a-422e-a922-65920c6d70d1	a09d3d50-c5c3-4c2d-ba87-a3e9db51f3cd	2015-03-15 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
f5e59d47-8e50-4461-b8f1-21a180ffaf5c	c9418845-31f6-4c50-8bbb-efc4f0e40ad6	2015-03-15 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
e6bd5e8d-0b03-4763-847e-96462f0bd610	8d20c463-d211-4e89-a359-6d1176cff333	2015-03-15 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
476d4ae3-b5fc-4f9c-a910-2d5211f23b5e	0f6322aa-4f54-47e0-9f48-844e96733f86	2019-07-27 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
9a4bb6c5-9e25-42e3-ba5e-4f90b22ed003	a0497766-0c92-4872-8271-0d20acf0af13	2017-10-01 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
0c372711-789c-48bc-8304-ac9f72dc6720	42495344-a2dd-4fdc-85cb-00be6f956588	2012-11-28 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
1c83cbfe-1ebc-4a67-ab31-3090237e4a07	decadbb0-ac38-4903-a445-2732a0467915	2018-05-17 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
b5884ce4-7f7d-4c64-87d4-9f094417c395	addc86d9-d86a-4aee-a025-502a4d4990c3	2013-10-23 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
301c40cd-ea72-421c-88dc-11ba59e400cc	a9dbef18-3568-4243-bdd4-573f0240f79b	2013-12-28 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
beb4235f-387e-4e23-a41c-1a519656b15d	cfed498c-a31f-4c59-b15d-b533c05639dd	2016-08-27 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
a4f1ff36-88f7-453d-ba9d-fd00fa53c7df	ba067402-960f-49e5-827b-6740391da20d	2011-08-05 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
ca6405b9-0263-4f55-9efc-a744c2f1c123	e0c5bc58-c3bc-475f-b97b-b7a48cdec624	2015-01-10 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
c64e8f33-f3ff-4e20-a92b-f8c54f808949	f479438f-70c2-4082-8b93-b4eced25432e	2014-02-02 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
eba3fb6f-6c46-432f-a314-921b54465e8e	e309c3bf-5623-4bbb-96f9-b69f04f42211	2017-11-06 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
2568cea7-c8e1-4276-8372-13e9379e65f2	97f93a86-2e8e-4560-91e6-84df9763477c	2010-10-15 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
02aba96d-7de7-46e0-b02e-952a5adb9082	067bfb87-ad52-4dbf-8e10-d899060bb71c	2011-10-03 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
a9a55ef5-fc28-4037-bab4-168663523c20	a18dfae2-259f-4d9e-a846-3b1d44830fe7	2011-02-08 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
d744ce6e-56c9-4585-bdae-d6a6f872e681	0fd1a480-6fc4-40f3-a79d-8e4ad43cb4bf	2012-05-12 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
973200e5-a3f6-42c4-956d-b27d11a85fb0	5fd8b4b2-c7a9-41c1-8dfa-31dd5ae62fda	2012-07-19 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
656d6161-73e9-45a0-90a0-0c8209374b9a	66201a46-db33-473a-96a1-9aef06975180	2015-09-23 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
50445e70-7036-4dc2-bc1d-dbc8265caec3	7de1e69d-d1be-45b0-a526-d0cd4d1637e2	2017-08-16 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
5c1c1645-806b-4383-a1bd-6b45a18e3785	37a4ca73-e691-4b3c-82c6-44d7ea03f2d0	2015-11-06 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
79be7ad7-ef59-4695-962c-c48c52f48203	8e31c1ff-e087-4c7f-a367-feadc19fb7db	2016-08-29 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
d9317b6f-309c-47d2-aec7-373e12062ecf	bbda5f2f-39f6-45c8-9444-f4dec3e72102	2016-08-04 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
c318e3f0-f4ba-4737-9075-095278f0ef9a	ff599b72-b9d2-4f48-8572-5f4c39df52de	2013-12-15 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
1db16227-c8f5-4329-9e48-828c4788496f	39bc7ecd-431c-4c12-b55d-9b90da94e29d	2015-06-28 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
36f6b85e-f4f1-4b28-a184-65c2b11fc78c	75e15e9d-50f9-4334-ac28-658793144475	2013-06-13 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
9266dfb0-af61-4a8a-bd3b-b87d73975602	e345509b-938c-423c-b9c8-a77a0cc817f5	2012-08-12 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
78ed9f38-448c-4d6e-b2da-a94d78884d33	166df220-50a6-4668-8215-2d0d45bef2fb	2010-04-18 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
e25ca7ad-fbdd-4691-8594-b6ce11d78f3c	0908b890-968b-427d-a6da-b37f67d0ee03	2018-08-13 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
b745c589-7453-4600-99bc-82a35e5ced21	7e38837b-0b28-4d09-b12f-7debc59f8a2b	2019-05-30 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
f71c1291-e153-40fc-ad48-fdb98f472535	6d9cfd2d-f110-429c-becd-95af311544b4	2015-10-06 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
262d11d1-ccd8-4aa2-bbda-8406b95c9de7	b6664603-0899-4396-80c6-59f4fb65589a	2019-08-12 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
2bf62011-9339-4377-809d-d164cbe697fa	6b9e2d45-2320-4060-bfd5-28634479dfc1	2019-04-16 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
e44bf447-b407-4c5a-8e4f-1bfaff3b6284	81b74550-4251-48e9-a2d6-6f7caef01c75	2015-10-22 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
650ef93f-65fb-4148-8eff-b593c0fd185e	2da28665-a1ba-4342-b00d-73e98d4ca9d4	2012-08-16 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
cf2e0a13-f434-4bb4-b0e1-246fa32b455b	2e419ecd-a12b-4f5c-b19c-3ab50b6daf99	2018-09-11 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
7ea33b53-d45f-4340-971d-57aec1a41e70	e9f5aba8-9767-481a-9ce9-2754eed2d9ff	2015-02-28 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
f434ac6a-0621-4b49-a313-ae8801e54c86	77dae8b4-f53f-45c4-a2e4-9f60ddd927a7	2010-11-05 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
e6f9d1cb-d759-4bf5-99bd-e258bf11bfb0	a1ed9a1c-90f6-4d12-9315-b885b429d919	2019-01-01 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
5251c1e1-fad3-443e-9079-12b8de08dbd0	7c11c074-7968-44c7-88b6-cb1462d91f2f	2017-02-10 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
cc8eb71f-766d-493e-94c8-cc4877e101f6	d4719f90-8ea8-4681-a445-cc58ab593450	2017-08-08 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
857a696f-f757-4143-806d-9bce8b90b86b	ded0927f-2454-462c-9f14-804f3bba34ae	2018-02-26 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
174776b6-91ca-4ddc-84be-a3776b6fd38f	1d64d466-9d07-48ec-a392-e503ebc2fdb6	2019-07-04 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
30415589-e236-4f04-b995-cfcb71ca79d9	f4e0ece2-aa80-4843-81cb-c3a1fe68bcfe	2015-10-05 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
6a308156-a98b-4ab2-927e-07e258844607	0168b1be-f3bd-4d8f-a5bd-a874791eb419	2019-04-24 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
30e5a298-d137-49f8-8637-62176f0d832a	8e11a959-d891-4dcf-8d48-ca5c55c29a34	2010-09-30 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
54b7afa6-03a7-4751-8804-07f29e43ea04	0d4af5e4-73bd-43de-9026-46aaf282de35	2012-09-11 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
d4da59a0-a864-4643-8796-f09d56715025	8f3e7f09-414b-49de-8203-89e4331404a4	2013-06-20 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
c006c39a-9747-45a8-a374-dc60cf41059d	f781c199-0db5-4632-a8f1-f92071d2f2f6	2016-07-14 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
53a8db3c-a8f5-41bd-bc58-b27f3bc1d5d9	48310e68-b9f5-494a-a815-efb9d6d5a7a0	2016-03-11 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
c57b5e1b-090c-466f-b655-c81c3a61a8fa	04d6904a-f173-484e-bed4-c765d6036372	2011-10-11 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
a7cd11fe-533d-4a73-a31a-e111e4c76a25	ce715557-0bfc-4202-a3ea-d8767d0188a0	2010-09-30 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
13464fbc-2f34-4b23-868f-8748541a4e95	d64bbef0-0c57-46b5-b06a-92b41c23ab90	2016-12-04 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
7c68ead2-22a9-40c9-9fc9-f07b18ba1d52	568769e8-bfdc-4939-8d0a-7fd56142b656	2012-12-17 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
db85f397-a133-4c1d-8a7b-087aa2515022	8d4c489a-60bc-40dd-83cd-e1ad7a9102c3	2019-02-26 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
bdd09c05-1dc4-4f4b-9ff0-56a59a33ac14	7d7c5155-9acc-4b6a-8b77-f9926566a7bb	2010-12-17 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
a435e446-9c5e-41a4-8e20-f6db685cc1da	35e2d654-6ac7-4ae6-88a7-c699eaf89d33	2018-08-03 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
9ee199fe-5e00-44d2-b590-f528ee806421	9884669c-912e-4301-8abb-fad814aa5120	2010-03-16 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
c849b002-e627-4b98-8044-6375c181d616	b05bcf40-4ab7-4380-acc4-9dfe5d772d39	2010-07-13 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
4b36b1a3-b05c-449a-a47a-bd1947ea7560	04f95695-c074-4305-91a2-f5ee88a38f11	2016-11-09 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
0572d363-57cd-4a74-aac1-a2077c4f12f5	a2ed7452-ff32-4f5b-83a3-61c892a43b18	2019-02-18 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
be0077ef-9c90-4d9f-b2c7-db22477b41ca	db2f994e-3fa3-4599-b55f-17585fa7f09f	2018-08-30 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
82a747c1-4e13-4ee0-803e-f66f05ad841e	9b2b911a-1976-4047-a523-4b7e05e5374b	2013-11-02 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
54d6162e-bad1-482c-8ba6-69231ca94feb	5206a77e-7609-4312-a5cb-5d15aed6f8f5	2016-12-28 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
13534b17-9116-4c69-beaa-20186db16e6b	eb9e8d20-17a9-439c-a8c1-6c07983690a9	2012-05-28 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
329a0c8a-1f53-4e39-a1f5-2fa47de01c27	8de5a622-8471-4013-9400-a59dd97c69cf	2019-02-26 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
174edffb-c983-454a-b103-b003f8df814b	b176dd8d-3e1b-488b-b92d-d7e38c9dcc27	2019-02-13 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
ddc97a88-0eb4-4109-8970-925a198f433a	f02e915a-d80d-4cfa-a425-840242f5b33f	2010-11-19 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
229e5d75-880e-4621-bbc5-f853eb488e8c	0cd35625-f147-4059-bb92-26ff5eaf3bfc	2010-07-06 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
ac0174f0-6567-4603-aae0-3d1f180076f9	d2059b84-398e-41d2-afab-f6537d2ad3a0	2015-06-07 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
918762d9-e398-4851-8565-e1244a378ba7	99697a6e-ecd2-4063-b235-afd698921c9e	2013-04-26 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
6e4110c2-f77a-4636-8c2e-e3b9df409ec0	9f940688-ee63-4ccf-a8fb-0cc4314b11bf	2017-06-19 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
8146e083-8198-4f06-9ddb-592d48187f68	a9be7145-8f65-4b56-944e-215663d3a0a9	2019-08-19 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
7638e755-2717-4a37-90f5-be0be944cb8e	7c8050be-223e-4b5e-8b26-7e61af1928d6	2011-01-10 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
f89b7264-48f4-4294-a54b-b6cd18666634	563c5400-e6b4-4fa6-a708-8ed62952b882	2016-01-15 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
a6bae590-9cc0-448d-9838-bfea3e3dae69	358d5760-1767-4dd0-890c-92753f4bc2e5	2016-11-17 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
eb53fcb5-1dcc-4ffb-94ab-21170706299d	d3e6e291-0f98-4af7-a560-f28e9e61c817	2016-04-03 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
26100c20-1051-4c24-94a9-1b45b46d8106	1516f974-4716-4ffa-b306-c54723310e46	2015-11-03 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
e7e75d71-f120-420b-83c3-8b7053072e2b	f7eeab19-abdd-4c10-9422-f9105ec664cb	2017-12-20 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
27ad46e3-3b8a-4a7d-8f5e-0355edbc7d5a	af486a23-9fe8-426d-af5d-949285e5db37	2011-02-08 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
fdff6f69-117d-4834-8398-0c75b506d2a4	4d8ae02b-a6af-449d-a2ce-43e56cb12a36	2016-12-21 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
c660b8a8-8329-466c-9bac-2461984d52d2	bc4e7385-133d-49fa-a1e0-2594cee7f858	2017-05-28 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
9308f3e6-d1a4-4c1e-bd49-e2fdacffccc4	94f3db5a-a3c3-4bcd-8945-34baa1beac0d	2013-11-26 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
3e731f08-f2ae-408f-93e6-5dc08dd35b77	0e760390-f472-4d20-bf75-4d1aa335b5bd	2010-05-18 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
87c08caa-f1ac-4e1d-b222-c2219d78007f	71daca88-28ed-43b9-bfe5-48d6614d7985	2014-05-30 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
f0145f4f-655a-44ef-8cba-691d220dd6c3	b62323b4-3312-49d7-b652-77b82f7530c9	2012-12-28 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
34748925-89e3-4410-8a66-15b63c54e6e7	14adc0e8-e37c-43f5-9a3e-7a6bea64514d	2011-05-11 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
3a10356c-dee9-4c80-a732-d9df5e5cbf58	1ca6d0d9-b599-42ab-b38f-3cc1414946f5	2010-12-24 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
bc83f56d-49cf-401a-972a-0df09b625151	35c48330-3f39-4a92-aab6-28745ca954e3	2010-05-17 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
7f8aad1e-ab04-4484-99ce-06aa83ce29ce	63a9b6db-f71c-4123-b37f-07f26ba265e9	2011-07-29 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
e910fac6-bc3d-4cc0-a9b7-faa62d7b7dc9	8c4a2b20-1d15-4de9-88c1-1730ff2d00c7	2019-07-27 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
cbc6c58d-f062-4d22-bc19-633ff50b777a	3b738df3-b5c7-4598-809d-e55bb73152f0	2015-04-01 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
16daff3f-4029-4a97-98ab-7d9aa437dbb7	dbabdea2-cbd8-4f47-8856-df9b49751d59	2013-08-17 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
2c264fe1-ab22-4478-9d1f-608c1a53056f	2f49e79f-98b0-438d-ac4b-d2c847a3027f	2019-07-10 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
e7964b66-b9e0-49c8-ae2c-94102f8d0809	c2bea9f3-2018-4de9-8d1e-e02d7c659123	2019-07-22 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
7335607b-3369-40e9-a1d6-1cebd1f6def0	02fead52-5004-4ac7-9a6f-101df7c39831	2012-08-07 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
1776d9b5-b2dc-426c-8faa-b4ee47b9b3d5	37f4c73c-20de-4438-bd20-725092240179	2015-03-25 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
ba4502d0-c96f-44d5-9ef7-879f07c4a35e	5fed4868-3369-4880-adbe-6d59007a9c2c	2015-11-14 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
d5511a4d-d073-4102-906e-502f8fb1c0df	cc6a17c5-fb34-49ef-96ef-e2e549ae65b0	2013-08-25 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
7cdeab87-16ba-44c1-a898-f9070a0a05b0	d2263269-9059-4507-98a1-a135958e3911	2019-02-12 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
006c8302-85ea-4e11-ae58-328a157ca31c	5d7fa22e-fb06-457e-9d42-15131cd51068	2010-06-27 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
68212386-1bf1-444d-9e11-42d4cc72ee28	672c179b-81af-4252-8317-798f37cfaeec	2016-01-18 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
0d82e8be-0bee-4c1b-8244-7640170487d7	24e52226-9f5b-4de0-9be0-254bb50584e2	2019-02-13 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
41deb728-5b6e-4072-9adc-3656a0fe705f	de457c0b-63b8-489e-9475-b153f335c200	2017-01-25 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
14e36239-be02-4e84-af2b-d4348313d313	f9140927-59f5-4ceb-9542-e3d819f7264e	2014-06-28 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
86145a3a-5b22-4ed8-a499-d0008b2bfe07	7d40d0ae-66ab-4c19-ab89-4104e43b7730	2016-09-14 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
3ffaa5b1-fc16-4c0f-a7a2-9aaa67e70932	082e9b3b-574a-4031-a98f-4dec17460291	2016-08-22 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
66d0b7c4-b700-43f2-882b-0188be510f56	b9115495-5bce-475a-8c31-601be8c340e3	2016-04-01 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
150940dd-9a4b-4767-bf06-aac8c5829c79	c2f59945-dc1d-4abb-a706-8e5aa888baa8	2014-05-05 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
ac3eea63-1238-4e6e-910e-8b9fde560f15	95a6b551-549a-4268-85a2-ae48d1816852	2015-08-28 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
f643319d-654b-4a57-9995-ce113b831bba	dd0cbc03-be03-48ff-9f70-db7626075b6f	2010-04-28 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
a88a793d-4a67-47bf-964c-532e642e0a42	58169734-aa36-4301-8541-1bf6729cebcd	2017-05-06 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
6394342f-2a41-47db-ba58-f601573b3cae	51a3a1d1-79ec-4b4b-8729-0e19f4221a0f	2016-09-24 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
6ab88b8c-743d-429a-a678-e2db9b18bcec	2b965826-79f5-4d2c-a75c-d76938cff748	2011-04-24 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
9494375f-ece9-4ff4-acf8-00aaee3abcde	0021da48-8a44-48fb-b2d7-eaeb717b6241	2014-09-20 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
413bce4a-a2ee-41aa-9c3c-8f9ce7c49787	db41d0e1-c2b9-42ef-9bd3-857c16a30549	2015-04-04 00:00:00+00	\N	\N	f304e1bd-4ea5-496a-9644-76c2eb9e7483
\.


--
-- Name: remote_schemas_id_seq; Type: SEQUENCE SET; Schema: hdb_catalog; Owner: doadmin
--

SELECT pg_catalog.setval('hdb_catalog.remote_schemas_id_seq', 1, false);


--
-- Name: event_invocation_logs event_invocation_logs_pkey; Type: CONSTRAINT; Schema: hdb_catalog; Owner: doadmin
--

ALTER TABLE ONLY hdb_catalog.event_invocation_logs
    ADD CONSTRAINT event_invocation_logs_pkey PRIMARY KEY (id);


--
-- Name: event_log event_log_pkey; Type: CONSTRAINT; Schema: hdb_catalog; Owner: doadmin
--

ALTER TABLE ONLY hdb_catalog.event_log
    ADD CONSTRAINT event_log_pkey PRIMARY KEY (id);


--
-- Name: event_triggers event_triggers_pkey; Type: CONSTRAINT; Schema: hdb_catalog; Owner: doadmin
--

ALTER TABLE ONLY hdb_catalog.event_triggers
    ADD CONSTRAINT event_triggers_pkey PRIMARY KEY (name);


--
-- Name: hdb_allowlist hdb_allowlist_collection_name_key; Type: CONSTRAINT; Schema: hdb_catalog; Owner: doadmin
--

ALTER TABLE ONLY hdb_catalog.hdb_allowlist
    ADD CONSTRAINT hdb_allowlist_collection_name_key UNIQUE (collection_name);


--
-- Name: hdb_computed_field hdb_computed_field_pkey; Type: CONSTRAINT; Schema: hdb_catalog; Owner: doadmin
--

ALTER TABLE ONLY hdb_catalog.hdb_computed_field
    ADD CONSTRAINT hdb_computed_field_pkey PRIMARY KEY (table_schema, table_name, computed_field_name);


--
-- Name: hdb_function hdb_function_pkey; Type: CONSTRAINT; Schema: hdb_catalog; Owner: doadmin
--

ALTER TABLE ONLY hdb_catalog.hdb_function
    ADD CONSTRAINT hdb_function_pkey PRIMARY KEY (function_schema, function_name);


--
-- Name: hdb_permission hdb_permission_pkey; Type: CONSTRAINT; Schema: hdb_catalog; Owner: doadmin
--

ALTER TABLE ONLY hdb_catalog.hdb_permission
    ADD CONSTRAINT hdb_permission_pkey PRIMARY KEY (table_schema, table_name, role_name, perm_type);


--
-- Name: hdb_query_collection hdb_query_collection_pkey; Type: CONSTRAINT; Schema: hdb_catalog; Owner: doadmin
--

ALTER TABLE ONLY hdb_catalog.hdb_query_collection
    ADD CONSTRAINT hdb_query_collection_pkey PRIMARY KEY (collection_name);


--
-- Name: hdb_relationship hdb_relationship_pkey; Type: CONSTRAINT; Schema: hdb_catalog; Owner: doadmin
--

ALTER TABLE ONLY hdb_catalog.hdb_relationship
    ADD CONSTRAINT hdb_relationship_pkey PRIMARY KEY (table_schema, table_name, rel_name);


--
-- Name: hdb_table hdb_table_pkey; Type: CONSTRAINT; Schema: hdb_catalog; Owner: doadmin
--

ALTER TABLE ONLY hdb_catalog.hdb_table
    ADD CONSTRAINT hdb_table_pkey PRIMARY KEY (table_schema, table_name);


--
-- Name: hdb_version hdb_version_pkey; Type: CONSTRAINT; Schema: hdb_catalog; Owner: doadmin
--

ALTER TABLE ONLY hdb_catalog.hdb_version
    ADD CONSTRAINT hdb_version_pkey PRIMARY KEY (hasura_uuid);


--
-- Name: remote_schemas remote_schemas_name_key; Type: CONSTRAINT; Schema: hdb_catalog; Owner: doadmin
--

ALTER TABLE ONLY hdb_catalog.remote_schemas
    ADD CONSTRAINT remote_schemas_name_key UNIQUE (name);


--
-- Name: remote_schemas remote_schemas_pkey; Type: CONSTRAINT; Schema: hdb_catalog; Owner: doadmin
--

ALTER TABLE ONLY hdb_catalog.remote_schemas
    ADD CONSTRAINT remote_schemas_pkey PRIMARY KEY (id);


--
-- Name: address address_pkey; Type: CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.address
    ADD CONSTRAINT address_pkey PRIMARY KEY (id);


--
-- Name: broadcast broadcast_pkey; Type: CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.broadcast
    ADD CONSTRAINT broadcast_pkey PRIMARY KEY (id);


--
-- Name: broadcast_recipient broadcast_recipient_pkey; Type: CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.broadcast_recipient
    ADD CONSTRAINT broadcast_recipient_pkey PRIMARY KEY (id);


--
-- Name: customer customer_pkey; Type: CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.customer
    ADD CONSTRAINT customer_pkey PRIMARY KEY (id);


--
-- Name: customer_user customer_user_pkey; Type: CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.customer_user
    ADD CONSTRAINT customer_user_pkey PRIMARY KEY (customer_id, user_id);


--
-- Name: department department_pkey; Type: CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.department
    ADD CONSTRAINT department_pkey PRIMARY KEY (id);


--
-- Name: location location_pkey; Type: CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.location
    ADD CONSTRAINT location_pkey PRIMARY KEY (id);


--
-- Name: organization organization_pkey; Type: CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.organization
    ADD CONSTRAINT organization_pkey PRIMARY KEY (id);


--
-- Name: position position_pkey; Type: CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public."position"
    ADD CONSTRAINT position_pkey PRIMARY KEY (id);


--
-- Name: position_status position_status_pkey; Type: CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.position_status
    ADD CONSTRAINT position_status_pkey PRIMARY KEY (value);


--
-- Name: position_subtype position_subtype_pkey; Type: CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.position_subtype
    ADD CONSTRAINT position_subtype_pkey PRIMARY KEY (value);


--
-- Name: position_time_type position_time_type_pkey; Type: CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.position_time_type
    ADD CONSTRAINT position_time_type_pkey PRIMARY KEY (value);


--
-- Name: positionsancestors positionsancestors_pkey; Type: CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.positionsancestors
    ADD CONSTRAINT positionsancestors_pkey PRIMARY KEY (position_id, ancestor_id);


--
-- Name: profile profile_pkey; Type: CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.profile
    ADD CONSTRAINT profile_pkey PRIMARY KEY (id);


--
-- Name: user user_pkey; Type: CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public."user"
    ADD CONSTRAINT user_pkey PRIMARY KEY (id);


--
-- Name: worker worker_email_key; Type: CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.worker
    ADD CONSTRAINT worker_email_key UNIQUE (email);


--
-- Name: worker_gender worker_gender_pkey; Type: CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.worker_gender
    ADD CONSTRAINT worker_gender_pkey PRIMARY KEY (value);


--
-- Name: worker worker_pkey; Type: CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.worker
    ADD CONSTRAINT worker_pkey PRIMARY KEY (id);


--
-- Name: worker_position worker_position_pkey; Type: CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.worker_position
    ADD CONSTRAINT worker_position_pkey PRIMARY KEY (position_id, worker_id);


--
-- Name: event_invocation_logs_event_id_idx; Type: INDEX; Schema: hdb_catalog; Owner: doadmin
--

CREATE INDEX event_invocation_logs_event_id_idx ON hdb_catalog.event_invocation_logs USING btree (event_id);


--
-- Name: event_log_delivered_idx; Type: INDEX; Schema: hdb_catalog; Owner: doadmin
--

CREATE INDEX event_log_delivered_idx ON hdb_catalog.event_log USING btree (delivered);


--
-- Name: event_log_locked_idx; Type: INDEX; Schema: hdb_catalog; Owner: doadmin
--

CREATE INDEX event_log_locked_idx ON hdb_catalog.event_log USING btree (locked);


--
-- Name: event_log_trigger_name_idx; Type: INDEX; Schema: hdb_catalog; Owner: doadmin
--

CREATE INDEX event_log_trigger_name_idx ON hdb_catalog.event_log USING btree (trigger_name);


--
-- Name: hdb_schema_update_event_one_row; Type: INDEX; Schema: hdb_catalog; Owner: doadmin
--

CREATE UNIQUE INDEX hdb_schema_update_event_one_row ON hdb_catalog.hdb_schema_update_event USING btree (((occurred_at IS NOT NULL)));


--
-- Name: hdb_version_one_row; Type: INDEX; Schema: hdb_catalog; Owner: doadmin
--

CREATE UNIQUE INDEX hdb_version_one_row ON hdb_catalog.hdb_version USING btree (((version IS NOT NULL)));


--
-- Name: fki_broadcast_id_fk; Type: INDEX; Schema: public; Owner: doadmin
--

CREATE INDEX fki_broadcast_id_fk ON public.broadcast_recipient USING btree (broadcast_id);


--
-- Name: fki_organization_id_fk; Type: INDEX; Schema: public; Owner: doadmin
--

CREATE INDEX fki_organization_id_fk ON public.broadcast USING btree (organization_id);


--
-- Name: fki_position_time_time_fkey; Type: INDEX; Schema: public; Owner: doadmin
--

CREATE INDEX fki_position_time_time_fkey ON public."position" USING btree (time_type);


--
-- Name: fki_receiver_id_fk; Type: INDEX; Schema: public; Owner: doadmin
--

CREATE INDEX fki_receiver_id_fk ON public.broadcast_recipient USING btree (receiver_id);


--
-- Name: hdb_schema_update_event hdb_schema_update_event_notifier; Type: TRIGGER; Schema: hdb_catalog; Owner: doadmin
--

CREATE TRIGGER hdb_schema_update_event_notifier AFTER INSERT OR UPDATE ON hdb_catalog.hdb_schema_update_event FOR EACH ROW EXECUTE PROCEDURE hdb_catalog.hdb_schema_update_event_notifier();


--
-- Name: address set_public_address_updated_at; Type: TRIGGER; Schema: public; Owner: doadmin
--

CREATE TRIGGER set_public_address_updated_at BEFORE UPDATE ON public.address FOR EACH ROW EXECUTE PROCEDURE public.set_current_timestamp_updated_at();


--
-- Name: TRIGGER set_public_address_updated_at ON address; Type: COMMENT; Schema: public; Owner: doadmin
--

COMMENT ON TRIGGER set_public_address_updated_at ON public.address IS 'trigger to set value of column "updated_at" to current timestamp on row update';


--
-- Name: broadcast_recipient set_public_broadcast_recipient_updated_at; Type: TRIGGER; Schema: public; Owner: doadmin
--

CREATE TRIGGER set_public_broadcast_recipient_updated_at BEFORE UPDATE ON public.broadcast_recipient FOR EACH ROW EXECUTE PROCEDURE public.set_current_timestamp_updated_at();


--
-- Name: TRIGGER set_public_broadcast_recipient_updated_at ON broadcast_recipient; Type: COMMENT; Schema: public; Owner: doadmin
--

COMMENT ON TRIGGER set_public_broadcast_recipient_updated_at ON public.broadcast_recipient IS 'trigger to set value of column "updated_at" to current timestamp on row update';


--
-- Name: broadcast set_public_broadcast_updated_at; Type: TRIGGER; Schema: public; Owner: doadmin
--

CREATE TRIGGER set_public_broadcast_updated_at BEFORE UPDATE ON public.broadcast FOR EACH ROW EXECUTE PROCEDURE public.set_current_timestamp_updated_at();


--
-- Name: TRIGGER set_public_broadcast_updated_at ON broadcast; Type: COMMENT; Schema: public; Owner: doadmin
--

COMMENT ON TRIGGER set_public_broadcast_updated_at ON public.broadcast IS 'trigger to set value of column "updated_at" to current timestamp on row update';


--
-- Name: customer set_public_customer_updated_at; Type: TRIGGER; Schema: public; Owner: doadmin
--

CREATE TRIGGER set_public_customer_updated_at BEFORE UPDATE ON public.customer FOR EACH ROW EXECUTE PROCEDURE public.set_current_timestamp_updated_at();


--
-- Name: TRIGGER set_public_customer_updated_at ON customer; Type: COMMENT; Schema: public; Owner: doadmin
--

COMMENT ON TRIGGER set_public_customer_updated_at ON public.customer IS 'trigger to set value of column "updated_at" to current timestamp on row update';


--
-- Name: department set_public_department_updated_at; Type: TRIGGER; Schema: public; Owner: doadmin
--

CREATE TRIGGER set_public_department_updated_at BEFORE UPDATE ON public.department FOR EACH ROW EXECUTE PROCEDURE public.set_current_timestamp_updated_at();


--
-- Name: TRIGGER set_public_department_updated_at ON department; Type: COMMENT; Schema: public; Owner: doadmin
--

COMMENT ON TRIGGER set_public_department_updated_at ON public.department IS 'trigger to set value of column "updated_at" to current timestamp on row update';


--
-- Name: location set_public_location_updated_at; Type: TRIGGER; Schema: public; Owner: doadmin
--

CREATE TRIGGER set_public_location_updated_at BEFORE UPDATE ON public.location FOR EACH ROW EXECUTE PROCEDURE public.set_current_timestamp_updated_at();


--
-- Name: TRIGGER set_public_location_updated_at ON location; Type: COMMENT; Schema: public; Owner: doadmin
--

COMMENT ON TRIGGER set_public_location_updated_at ON public.location IS 'trigger to set value of column "updated_at" to current timestamp on row update';


--
-- Name: organization set_public_organization_updated_at; Type: TRIGGER; Schema: public; Owner: doadmin
--

CREATE TRIGGER set_public_organization_updated_at BEFORE UPDATE ON public.organization FOR EACH ROW EXECUTE PROCEDURE public.set_current_timestamp_updated_at();


--
-- Name: TRIGGER set_public_organization_updated_at ON organization; Type: COMMENT; Schema: public; Owner: doadmin
--

COMMENT ON TRIGGER set_public_organization_updated_at ON public.organization IS 'trigger to set value of column "updated_at" to current timestamp on row update';


--
-- Name: position set_public_position_updated_at; Type: TRIGGER; Schema: public; Owner: doadmin
--

CREATE TRIGGER set_public_position_updated_at BEFORE UPDATE ON public."position" FOR EACH ROW EXECUTE PROCEDURE public.set_current_timestamp_updated_at();


--
-- Name: TRIGGER set_public_position_updated_at ON "position"; Type: COMMENT; Schema: public; Owner: doadmin
--

COMMENT ON TRIGGER set_public_position_updated_at ON public."position" IS 'trigger to set value of column "updated_at" to current timestamp on row update';


--
-- Name: profile set_public_profile_updated_at; Type: TRIGGER; Schema: public; Owner: doadmin
--

CREATE TRIGGER set_public_profile_updated_at BEFORE UPDATE ON public.profile FOR EACH ROW EXECUTE PROCEDURE public.set_current_timestamp_updated_at();


--
-- Name: TRIGGER set_public_profile_updated_at ON profile; Type: COMMENT; Schema: public; Owner: doadmin
--

COMMENT ON TRIGGER set_public_profile_updated_at ON public.profile IS 'trigger to set value of column "updated_at" to current timestamp on row update';


--
-- Name: user set_public_user_updated_at; Type: TRIGGER; Schema: public; Owner: doadmin
--

CREATE TRIGGER set_public_user_updated_at BEFORE UPDATE ON public."user" FOR EACH ROW EXECUTE PROCEDURE public.set_current_timestamp_updated_at();


--
-- Name: TRIGGER set_public_user_updated_at ON "user"; Type: COMMENT; Schema: public; Owner: doadmin
--

COMMENT ON TRIGGER set_public_user_updated_at ON public."user" IS 'trigger to set value of column "updated_at" to current timestamp on row update';


--
-- Name: worker set_public_worker_updated_at; Type: TRIGGER; Schema: public; Owner: doadmin
--

CREATE TRIGGER set_public_worker_updated_at BEFORE UPDATE ON public.worker FOR EACH ROW EXECUTE PROCEDURE public.set_current_timestamp_updated_at();


--
-- Name: TRIGGER set_public_worker_updated_at ON worker; Type: COMMENT; Schema: public; Owner: doadmin
--

COMMENT ON TRIGGER set_public_worker_updated_at ON public.worker IS 'trigger to set value of column "updated_at" to current timestamp on row update';


--
-- Name: event_invocation_logs event_invocation_logs_event_id_fkey; Type: FK CONSTRAINT; Schema: hdb_catalog; Owner: doadmin
--

ALTER TABLE ONLY hdb_catalog.event_invocation_logs
    ADD CONSTRAINT event_invocation_logs_event_id_fkey FOREIGN KEY (event_id) REFERENCES hdb_catalog.event_log(id);


--
-- Name: event_triggers event_triggers_schema_name_fkey; Type: FK CONSTRAINT; Schema: hdb_catalog; Owner: doadmin
--

ALTER TABLE ONLY hdb_catalog.event_triggers
    ADD CONSTRAINT event_triggers_schema_name_fkey FOREIGN KEY (schema_name, table_name) REFERENCES hdb_catalog.hdb_table(table_schema, table_name) ON UPDATE CASCADE;


--
-- Name: hdb_allowlist hdb_allowlist_collection_name_fkey; Type: FK CONSTRAINT; Schema: hdb_catalog; Owner: doadmin
--

ALTER TABLE ONLY hdb_catalog.hdb_allowlist
    ADD CONSTRAINT hdb_allowlist_collection_name_fkey FOREIGN KEY (collection_name) REFERENCES hdb_catalog.hdb_query_collection(collection_name);


--
-- Name: hdb_computed_field hdb_computed_field_table_schema_fkey; Type: FK CONSTRAINT; Schema: hdb_catalog; Owner: doadmin
--

ALTER TABLE ONLY hdb_catalog.hdb_computed_field
    ADD CONSTRAINT hdb_computed_field_table_schema_fkey FOREIGN KEY (table_schema, table_name) REFERENCES hdb_catalog.hdb_table(table_schema, table_name) ON UPDATE CASCADE;


--
-- Name: hdb_permission hdb_permission_table_schema_fkey; Type: FK CONSTRAINT; Schema: hdb_catalog; Owner: doadmin
--

ALTER TABLE ONLY hdb_catalog.hdb_permission
    ADD CONSTRAINT hdb_permission_table_schema_fkey FOREIGN KEY (table_schema, table_name) REFERENCES hdb_catalog.hdb_table(table_schema, table_name) ON UPDATE CASCADE;


--
-- Name: hdb_relationship hdb_relationship_table_schema_fkey; Type: FK CONSTRAINT; Schema: hdb_catalog; Owner: doadmin
--

ALTER TABLE ONLY hdb_catalog.hdb_relationship
    ADD CONSTRAINT hdb_relationship_table_schema_fkey FOREIGN KEY (table_schema, table_name) REFERENCES hdb_catalog.hdb_table(table_schema, table_name) ON UPDATE CASCADE;


--
-- Name: broadcast_recipient broadcast_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.broadcast_recipient
    ADD CONSTRAINT broadcast_id_fk FOREIGN KEY (broadcast_id) REFERENCES public.broadcast(id);


--
-- Name: customer_user customer_user_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.customer_user
    ADD CONSTRAINT customer_user_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customer(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: customer_user customer_user_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.customer_user
    ADD CONSTRAINT customer_user_user_id_fkey FOREIGN KEY (user_id) REFERENCES public."user"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: department department_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.department
    ADD CONSTRAINT department_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: department department_parent_department_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.department
    ADD CONSTRAINT department_parent_department_id_fkey FOREIGN KEY (parent_id) REFERENCES public.department(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: location location_address_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.location
    ADD CONSTRAINT location_address_id_fkey FOREIGN KEY (address_id) REFERENCES public.address(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: location location_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.location
    ADD CONSTRAINT location_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: organization organization_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.organization
    ADD CONSTRAINT organization_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customer(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: broadcast organization_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.broadcast
    ADD CONSTRAINT organization_id_fk FOREIGN KEY (organization_id) REFERENCES public.organization(id) NOT VALID;


--
-- Name: position position_department_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public."position"
    ADD CONSTRAINT position_department_id_fkey FOREIGN KEY (department_id) REFERENCES public.department(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: position position_location_fkey; Type: FK CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public."position"
    ADD CONSTRAINT position_location_fkey FOREIGN KEY (location_id) REFERENCES public.location(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: position position_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public."position"
    ADD CONSTRAINT position_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: position position_parent_position_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public."position"
    ADD CONSTRAINT position_parent_position_id_fkey FOREIGN KEY (parent_id) REFERENCES public."position"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: position position_profile_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public."position"
    ADD CONSTRAINT position_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES public.profile(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: position position_status_fkey; Type: FK CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public."position"
    ADD CONSTRAINT position_status_fkey FOREIGN KEY (status) REFERENCES public.position_status(value);


--
-- Name: position position_subtype_fkey; Type: FK CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public."position"
    ADD CONSTRAINT position_subtype_fkey FOREIGN KEY (subtype) REFERENCES public.position_subtype(value);


--
-- Name: position position_time_type_fkey; Type: FK CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public."position"
    ADD CONSTRAINT position_time_type_fkey FOREIGN KEY (time_type) REFERENCES public.position_time_type(value);


--
-- Name: positionsancestors positionsancestors_ancestor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.positionsancestors
    ADD CONSTRAINT positionsancestors_ancestor_id_fkey FOREIGN KEY (ancestor_id) REFERENCES public."position"(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: positionsancestors positionsancestors_position_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.positionsancestors
    ADD CONSTRAINT positionsancestors_position_id_fkey FOREIGN KEY (position_id) REFERENCES public."position"(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: broadcast_recipient receiver_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.broadcast_recipient
    ADD CONSTRAINT receiver_id_fk FOREIGN KEY (receiver_id) REFERENCES public.worker(id) NOT VALID;


--
-- Name: broadcast_recipient response_location_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.broadcast_recipient
    ADD CONSTRAINT response_location_id_fk FOREIGN KEY (response_location_id) REFERENCES public.location(id);


--
-- Name: broadcast sender_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.broadcast
    ADD CONSTRAINT sender_id_fk FOREIGN KEY (sender_id) REFERENCES public.worker(id);


--
-- Name: worker worker_gender_fkey; Type: FK CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.worker
    ADD CONSTRAINT worker_gender_fkey FOREIGN KEY (gender) REFERENCES public.worker_gender(value);


--
-- Name: worker worker_location_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.worker
    ADD CONSTRAINT worker_location_id_fkey FOREIGN KEY (location_id) REFERENCES public.location(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: worker_position worker_position_position_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.worker_position
    ADD CONSTRAINT worker_position_position_id_fkey FOREIGN KEY (position_id) REFERENCES public."position"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: worker_position worker_position_worker_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.worker_position
    ADD CONSTRAINT worker_position_worker_id_fkey FOREIGN KEY (worker_id) REFERENCES public.worker(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: worker worker_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: doadmin
--

ALTER TABLE ONLY public.worker
    ADD CONSTRAINT worker_user_id_fkey FOREIGN KEY (user_id) REFERENCES public."user"(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- PostgreSQL database dump complete
--


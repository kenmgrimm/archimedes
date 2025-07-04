SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: vector; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA public;


--
-- Name: EXTENSION vector; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION vector IS 'vector data type and ivfflat and hnsw access methods';


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: active_storage_attachments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_attachments (
    id bigint NOT NULL,
    name character varying NOT NULL,
    record_type character varying NOT NULL,
    record_id bigint NOT NULL,
    blob_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: active_storage_attachments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.active_storage_attachments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: active_storage_attachments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.active_storage_attachments_id_seq OWNED BY public.active_storage_attachments.id;


--
-- Name: active_storage_blobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_blobs (
    id bigint NOT NULL,
    key character varying NOT NULL,
    filename character varying NOT NULL,
    content_type character varying,
    metadata text,
    service_name character varying NOT NULL,
    byte_size bigint NOT NULL,
    checksum character varying,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: active_storage_blobs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.active_storage_blobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: active_storage_blobs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.active_storage_blobs_id_seq OWNED BY public.active_storage_blobs.id;


--
-- Name: active_storage_variant_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_variant_records (
    id bigint NOT NULL,
    blob_id bigint NOT NULL,
    variation_digest character varying NOT NULL
);


--
-- Name: active_storage_variant_records_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.active_storage_variant_records_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: active_storage_variant_records_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.active_storage_variant_records_id_seq OWNED BY public.active_storage_variant_records.id;


--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: contents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contents (
    id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    note text,
    openai_response jsonb,
    note_embedding public.vector(1536)
);


--
-- Name: contents_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.contents_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: contents_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.contents_id_seq OWNED BY public.contents.id;


--
-- Name: entities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.entities (
    id bigint NOT NULL,
    content_id integer NOT NULL,
    name character varying NOT NULL,
    canonical_entity_id bigint,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    name_embedding public.vector(1536),
    description text,
    verification_status character varying DEFAULT 'verified'::character varying,
    verified_at timestamp(6) without time zone,
    verified_by character varying
);


--
-- Name: entities_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.entities_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: entities_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.entities_id_seq OWNED BY public.entities.id;


--
-- Name: entity_merges; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.entity_merges (
    id bigint NOT NULL,
    source_entity_id bigint,
    target_entity_id bigint NOT NULL,
    transferred_statements_count integer,
    initiated_by character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: entity_merges_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.entity_merges_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: entity_merges_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.entity_merges_id_seq OWNED BY public.entity_merges.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: statements; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.statements (
    id bigint NOT NULL,
    entity_id bigint NOT NULL,
    object_entity_id bigint,
    content_id bigint NOT NULL,
    text text NOT NULL,
    confidence double precision DEFAULT 1.0,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    text_embedding public.vector(1536),
    predicate character varying,
    object character varying,
    object_type character varying DEFAULT 'literal'::character varying,
    source character varying,
    extraction_method character varying DEFAULT 'ai'::character varying
);


--
-- Name: COLUMN statements.entity_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.statements.entity_id IS 'Subject entity';


--
-- Name: COLUMN statements.object_entity_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.statements.object_entity_id IS 'Optional object entity for relationships';


--
-- Name: COLUMN statements.content_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.statements.content_id IS 'Source content';


--
-- Name: COLUMN statements.text; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.statements.text IS 'The statement text';


--
-- Name: COLUMN statements.confidence; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.statements.confidence IS 'Confidence score (0-1)';


--
-- Name: statements_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.statements_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: statements_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.statements_id_seq OWNED BY public.statements.id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id bigint NOT NULL,
    email character varying DEFAULT ''::character varying NOT NULL,
    encrypted_password character varying DEFAULT ''::character varying NOT NULL,
    reset_password_token character varying,
    reset_password_sent_at timestamp(6) without time zone,
    remember_created_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    full_name character varying NOT NULL,
    given_name character varying NOT NULL,
    family_name character varying NOT NULL,
    phone character varying,
    birth_date date,
    aliases jsonb DEFAULT '[]'::jsonb NOT NULL
);


--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- Name: verification_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.verification_requests (
    id bigint NOT NULL,
    content_id bigint NOT NULL,
    candidate_name character varying NOT NULL,
    status character varying DEFAULT 'pending'::character varying,
    similar_entities json,
    pending_statements json,
    verified_entity_id bigint,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: verification_requests_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.verification_requests_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: verification_requests_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.verification_requests_id_seq OWNED BY public.verification_requests.id;


--
-- Name: active_storage_attachments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments ALTER COLUMN id SET DEFAULT nextval('public.active_storage_attachments_id_seq'::regclass);


--
-- Name: active_storage_blobs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_blobs ALTER COLUMN id SET DEFAULT nextval('public.active_storage_blobs_id_seq'::regclass);


--
-- Name: active_storage_variant_records id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records ALTER COLUMN id SET DEFAULT nextval('public.active_storage_variant_records_id_seq'::regclass);


--
-- Name: contents id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contents ALTER COLUMN id SET DEFAULT nextval('public.contents_id_seq'::regclass);


--
-- Name: entities id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entities ALTER COLUMN id SET DEFAULT nextval('public.entities_id_seq'::regclass);


--
-- Name: entity_merges id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entity_merges ALTER COLUMN id SET DEFAULT nextval('public.entity_merges_id_seq'::regclass);


--
-- Name: statements id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.statements ALTER COLUMN id SET DEFAULT nextval('public.statements_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Name: verification_requests id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.verification_requests ALTER COLUMN id SET DEFAULT nextval('public.verification_requests_id_seq'::regclass);


--
-- Name: active_storage_attachments active_storage_attachments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments
    ADD CONSTRAINT active_storage_attachments_pkey PRIMARY KEY (id);


--
-- Name: active_storage_blobs active_storage_blobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_blobs
    ADD CONSTRAINT active_storage_blobs_pkey PRIMARY KEY (id);


--
-- Name: active_storage_variant_records active_storage_variant_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records
    ADD CONSTRAINT active_storage_variant_records_pkey PRIMARY KEY (id);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: contents contents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contents
    ADD CONSTRAINT contents_pkey PRIMARY KEY (id);


--
-- Name: entities entities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entities
    ADD CONSTRAINT entities_pkey PRIMARY KEY (id);


--
-- Name: entity_merges entity_merges_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entity_merges
    ADD CONSTRAINT entity_merges_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: statements statements_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.statements
    ADD CONSTRAINT statements_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: verification_requests verification_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.verification_requests
    ADD CONSTRAINT verification_requests_pkey PRIMARY KEY (id);


--
-- Name: index_active_storage_attachments_on_blob_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_active_storage_attachments_on_blob_id ON public.active_storage_attachments USING btree (blob_id);


--
-- Name: index_active_storage_attachments_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_attachments_uniqueness ON public.active_storage_attachments USING btree (record_type, record_id, name, blob_id);


--
-- Name: index_active_storage_blobs_on_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_blobs_on_key ON public.active_storage_blobs USING btree (key);


--
-- Name: index_active_storage_variant_records_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_variant_records_uniqueness ON public.active_storage_variant_records USING btree (blob_id, variation_digest);


--
-- Name: index_contents_on_note_embedding; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_contents_on_note_embedding ON public.contents USING ivfflat (note_embedding) WITH (lists='10');


--
-- Name: index_entities_on_canonical_entity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_entities_on_canonical_entity_id ON public.entities USING btree (canonical_entity_id);


--
-- Name: index_entities_on_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_entities_on_name ON public.entities USING btree (name);


--
-- Name: index_entities_on_name_embedding; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_entities_on_name_embedding ON public.entities USING ivfflat (name_embedding) WITH (lists='10');


--
-- Name: index_entity_merges_on_source_entity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_entity_merges_on_source_entity_id ON public.entity_merges USING btree (source_entity_id);


--
-- Name: index_entity_merges_on_target_entity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_entity_merges_on_target_entity_id ON public.entity_merges USING btree (target_entity_id);


--
-- Name: index_statements_on_content_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_statements_on_content_id ON public.statements USING btree (content_id);


--
-- Name: index_statements_on_entity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_statements_on_entity_id ON public.statements USING btree (entity_id);


--
-- Name: index_statements_on_entity_id_and_predicate; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_statements_on_entity_id_and_predicate ON public.statements USING btree (entity_id, predicate);


--
-- Name: index_statements_on_object_entity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_statements_on_object_entity_id ON public.statements USING btree (object_entity_id);


--
-- Name: index_statements_on_object_entity_id_and_predicate; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_statements_on_object_entity_id_and_predicate ON public.statements USING btree (object_entity_id, predicate);


--
-- Name: index_statements_on_object_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_statements_on_object_type ON public.statements USING btree (object_type);


--
-- Name: index_statements_on_predicate; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_statements_on_predicate ON public.statements USING btree (predicate);


--
-- Name: index_users_on_aliases; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_users_on_aliases ON public.users USING gin (aliases);


--
-- Name: index_users_on_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_email ON public.users USING btree (email);


--
-- Name: index_users_on_family_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_users_on_family_name ON public.users USING btree (family_name);


--
-- Name: index_users_on_given_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_users_on_given_name ON public.users USING btree (given_name);


--
-- Name: index_users_on_reset_password_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_reset_password_token ON public.users USING btree (reset_password_token);


--
-- Name: index_verification_requests_on_content_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_verification_requests_on_content_id ON public.verification_requests USING btree (content_id);


--
-- Name: index_verification_requests_on_content_id_and_candidate_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_verification_requests_on_content_id_and_candidate_name ON public.verification_requests USING btree (content_id, candidate_name);


--
-- Name: index_verification_requests_on_verified_entity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_verification_requests_on_verified_entity_id ON public.verification_requests USING btree (verified_entity_id);


--
-- Name: statements_text_embedding_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX statements_text_embedding_idx ON public.statements USING ivfflat (text_embedding public.vector_cosine_ops);


--
-- Name: verification_requests fk_rails_0b202b196c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.verification_requests
    ADD CONSTRAINT fk_rails_0b202b196c FOREIGN KEY (verified_entity_id) REFERENCES public.entities(id);


--
-- Name: entity_merges fk_rails_2519e311e7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entity_merges
    ADD CONSTRAINT fk_rails_2519e311e7 FOREIGN KEY (target_entity_id) REFERENCES public.entities(id);


--
-- Name: verification_requests fk_rails_775eb4705d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.verification_requests
    ADD CONSTRAINT fk_rails_775eb4705d FOREIGN KEY (content_id) REFERENCES public.contents(id);


--
-- Name: entity_merges fk_rails_7e85dd8717; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entity_merges
    ADD CONSTRAINT fk_rails_7e85dd8717 FOREIGN KEY (source_entity_id) REFERENCES public.entities(id);


--
-- Name: active_storage_variant_records fk_rails_993965df05; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records
    ADD CONSTRAINT fk_rails_993965df05 FOREIGN KEY (blob_id) REFERENCES public.active_storage_blobs(id);


--
-- Name: active_storage_attachments fk_rails_c3b3935057; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments
    ADD CONSTRAINT fk_rails_c3b3935057 FOREIGN KEY (blob_id) REFERENCES public.active_storage_blobs(id);


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20250704224601'),
('20250625000000'),
('20250624233500'),
('20250624211254'),
('20250624210618'),
('20250624210606'),
('20250624042542'),
('20250623202600'),
('20250623202500'),
('20250623051144'),
('20250623050527'),
('20250623031347'),
('20250623031312'),
('20250623022522'),
('2025062302'),
('2025062301');


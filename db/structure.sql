CREATE TABLE IF NOT EXISTS "schema_migrations" ("version" varchar NOT NULL PRIMARY KEY);
CREATE TABLE IF NOT EXISTS "ar_internal_metadata" ("key" varchar NOT NULL PRIMARY KEY, "value" varchar, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE TABLE IF NOT EXISTS "active_storage_blobs" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "key" varchar NOT NULL, "filename" varchar NOT NULL, "content_type" varchar, "metadata" text, "service_name" varchar NOT NULL, "byte_size" bigint NOT NULL, "checksum" varchar, "created_at" datetime(6) NOT NULL);
CREATE UNIQUE INDEX "index_active_storage_blobs_on_key" ON "active_storage_blobs" ("key") /*application='Docsage'*/;
CREATE TABLE IF NOT EXISTS "active_storage_attachments" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "name" varchar NOT NULL, "record_type" varchar NOT NULL, "record_id" bigint NOT NULL, "blob_id" bigint NOT NULL, "created_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_c3b3935057"
FOREIGN KEY ("blob_id")
  REFERENCES "active_storage_blobs" ("id")
);
CREATE INDEX "index_active_storage_attachments_on_blob_id" ON "active_storage_attachments" ("blob_id") /*application='Docsage'*/;
CREATE UNIQUE INDEX "index_active_storage_attachments_uniqueness" ON "active_storage_attachments" ("record_type", "record_id", "name", "blob_id") /*application='Docsage'*/;
CREATE TABLE IF NOT EXISTS "active_storage_variant_records" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "blob_id" bigint NOT NULL, "variation_digest" varchar NOT NULL, CONSTRAINT "fk_rails_993965df05"
FOREIGN KEY ("blob_id")
  REFERENCES "active_storage_blobs" ("id")
);
CREATE UNIQUE INDEX "index_active_storage_variant_records_uniqueness" ON "active_storage_variant_records" ("blob_id", "variation_digest") /*application='Docsage'*/;
CREATE TABLE IF NOT EXISTS "documents" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "title" varchar, "status" varchar, "content_kind" varchar, "byte_size" integer, "chunk_count" integer, "error_message" varchar, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, "page_count" integer DEFAULT 0 NOT NULL /*application='Docsage'*/, "indexed_page_count" integer DEFAULT 0 NOT NULL /*application='Docsage'*/, "outline" text /*application='Docsage'*/);
CREATE VIRTUAL TABLE chunk_search USING fts5(
  content,
  chunk_id UNINDEXED,
  document_id UNINDEXED,
  tokenize = 'porter unicode61'
)
/* chunk_search(content,chunk_id,document_id) */;
CREATE TABLE IF NOT EXISTS 'chunk_search_data'(id INTEGER PRIMARY KEY, block BLOB);
CREATE TABLE IF NOT EXISTS 'chunk_search_idx'(segid, term, pgno, PRIMARY KEY(segid, term)) WITHOUT ROWID;
CREATE TABLE IF NOT EXISTS 'chunk_search_content'(id INTEGER PRIMARY KEY, c0, c1, c2);
CREATE TABLE IF NOT EXISTS 'chunk_search_docsize'(id INTEGER PRIMARY KEY, sz BLOB);
CREATE TABLE IF NOT EXISTS 'chunk_search_config'(k PRIMARY KEY, v) WITHOUT ROWID;
CREATE TABLE IF NOT EXISTS "agent_contexts" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "contextable_type" varchar, "contextable_id" integer, "agent_name" varchar NOT NULL, "action_name" varchar NOT NULL, "instructions" text, "options" json DEFAULT '{}', "trace_id" varchar, "total_input_tokens" integer DEFAULT 0, "total_output_tokens" integer DEFAULT 0, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE INDEX "index_agent_contexts_on_contextable" ON "agent_contexts" ("contextable_type", "contextable_id") /*application='Docsage'*/;
CREATE INDEX "index_agent_contexts_on_trace_id" ON "agent_contexts" ("trace_id") /*application='Docsage'*/;
CREATE INDEX "index_agent_contexts_on_agent_name_and_action_name" ON "agent_contexts" ("agent_name", "action_name") /*application='Docsage'*/;
CREATE INDEX "index_agent_contexts_on_created_at" ON "agent_contexts" ("created_at") /*application='Docsage'*/;
CREATE TABLE IF NOT EXISTS "agent_messages" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "agent_context_id" integer NOT NULL, "role" varchar NOT NULL, "content" text, "tool_call_id" varchar, "tool_name" varchar, "tool_arguments" json DEFAULT '{}', "tool_result" json, "attachments" json DEFAULT '[]', "metadata" json DEFAULT '{}', "provenance" json DEFAULT '{}', "content_checksum" varchar, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_898e910e87"
FOREIGN KEY ("agent_context_id")
  REFERENCES "agent_contexts" ("id")
);
CREATE INDEX "index_agent_messages_on_agent_context_id" ON "agent_messages" ("agent_context_id") /*application='Docsage'*/;
CREATE INDEX "index_agent_messages_on_role" ON "agent_messages" ("role") /*application='Docsage'*/;
CREATE INDEX "index_agent_messages_on_tool_call_id" ON "agent_messages" ("tool_call_id") /*application='Docsage'*/;
CREATE INDEX "index_agent_messages_on_agent_context_id_and_created_at" ON "agent_messages" ("agent_context_id", "created_at") /*application='Docsage'*/;
CREATE TABLE IF NOT EXISTS "agent_generations" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "agent_context_id" integer NOT NULL, "content" text, "model" varchar, "provider" varchar, "finish_reason" varchar, "input_tokens" integer DEFAULT 0, "output_tokens" integer DEFAULT 0, "cached_tokens" integer DEFAULT 0, "reasoning_tokens" integer DEFAULT 0, "tool_calls" json DEFAULT '[]', "raw_response" json, "duration_seconds" float, "trace_id" varchar, "provenance" json DEFAULT '{}', "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_1eef1d7845"
FOREIGN KEY ("agent_context_id")
  REFERENCES "agent_contexts" ("id")
);
CREATE INDEX "index_agent_generations_on_agent_context_id" ON "agent_generations" ("agent_context_id") /*application='Docsage'*/;
CREATE INDEX "index_agent_generations_on_model" ON "agent_generations" ("model") /*application='Docsage'*/;
CREATE INDEX "index_agent_generations_on_finish_reason" ON "agent_generations" ("finish_reason") /*application='Docsage'*/;
CREATE INDEX "index_agent_generations_on_trace_id" ON "agent_generations" ("trace_id") /*application='Docsage'*/;
CREATE INDEX "index_agent_generations_on_agent_context_id_and_created_at" ON "agent_generations" ("agent_context_id", "created_at") /*application='Docsage'*/;
CREATE TABLE IF NOT EXISTS "agent_memories" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "memorable_type" varchar, "memorable_id" integer, "scope" varchar DEFAULT 'default' NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE INDEX "index_agent_memories_on_memorable" ON "agent_memories" ("memorable_type", "memorable_id") /*application='Docsage'*/;
CREATE UNIQUE INDEX "idx_on_memorable_type_memorable_id_scope_4cc0762a41" ON "agent_memories" ("memorable_type", "memorable_id", "scope") /*application='Docsage'*/;
CREATE TABLE IF NOT EXISTS "agent_memory_entries" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "agent_memory_id" integer NOT NULL, "content" text NOT NULL, "source_agent" varchar, "category" varchar, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_1b2cea67c7"
FOREIGN KEY ("agent_memory_id")
  REFERENCES "agent_memories" ("id")
);
CREATE INDEX "index_agent_memory_entries_on_agent_memory_id" ON "agent_memory_entries" ("agent_memory_id") /*application='Docsage'*/;
CREATE INDEX "index_agent_memory_entries_on_agent_memory_id_and_created_at" ON "agent_memory_entries" ("agent_memory_id", "created_at") /*application='Docsage'*/;
CREATE INDEX "index_agent_memory_entries_on_category" ON "agent_memory_entries" ("category") /*application='Docsage'*/;
CREATE TABLE IF NOT EXISTS "agent_runs" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "runnable_type" varchar, "runnable_id" integer, "agent_name" varchar, "action_name" varchar, "trace_id" varchar, "status" varchar DEFAULT 'pending' NOT NULL, "input_prompt" text, "input_params" json DEFAULT '{}', "output" text, "output_metadata" json DEFAULT '{}', "error_message" text, "events" json DEFAULT '[]', "instructions_digest" varchar, "input_tokens" integer DEFAULT 0, "output_tokens" integer DEFAULT 0, "duration_ms" integer, "started_at" datetime(6), "completed_at" datetime(6), "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE INDEX "index_agent_runs_on_runnable" ON "agent_runs" ("runnable_type", "runnable_id") /*application='Docsage'*/;
CREATE INDEX "index_agent_runs_on_status" ON "agent_runs" ("status") /*application='Docsage'*/;
CREATE INDEX "index_agent_runs_on_trace_id" ON "agent_runs" ("trace_id") /*application='Docsage'*/;
CREATE INDEX "index_agent_runs_on_instructions_digest" ON "agent_runs" ("instructions_digest") /*application='Docsage'*/;
CREATE INDEX "index_agent_runs_on_created_at" ON "agent_runs" ("created_at") /*application='Docsage'*/;
CREATE TABLE IF NOT EXISTS "document_pages" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "document_id" integer NOT NULL, "number" integer NOT NULL, "status" varchar DEFAULT 'pending' NOT NULL, "content" text, "start_line" integer, "chunk_count" integer DEFAULT 0 NOT NULL, "error_message" varchar, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_1ce94307b7"
FOREIGN KEY ("document_id")
  REFERENCES "documents" ("id")
);
CREATE INDEX "index_document_pages_on_document_id" ON "document_pages" ("document_id") /*application='Docsage'*/;
CREATE UNIQUE INDEX "index_document_pages_on_document_id_and_number" ON "document_pages" ("document_id", "number") /*application='Docsage'*/;
CREATE TABLE IF NOT EXISTS "chunks" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "document_id" integer NOT NULL, "position" integer, "content" text, "locator" varchar, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, "document_page_id" integer, CONSTRAINT "fk_rails_1dac2f17d2"
FOREIGN KEY ("document_id")
  REFERENCES "documents" ("id")
, CONSTRAINT "fk_rails_9d4dd89ac1"
FOREIGN KEY ("document_page_id")
  REFERENCES "document_pages" ("id")
);
CREATE INDEX "index_chunks_on_document_id" ON "chunks" ("document_id") /*application='Docsage'*/;
CREATE INDEX "index_chunks_on_document_page_id" ON "chunks" ("document_page_id") /*application='Docsage'*/;
INSERT INTO "schema_migrations" (version) VALUES
('20260801181000'),
('20260801180000'),
('20260801164510'),
('20260801164509'),
('20260801164508'),
('20260801164507'),
('20260801164506'),
('20260801162526'),
('20260801162525'),
('20260801162524'),
('20260801162413');


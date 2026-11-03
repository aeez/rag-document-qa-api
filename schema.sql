CREATE EXTENSION IF NOT EXISTS vector;
CREATE TABLE chunks (
    document_id uuid NOT NULL,
    chunk_id integer NOT NULL,
    filename text NOT NULL,
    page integer NOT NULL,
    passage text NOT NULL,
    embedding vector(1024) NOT NULL,
    PRIMARY KEY (document_id, chunk_id)
);

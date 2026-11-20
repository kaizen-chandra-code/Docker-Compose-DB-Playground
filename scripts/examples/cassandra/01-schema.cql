CREATE TABLE IF NOT EXISTS app.demo_stream_titles_by_id (
    title_id text PRIMARY KEY,
    title text,
    release_year int,
    genres set<text>,
    synopsis text
);

CREATE TABLE IF NOT EXISTS app.demo_stream_titles_by_genre_year (
    genre text,
    release_year int,
    title_id text,
    title text,
    PRIMARY KEY ((genre, release_year), title_id)
);

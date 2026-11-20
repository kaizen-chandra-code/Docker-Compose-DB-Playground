INSERT INTO app.demo_stream_titles_by_id
(title_id, title, release_year, genres, synopsis)
VALUES ('t01', 'Signal at Dawn', 2025, {'Sci-Fi', 'Drama'}, 'An engineer traces a mysterious broadcast.');
INSERT INTO app.demo_stream_titles_by_id
(title_id, title, release_year, genres, synopsis)
VALUES ('t02', 'Beyond the Reef', 2025, {'Documentary'}, 'Divers survey a coral reef.');
INSERT INTO app.demo_stream_titles_by_id
(title_id, title, release_year, genres, synopsis)
VALUES ('t03', 'The Quiet Orbit', 2025, {'Sci-Fi'}, 'A pilot makes one last delivery.');
INSERT INTO app.demo_stream_titles_by_id
(title_id, title, release_year, genres, synopsis)
VALUES ('t04', 'Red Horizon', 2024, {'Sci-Fi'}, 'A survey crew maps a desert moon.');

INSERT INTO app.demo_stream_titles_by_genre_year (genre, release_year, title_id, title)
VALUES ('Sci-Fi', 2025, 't01', 'Signal at Dawn');
INSERT INTO app.demo_stream_titles_by_genre_year (genre, release_year, title_id, title)
VALUES ('Drama', 2025, 't01', 'Signal at Dawn');
INSERT INTO app.demo_stream_titles_by_genre_year (genre, release_year, title_id, title)
VALUES ('Documentary', 2025, 't02', 'Beyond the Reef');
INSERT INTO app.demo_stream_titles_by_genre_year (genre, release_year, title_id, title)
VALUES ('Sci-Fi', 2025, 't03', 'The Quiet Orbit');
INSERT INTO app.demo_stream_titles_by_genre_year (genre, release_year, title_id, title)
VALUES ('Sci-Fi', 2024, 't04', 'Red Horizon');

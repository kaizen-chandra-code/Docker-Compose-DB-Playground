SELECT title_id, title, release_year, genres, synopsis
FROM app.demo_stream_titles_by_id WHERE title_id = 't01';

SELECT title_id, title
FROM app.demo_stream_titles_by_genre_year
WHERE genre = 'Sci-Fi' AND release_year = 2025
ORDER BY title_id ASC LIMIT 10;

SELECT title_id, title
FROM app.demo_stream_titles_by_genre_year
WHERE genre = 'Drama' AND release_year = 2025;

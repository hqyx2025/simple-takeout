SET @takeout_score_ddl = IF(
    EXISTS(SELECT 1 FROM information_schema.columns
           WHERE table_schema = DATABASE() AND table_name = 'stores' AND column_name = 'rating_count'),
    'SELECT 1', 'ALTER TABLE stores ADD COLUMN rating_count INT NOT NULL DEFAULT 0');
PREPARE takeout_score_stmt FROM @takeout_score_ddl;
EXECUTE takeout_score_stmt;
DEALLOCATE PREPARE takeout_score_stmt;

UPDATE stores s LEFT JOIN (
    SELECT store_id, ROUND(AVG(person_rating), 1) AS score, COUNT(*) AS voters
    FROM (SELECT store_id, user_id, AVG(rating) AS person_rating FROM reviews
          WHERE user_id > 0 AND rating BETWEEN 1 AND 5 GROUP BY store_id, user_id) per_person
    GROUP BY store_id
) r ON r.store_id = s.id
SET s.rating = COALESCE(r.score, 0), s.rating_count = COALESCE(r.voters, 0);

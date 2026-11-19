SET @takeout_gallery_ddl = IF(
    EXISTS(SELECT 1 FROM information_schema.columns
           WHERE table_schema = DATABASE() AND table_name = 'stores' AND column_name = 'images'),
    'SELECT 1', 'ALTER TABLE stores ADD COLUMN images TEXT NULL');
PREPARE takeout_gallery_stmt FROM @takeout_gallery_ddl;
EXECUTE takeout_gallery_stmt;
DEALLOCATE PREPARE takeout_gallery_stmt;

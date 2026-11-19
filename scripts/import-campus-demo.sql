-- Run as one MySQL session in the target takeout schema, with --force disabled.
-- Set @campus_owner to an existing disabled demo merchant before running this file.
SET NAMES utf8mb4;
SET @campus_marker = '【演示数据】南宁学院周边；模拟点位与菜单，非真实商家。';
CREATE TEMPORARY TABLE campus_import_guard (ok INT NOT NULL CHECK (ok = 1));
CREATE TEMPORARY TABLE campus_catalog (
    name VARCHAR(128) PRIMARY KEY, category_id INT NOT NULL, area VARCHAR(32) NOT NULL,
    latitude DECIMAL(10,7) NOT NULL, longitude DECIMAL(10,7) NOT NULL, menu JSON NOT NULL
) DEFAULT CHARSET=utf8mb4;
INSERT INTO campus_catalog VALUES
('【演示】南院老友粉',7,'北门周边',22.7568,108.4540,JSON_ARRAY('经典老友粉','酸辣牛肉粉','炸蛋')),
('【演示】南院桂味快餐',2,'北门周边',22.7578,108.4540,JSON_ARRAY('柠檬鸭饭','酸笋牛肉饭','时蔬')),
('【演示】南院茶饮站',3,'北门周边',22.7568,108.4553,JSON_ARRAY('手打柠檬茶','茉莉奶茶','百香果茶')),
('【演示】南院烧烤小铺',6,'北门周边',22.7578,108.4553,JSON_ARRAY('烤鸡翅','烤玉米','肉串拼盘')),
('【演示】南院螺蛳粉',7,'校区东侧',22.7490,108.4620,JSON_ARRAY('经典螺蛳粉','酸笋拌粉','炸腐竹')),
('【演示】南院盖饭食堂',2,'校区东侧',22.7500,108.4620,JSON_ARRAY('黑椒鸡腿饭','番茄牛腩饭','番茄蛋汤')),
('【演示】南院咖啡烘焙',3,'校区东侧',22.7490,108.4633,JSON_ARRAY('冰美式','拿铁','黄油可颂')),
('【演示】南院糖水铺',4,'校区东侧',22.7500,108.4633,JSON_ARRAY('芋圆糖水','红豆双皮奶','龟苓膏')),
('【演示】南院手作饺子',7,'校区南侧',22.7390,108.4510,JSON_ARRAY('玉米鲜肉饺','韭菜鸡蛋饺','凉拌黄瓜')),
('【演示】南院轻食饭团',2,'校区南侧',22.7400,108.4510,JSON_ARRAY('照烧鸡肉饭团','牛油果饭团','玉米沙拉')),
('【演示】南院鸡排小食',6,'校区南侧',22.7390,108.4523,JSON_ARRAY('椒盐鸡排','炸红薯条','鸡米花')),
('【演示】南院砂锅小馆',2,'校区南侧',22.7400,108.4523,JSON_ARRAY('砂锅牛肉饭','香菇滑鸡饭','海带汤'));

INSERT INTO campus_import_guard VALUES (GET_LOCK('takeout-campus-demo-import', 10));
START TRANSACTION;
INSERT INTO campus_import_guard
    SELECT COUNT(*) FROM users WHERE id = @campus_owner AND role = 1 AND status = 0
        AND username LIKE '演示店主-%' FOR UPDATE;
INSERT INTO campus_import_guard
    SELECT NOT EXISTS(SELECT 1 FROM stores s JOIN campus_catalog c ON c.name = s.name
        WHERE s.owner_id <> @campus_owner OR NOT (s.notice <=> @campus_marker));
INSERT INTO stores(name,owner_id,category_id,category_ids,review_status,address,latitude,longitude,
                   delivery_radius,delivery_fee,min_order,delivery_time,notice,create_time)
SELECT c.name,@campus_owner,c.category_id,JSON_ARRAY(1,c.category_id),1,
       CONCAT('南宁市邕宁区南宁学院',c.area,'（演示点位）'),c.latitude,c.longitude,
       0,2,10,'25分钟',@campus_marker,NOW()
FROM campus_catalog c WHERE NOT EXISTS(SELECT 1 FROM stores s WHERE s.name = c.name);
INSERT INTO goods(store_id,name,description,price,category_id,stock,rating,create_time)
SELECT s.id,m.name,'演示菜单',CASE m.ord WHEN 1 THEN 15 WHEN 2 THEN 18 ELSE 8 END,c.category_id,50,0,NOW()
FROM campus_catalog c JOIN stores s ON s.name = c.name AND s.owner_id = @campus_owner AND s.notice = @campus_marker
JOIN JSON_TABLE(c.menu, '$[*]' COLUMNS(ord FOR ORDINALITY, name VARCHAR(128) PATH '$')) m
WHERE NOT EXISTS(SELECT 1 FROM goods g WHERE g.store_id = s.id AND g.name = m.name);
INSERT INTO campus_import_guard
    SELECT COUNT(*) = 12 FROM stores WHERE owner_id = @campus_owner AND notice = @campus_marker;
INSERT INTO campus_import_guard
    SELECT COUNT(*) = 36 FROM goods g JOIN stores s ON s.id = g.store_id
        WHERE s.owner_id = @campus_owner AND s.notice = @campus_marker;
COMMIT;
SELECT 'campus demo stores' AS kind, COUNT(*) AS row_count FROM stores WHERE owner_id=@campus_owner AND notice=@campus_marker
UNION ALL
SELECT 'campus demo goods', COUNT(*) FROM goods g JOIN stores s ON s.id=g.store_id
 WHERE s.owner_id=@campus_owner AND s.notice=@campus_marker;
DO RELEASE_LOCK('takeout-campus-demo-import');

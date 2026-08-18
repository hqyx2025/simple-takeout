package com.example.takeout.config;

import com.example.takeout.security.PasswordUtil;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.concurrent.ThreadLocalRandom;

/**
 * 种子数据初始化：首次启动（数据表为空）时生成
 * 与客户端 MockDataService 对齐：8 分类、30 家店铺、每家 30 商品、5 个测试账号
 */
@Component
public class DataSeeder implements ApplicationRunner {

    private static final Logger log = LoggerFactory.getLogger(DataSeeder.class);
    private static final DateTimeFormatter FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    private final JdbcTemplate jdbc;

    public DataSeeder(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    @Override
    public void run(ApplicationArguments args) {
        ensureOrderEscrowColumn();
        ensureUserStatusColumn();
        ensureGoodsColumns();
        ensureCategoryColumns();
        ensureRefundTable();
        ensureCartTable();
        ensureReviewGoodsColumn();
        ensureStoreRecommendedColumn();
        // 分类是首页导航的基础数据，即使已有用户数据，也必须单独补齐。
        ensureCategories();
        Integer userCount = jdbc.queryForObject("SELECT COUNT(*) FROM users", Integer.class);
        if (userCount != null && userCount > 0) {
            ensureAdminUser();
            ensureStoresAndGoods();
            ensureAdditionalStores();
            log.info("用户数据已存在（users={}），已校验分类、店铺、商品和附近推荐数据", userCount);
            return;
        }
        seed();
        ensureAdminUser();
        ensureAdditionalStores();
        log.info("种子数据初始化完成：8 分类 / 40 店铺 / 1200 商品 / 5 账号");
    }

    private void ensureOrderEscrowColumn() {
        Integer count = jdbc.queryForObject(
                "SELECT COUNT(*) FROM information_schema.columns WHERE table_schema = DATABASE() " +
                        "AND table_name = 'orders' AND column_name = 'escrow_status'", Integer.class);
        if (count == null || count == 0) {
            jdbc.execute("ALTER TABLE orders ADD COLUMN escrow_status INT NOT NULL DEFAULT 0 AFTER reviewed");
            log.info("订单表已补充托管资金状态字段 escrow_status");
        }
    }

    /** 存量用户补充账号状态：1 启用，0 停用。 */
    private void ensureUserStatusColumn() {
        ensureColumn("users", "status", "INT NOT NULL DEFAULT 1");
    }

    /** 存量商品表补充库存/乐观锁/商户分类字段；存量商品默认库存 999（充足），避免旧数据无法下单。 */
    private void ensureGoodsColumns() {
        ensureColumn("goods", "stock", "INT NOT NULL DEFAULT 999");
        ensureColumn("goods", "version", "INT NOT NULL DEFAULT 0");
        ensureColumn("goods", "merchant_category_id", "BIGINT NOT NULL DEFAULT 0");
        boolean specialColumnAdded = ensureColumn("goods", "is_special", "INT NOT NULL DEFAULT 0");
        if (specialColumnAdded) {
            // 将旧版本已有原价折扣商品迁移为特价商品，后续启动不覆盖商户的取消操作。
            jdbc.update("UPDATE goods SET is_special = 1 WHERE is_special = 0 AND status = 1 " +
                    "AND original_price > price");
        }
        Integer count = jdbc.queryForObject("SELECT COUNT(*) FROM goods WHERE stock = 0", Integer.class);
        if (count != null && count > 0) {
            jdbc.update("UPDATE goods SET stock = 999 WHERE stock = 0");
            log.info("已为 {} 个存量商品补齐默认库存", count);
        }
    }

    /** 分类表补充类型/商户/排序字段（存量行均为平台分类）。 */
    private void ensureCategoryColumns() {
        ensureColumn("categories", "type", "VARCHAR(16) NOT NULL DEFAULT 'PLATFORM'");
        ensureColumn("categories", "merchant_id", "BIGINT NOT NULL DEFAULT 0");
        ensureColumn("categories", "sort", "INT NOT NULL DEFAULT 0");
        ensureColumn("categories", "status", "INT NOT NULL DEFAULT 1");
    }

    /** 退款记录表（演进项落地：用户申请退款 + 管理端审批）。 */
    private void ensureRefundTable() {
        Integer count = jdbc.queryForObject(
                "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() " +
                        "AND table_name = 'refund_records'", Integer.class);
        if (count == null || count == 0) {
            jdbc.execute("CREATE TABLE IF NOT EXISTS refund_records (" +
                    "id BIGINT AUTO_INCREMENT PRIMARY KEY, order_id BIGINT NOT NULL, user_id BIGINT NOT NULL, " +
                    "merchant_id BIGINT NOT NULL, reason VARCHAR(255) DEFAULT '', amount DECIMAL(10,2) NOT NULL DEFAULT 0, " +
                    "status VARCHAR(20) NOT NULL DEFAULT 'PENDING', apply_time VARCHAR(32) NOT NULL, " +
                    "process_time VARCHAR(32) DEFAULT '', reject_reason VARCHAR(255) DEFAULT '', " +
                    "KEY idx_refund_order (order_id), KEY idx_refund_status (status)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
            log.info("已创建退款记录表 refund_records");
        }
    }

    private void ensureCartTable() {
        Integer count = jdbc.queryForObject(
                "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() " +
                        "AND table_name = 'cart_items'", Integer.class);
        if (count == null || count == 0) {
            jdbc.execute("CREATE TABLE IF NOT EXISTS cart_items (" +
                    "id BIGINT AUTO_INCREMENT PRIMARY KEY, user_id BIGINT NOT NULL, goods_id BIGINT NOT NULL, " +
                    "quantity INT NOT NULL DEFAULT 1, create_time VARCHAR(32) NOT NULL, " +
                    "update_time VARCHAR(32) NOT NULL, UNIQUE KEY uk_cart_user_goods (user_id, goods_id), " +
                    "KEY idx_cart_user (user_id), KEY idx_cart_goods (goods_id)) " +
                    "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
            log.info("已创建购物车表 cart_items");
        }
    }

    private void ensureReviewGoodsColumn() {
        ensureColumn("reviews", "goods_id", "BIGINT NOT NULL DEFAULT 0 AFTER store_id");
    }

    private void ensureStoreRecommendedColumn() {
        ensureColumn("stores", "recommended", "INT NOT NULL DEFAULT 0 AFTER status");
    }

    private boolean ensureColumn(String table, String column, String definition) {
        Integer count = jdbc.queryForObject(
                "SELECT COUNT(*) FROM information_schema.columns WHERE table_schema = DATABASE() " +
                        "AND table_name = ? AND column_name = ?", Integer.class, table, column);
        if (count == null || count == 0) {
            jdbc.execute("ALTER TABLE " + table + " ADD COLUMN " + column + " " + definition);
            log.info("表 {} 已补充字段 {}", table, column);
            return true;
        }
        return false;
    }

    private void ensureAdminUser() {
        Integer count = jdbc.queryForObject("SELECT COUNT(*) FROM users WHERE phone = ?", Integer.class,
                "13100131000");
        if (count == null || count == 0) {
            jdbc.update("INSERT INTO users(username, avatar, phone, password, role, balance, create_time) " +
                            "VALUES(?,?,?,?,?,?,?)",
                    "平台管理员", "", "13100131000", PasswordUtil.hash("123456"), 2, 0.0, now());
            log.info("已补充管理端测试账号 phone=13100131000");
        }
    }

    private void ensureStoresAndGoods() {
        Integer storeCount = jdbc.queryForObject("SELECT COUNT(*) FROM stores", Integer.class);
        if (storeCount != null && storeCount > 0) {
            ensureGoods();
            return;
        }
        long[] merchantIds = ensureMerchantUsers();
        seedStoresAndGoods(merchantIds);
        log.info("店铺数据为空，已补齐 30 家店铺及对应商品");
    }

    private void ensureGoods() {
        Integer goodsCount = jdbc.queryForObject("SELECT COUNT(*) FROM goods", Integer.class);
        if (goodsCount != null && goodsCount > 0) {
            return;
        }
        List<java.util.Map<String, Object>> stores = jdbc.queryForList("SELECT id, category_id FROM stores");
        for (java.util.Map<String, Object> store : stores) {
            long storeId = ((Number) store.get("id")).longValue();
            int categoryId = ((Number) store.get("category_id")).intValue();
            seedGoods(storeId, categoryId, 6);
        }
        log.info("商品数据为空，已为 {} 家店铺补齐商品", stores.size());
    }

    /** 幂等补充 10 家距离较近的店铺，并默认标记为平台推荐，供发现页展示。 */
    private void ensureAdditionalStores() {
        long[] merchantIds = ensureMerchantUsers();
        String[] names = {"光谷牛肉粉", "江汉路炸鸡铺", "东湖烧烤屋", "武昌热干面", "汉口甜品站",
                "青山砂锅饭", "关山便当", "街角寿司屋", "南湖小龙虾", "珞喻路煲仔饭"};
        int[] categories = {7, 6, 6, 7, 4, 1, 2, 8, 6, 1};
        double[] distances = {0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 1.1};
        for (int i = 0; i < names.length; i++) {
            Integer exists = jdbc.queryForObject("SELECT COUNT(*) FROM stores WHERE name = ?", Integer.class, names[i]);
            if (exists != null && exists > 0) {
                continue;
            }
            int categoryId = categories[i];
            jdbc.update("INSERT INTO stores(name, image, rating, monthly_sales, delivery_fee, min_order, delivery_time, distance, tags, notice, category_id, category_ids, owner_id, status, recommended, create_time) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                    names[i], "", 4.5 + (i % 5) * 0.1, 800 + i * 137,
                    2 + i % 3, 10 + i % 3 * 5, (18 + i * 2) + "分钟", distances[i] + "km",
                    "[\"附近推荐\",\"满减\"]", "平台推荐附近好店，欢迎光临" + names[i],
                    categoryId, "[" + categoryId + "]", merchantIds[i % merchantIds.length], 1, 1, now());
            long storeId = jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class);
            seedGoods(storeId, categoryId, 6);
        }
    }

    private long[] ensureMerchantUsers() {
        String[][] merchants = {
                {"黄焖鸡老板", "13600136000"},
                {"串串香老板", "13700137000"},
                {"甜品店老板", "13500135000"}
        };
        long[] ids = new long[merchants.length];
        for (int i = 0; i < merchants.length; i++) {
            List<Long> existing = jdbc.queryForList("SELECT id FROM users WHERE phone = ? LIMIT 1",
                    Long.class, merchants[i][1]);
            if (existing.isEmpty()) {
                jdbc.update("INSERT INTO users(username, avatar, phone, password, role, balance, create_time) " +
                                "VALUES(?,?,?,?,?,?,?)",
                        merchants[i][0], "", merchants[i][1], PasswordUtil.hash("123456"), 1, 0.0, now());
                ids[i] = jdbc.queryForObject("SELECT id FROM users WHERE phone = ?", Long.class, merchants[i][1]);
            } else {
                ids[i] = existing.get(0);
            }
        }
        return ids;
    }

    private void seed() {
        long[] userIds = seedUsers();
        long[] merchantIds = {userIds[2], userIds[3], userIds[4]};
        seedStoresAndGoods(merchantIds);
        seedExtras(userIds[0], userIds[1]);
    }

    private void ensureCategories() {
        String[][] categories = defaultCategories();
        Integer count = jdbc.queryForObject("SELECT COUNT(*) FROM categories", Integer.class);
        if (count == null || count == 0) {
            seedCategories();
            log.info("分类数据为空，已补齐 {} 个默认分类", categories.length);
            return;
        }
        for (String[] category : categories) {
            Integer exists = jdbc.queryForObject("SELECT COUNT(*) FROM categories WHERE name = ?", Integer.class,
                    category[0]);
            if (exists == null || exists == 0) {
                jdbc.update("INSERT INTO categories(name, icon, color) VALUES(?,?,?)",
                        category[0], category[1], category[2]);
            } else {
                jdbc.update("UPDATE categories SET icon=?, color=? WHERE name=? " +
                                "AND (icon IS NULL OR TRIM(icon) = '' OR icon = '??')",
                        category[1], category[2], category[0]);
            }
        }
    }

    private void seedCategories() {
        String[][] categories = defaultCategories();
        for (String[] c : categories) {
            jdbc.update("INSERT INTO categories(name, icon, color) VALUES(?,?,?)", c[0], c[1], c[2]);
        }
    }

    private String[][] defaultCategories() {
        return new String[][]{
                {"美食", "🍔", "#FF6B35"}, {"快餐", "🍟", "#FFB74D"}, {"饮品", "🧋", "#4FC3F7"},
                {"甜品", "🍰", "#F06292"}, {"火锅", "🍲", "#E53935"}, {"烧烤", "🍢", "#FF7043"},
                {"面食", "🍜", "#FFA726"}, {"寿司", "🍣", "#66BB6A"}
        };
    }

    private long[] seedUsers() {
        String[][] accounts = {
                {"美食家小张", "13800138000", "0", "20.0"},
                {"小王", "13900139000", "0", "15.0"},
                {"黄焖鸡老板", "13600136000", "1", "0"},
                {"串串香老板", "13700137000", "1", "0"},
                {"甜品店老板", "13500135000", "1", "0"}
        };
        long[] ids = new long[accounts.length];
        for (int i = 0; i < accounts.length; i++) {
            String[] a = accounts[i];
            jdbc.update("INSERT INTO users(username, avatar, phone, password, role, balance, create_time) VALUES(?,?,?,?,?,?,?)",
                    a[0], "", a[1], PasswordUtil.hash("123456"), Integer.parseInt(a[2]),
                    Double.parseDouble(a[3]), now());
            ids[i] = jdbc.queryForObject("SELECT id FROM users WHERE phone = ?", Long.class, a[1]);
        }
        return ids;
    }

    private void seedStoresAndGoods(long[] merchantIds) {
        String[] baseStores = {
                "黄焖鸡米饭", "星巴克咖啡", "张亮麻辣烫", "肯德基", "一点点奶茶",
                "重庆老火锅", "兰州拉面", "小郡肝串串香", "好利来蛋糕", "食其家牛丼饭"
        };
        String[] extraStores = {
                "老王饺子馆", "川味家常菜", "湘菜小馆", "粤式烧腊", "沙县小吃",
                "杨国福麻辣烫", "蜜雪冰城", "沪上阿姨", "瑞幸咖啡", "库迪咖啡",
                "必胜客", "麦当劳", "德克士", "正新鸡排", "桥头排骨",
                "柳州螺蛳粉", "重庆小面", "陕西凉皮", "东北饺子王", "山西刀削面"
        };
        int[] baseCategory = {1, 3, 1, 2, 3, 5, 7, 6, 4, 2};
        double[] baseRating = {4.8, 4.9, 4.6, 4.7, 4.5, 4.8, 4.4, 4.6, 4.9, 4.5};
        int[] baseSales = {2356, 5621, 1890, 8900, 3200, 980, 1560, 2100, 4500, 1200};

        String now = now();
        long storeSequence = 1;
        for (int i = 0; i < baseStores.length; i++) {
            long owner = merchantIds[i / 4];
            jdbc.update("INSERT INTO stores(name, image, rating, monthly_sales, delivery_fee, min_order, delivery_time, distance, tags, notice, category_id, category_ids, owner_id, status, create_time) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                    baseStores[i], "", baseRating[i], baseSales[i],
                    2 + i % 4, 12 + (i % 4) * 5,
                    (20 + i * 2) + "分钟", (0.5 + i * 0.3) + "km",
                    "[\"满减\",\"新客立减\"]", "本店菜品现做现卖，保证新鲜",
                    baseCategory[i], "[" + baseCategory[i] + "]", owner, 1, now);
            long persistedStoreId = jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class);
            seedGoods(persistedStoreId, baseCategory[i], 8);
            storeSequence++;
        }
        for (String name : extraStores) {
            long owner = merchantIds[(int) (storeSequence % 3)];
            int cat = 1 + (int) (storeSequence % 8);
            int sales = 300 + ThreadLocalRandom.current().nextInt(5000);
            jdbc.update("INSERT INTO stores(name, image, rating, monthly_sales, delivery_fee, min_order, delivery_time, distance, tags, notice, category_id, category_ids, owner_id, status, create_time) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                    name, "", 4.0 + ThreadLocalRandom.current().nextDouble(0.9),
                    sales, 2 + (int) (storeSequence % 4), 10 + (int) (storeSequence % 3) * 5,
                    (18 + (int) (storeSequence % 10) * 3) + "分钟",
                    (0.3 + (storeSequence % 20) * 0.2) + "km",
                    "[\"满减\"]", "欢迎光临" + name,
                    cat, "[" + cat + "]", owner, 1, now);
            long persistedStoreId = jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class);
            seedGoods(persistedStoreId, cat, 6);
            storeSequence++;
        }
    }

    private void seedGoods(long storeId, int categoryId, int specialCount) {
        String[] specialGoods = {
                "招牌套餐", "经典单品", "人气小吃", "时令饮品", "特色主食", "加料升级"
        };
        String[] descriptions = {"精选食材，匠心制作", "招牌菜品，必点推荐", "人气爆款，销量领先",
                "新鲜现做，美味可口", "特色风味，回味无穷", "经典口味，百吃不厌"};
        double basePrice = 8 + ThreadLocalRandom.current().nextDouble(30);
        for (int i = 0; i < specialCount; i++) {
            double price = round2(basePrice + i * 3 + ThreadLocalRandom.current().nextDouble(5));
            jdbc.update("INSERT INTO goods(store_id, name, description, price, original_price, image, category_id, sales, rating, tag, is_special, status, create_time) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)",
                    storeId, specialGoods[i % specialGoods.length] + (i == 0 ? "(店长推荐)" : ""), descriptions[i % descriptions.length],
                    price, round2(price + 3), "", categoryId,
                    300 + ThreadLocalRandom.current().nextInt(2000),
                    4.3 + ThreadLocalRandom.current().nextDouble(0.7),
                    i == 0 ? "招牌" : "", i < specialGoods.length ? 1 : 0, 1, now());
        }
        // 程序化补充至 30 个商品
        for (int i = specialCount; i < 30; i++) {
            double price = round2(6 + ThreadLocalRandom.current().nextDouble(40));
            jdbc.update("INSERT INTO goods(store_id, name, description, price, original_price, image, category_id, sales, rating, tag, is_special, status, create_time) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)",
                    storeId, "精选菜品" + (i + 1), descriptions[i % descriptions.length],
                    price, 0, "", categoryId,
                    50 + ThreadLocalRandom.current().nextInt(1500),
                    4.0 + ThreadLocalRandom.current().nextDouble(0.8),
                    "", 0, 1, now());
        }
    }

    private void seedExtras(long user1Id, long user2Id) {
        String now = now();
        // 默认优惠券
        String expire = LocalDateTime.now().plusDays(30).format(FMT);
        jdbc.update("INSERT INTO coupons(user_id, store_id, name, threshold, amount, status, expire_time, source, create_time) VALUES(?,?,?,?,?,?,?,?,?)",
                user1Id, 0, "新客立减券", 20, 5, 0, expire, "default", now);
        jdbc.update("INSERT INTO coupons(user_id, store_id, name, threshold, amount, status, expire_time, source, create_time) VALUES(?,?,?,?,?,?,?,?,?)",
                user1Id, 0, "满50减10券", 50, 10, 0, expire, "default", now);
        jdbc.update("INSERT INTO coupons(user_id, store_id, name, threshold, amount, status, expire_time, source, create_time) VALUES(?,?,?,?,?,?,?,?,?)",
                user2Id, 0, "新客立减券", 20, 5, 0, expire, "default", now);
        // 默认地址
        jdbc.update("INSERT INTO addresses(user_id, name, phone, detail, is_default, create_time) VALUES(?,?,?,?,?,?)",
                user1Id, "小张", "13800138000", "华中科技大学紫菘公寓3栋502", 1, now);
        jdbc.update("INSERT INTO addresses(user_id, name, phone, detail, is_default, create_time) VALUES(?,?,?,?,?,?)",
                user1Id, "小张", "13800138000", "光谷广场步行街B座1201", 0, now);
        jdbc.update("INSERT INTO addresses(user_id, name, phone, detail, is_default, create_time) VALUES(?,?,?,?,?,?)",
                user2Id, "小王", "13900139000", "华中科技大学韵苑公寓5栋301", 1, now);
        // 默认评价（前两家店各 3 条）
        List<Long> storeIds = jdbc.queryForList("SELECT id FROM stores ORDER BY id LIMIT 2", Long.class);
        String[] contents = {"味道很好，分量足，配送也快！", "包装很用心，菜还是热的，好评",
                "第二次点了，品质稳定，推荐招牌"};
        for (long sid : storeIds) {
            Long goodsId = jdbc.queryForObject("SELECT id FROM goods WHERE store_id = ? ORDER BY id LIMIT 1", Long.class, sid);
            for (int i = 0; i < contents.length; i++) {
                jdbc.update("INSERT INTO reviews(store_id, goods_id, user_id, user_name, rating, content, tags, create_time) VALUES(?,?,?,?,?,?,?,?)",
                        sid, goodsId == null ? 0 : goodsId, user1Id, "美食家小张", 5 - i, contents[i], "[\"味道好\",\"配送快\"]", now);
            }
        }
    }

    private static String now() {
        return LocalDateTime.now().format(FMT);
    }

    private static double round2(double v) {
        return Math.round(v * 100.0) / 100.0;
    }
}

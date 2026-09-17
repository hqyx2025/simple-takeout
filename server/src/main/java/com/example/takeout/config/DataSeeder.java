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
        ensureBankCardTable();
        ensureReviewGoodsColumn();
        ensureStoreRecommendedColumn();
        ensureStoreLocationColumns();
        // 分类是首页导航的基础数据，即使已有用户数据，也必须单独补齐。
        ensureCategories();
        Integer userCount = jdbc.queryForObject("SELECT COUNT(*) FROM users", Integer.class);
        if (userCount != null && userCount > 0) {
            ensureAdminUser();
            ensureRiderUser();
            ensureBankCards();
            ensureStoresAndGoods();
            ensureAdditionalStores();
            ensureStoreCoordinates();
            ensureStoreMerchantCategories();
            ensureMarketingData();
            log.info("用户数据已存在（users={}），已校验分类、店铺、商品和附近推荐数据", userCount);
            return;
        }
        seed();
        ensureAdminUser();
        ensureRiderUser();
        ensureBankCards();
        ensureAdditionalStores();
        ensureStoreCoordinates();
        ensureStoreMerchantCategories();
        ensureMarketingData();
        log.info("种子数据初始化完成：8 分类 / 40 店铺 / 1200 商品 / 6 账号（含骑手）");
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

    /** 存量店铺补充地址与坐标，坐标为空时由客户端继续显示历史距离兜底。 */
    private void ensureStoreLocationColumns() {
        ensureColumn("stores", "address", "VARCHAR(512) NOT NULL DEFAULT '' AFTER notice");
        ensureColumn("stores", "latitude", "DECIMAL(10,7) DEFAULT NULL AFTER address");
        ensureColumn("stores", "longitude", "DECIMAL(10,7) DEFAULT NULL AFTER latitude");
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

    /**
     * 骑手测试账号（四端改造）：role=3。
     * 与管理端账号同理，即使已有用户数据也要补齐，否则骑手端无法登录
     * （登录页的角色校验会因 role 不匹配直接退回登录页）。
     * 同时把骑手档案一并建好，管理端「骑手管理」列表开箱即有数据——
     * 否则要等骑手首次登录时由 RiderService.profile() 惰性建档。
     */
    private void ensureRiderUser() {
        String phone = "13300133000";
        String name = "骑手小李";
        Long userId = jdbc.query("SELECT id FROM users WHERE phone = ?",
                (rs, i) -> rs.getLong("id"), phone).stream().findFirst().orElse(null);
        if (userId == null) {
            jdbc.update("INSERT INTO users(username, avatar, phone, password, role, balance, create_time) " +
                            "VALUES(?,?,?,?,?,?,?)",
                    name, "", phone, PasswordUtil.hash("123456"), 3, 0.0, now());
            userId = jdbc.queryForObject("SELECT id FROM users WHERE phone = ?", Long.class, phone);
            log.info("已补充骑手端测试账号 phone={}", phone);
        }
        Integer profileCount = jdbc.queryForObject(
                "SELECT COUNT(*) FROM riders WHERE user_id = ?", Integer.class, userId);
        if (profileCount == null || profileCount == 0) {
            jdbc.update("INSERT INTO riders(user_id, name, phone, online, total_orders, total_income, " +
                            "status, create_time) VALUES(?,?,?,0,0,0,1,?)",
                    userId, name, phone, now());
            log.info("已补充骑手档案 user_id={}", userId);
        }
    }

    /**
     * 补齐「店内分类」并把商品归入分类（幂等，存量库也会补）。
     *
     * 背景：店铺详情页顶部的分类芯片走的是美团式的店内分组
     * （categories.type='MERCHANT' + goods.merchant_category_id），这条链路
     * 后端（StoreController/StoreDao.listMerchantCategories）与前端
     * （fetchStoreMerchantCategoriesApi + getGoodsCategoryNames）早已就绪，
     * 但种子数据从未创建过任何 MERCHANT 分类，1200 个商品的
     * merchant_category_id 全为 0 —— 结果芯片只剩「全部 + 该店唯一的平台分类」
     * 两个，而两者返回的商品列表完全相同，用户点分类看起来「点了没反应」。
     *
     * 幂等与安全边界：
     *  - 分类按商户（owner_id）维度存放，与该商户名下多家店铺共用一套分类名，
     *    这正是 listMerchantCategories 的既有口径。
     *  - 4 个默认分类**按名字**补齐，不能按位置推断：商户 3 自己建了「你好」并
     *    占据第一个位置，按位置对应会把「人气主食」之类张冠李戴，且永远建不出
     *    「招牌热销」（曾经的 bug）。
     *  - 只有「使用的分类数 < 2」的店铺才重新分组。这类店铺本来就没有可切换的
     *    分区（芯片点了没有任何变化），重新分组不损失任何功能；而使用 >=2 个
     *    分类的店铺（含商户自己整理过的）一律不动，尊重既有分组。
     *  - 分配用确定性轮转（只取决于商品 id 顺序），重复执行结果一致 → 幂等；
     *    分组后该店的分类数必然 >= 2，下次运行直接跳过。分类本身从不删除。
     *  - 必须**按店铺**铺开，不能按 is_special 全局一刀切：后者会让「整店商品
     *    全是招牌」的店铺（31~40 号店各 6 个商品全是招牌）全部落进同一个分类，
     *    芯片仍只有一个非空项，点了依旧没反应。
     */
    private void ensureStoreMerchantCategories() {
        String[] defaults = {"招牌热销", "人气主食", "特色小吃", "解腻饮品"};
        List<java.util.Map<String, Object>> owners = jdbc.queryForList(
                "SELECT DISTINCT owner_id FROM stores WHERE owner_id > 0");
        int createdCategories = 0;
        int regrouped = 0;
        for (java.util.Map<String, Object> owner : owners) {
            long ownerId = ((Number) owner.get("owner_id")).longValue();
            // 按名字补齐 4 个默认分类（已存在的商户自定义分类原样保留）
            for (String name : defaults) {
                Integer exists = jdbc.queryForObject(
                        "SELECT COUNT(*) FROM categories WHERE type = 'MERCHANT' AND merchant_id = ? AND name = ?",
                        Integer.class, ownerId, name);
                if (exists == null || exists == 0) {
                    Integer maxSort = jdbc.queryForObject(
                            "SELECT COALESCE(MAX(sort), 0) FROM categories WHERE type = 'MERCHANT' AND merchant_id = ?",
                            Integer.class, ownerId);
                    jdbc.update("INSERT INTO categories(name, icon, color, type, merchant_id, sort, status) " +
                                    "VALUES(?,'','','MERCHANT',?,?,1)",
                            name, ownerId, (maxSort == null ? 0 : maxSort) + 1);
                    createdCategories++;
                }
            }
            // 分配序列：招牌热销固定第一位（招牌商品落点），其余默认分类按 sort 随后
            Long specialCategoryId = jdbc.query(
                    "SELECT id FROM categories WHERE type = 'MERCHANT' AND merchant_id = ? AND name = '招牌热销'",
                    (rs, i) -> rs.getLong("id"), ownerId).stream().findFirst().orElse(null);
            if (specialCategoryId == null) {
                continue;
            }
            List<Long> categoryIds = new java.util.ArrayList<>();
            categoryIds.add(specialCategoryId);
            categoryIds.addAll(jdbc.query(
                    "SELECT id FROM categories WHERE type = 'MERCHANT' AND merchant_id = ? " +
                            "AND name IN ('人气主食','特色小吃','解腻饮品') AND id <> ? ORDER BY sort, id",
                    (rs, i) -> rs.getLong("id"), ownerId, specialCategoryId));
            if (categoryIds.size() < 2) {
                continue;
            }
            List<Long> storeIds = jdbc.query("SELECT id FROM stores WHERE owner_id = ? ORDER BY id",
                    (rs, i) -> rs.getLong("id"), ownerId);
            for (long storeId : storeIds) {
                List<long[]> rows = jdbc.query(
                        "SELECT id, is_special, merchant_category_id FROM goods WHERE store_id = ? ORDER BY id",
                        (rs, i) -> new long[]{rs.getLong("id"), rs.getLong("is_special"),
                                rs.getLong("merchant_category_id")}, storeId);
                if (rows.isEmpty()) {
                    continue;
                }
                long usedCategories = rows.stream().map(r -> r[2]).filter(c -> c > 0).distinct().count();
                if (usedCategories >= 2) {
                    // 已有 >=2 个分类在生效，切换本来就能工作，不动它
                    continue;
                }
                boolean hasNonSpecial = rows.stream().anyMatch(r -> r[1] == 0);
                int cursor = 0;
                for (long[] row : rows) {
                    long categoryId;
                    if (hasNonSpecial && row[1] == 1) {
                        // 招牌商品统一落「招牌热销」（categoryIds 第一位）
                        categoryId = categoryIds.get(0);
                    } else if (hasNonSpecial) {
                        // 非招牌在其余默认分类间轮转
                        categoryId = categoryIds.get(1 + (cursor % (categoryIds.size() - 1)));
                        cursor++;
                    } else {
                        // 整店都是招牌商品：没有「其余分类」可用，就在全部分类间轮转，
                        // 否则这家店的芯片永远只有一个非空项
                        categoryId = categoryIds.get(cursor % categoryIds.size());
                        cursor++;
                    }
                    jdbc.update("UPDATE goods SET merchant_category_id = ? WHERE id = ?", categoryId, row[0]);
                }
                regrouped++;
            }
        }
        if (createdCategories > 0 || regrouped > 0) {
            log.info("店内分类：新建 {} 个默认分类，重新分组 {} 家店铺（分类数<2、原本无法切换的店铺）",
                    createdCategories, regrouped);
        }
    }

    /** 钱包银行卡表（演进项：余额页展示已绑定银行卡）。只存卡号后四位，不存完整卡号。 */
    private void ensureBankCardTable() {
        Integer count = jdbc.queryForObject(
                "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() " +
                        "AND table_name = 'bank_cards'", Integer.class);
        if (count == null || count == 0) {
            jdbc.execute("CREATE TABLE IF NOT EXISTS bank_cards (" +
                    "id BIGINT AUTO_INCREMENT PRIMARY KEY, user_id BIGINT NOT NULL, " +
                    "bank_name VARCHAR(64) NOT NULL, card_type VARCHAR(32) NOT NULL DEFAULT '储蓄卡', " +
                    "card_no_last4 VARCHAR(4) NOT NULL, is_default INT NOT NULL DEFAULT 0, " +
                    "status INT NOT NULL DEFAULT 1, create_time VARCHAR(32) NOT NULL, " +
                    "KEY idx_bank_card_user (user_id)) " +
                    "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
            log.info("已创建钱包银行卡表 bank_cards");
        }
    }

    /**
     * 给用户端测试账号各绑一张卡（幂等：已有卡就跳过，不覆盖用户数据）。
     * 只写后四位，卡号是演示数据，不对应任何真实账户。
     */
    private void ensureBankCards() {
        String[][] seeds = {
                {"13800138000", "招商银行", "储蓄卡", "6688"},
                {"13900139000", "工商银行", "信用卡", "8899"},
        };
        int created = 0;
        for (String[] seed : seeds) {
            Long userId = jdbc.query("SELECT id FROM users WHERE phone = ?",
                    (rs, i) -> rs.getLong("id"), seed[0]).stream().findFirst().orElse(null);
            if (userId == null) {
                continue;
            }
            Integer existing = jdbc.queryForObject(
                    "SELECT COUNT(*) FROM bank_cards WHERE user_id = ?", Integer.class, userId);
            if (existing != null && existing > 0) {
                continue;
            }
            jdbc.update("INSERT INTO bank_cards(user_id, bank_name, card_type, card_no_last4, " +
                            "is_default, status, create_time) VALUES(?,?,?,?,1,1,?)",
                    userId, seed[1], seed[2], seed[3], now());
            created++;
        }
        if (created > 0) {
            log.info("已为 {} 个用户补充钱包银行卡", created);
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

    /** 种子门店基准点（南宁市中心）+ 环状偏移，让附近推荐有真实可算的距离。 */
    private static final double SEED_BASE_LATITUDE = 22.8177;
    private static final double SEED_BASE_LONGITUDE = 108.3665;

    /**
     * 幂等给种子店铺落坐标（南宁基准点 + 确定性环状偏移，约 0.2~1.2 公里）。
     * 覆盖两种情形：① 没有坐标的店（算不出距离，附近推荐会把它们整体丢掉）；
     * ② 还停在**旧武汉基准点**上的店（基准点从武汉改成南宁后，不重新落位的话存量店仍在武汉）。
     * 条件里用「旧武汉环」而不是「有没有地址」来判定，避免误伤商户用地图正式选过点的门店。
     */
    private void ensureStoreCoordinates() {
        List<java.util.Map<String, Object>> pending = jdbc.queryForList(
                "SELECT id FROM stores WHERE latitude IS NULL OR longitude IS NULL "
                        + "OR (latitude BETWEEN 30.5 AND 30.7 AND longitude BETWEEN 114.2 AND 114.4) "
                        + "ORDER BY id");
        for (int i = 0; i < pending.size(); i++) {
            long storeId = ((Number) pending.get(i).get("id")).longValue();
            double angle = i * 0.7;
            double radiusDeg = 0.002 + (i % 8) * 0.0012;
            double latitude = SEED_BASE_LATITUDE + radiusDeg * Math.cos(angle);
            double longitude = SEED_BASE_LONGITUDE + radiusDeg * Math.sin(angle) * 1.15;
            jdbc.update("UPDATE stores SET latitude = ?, longitude = ? WHERE id = ?", latitude, longitude, storeId);
        }
        if (!pending.isEmpty()) {
            log.info("已为 {} 家种子店铺落位门店坐标（基准点南宁）", pending.size());
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

    // ============ 多规格 SKU / 限时秒杀演示数据 ============

    /**
     * 多规格与秒杀演示数据：仅在为空时补齐，不覆盖商户后续在商户端的维护结果。
     */
    private void ensureMarketingData() {
        seedDemoSpecs();
        seedDemoSeckills();
        seedMarketingActivities();
        seedSetmeals();
    }

    /** 营销活动演示数据：第一家营业店铺 全套（8折/新客立减3/满50赠招牌菜），幂等。 */
    private void seedMarketingActivities() {
        Integer count = jdbc.queryForObject("SELECT COUNT(*) FROM marketing_activities", Integer.class);
        if (count != null && count > 0) {
            return;
        }
        List<java.util.Map<String, Object>> stores = jdbc.queryForList(
                "SELECT id FROM stores WHERE status = 1 ORDER BY id LIMIT 1");
        if (stores.isEmpty()) {
            return;
        }
        long storeId = ((Number) stores.get(0).get("id")).longValue();
        Long gift = jdbc.queryForObject(
                "SELECT id FROM goods WHERE store_id = ? AND status = 1 AND is_special = 1 ORDER BY id LIMIT 1",
                Long.class, storeId);
        long giftGoodsId = gift == null ? 0 : gift;
        String now = now();
        String end = "2099-12-31 23:59:59";
        insertMarketingActivity(storeId, "DISCOUNT", "全场8折", 0.800, 0, 0, 0, now, end);
        insertMarketingActivity(storeId, "NEW_USER", "新客立减3元", 0, 3, 0, 0, now, end);
        insertMarketingActivity(storeId, "GIFT", "满50赠招牌菜", 0, 0, 50, giftGoodsId, now, end);
        log.info("已为店铺 {} 补充营销活动演示数据（8折/新客立减/满赠赠品 {}）", storeId, giftGoodsId);
    }

    private void insertMarketingActivity(long storeId, String type, String title, double rate,
                                         double reduce, double threshold, long gift, String start, String end) {
        jdbc.update("INSERT INTO marketing_activities(store_id, type, title, discount_rate, reduce_amount, threshold, gift_goods_id, start_time, end_time, status, create_time) VALUES(?,?,?,?,?,?,?,?,?,?,?)",
                storeId, type, title, rate, reduce, threshold, gift, start, end, 1, start);
    }

    /** 套餐演示数据：第一家营业店铺用前两件商品组一个「双人套餐」，幂等。 */
    private void seedSetmeals() {
        Integer count = jdbc.queryForObject("SELECT COUNT(*) FROM setmeals", Integer.class);
        if (count != null && count > 0) {
            return;
        }
        List<java.util.Map<String, Object>> stores = jdbc.queryForList(
                "SELECT id FROM stores WHERE status = 1 ORDER BY id LIMIT 1");
        if (stores.isEmpty()) {
            return;
        }
        long storeId = ((Number) stores.get(0).get("id")).longValue();
        List<java.util.Map<String, Object>> goods = jdbc.queryForList(
                "SELECT id, name, price, image FROM goods WHERE store_id = ? AND status = 1 ORDER BY id LIMIT 2", storeId);
        if (goods.size() < 2) {
            return;
        }
        long g0 = ((Number) goods.get(0).get("id")).longValue();
        long g1 = ((Number) goods.get(1).get("id")).longValue();
        double p0 = ((Number) goods.get(0).get("price")).doubleValue();
        double p1 = ((Number) goods.get(1).get("price")).doubleValue();
        String img = (String) goods.get(0).get("image");
        String now = now();
        long setId = insertSetmealHeader(storeId, "超值双人套餐", "招牌组合，两份更划算",
                round2(p0 + p1 - 3), round2(p0 + p1), img, now);
        insertSetmealItemRow(setId, g0, (String) goods.get(0).get("name"), 1);
        insertSetmealItemRow(setId, g1, (String) goods.get(1).get("name"), 1);
        log.info("已为店铺 {} 补充套餐演示数据（setmeal_id={}）", storeId, setId);
    }

    private long insertSetmealHeader(long storeId, String name, String desc, double price, double orig, String img, String now) {
        jdbc.update("INSERT INTO setmeals(store_id, name, description, price, original_price, image, status, create_time) VALUES(?,?,?,?,?,?,1,?)",
                storeId, name, desc, price, orig, img, now);
        return jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class);
    }

    private void insertSetmealItemRow(long setmealId, long goodsId, String name, int qty) {
        jdbc.update("INSERT INTO setmeal_items(setmeal_id, goods_id, goods_name, quantity) VALUES(?,?,?,?)",
                setmealId, goodsId, name, qty);
    }

    /** 为 3 个招牌商品补「标准份/大份/双人份」规格，用于演示多规格点单。 */
    private void seedDemoSpecs() {
        Integer count = jdbc.queryForObject("SELECT COUNT(*) FROM goods_specs", Integer.class);
        if (count != null && count > 0) {
            return;
        }
        List<java.util.Map<String, Object>> rows = jdbc.queryForList(
                "SELECT id, price FROM goods WHERE status = 1 AND is_special = 1 ORDER BY id LIMIT 3");
        for (java.util.Map<String, Object> row : rows) {
            long goodsId = ((Number) row.get("id")).longValue();
            double price = ((Number) row.get("price")).doubleValue();
            insertSpec(goodsId, "标准份", price, 200, 0);
            insertSpec(goodsId, "大份", round2(price + 3), 120, 1);
            insertSpec(goodsId, "双人份", round2(price + 8), 60, 2);
            syncGoodsFromSpecs(goodsId);
        }
        log.info("已为 {} 个招牌商品补充多规格 SKU 演示数据", rows.size());
    }

    private void insertSpec(long goodsId, String name, double price, int stock, int sort) {
        jdbc.update("INSERT INTO goods_specs(goods_id, name, price, stock, version, sort, status, create_time) " +
                "VALUES(?,?,?,?,0,?,1,?)", goodsId, name, price, stock, sort, now());
    }

    /** 多规格菜品的菜品价与库存按规格聚合回写（与 StoreService 口径一致）。 */
    private void syncGoodsFromSpecs(long goodsId) {
        Double minPrice = jdbc.queryForObject(
                "SELECT MIN(price) FROM goods_specs WHERE goods_id = ? AND status = 1", Double.class, goodsId);
        Integer stock = jdbc.queryForObject(
                "SELECT COALESCE(SUM(stock), 0) FROM goods_specs WHERE goods_id = ? AND status = 1",
                Integer.class, goodsId);
        if (minPrice != null && stock != null) {
            jdbc.update("UPDATE goods SET price = ?, stock = ? WHERE id = ?", minPrice, stock, goodsId);
        }
    }

    /** 为热销单品（无规格）创建限时秒杀，用于演示首页秒杀专区与秒杀价下单。 */
    private void seedDemoSeckills() {
        Integer count = jdbc.queryForObject("SELECT COUNT(*) FROM seckills", Integer.class);
        if (count != null && count > 0) {
            return;
        }
        List<java.util.Map<String, Object>> rows = jdbc.queryForList(
                "SELECT g.id, g.store_id, g.price FROM goods g JOIN stores s ON s.id = g.store_id " +
                        "WHERE g.status = 1 AND s.status = 1 AND g.price > 6 " +
                        "AND NOT EXISTS (SELECT 1 FROM goods_specs sp WHERE sp.goods_id = g.id AND sp.status = 1) " +
                        "ORDER BY g.sales DESC LIMIT 4");
        LocalDateTime start = LocalDateTime.now().minusMinutes(5);
        LocalDateTime end = LocalDateTime.now().plusHours(6);
        for (java.util.Map<String, Object> row : rows) {
            long goodsId = ((Number) row.get("id")).longValue();
            long storeId = ((Number) row.get("store_id")).longValue();
            double price = round2(((Number) row.get("price")).doubleValue() * 0.6);
            jdbc.update("INSERT INTO seckills(goods_id, store_id, price, quota, sold, start_time, end_time, status, create_time) " +
                            "VALUES(?,?,?,?,?,?,?,1,?)",
                    goodsId, storeId, price, 50, ThreadLocalRandom.current().nextInt(10, 30),
                    start.format(FMT), end.format(FMT), now());
        }
        log.info("已创建 {} 个限时秒杀演示活动", rows.size());
    }
}

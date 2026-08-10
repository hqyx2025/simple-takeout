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
        Integer userCount = jdbc.queryForObject("SELECT COUNT(*) FROM users", Integer.class);
        if (userCount != null && userCount > 0) {
            log.info("种子数据已存在（users={}），跳过初始化", userCount);
            return;
        }
        seed();
        log.info("种子数据初始化完成：8 分类 / 30 店铺 / 900 商品 / 5 账号");
    }

    private void seed() {
        seedCategories();
        long[] userIds = seedUsers();
        long[] merchantIds = {userIds[2], userIds[3], userIds[4]};
        seedStoresAndGoods(merchantIds);
        seedExtras(userIds[0], userIds[1]);
    }

    private void seedCategories() {
        String[][] categories = {
                {"美食", "🍔", "#FF6B35"}, {"快餐", "🍟", "#FFB74D"}, {"饮品", "🧋", "#4FC3F7"},
                {"甜品", "🍰", "#F06292"}, {"火锅", "🍲", "#E53935"}, {"烧烤", "🍢", "#FF7043"},
                {"面食", "🍜", "#FFA726"}, {"寿司", "🍣", "#66BB6A"}
        };
        for (String[] c : categories) {
            jdbc.update("INSERT INTO categories(name, icon, color) VALUES(?,?,?)", c[0], c[1], c[2]);
        }
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
        long storeId = 1;
        for (int i = 0; i < baseStores.length; i++) {
            long owner = merchantIds[i / 4];
            jdbc.update("INSERT INTO stores(name, image, rating, monthly_sales, delivery_fee, min_order, delivery_time, distance, tags, notice, category_id, category_ids, owner_id, status, create_time) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                    baseStores[i], "", baseRating[i], baseSales[i],
                    2 + i % 4, 12 + (i % 4) * 5,
                    (20 + i * 2) + "分钟", (0.5 + i * 0.3) + "km",
                    "[\"满减\",\"新客立减\"]", "本店菜品现做现卖，保证新鲜",
                    baseCategory[i], "[" + baseCategory[i] + "]", owner, 1, now);
            seedGoods(storeId, baseCategory[i], 8);
            storeId++;
        }
        for (String name : extraStores) {
            long owner = merchantIds[(int) (storeId % 3)];
            int cat = 1 + (int) (storeId % 8);
            int sales = 300 + ThreadLocalRandom.current().nextInt(5000);
            jdbc.update("INSERT INTO stores(name, image, rating, monthly_sales, delivery_fee, min_order, delivery_time, distance, tags, notice, category_id, category_ids, owner_id, status, create_time) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                    name, "", 4.0 + ThreadLocalRandom.current().nextDouble(0.9),
                    sales, 2 + (int) (storeId % 4), 10 + (int) (storeId % 3) * 5,
                    (18 + (int) (storeId % 10) * 3) + "分钟",
                    (0.3 + (storeId % 20) * 0.2) + "km",
                    "[\"满减\"]", "欢迎光临" + name,
                    cat, "[" + cat + "]", owner, 1, now);
            seedGoods(storeId, cat, 6);
            storeId++;
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
            jdbc.update("INSERT INTO goods(store_id, name, description, price, original_price, image, category_id, sales, rating, tag, status, create_time) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)",
                    storeId, specialGoods[i % specialGoods.length] + (i == 0 ? "(店长推荐)" : ""), descriptions[i % descriptions.length],
                    price, round2(price + 3), "", categoryId,
                    300 + ThreadLocalRandom.current().nextInt(2000),
                    4.3 + ThreadLocalRandom.current().nextDouble(0.7),
                    i == 0 ? "招牌" : "", 1, now());
        }
        // 程序化补充至 30 个商品
        for (int i = specialCount; i < 30; i++) {
            double price = round2(6 + ThreadLocalRandom.current().nextDouble(40));
            jdbc.update("INSERT INTO goods(store_id, name, description, price, original_price, image, category_id, sales, rating, tag, status, create_time) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)",
                    storeId, "精选菜品" + (i + 1), descriptions[i % descriptions.length],
                    price, 0, "", categoryId,
                    50 + ThreadLocalRandom.current().nextInt(1500),
                    4.0 + ThreadLocalRandom.current().nextDouble(0.8),
                    "", 1, now());
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
            for (int i = 0; i < contents.length; i++) {
                jdbc.update("INSERT INTO reviews(store_id, user_id, user_name, rating, content, tags, create_time) VALUES(?,?,?,?,?,?,?)",
                        sid, user1Id, "美食家小张", 5 - i, contents[i], "[\"味道好\",\"配送快\"]", now);
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

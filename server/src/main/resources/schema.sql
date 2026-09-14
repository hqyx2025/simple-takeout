-- 简单外卖数据库表结构（MySQL 8.x）
-- 由 Spring 启动时自动执行（spring.sql.init.mode=always）

CREATE TABLE IF NOT EXISTS users (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(64) NOT NULL,
    avatar VARCHAR(255) DEFAULT '',
    phone VARCHAR(20) NOT NULL UNIQUE,
    password VARCHAR(128) NOT NULL,
    role INT NOT NULL DEFAULT 0,
    status INT NOT NULL DEFAULT 1,
    balance DECIMAL(10,2) NOT NULL DEFAULT 0,
    create_time VARCHAR(32) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS stores (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(128) NOT NULL,
    image VARCHAR(255) DEFAULT '',
    rating DECIMAL(3,1) NOT NULL DEFAULT 4.5,
    monthly_sales INT NOT NULL DEFAULT 0,
    delivery_fee DECIMAL(10,2) NOT NULL DEFAULT 0,
    min_order DECIMAL(10,2) NOT NULL DEFAULT 0,
    delivery_time VARCHAR(32) DEFAULT '30分钟',
    distance VARCHAR(32) DEFAULT '1.0km',
    tags TEXT,
    notice VARCHAR(512) DEFAULT '',
    address VARCHAR(512) NOT NULL DEFAULT '',
    latitude DECIMAL(10,7) DEFAULT NULL,
    longitude DECIMAL(10,7) DEFAULT NULL,
    category_id INT NOT NULL DEFAULT 1,
    category_ids VARCHAR(128) DEFAULT '[]',
    owner_id BIGINT NOT NULL,
    status INT NOT NULL DEFAULT 1,
    recommended INT NOT NULL DEFAULT 0,
    create_time VARCHAR(32) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS goods (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    store_id BIGINT NOT NULL,
    name VARCHAR(128) NOT NULL,
    description VARCHAR(512) DEFAULT '',
    price DECIMAL(10,2) NOT NULL DEFAULT 0,
    original_price DECIMAL(10,2) DEFAULT 0,
    image VARCHAR(255) DEFAULT '',
    category_id INT NOT NULL DEFAULT 1,
    merchant_category_id BIGINT NOT NULL DEFAULT 0,
    stock INT NOT NULL DEFAULT 999,
    version INT NOT NULL DEFAULT 0,
    sales INT NOT NULL DEFAULT 0,
    rating DECIMAL(3,1) NOT NULL DEFAULT 4.5,
    tag VARCHAR(32) DEFAULT '',
    is_special INT NOT NULL DEFAULT 0,
    status INT NOT NULL DEFAULT 1,
    create_time VARCHAR(32) NOT NULL,
    KEY idx_goods_store (store_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 菜品多规格 SKU（演进项已落地）：同一菜品可有大份/小份等规格，各自独立价格与库存。
-- goods.price/goods.stock 始终保存「启用规格的最低价 / 库存合计」，保证列表与筛选口径一致。
CREATE TABLE IF NOT EXISTS goods_specs (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    goods_id BIGINT NOT NULL,
    name VARCHAR(64) NOT NULL,
    price DECIMAL(10,2) NOT NULL DEFAULT 0,
    stock INT NOT NULL DEFAULT 999,
    version INT NOT NULL DEFAULT 0,
    sort INT NOT NULL DEFAULT 0,
    status INT NOT NULL DEFAULT 1,
    create_time VARCHAR(32) NOT NULL,
    KEY idx_specs_goods (goods_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS orders (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    order_no VARCHAR(32) NOT NULL UNIQUE,
    user_id BIGINT NOT NULL,
    store_id BIGINT NOT NULL,
    store_name VARCHAR(128) NOT NULL,
    -- 0 待付款（15 分钟未支付自动取消） 1 待接单 2 制作中 3 配送中 4 已送达 5 已取消 6 退款中
    status INT NOT NULL DEFAULT 0,
    items TEXT NOT NULL,
    address TEXT NOT NULL,
    goods_amount DECIMAL(10,2) NOT NULL DEFAULT 0,
    delivery_fee DECIMAL(10,2) NOT NULL DEFAULT 0,
    discount DECIMAL(10,2) NOT NULL DEFAULT 0,
    coupon_id BIGINT NOT NULL DEFAULT 0,
    pay_amount DECIMAL(10,2) NOT NULL DEFAULT 0,
    remark VARCHAR(255) DEFAULT '',
    reviewed INT NOT NULL DEFAULT 0,
    escrow_status INT NOT NULL DEFAULT 0,
    create_time VARCHAR(32) NOT NULL,
    pay_time VARCHAR(32) DEFAULT '',
    accept_time VARCHAR(32) DEFAULT '',
    deliver_time VARCHAR(32) DEFAULT '',
    complete_time VARCHAR(32) DEFAULT '',
    rider_id BIGINT NOT NULL DEFAULT 0,
    ready_time VARCHAR(32) DEFAULT '',
    expect_time VARCHAR(32) DEFAULT '',
    KEY idx_orders_user (user_id),
    KEY idx_orders_store (store_id),
    KEY idx_orders_rider (rider_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS coupons (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT NOT NULL,
    store_id BIGINT NOT NULL DEFAULT 0,
    name VARCHAR(64) NOT NULL,
    threshold DECIMAL(10,2) NOT NULL DEFAULT 0,
    amount DECIMAL(10,2) NOT NULL DEFAULT 0,
    status INT NOT NULL DEFAULT 0,
    expire_time VARCHAR(32) NOT NULL,
    source VARCHAR(16) DEFAULT 'default',
    create_time VARCHAR(32) NOT NULL,
    KEY idx_coupons_user (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS reviews (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    order_id BIGINT NOT NULL DEFAULT 0,
    store_id BIGINT NOT NULL,
    goods_id BIGINT NOT NULL DEFAULT 0,
    user_id BIGINT NOT NULL,
    user_name VARCHAR(64) NOT NULL,
    rating INT NOT NULL DEFAULT 5,
    content VARCHAR(512) DEFAULT '',
    tags TEXT,
    images TEXT,
    anonymous INT NOT NULL DEFAULT 0,
    reply VARCHAR(512) DEFAULT '',
    reply_time VARCHAR(32) DEFAULT '',
    create_time VARCHAR(32) NOT NULL,
    KEY idx_reviews_store (store_id),
    KEY idx_reviews_goods (goods_id),
    KEY idx_reviews_order (order_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS favorites (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT NOT NULL,
    store_id BIGINT NOT NULL,
    create_time VARCHAR(32) NOT NULL,
    UNIQUE KEY uk_fav (user_id, store_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS addresses (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT NOT NULL,
    name VARCHAR(64) NOT NULL,
    phone VARCHAR(20) NOT NULL,
    detail VARCHAR(255) NOT NULL,
    is_default INT NOT NULL DEFAULT 0,
    create_time VARCHAR(32) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS categories (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(32) NOT NULL,
    icon VARCHAR(16) DEFAULT '',
    color VARCHAR(16) DEFAULT '#FF6B35',
    type VARCHAR(16) NOT NULL DEFAULT 'PLATFORM',
    merchant_id BIGINT NOT NULL DEFAULT 0,
    sort INT NOT NULL DEFAULT 0,
    status INT NOT NULL DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS refund_records (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    order_id BIGINT NOT NULL,
    user_id BIGINT NOT NULL,
    merchant_id BIGINT NOT NULL,
    reason VARCHAR(255) DEFAULT '',
    amount DECIMAL(10,2) NOT NULL DEFAULT 0,
    status VARCHAR(20) NOT NULL DEFAULT 'PENDING',
    apply_time VARCHAR(32) NOT NULL,
    process_time VARCHAR(32) DEFAULT '',
    reject_reason VARCHAR(255) DEFAULT '',
    KEY idx_refund_order (order_id),
    KEY idx_refund_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS cart_items (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT NOT NULL,
    goods_id BIGINT NOT NULL,
    -- 多规格：0 表示无规格菜品，>0 指向 goods_specs.id
    spec_id BIGINT NOT NULL DEFAULT 0,
    quantity INT NOT NULL DEFAULT 1,
    create_time VARCHAR(32) NOT NULL,
    update_time VARCHAR(32) NOT NULL,
    UNIQUE KEY uk_cart_user_goods_spec (user_id, goods_id, spec_id),
    KEY idx_cart_user (user_id),
    KEY idx_cart_goods (goods_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 骑手档案（四端改造：用户/商户/平台/骑手）。users.role=3 为骑手账号。
CREATE TABLE IF NOT EXISTS riders (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT NOT NULL,
    name VARCHAR(64) NOT NULL DEFAULT '',
    phone VARCHAR(20) NOT NULL DEFAULT '',
    online INT NOT NULL DEFAULT 0,
    total_orders INT NOT NULL DEFAULT 0,
    total_income DECIMAL(10,2) NOT NULL DEFAULT 0,
    status INT NOT NULL DEFAULT 1,
    create_time VARCHAR(32) NOT NULL,
    UNIQUE KEY uk_riders_user (user_id),
    KEY idx_riders_online (online)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 首页轮播 Banner（演进项已落地：内容管理）
CREATE TABLE IF NOT EXISTS banners (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    title VARCHAR(64) NOT NULL DEFAULT '',
    subtitle VARCHAR(128) DEFAULT '',
    image VARCHAR(255) DEFAULT '',
    color VARCHAR(16) DEFAULT '#FF6B35',
    link_type VARCHAR(16) DEFAULT 'NONE',
    link_value VARCHAR(128) DEFAULT '',
    sort INT NOT NULL DEFAULT 0,
    status INT NOT NULL DEFAULT 1,
    create_time VARCHAR(32) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 平台公告
CREATE TABLE IF NOT EXISTS announcements (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    title VARCHAR(128) NOT NULL DEFAULT '',
    content VARCHAR(1024) NOT NULL DEFAULT '',
    status INT NOT NULL DEFAULT 1,
    create_time VARCHAR(32) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 限时秒杀（营销类演进项）：时间窗口内下单自动按秒杀价结算，quota 控制秒杀名额。
CREATE TABLE IF NOT EXISTS seckills (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    goods_id BIGINT NOT NULL,
    store_id BIGINT NOT NULL,
    price DECIMAL(10,2) NOT NULL DEFAULT 0,
    quota INT NOT NULL DEFAULT 0,
    sold INT NOT NULL DEFAULT 0,
    start_time VARCHAR(32) NOT NULL,
    end_time VARCHAR(32) NOT NULL,
    status INT NOT NULL DEFAULT 1,
    create_time VARCHAR(32) NOT NULL,
    KEY idx_seckill_goods (goods_id),
    KEY idx_seckill_window (status, start_time, end_time)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 事务性 Outbox：领域事件与业务数据同事务落库，再由中继任务投递到 Redis Stream。
-- status：0 待投递 / 1 已投递；retry_count 用于限制投递重试次数。
CREATE TABLE IF NOT EXISTS outbox_events (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    event_type VARCHAR(64) NOT NULL,
    order_id BIGINT NOT NULL DEFAULT 0,
    payload TEXT,
    status INT NOT NULL DEFAULT 0,
    retry_count INT NOT NULL DEFAULT 0,
    create_time VARCHAR(32) NOT NULL,
    KEY idx_outbox_pending (status, id),
    KEY idx_outbox_order (order_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

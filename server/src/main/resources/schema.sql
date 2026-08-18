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

CREATE TABLE IF NOT EXISTS orders (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    order_no VARCHAR(32) NOT NULL UNIQUE,
    user_id BIGINT NOT NULL,
    store_id BIGINT NOT NULL,
    store_name VARCHAR(128) NOT NULL,
    status INT NOT NULL DEFAULT 1,
    items TEXT NOT NULL,
    address TEXT NOT NULL,
    goods_amount DECIMAL(10,2) NOT NULL DEFAULT 0,
    delivery_fee DECIMAL(10,2) NOT NULL DEFAULT 0,
    discount DECIMAL(10,2) NOT NULL DEFAULT 0,
    pay_amount DECIMAL(10,2) NOT NULL DEFAULT 0,
    remark VARCHAR(255) DEFAULT '',
    reviewed INT NOT NULL DEFAULT 0,
    escrow_status INT NOT NULL DEFAULT 0,
    create_time VARCHAR(32) NOT NULL,
    pay_time VARCHAR(32) DEFAULT '',
    accept_time VARCHAR(32) DEFAULT '',
    deliver_time VARCHAR(32) DEFAULT '',
    complete_time VARCHAR(32) DEFAULT '',
    KEY idx_orders_user (user_id),
    KEY idx_orders_store (store_id)
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
    store_id BIGINT NOT NULL,
    goods_id BIGINT NOT NULL DEFAULT 0,
    user_id BIGINT NOT NULL,
    user_name VARCHAR(64) NOT NULL,
    rating INT NOT NULL DEFAULT 5,
    content VARCHAR(512) DEFAULT '',
    tags TEXT,
    create_time VARCHAR(32) NOT NULL,
    KEY idx_reviews_store (store_id),
    KEY idx_reviews_goods (goods_id)
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
    quantity INT NOT NULL DEFAULT 1,
    create_time VARCHAR(32) NOT NULL,
    update_time VARCHAR(32) NOT NULL,
    UNIQUE KEY uk_cart_user_goods (user_id, goods_id),
    KEY idx_cart_user (user_id),
    KEY idx_cart_goods (goods_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 简单外卖数据库表结构（SQLite）
-- 由 Spring 启动时自动执行（spring.sql.init.mode=always）

CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT NOT NULL,
    avatar TEXT DEFAULT '',
    phone TEXT NOT NULL UNIQUE,
    password TEXT NOT NULL,
    role INTEGER NOT NULL DEFAULT 0,
    balance REAL NOT NULL DEFAULT 0,
    create_time TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS stores (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    image TEXT DEFAULT '',
    rating REAL NOT NULL DEFAULT 4.5,
    monthly_sales INTEGER NOT NULL DEFAULT 0,
    delivery_fee REAL NOT NULL DEFAULT 0,
    min_order REAL NOT NULL DEFAULT 0,
    delivery_time TEXT DEFAULT '30分钟',
    distance TEXT DEFAULT '1.0km',
    tags TEXT DEFAULT '[]',
    notice TEXT DEFAULT '',
    category_id INTEGER NOT NULL DEFAULT 1,
    category_ids TEXT DEFAULT '[]',
    owner_id INTEGER NOT NULL,
    status INTEGER NOT NULL DEFAULT 1,
    create_time TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS goods (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    store_id INTEGER NOT NULL,
    name TEXT NOT NULL,
    description TEXT DEFAULT '',
    price REAL NOT NULL DEFAULT 0,
    original_price REAL DEFAULT 0,
    image TEXT DEFAULT '',
    category_id INTEGER NOT NULL DEFAULT 1,
    sales INTEGER NOT NULL DEFAULT 0,
    rating REAL NOT NULL DEFAULT 4.5,
    tag TEXT DEFAULT '',
    status INTEGER NOT NULL DEFAULT 1,
    create_time TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS orders (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    order_no TEXT NOT NULL UNIQUE,
    user_id INTEGER NOT NULL,
    store_id INTEGER NOT NULL,
    store_name TEXT NOT NULL,
    status INTEGER NOT NULL DEFAULT 1,
    items TEXT NOT NULL DEFAULT '[]',
    address TEXT NOT NULL DEFAULT '{}',
    goods_amount REAL NOT NULL DEFAULT 0,
    delivery_fee REAL NOT NULL DEFAULT 0,
    discount REAL NOT NULL DEFAULT 0,
    pay_amount REAL NOT NULL DEFAULT 0,
    remark TEXT DEFAULT '',
    reviewed INTEGER NOT NULL DEFAULT 0,
    create_time TEXT NOT NULL,
    pay_time TEXT DEFAULT '',
    accept_time TEXT DEFAULT '',
    deliver_time TEXT DEFAULT '',
    complete_time TEXT DEFAULT ''
);

CREATE TABLE IF NOT EXISTS coupons (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    store_id INTEGER NOT NULL DEFAULT 0,
    name TEXT NOT NULL,
    threshold REAL NOT NULL DEFAULT 0,
    amount REAL NOT NULL DEFAULT 0,
    status INTEGER NOT NULL DEFAULT 0,
    expire_time TEXT NOT NULL,
    source TEXT DEFAULT 'default',
    create_time TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS reviews (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    store_id INTEGER NOT NULL,
    user_id INTEGER NOT NULL,
    user_name TEXT NOT NULL,
    rating INTEGER NOT NULL DEFAULT 5,
    content TEXT DEFAULT '',
    tags TEXT DEFAULT '[]',
    create_time TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS favorites (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    store_id INTEGER NOT NULL,
    create_time TEXT NOT NULL,
    UNIQUE (user_id, store_id)
);

CREATE TABLE IF NOT EXISTS addresses (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    name TEXT NOT NULL,
    phone TEXT NOT NULL,
    detail TEXT NOT NULL,
    is_default INTEGER NOT NULL DEFAULT 0,
    create_time TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS categories (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    icon TEXT DEFAULT '',
    color TEXT DEFAULT '#FF6B35'
);

CREATE INDEX IF NOT EXISTS idx_goods_store ON goods(store_id);
CREATE INDEX IF NOT EXISTS idx_orders_user ON orders(user_id);
CREATE INDEX IF NOT EXISTS idx_orders_store ON orders(store_id);
CREATE INDEX IF NOT EXISTS idx_reviews_store ON reviews(store_id);
CREATE INDEX IF NOT EXISTS idx_coupons_user ON coupons(user_id);

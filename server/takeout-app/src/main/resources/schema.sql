-- 简单外卖数据库表结构（MySQL 8.x）
-- 由 Spring 启动时自动执行（spring.sql.init.mode=always）

CREATE TABLE IF NOT EXISTS users (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(64) NOT NULL,
    avatar VARCHAR(255) DEFAULT '',
    phone VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_bin NOT NULL UNIQUE,
    email VARCHAR(254) DEFAULT NULL,
    password VARCHAR(128) NOT NULL,
    role INT NOT NULL DEFAULT 0,
    status INT NOT NULL DEFAULT 1,
    balance DECIMAL(10,2) NOT NULL DEFAULT 0,
    create_time VARCHAR(32) NOT NULL,
    -- 最后一次改密时间（yyyy-MM-dd HH:mm:ss，空=从未改密）：签发时间早于它的 token 一律失效
    password_changed_at VARCHAR(32) NOT NULL DEFAULT '',
    -- 与登录密码独立的 6 位支付密码哈希；空值表示尚未设置
    payment_password_hash VARCHAR(128) DEFAULT NULL,
    UNIQUE KEY uk_users_username (username),
    KEY idx_users_admin_role_status_page (role, status, id),
    KEY idx_users_admin_status_page (status, id)
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
    delivery_radius INT NOT NULL DEFAULT 0,
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
    deleted INT NOT NULL DEFAULT 0,
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

-- 下单防重与业务事务一同提交；不依赖 Redis 可用性或缓存 TTL。
CREATE TABLE IF NOT EXISTS order_create_requests (
    user_id BIGINT NOT NULL,
    request_key VARCHAR(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL,
    order_id BIGINT DEFAULT NULL,
    create_time DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, request_key)
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
    cancel_source VARCHAR(16) NOT NULL DEFAULT '',
    cancel_reason_code VARCHAR(32) NOT NULL DEFAULT '',
    cancel_reason VARCHAR(255) NOT NULL DEFAULT '',
    reject_note VARCHAR(255) NOT NULL DEFAULT '',
    reject_goods_id BIGINT NOT NULL DEFAULT 0,
    reject_spec_id BIGINT NOT NULL DEFAULT 0,
    cancel_operator_id BIGINT NOT NULL DEFAULT 0,
    rider_id BIGINT NOT NULL DEFAULT 0,
    ready_time VARCHAR(32) DEFAULT '',
    expect_time VARCHAR(32) DEFAULT '',
    -- DATETIME shadows are dual-written; legacy strings remain during the rolling compatibility window.
    create_time_dt DATETIME DEFAULT NULL,
    pay_time_dt DATETIME DEFAULT NULL,
    accept_time_dt DATETIME DEFAULT NULL,
    deliver_time_dt DATETIME DEFAULT NULL,
    complete_time_dt DATETIME DEFAULT NULL,
    ready_time_dt DATETIME DEFAULT NULL,
    expect_time_dt DATETIME DEFAULT NULL,
    delivery_type VARCHAR(16) NOT NULL DEFAULT 'DELIVERY',
    KEY idx_orders_user (user_id),
    KEY idx_orders_store (store_id),
    KEY idx_orders_rider (rider_id),
    KEY idx_orders_user_page (user_id, id),
    KEY idx_orders_store_page (store_id, id),
    KEY idx_orders_rider_page (rider_id, id),
    KEY idx_orders_admin_status_page (status, id),
    KEY idx_orders_pending_timeout (status, create_time, id),
    KEY idx_orders_rider_pool (status, rider_id, ready_time, id),
    KEY idx_orders_auto_confirm (status, escrow_status, complete_time_dt)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 结构化订单商品快照；orders.items 保留用于旧客户端与存量订单兼容。
CREATE TABLE IF NOT EXISTS order_items (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    order_id BIGINT NOT NULL,
    line_no INT NOT NULL,
    goods_id BIGINT NOT NULL,
    goods_name VARCHAR(128) NOT NULL,
    unit_price DECIMAL(10,2) NOT NULL,
    quantity INT NOT NULL,
    image VARCHAR(255) NOT NULL DEFAULT '',
    spec_id BIGINT NOT NULL DEFAULT 0,
    spec_name VARCHAR(64) NOT NULL DEFAULT '',
    seckill_id BIGINT NOT NULL DEFAULT 0,
    UNIQUE KEY uk_order_items_line (order_id, line_no),
    KEY idx_order_items_goods (goods_id, order_id),
    KEY idx_order_items_spec (spec_id, order_id)
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
    expire_time_dt DATETIME DEFAULT NULL,
    create_time_dt DATETIME DEFAULT NULL,
    KEY idx_coupons_user (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 钱包银行卡信息：完整卡号使用服务端 AES-GCM 加密，列表只返回掩码；解绑保留记录。
CREATE TABLE IF NOT EXISTS bank_cards (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT NOT NULL,
    bank_name VARCHAR(64) NOT NULL,
    card_type VARCHAR(32) NOT NULL DEFAULT '储蓄卡',
    card_no_last4 VARCHAR(4) NOT NULL,
    full_card_encrypted TEXT DEFAULT NULL,
    is_default INT NOT NULL DEFAULT 0,
    status INT NOT NULL DEFAULT 1,
    create_time VARCHAR(32) NOT NULL,
    KEY idx_bank_card_user (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 支付/退款明细台账（最小侵入拆表：只增此表，订单商品仍走 items JSON 快照）
CREATE TABLE IF NOT EXISTS payment_records (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    order_id BIGINT NOT NULL,
    user_id BIGINT NOT NULL,
    amount DECIMAL(10,2) NOT NULL DEFAULT 0,
    type VARCHAR(16) NOT NULL,
    channel VARCHAR(16) NOT NULL DEFAULT 'BALANCE',
    status VARCHAR(16) NOT NULL DEFAULT 'SUCCESS',
    create_time VARCHAR(32) NOT NULL,
    KEY idx_payment_records_order (order_id),
    KEY idx_payment_records_user (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Third-party payment attempts. active_order_id serializes concurrent channels for one pending order.
CREATE TABLE IF NOT EXISTS payment_transactions (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    order_id BIGINT NOT NULL,
    user_id BIGINT NOT NULL,
    channel VARCHAR(16) NOT NULL,
    amount DECIMAL(10,2) NOT NULL,
    out_trade_no VARCHAR(32) NOT NULL,
    provider_transaction_id VARCHAR(128) DEFAULT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'PENDING',
    payment_url TEXT,
    payment_mode VARCHAR(8) NOT NULL DEFAULT 'QR',
    active_order_id BIGINT DEFAULT NULL,
    create_time VARCHAR(32) NOT NULL,
    notify_time VARCHAR(32) DEFAULT NULL,
    UNIQUE KEY uk_payment_transactions_out_trade_no (out_trade_no),
    UNIQUE KEY uk_payment_transactions_provider_id (channel, provider_transaction_id),
    UNIQUE KEY uk_payment_transactions_active_order (active_order_id),
    KEY idx_payment_transactions_order (order_id, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 优惠券领取台账：按活动唯一(user_id,store_id,name)终身限领一次，唯一键兜底并发
CREATE TABLE IF NOT EXISTS user_coupons (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT NOT NULL,
    store_id BIGINT NOT NULL DEFAULT 0,
    name VARCHAR(64) NOT NULL,
    threshold DECIMAL(10,2) NOT NULL DEFAULT 0,
    amount DECIMAL(10,2) NOT NULL DEFAULT 0,
    claim_time VARCHAR(32) NOT NULL,
    expire_time VARCHAR(32) NOT NULL,
    claim_time_dt DATETIME DEFAULT NULL,
    expire_time_dt DATETIME DEFAULT NULL,
    UNIQUE KEY uk_user_coupon_campaign (user_id, store_id, name),
    KEY idx_user_coupons_user (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 营销活动：DISCOUNT 折扣率 / NEW_USER 新客立减 / GIFT 满赠（赠品商品）
CREATE TABLE IF NOT EXISTS marketing_activities (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    store_id BIGINT NOT NULL,
    type VARCHAR(16) NOT NULL,
    title VARCHAR(64) NOT NULL,
    discount_rate DECIMAL(4,3) NOT NULL DEFAULT 0,
    reduce_amount DECIMAL(10,2) NOT NULL DEFAULT 0,
    threshold DECIMAL(10,2) NOT NULL DEFAULT 0,
    gift_goods_id BIGINT NOT NULL DEFAULT 0,
    start_time VARCHAR(32) NOT NULL,
    end_time VARCHAR(32) NOT NULL,
    status INT NOT NULL DEFAULT 1,
    create_time VARCHAR(32) NOT NULL,
    start_time_dt DATETIME DEFAULT NULL,
    end_time_dt DATETIME DEFAULT NULL,
    create_time_dt DATETIME DEFAULT NULL,
    KEY idx_mkt_store (store_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 套餐与组合购：套餐头 + 套餐明细（组件商品）
CREATE TABLE IF NOT EXISTS setmeals (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    store_id BIGINT NOT NULL,
    name VARCHAR(128) NOT NULL,
    description VARCHAR(512) DEFAULT '',
    price DECIMAL(10,2) NOT NULL DEFAULT 0,
    original_price DECIMAL(10,2) NOT NULL DEFAULT 0,
    image VARCHAR(255) DEFAULT '',
    status INT NOT NULL DEFAULT 1,
    create_time VARCHAR(32) NOT NULL,
    KEY idx_setmeal_store (store_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS setmeal_items (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    setmeal_id BIGINT NOT NULL,
    goods_id BIGINT NOT NULL,
    goods_name VARCHAR(128) NOT NULL,
    quantity INT NOT NULL DEFAULT 1,
    KEY idx_setmeal_item_setmeal (setmeal_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 门店员工：商户可把账号按店分配角色，员工仅能操作被分配的店铺
CREATE TABLE IF NOT EXISTS employees (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    store_id BIGINT NOT NULL,
    user_id BIGINT NOT NULL,
    role_name VARCHAR(16) NOT NULL DEFAULT '',
    status INT NOT NULL DEFAULT 1,
    create_time VARCHAR(32) NOT NULL,
    UNIQUE KEY uk_employee_store_user (store_id, user_id),
    KEY idx_employee_user (user_id)
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
    latitude DECIMAL(10,7) DEFAULT NULL,
    longitude DECIMAL(10,7) DEFAULT NULL,
    map_address VARCHAR(255) DEFAULT NULL,
    door_detail VARCHAR(255) DEFAULT NULL,
    tag VARCHAR(16) NOT NULL DEFAULT '',
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
    status INT NOT NULL DEFAULT 1,
    deleted INT NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS refund_records (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    order_id BIGINT NOT NULL,
    user_id BIGINT NOT NULL,
    merchant_id BIGINT NOT NULL,
    reason VARCHAR(255) DEFAULT '',
    reason_type VARCHAR(32) NOT NULL DEFAULT 'OTHER',
    request_key VARCHAR(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_bin DEFAULT NULL,
    amount DECIMAL(10,2) NOT NULL DEFAULT 0,
    status VARCHAR(20) NOT NULL DEFAULT 'PENDING',
    apply_time VARCHAR(32) NOT NULL,
    process_time VARCHAR(32) DEFAULT '',
    reject_reason VARCHAR(255) DEFAULT '',
    KEY idx_refund_order (order_id),
    UNIQUE KEY uk_refund_order_request (order_id, request_key),
    KEY idx_refund_status_page (status, id),
    KEY idx_refund_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 每个已接受的退款请求都固定指向原申请，包括复用同一 PENDING 的并发请求。
CREATE TABLE IF NOT EXISTS refund_apply_requests (
    order_id BIGINT NOT NULL,
    request_key VARCHAR(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_bin NOT NULL,
    refund_id BIGINT NOT NULL,
    create_time DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (order_id, request_key)
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
    -- 骑手配送半径（米）：默认 25 公里；接单圆心=下方 latitude/longitude
    delivery_radius INT NOT NULL DEFAULT 25000,
    latitude DOUBLE DEFAULT NULL,
    longitude DOUBLE DEFAULT NULL,
    location_address VARCHAR(255) NOT NULL DEFAULT '',
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
    deleted INT NOT NULL DEFAULT 0,
    create_time VARCHAR(32) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 平台公告
CREATE TABLE IF NOT EXISTS announcements (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    title VARCHAR(128) NOT NULL DEFAULT '',
    content VARCHAR(1024) NOT NULL DEFAULT '',
    status INT NOT NULL DEFAULT 1,
    deleted INT NOT NULL DEFAULT 0,
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
    start_time_dt DATETIME DEFAULT NULL,
    end_time_dt DATETIME DEFAULT NULL,
    create_time_dt DATETIME DEFAULT NULL,
    KEY idx_seckill_goods (goods_id),
    KEY idx_seckill_window (status, start_time, end_time)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 秒杀「一人一单」：同一用户对同一场秒杀最多一笔未取消订单；下单登记，取消/超时释放。
-- 唯一键(user_id, seckill_id)是防重的唯一权威，Dao 用 INSERT IGNORE 依赖它。
CREATE TABLE IF NOT EXISTS seckill_orders (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT NOT NULL,
    seckill_id BIGINT NOT NULL,
    order_id BIGINT NOT NULL DEFAULT 0,
    create_time VARCHAR(32) NOT NULL,
    create_time_dt DATETIME DEFAULT NULL,
    UNIQUE KEY uk_seckill_user (user_id, seckill_id),
    KEY idx_seckill_orders_seckill (seckill_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 事务性 Outbox：领域事件与业务数据同事务落库，再由中继任务投递到 Redis Stream。
-- status：0 待投递 / 1 已投递；retry_count 用于限制投递重试次数。
-- owner/lease_until：多实例行级认领（SELECT ... FOR UPDATE SKIP LOCKED）。
--   owner = 认领者实例 ID（仅诊断用）；lease_until = 租约到期 epoch 毫秒，
--   0 表示未认领；认领后崩溃的行在租约过期后可由任意实例重新认领。
CREATE TABLE IF NOT EXISTS outbox_events (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    event_type VARCHAR(64) NOT NULL,
    order_id BIGINT NOT NULL DEFAULT 0,
    payload TEXT,
    status INT NOT NULL DEFAULT 0,
    retry_count INT NOT NULL DEFAULT 0,
    owner VARCHAR(64) NOT NULL DEFAULT '',
    lease_until BIGINT NOT NULL DEFAULT 0,
    create_time VARCHAR(32) NOT NULL,
    create_time_dt DATETIME DEFAULT NULL,
    KEY idx_outbox_pending (status, id),
    KEY idx_outbox_claim (status, lease_until, id),
    KEY idx_outbox_order (order_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Token 黑名单：登出时把当前 token 的 jti 落库，过期时间与 token 自身一致。
-- 放数据库而非 Redis：登出必须"Redis 挂了也照样生效"，且本地开发常不开 Redis。
CREATE TABLE IF NOT EXISTS token_blacklist (
    jti VARCHAR(64) PRIMARY KEY,
    user_id BIGINT NOT NULL DEFAULT 0,
    reason VARCHAR(32) NOT NULL DEFAULT 'logout',
    expires_at BIGINT NOT NULL DEFAULT 0,
    create_time VARCHAR(32) NOT NULL,
    KEY idx_blacklist_expires (expires_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- HarmonyOS Push Kit device tokens are encrypted at rest and scoped to the authenticated account.
CREATE TABLE IF NOT EXISTS push_tokens (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT NOT NULL,
    token_hash CHAR(64) NOT NULL,
    token_encrypted TEXT NOT NULL,
    updated_at BIGINT NOT NULL,
    UNIQUE KEY uk_push_token_hash (token_hash),
    KEY idx_push_tokens_user (user_id, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 操作审计：只保存路由和结果元数据，不记录请求体或凭证。
CREATE TABLE IF NOT EXISTS operation_audit_logs (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    operator_id BIGINT NOT NULL,
    operator_role INT NOT NULL,
    order_id BIGINT NOT NULL DEFAULT 0,
    status_after INT NOT NULL DEFAULT -1,
    action VARCHAR(128) NOT NULL,
    http_method VARCHAR(10) NOT NULL,
    request_path VARCHAR(255) NOT NULL,
    outcome VARCHAR(16) NOT NULL,
    http_status INT NOT NULL,
    trace_id VARCHAR(64) NOT NULL DEFAULT '',
    created_at BIGINT NOT NULL,
    KEY idx_operation_audit_time (created_at, id),
    KEY idx_operation_audit_actor_time (operator_role, operator_id, created_at, id),
    KEY idx_operation_audit_order (order_id, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- AI 助手连接配置：API Key 使用服务端 AES-GCM 加密，管理员读取只返回是否已配置。
CREATE TABLE IF NOT EXISTS assistant_config (
    id INT PRIMARY KEY,
    enabled INT NOT NULL DEFAULT 0,
    endpoint VARCHAR(1024) NOT NULL DEFAULT '',
    model VARCHAR(128) NOT NULL DEFAULT '',
    api_key_encrypted TEXT NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT IGNORE INTO assistant_config (id, enabled, endpoint, model, api_key_encrypted)
VALUES (1, 0, '', '', '');

-- 上传历史容量预算；user_id=0 为全局预算。历史文件上线前须补录。
CREATE TABLE IF NOT EXISTS upload_usage (
    user_id BIGINT PRIMARY KEY,
    used_bytes BIGINT NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

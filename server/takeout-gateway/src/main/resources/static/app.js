(() => {
  'use strict';

  const ROLE = { 0: 'CUSTOMER', 1: 'MERCHANT', 2: 'ADMIN', 3: 'RIDER' };
  const STATUS = ['待付款', '待接单', '制作中', '配送中', '已送达', '已取消', '退款中'];
  const NAV = {
    0: [['首页', 'home', '⌂'], ['搜索与榜单', 'discover', '⌕'], ['购物车', 'cart', '▣'], ['我的订单', 'orders', '▤'], ['收藏与优惠券', 'perks', '♡'], ['地址与钱包', 'account', '◎'], ['个人设置', 'settings', '⚙'], ['智能客服', 'assistant', '?']],
    1: [['经营概况', 'overview', '▦'], ['订单处理', 'merchant-orders', '▤'], ['门店与商品', 'catalog', '▣'], ['评价回复', 'reviews', '☆'], ['营销活动', 'marketing', '◇']],
    2: [['平台总览', 'overview', '▦'], ['分类管理', 'categories', '▦'], ['店铺审核', 'stores', '⌂'], ['全平台订单', 'admin-orders', '▤'], ['退款审批', 'refunds', '↩'], ['用户与商品', 'users', '♙'], ['骑手管理', 'riders', '➤'], ['内容管理', 'content', '▧'], ['员工管理', 'employees', '♧'], ['操作日志', 'audit', '≡'], ['营销监管', 'admin-marketing', '◇']],
    3: [['待抢订单', 'rider-pool', '⌖'], ['配送订单', 'rider-orders', '➤'], ['骑手资料', 'rider-profile', '♙']]
  };
  const TITLES = {
    home: '首页', discover: '搜索与榜单', cart: '购物车', checkout: '确认订单', orders: '我的订单', perks: '收藏与优惠券', account: '地址与钱包', settings: '个人设置', assistant: '智能客服',
    overview: '经营概况', 'merchant-orders': '订单处理', catalog: '门店与商品', reviews: '评价回复', marketing: '营销活动',
    categories: '分类管理', stores: '店铺审核', 'admin-orders': '全平台订单', refunds: '退款审批', users: '用户与商品', riders: '骑手管理', content: '内容管理', employees: '员工管理', audit: '操作日志', 'admin-marketing': '营销监管',
    'rider-pool': '待抢订单', 'rider-orders': '配送订单', 'rider-profile': '骑手资料'
  };
  const state = {
    token: localStorage.getItem('takeout.demo.token') || '', refreshToken: localStorage.getItem('takeout.demo.refresh') || '',
    user: null, role: 0, page: 'home', search: '', categoryId: 0, stores: [], categories: [], storeId: 0,
    goods: [], cart: [], addresses: [], coupons: [], orders: [], favorites: [], rider: null, riderOrders: [],
    merchantStores: [], activeStoreId: 0, merchantGoods: [], editGoods: null, editAddress: null, reviewOrder: null,
    adminUsers: [], adminProducts: [], adminStores: [], adminCategories: [], adminOrders: [], adminRefunds: [],
    adminRiders: [], adminBanners: [], adminAnnouncements: [], adminEmployees: [], adminActivities: [], adminSeckills: [],
    merchantActivities: [], merchantSeckills: [], merchantReviews: [], assistantHistory: []
  };
  const $ = (id) => document.getElementById(id);
  const esc = (v) => String(v ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
  const cash = (v) => Number(v || 0).toFixed(2);
  const toast = (message, error = false) => { const el = $('notice'); el.textContent = message; el.classList.toggle('error', error); el.hidden = false; clearTimeout(toast.timer); toast.timer = setTimeout(() => { el.hidden = true; }, 3600); };
  const api = async (path, options = {}) => {
    const headers = { 'Content-Type': 'application/json', ...(options.headers || {}) };
    if (state.token) headers.Authorization = `Bearer ${state.token}`;
    const response = await fetch(path, { cache: 'no-store', ...options, headers });
    const body = await response.json().catch(() => ({}));
    if (response.status === 401) {
      state.token = ''; state.refreshToken = ''; localStorage.removeItem('takeout.demo.token'); localStorage.removeItem('takeout.demo.refresh');
      state.user = null; renderShell(); throw new Error('登录已过期，请重新登录');
    }
    if (!response.ok || body.code !== 200) throw new Error(body.message || `请求失败 (${response.status})`);
    return body.data;
  };
  const get = (path) => api(path);
  const send = (path, method, data) => api(path, { method, body: data === undefined ? undefined : JSON.stringify(data) });
  const pageHead = (title, description = '', actions = '') => `<div class="page-head"><div><h1>${esc(title)}</h1>${description ? `<p>${esc(description)}</p>` : ''}</div><div class="head-actions">${actions}</div></div>`;
  const empty = (text) => `<div class="empty">${esc(text)}</div>`;
  const btn = (label, action, value = '', style = '') => `<button class="btn ${style}" data-action="${esc(action)}" data-id="${esc(value)}">${esc(label)}</button>`;
  const statusTag = (value, kind = '') => `<span class="status ${kind}">${esc(value)}</span>`;
  const storeImage = (store) => store.image ? `<img src="${esc(store.image)}" alt="">` : '食';
  const orderStatus = (o) => o.status === 4 && o.escrowStatus === 1 ? '已完成' : (STATUS[o.status] || '未知');
  const openAuth = (mode = 'login') => {
    $('authTitle').textContent = mode === 'register' ? '注册用户账号' : '登录';
    $('authForm').dataset.mode = mode;
    $('authForm').innerHTML = mode === 'register'
      ? `<label class="field">用户名<input class="input" name="username" required placeholder="例如：小王"></label><label class="field">手机号<input class="input" name="phone" required inputmode="tel" placeholder="13800138000"></label><label class="field">邮箱<input class="input" name="email" required type="email" placeholder="name@example.com"></label><div class="row-between"><label class="field" style="flex:1">邮箱验证码<input class="input" name="code" required placeholder="验证码"></label><button class="btn" type="button" data-action="send-code" style="margin-top:20px">获取验证码</button></div><label class="field">登录密码<input class="input" name="password" required type="password" minlength="6"></label><div class="form-actions"><button class="btn" type="button" data-action="auth-switch" data-id="login">返回登录</button><button class="btn primary">注册</button></div>`
      : `<label class="field">登录端<select class="select" name="loginType"><option value="CUSTOMER">用户端</option><option value="MERCHANT">商户端</option><option value="RIDER">骑手端</option><option value="ADMIN">管理端</option></select></label><label class="field">手机号<input class="input" name="phone" required inputmode="tel" value="13800138000" autocomplete="username"></label><label class="field">密码<input class="input" name="password" required type="password" value="123456" autocomplete="current-password"></label><div class="form-actions"><button class="btn" type="button" data-action="auth-switch" data-id="register">注册用户</button><button class="btn primary">登录</button></div>`;
    $('authModal').hidden = false;
  };
  const loginWith = async (payload) => {
    const data = await send('/api/auth/login', 'POST', payload);
    state.token = data.token; state.refreshToken = data.refreshToken || '';
    localStorage.setItem('takeout.demo.token', state.token); localStorage.setItem('takeout.demo.refresh', state.refreshToken);
    state.user = data.user; state.role = Number(data.user.role); state.page = state.role === 0 ? 'home' : 'overview';
    $('authModal').hidden = true; renderShell(); await renderPage();
  };
  const logout = async () => {
    try { await send('/api/auth/logout', 'POST', { refreshToken: state.refreshToken, pushToken: '' }); } catch (_) {}
    state.token = ''; state.refreshToken = ''; state.user = null; state.role = 0;
    localStorage.removeItem('takeout.demo.token'); localStorage.removeItem('takeout.demo.refresh');
    state.page = 'home'; renderShell(); await renderPage(); toast('已退出登录');
  };
  const requireUser = (message = '请先登录') => { if (!state.token) { openAuth(); toast(message); return false; } return true; };
  function renderShell() {
    const logged = Boolean(state.user && state.token);
    $('topLogin').hidden = logged; $('topLogout').hidden = !logged; $('topCart').hidden = !logged || state.role !== 0;
    $('userMeta').textContent = logged ? `${state.user.username || state.user.phone} · ${['用户','商户','管理','骑手'][state.role] || '用户'}` : '与手机端共用服务端';
    $('navCaption').textContent = logged ? ({ 0: '用户服务', 1: '商户工作台', 2: '平台管理', 3: '配送工作台' }[state.role] || '工作台') : '浏览';
    let nav = logged ? (NAV[state.role] || NAV[0]) : [['首页', 'home', '⌂'], ['搜索与榜单', 'discover', '⌕']];
    if (!logged && state.role === 0 && !nav.some(x => x[1] === 'home')) nav = NAV[0].slice(0, 2);
    $('nav').innerHTML = nav.map(([label, page, icon]) => `<button class="nav-item ${state.page === page ? 'active' : ''}" data-page="${page}"><span class="nav-icon">${icon}</span>${label}</button>`).join('');
    $('topCart').onclick = () => { if (requireUser()) navigate('cart'); };
    $('topLogin').onclick = () => openAuth(); $('topLogout').onclick = logout;
  }
  const navigate = async (page) => {
    if (page !== 'home' && page !== 'discover' && !requireUser()) return;
    const allowed = (NAV[state.role] || NAV[0]).some(item => item[1] === page);
    if (!allowed && page !== 'store' && page !== 'checkout') { toast('当前账号无此页面权限', true); return; }
    state.page = page; renderShell(); await renderPage(); window.scrollTo({ top: 0, behavior: 'smooth' });
  };
  const renderPage = async () => {
    const app = $('app'); app.innerHTML = empty('正在读取服务端数据…');
    try {
      if (state.role === 0 || !state.user) await renderCustomer(state.page);
      else if (state.role === 1) await renderMerchant(state.page);
      else if (state.role === 2) await renderAdmin(state.page);
      else if (state.role === 3) await renderRider(state.page);
      bindForms();
    } catch (error) { app.innerHTML = `${pageHead(TITLES[state.page] || '工作台')}<div class="notice-line">${esc(error.message || '加载失败')}</div><div class="form-actions">${btn('重试', 'refresh')}</div>`; }
  };
  const renderCustomer = async (page) => {
    if (page === 'home' || page === 'discover') return renderBrowse(page);
    if (page === 'store') return renderStore();
    if (page === 'cart') return renderCart();
    if (page === 'checkout') return renderCheckout();
    if (page === 'orders') return renderOrders();
    if (page === 'perks') return renderPerks();
    if (page === 'account') return renderAccount();
    if (page === 'settings') return renderSettings();
    if (page === 'assistant') return renderAssistant();
  };
  const renderBrowse = async (page) => {
    if (!state.user || !state.token) {
      $('app').innerHTML = `${pageHead('简单外卖', '登录后浏览真实店铺、优惠活动和订单', btn('登录并开始点餐', 'login', '', 'primary'))}<div class="grid four"><div class="metric"><div class="metric-label">用户端</div><div class="metric-value">点餐</div><div class="metric-note">浏览店铺、购物车、订单与评价</div></div><div class="metric"><div class="metric-label">商户端</div><div class="metric-value">经营</div><div class="metric-note">接单、出餐、商品和营销</div></div><div class="metric"><div class="metric-label">骑手端</div><div class="metric-value">配送</div><div class="metric-note">抢单、取餐、送达</div></div><div class="metric"><div class="metric-label">平台端</div><div class="metric-value">管理</div><div class="metric-note">审核、退款、统计和内容</div></div></div><div class="page-panel section"><div class="notice-line">网页端与 HarmonyOS 客户端共用同一套账号、购物车、地址、订单和配送状态。请先登录再进入对应工作区。</div></div>`;
      return;
    }
    const [categories, stores, banners, announcements] = await Promise.all([
      get('/api/categories'), get(page === 'discover' ? `/api/search?keyword=${encodeURIComponent(state.search || '')}` : '/api/stores/recommended?limit=12'),
      get('/api/banners').catch(() => []), get('/api/announcements').catch(() => [])
    ]);
    state.categories = categories || []; state.stores = stores || [];
    const shortcuts = page === 'discover' ? `<div class="toolbar">${btn('热销店铺', 'rank-stores')} ${btn('热销菜品', 'rank-goods')} ${btn('特价商品', 'specials')} ${btn('限时秒杀', 'seckills')}</div>` : '';
    const bannersHtml = (banners || []).filter(b => b.status === 1).slice(0, 3).map(b => `<div class="surface"><strong>${esc(b.title)}</strong><div class="subtle">${esc(b.subtitle || '')}</div></div>`).join('');
    const annHtml = (announcements || []).filter(a => a.status === 1).slice(0, 3).map(a => `<div class="notice-line" style="margin-bottom:8px"><strong>${esc(a.title)}</strong> · ${esc(a.content)}</div>`).join('');
    $('app').innerHTML = `${pageHead(page === 'home' ? '附近好店' : '发现好味道', '店铺、商品和订单状态均来自共享服务端', `${state.user ? btn('我的订单','go','orders') : btn('登录点餐','login','','primary')}`)}${annHtml}${bannersHtml ? `<div class="grid section">${bannersHtml}</div>` : ''}<div class="toolbar section"><input class="input" id="storeSearch" placeholder="搜索店铺或菜品" value="${esc(state.search)}"><button class="btn primary" data-action="search">搜索</button><select class="select" id="categoryFilter" style="max-width:220px"><option value="0">全部分类</option>${state.categories.map(c => `<option value="${c.id}" ${Number(state.categoryId) === Number(c.id) ? 'selected' : ''}>${esc(c.name)}</option>`).join('')}</select>${page === 'home' ? '' : shortcuts}</div>${page === 'home' ? `<div class="toolbar">${btn('热销榜','rank-stores')} ${btn('热销菜品','rank-goods')} ${btn('特价专区','specials')} ${btn('限时秒杀','seckills')} ${state.user ? btn('优惠券','go','perks') : ''}</div>` : ''}<div class="grid" id="storeGrid">${renderStoreCards(state.stores)}</div><div class="section" id="browseResult"></div>`;
    $('categoryFilter').onchange = async (e) => { state.categoryId = Number(e.target.value); if (state.categoryId) state.stores = await get(`/api/stores?categoryId=${state.categoryId}`); else state.stores = await get('/api/stores'); $('storeGrid').innerHTML = renderStoreCards(state.stores); bindStoreButtons(); };
    bindStoreButtons();
  };
  const renderStoreCards = (stores) => (stores || []).map(s => `<article class="store-card"><div class="store-image">${storeImage(s)}</div><div class="store-body"><h3>${esc(s.name)}</h3><div class="subtle">★ ${Number(s.rating || 0).toFixed(1)} · 月售 ${Number(s.monthlySales || 0)} · ${esc(s.deliveryTime || '配送信息待更新')}</div><div class="tag-list">${(s.tags || []).slice(0,3).map(t=>`<span class="tag">${esc(t)}</span>`).join('')}</div><div class="row-between"><span class="subtle">起送 ¥${cash(s.minOrder)} · 配送 ¥${cash(s.deliveryFee)}</span><button class="btn small primary" data-action="open-store" data-id="${s.id}">进店</button></div></div></article>`).join('') || empty('暂时没有符合条件的店铺');
  const bindStoreButtons = () => document.querySelectorAll('[data-action="open-store"]').forEach(b => b.onclick = async () => { state.storeId = Number(b.dataset.id); await navigate('store'); });
  const renderStore = async () => {
    if (!state.storeId) { state.page = 'home'; return renderBrowse('home'); }
    const [store, goods, categories, reviews] = await Promise.all([get(`/api/stores/${state.storeId}`), get(`/api/stores/${state.storeId}/goods`), get(`/api/stores/${state.storeId}/categories`), get(`/api/stores/${state.storeId}/reviews`)]);
    state.goods = goods || [];
    $('app').innerHTML = `${pageHead(store.name, store.notice || store.address || '', `${btn('返回首页','go','home')} ${state.user ? btn('收藏店铺','favorite',store.id) : ''}`)}<div class="grid four"><div class="metric"><div class="metric-label">评分</div><div class="metric-value">★ ${Number(store.rating || 0).toFixed(1)}</div></div><div class="metric"><div class="metric-label">月售</div><div class="metric-value">${Number(store.monthlySales || 0)}</div></div><div class="metric"><div class="metric-label">配送费</div><div class="metric-value">¥${cash(store.deliveryFee)}</div></div><div class="metric"><div class="metric-label">起送价</div><div class="metric-value">¥${cash(store.minOrder)}</div></div></div><div class="section">${categories?.length ? `<div class="toolbar">${categories.map(c=>`<span class="tag">${esc(c.name)}</span>`).join('')}</div>`:''}<div class="page-panel">${state.goods.map(g=>`<div class="food-row"><div class="food-image">${g.image?`<img src="${esc(g.image)}" alt="">`:'食'}</div><div class="food-info"><h3>${esc(g.name)} ${g.special?'<span class="tag">特价</span>':''}</h3><p>${esc(g.description || g.tag || '今日推荐')} · 月售 ${g.sales || 0} · 库存 ${g.stock ?? '-'}</p><div class="price">¥${cash(g.price)} ${g.originalPrice>g.price?`<del class="subtle">¥${cash(g.originalPrice)}</del>`:''}</div></div><div class="food-actions">${(g.specs||[]).length?`<select class="select" data-spec-for="${g.id}" style="max-width:150px">${g.specs.map(s=>`<option value="${s.id}">${esc(s.name)} ¥${cash(s.price)}</option>`).join('')}</select>`:''}<button class="btn primary small" data-action="add-cart" data-id="${g.id}">加入购物车</button></div></div>`).join('') || empty('暂时没有上架商品')}</div></div><section class="section"><h2 class="section-title">顾客评价 (${reviews.length})</h2><div class="grid two">${reviews.slice(0,20).map(r=>`<div class="surface"><div class="row-between"><strong>${esc(r.userName || '顾客')}</strong><span class="rating">★ ${r.rating}</span></div><p>${esc(r.content || '')}</p><div class="subtle">${esc(r.createTime || '')}</div>${r.reply?`<div class="notice-line" style="margin-top:8px">商家回复：${esc(r.reply)}</div>`:''}</div>`).join('') || empty('暂无评价')}</div></section>`;
  };
  const renderCart = async () => {
    state.cart = await get('/api/cart') || [];
    const groups = Object.groupBy ? Object.groupBy(state.cart, x=>x.storeId) : state.cart.reduce((a,x)=>((a[x.storeId] ||= []).push(x),a),{});
    const total = state.cart.reduce((s,x)=>s+Number(x.price||0)*x.quantity,0);
    $('app').innerHTML = `${pageHead('购物车','服务端保存，手机端登录后可继续使用')}${state.cart.length ? Object.values(groups).map(items=>`<section class="page-panel section"><div class="row-between"><h2 class="section-title">${esc(items[0].storeName)}</h2><span class="subtle">同一店铺商品一次结算</span></div>${items.map(x=>`<div class="cart-row"><div class="row-main"><strong>${esc(x.goods?.name || '商品')}</strong><small>${esc(x.specName||'')} · ¥${cash(x.price)}</small></div><div class="stepper"><button class="btn small" data-action="cart-dec" data-id="${x.goodsId}" data-spec="${x.specId||0}">−</button><b>${x.quantity}</b><button class="btn small" data-action="cart-inc" data-id="${x.goodsId}" data-spec="${x.specId||0}">+</button></div></div>`).join('')}<div class="form-actions">${btn('清空本店','cart-clear',items[0].storeId,'danger')} ${btn('去结算','checkout',items[0].storeId,'primary')}</div></section>`).join('') : empty('购物车为空，请先选择店铺和商品')}<div class="panel-foot"><strong>全部商品合计 ¥${cash(total)}</strong></div>`;
  };
  const renderCheckout = async () => {
    if (!state.cart.length) state.cart = await get('/api/cart') || [];
    state.addresses = await get('/api/addresses') || []; state.coupons = await get('/api/coupons') || [];
    const storeId = Number(state.cart[0]?.storeId || 0); const items = state.cart.filter(x=>Number(x.storeId)===storeId);
    if (!items.length) { $('app').innerHTML = `${pageHead('确认订单')} ${empty('购物车中没有商品')}`; return; }
    const available = state.coupons.filter(c=>c.status===0 && (!c.storeId || c.storeId===0 || Number(c.storeId)===storeId));
    $('app').innerHTML = `${pageHead('确认订单',`店铺：${items[0].storeName}`,btn('返回购物车','go','cart'))}<div class="grid two"><section class="page-panel"><h2 class="section-title">收货方式</h2><div class="toolbar"><label><input type="radio" name="deliveryType" value="DELIVERY" checked> 外卖配送</label><label><input type="radio" name="deliveryType" value="PICKUP"> 到店自取</label></div><h2 class="section-title">收货地址</h2>${state.addresses.map(a=>`<label class="address-option ${a.isDefault?'selected':''}" style="display:block;margin:8px 0"><input type="radio" name="addressId" value="${a.id}" ${a.isDefault?'checked':''}> <strong>${esc(a.name)} ${esc(a.phone)}</strong><div class="subtle" style="margin-left:23px">${esc(a.detail)}</div></label>`).join('') || empty('请在“地址与钱包”添加收货地址')}<button class="btn small" data-action="go" data-id="account">管理地址</button></section><section class="page-panel"><h2 class="section-title">商品清单</h2>${items.map(x=>`<div class="row-between" style="padding:8px 0"><span>${esc(x.goods?.name)} ${x.specName?`· ${esc(x.specName)}`:''} × ${x.quantity}</span><strong>¥${cash(Number(x.price)*x.quantity)}</strong></div>`).join('')}<div class="muted-sep"></div><label class="field">优惠券<select class="select" id="checkoutCoupon"><option value="0">不使用</option>${available.map(c=>`<option value="${c.id}">${esc(c.name)} · 满${cash(c.threshold)}减${cash(c.amount)}</option>`).join('')}</select></label><label class="field" style="margin-top:12px">订单备注<textarea class="textarea" id="checkoutRemark" placeholder="口味偏好、配送说明"></textarea></label><div class="form-actions"><button class="btn primary" data-action="place-order" data-store="${storeId}">提交待付款订单</button></div></section></div>`;
  };
  const orderCard = (o, role = 'user') => {
    const actions = [];
    if (role === 'user') {
      if (o.status === 0) { actions.push(btn('余额支付','pay',o.id,'primary'),btn('支付宝沙箱','alipay-pay',o.id),o.paymentChannel==='ALIPAY'&&o.outTradeNo?btn('查询支付','alipay-query',o.id):'',btn('取消','cancel-order',o.id)); }
      if (o.status === 4 && o.escrowStatus === 0) actions.push(btn('确认收货','confirm-order',o.id,'primary'),btn('申请退款','refund',o.id));
      if (o.status === 4 && !o.reviewed) actions.push(btn('评价','review',o.id));
    }
    if (role === 'merchant') {
      if (o.status === 1) actions.push(btn('接单','merchant-flow',`${o.id}:accept`,'primary'));
      if (o.status === 2 && !o.readyTime) actions.push(btn('出餐完成','merchant-flow',`${o.id}:ready`,'primary'));
    }
    if (role === 'admin' && o.status === 4 && o.escrowStatus === 0) actions.push(btn('平台退款','admin-refund-order',o.id,'danger'));
    if (role === 'rider') {
      if (o.status === 2 && o.riderId) actions.push(btn('确认取餐','rider-pickup',o.id,'primary'));
      if (o.status === 3) actions.push(btn('送达','rider-deliver',o.id,'primary'));
    }
    return `<article class="order-card"><div class="row-between"><div><strong>${esc(o.storeName || `订单 ${o.id}`)}</strong><div class="subtle">${esc(o.orderNo || o.id)} · ${esc(o.createTime || '')}</div></div>${statusTag(orderStatus(o),o.status===0?'warn':o.status===5?'bad':o.status===4?'good':'')}</div><div class="order-items">${(o.items||[]).map(i=>`${esc(i.goodsName || i.name)}${i.specName?` · ${esc(i.specName)}`:''} ×${i.quantity}`).join('、')}<div class="row-between" style="margin-top:8px"><span>${esc(o.address?.detail || (o.deliveryType==='PICKUP'?'到店自取':''))}</span><strong>实付 ¥${cash(o.payAmount)}</strong></div>${o.riderName?`<div>骑手：${esc(o.riderName)} ${esc(o.riderPhone||'')}</div>`:''}</div>${actions.length?`<div class="td-actions">${actions.join('')}</div>`:''}</article>`;
  };
  const renderOrders = async () => { state.orders = await get('/api/orders') || []; $('app').innerHTML = `${pageHead('我的订单','订单由手机端和网页端共享')}<div class="toolbar"><button class="btn" data-action="refresh">刷新订单</button><select id="orderFilter" class="select" style="max-width:200px"><option value="">全部状态</option>${STATUS.map((s,i)=>`<option value="${i}">${s}</option>`).join('')}</select></div><div id="orderList">${state.orders.map(o=>orderCard(o)).join('') || empty('暂无订单')}</div>`; $('orderFilter').onchange=()=>{ const v=$('orderFilter').value; $('orderList').innerHTML=state.orders.filter(o=>v===''||o.status===Number(v)).map(o=>orderCard(o)).join('')||empty('没有匹配订单'); }; };
  const renderPerks = async () => {
    const [favs, coupons, activities] = await Promise.all([get('/api/favorites'),get('/api/coupons'),get('/api/coupons/activities')]); state.favorites=favs||[];state.coupons=coupons||[];
    $('app').innerHTML=`${pageHead('收藏与优惠券')}<div class="grid two"><section><h2 class="section-title">我的收藏</h2>${state.favorites.map(s=>`<article class="item-card row-between"><div><strong>${esc(s.name)}</strong><div class="subtle">★ ${Number(s.rating||0).toFixed(1)} · 月售 ${s.monthlySales||0}</div></div><div class="td-actions"><button class="btn small" data-action="open-store" data-id="${s.id}">进店</button><button class="btn small danger" data-action="favorite" data-id="${s.id}">取消收藏</button></div></article>`).join('')||empty('暂无收藏')}</section><section><h2 class="section-title">我的优惠券</h2>${state.coupons.map(c=>`<article class="item-card row-between"><div><strong>${esc(c.name)}</strong><div class="subtle">满 ¥${cash(c.threshold)} 减 ¥${cash(c.amount)} · ${esc(c.expireTime||'')}</div></div>${statusTag(c.status===0?'可使用':c.status===1?'已使用':'已失效',c.status===0?'good':'')}</article>`).join('')||empty('暂无优惠券')}<h2 class="section-title section">领券中心</h2>${(activities||[]).map(c=>`<article class="item-card row-between"><div><strong>${esc(c.name)}</strong><div class="subtle">满 ¥${cash(c.threshold)} 减 ¥${cash(c.amount)}</div></div><button class="btn small primary" data-action="claim-coupon" data-threshold="${c.threshold}" data-amount="${c.amount}">领取</button></article>`).join('')||empty('暂无可领优惠券')}</section></div>`;
  };
  const renderAccount = async () => {
    const [addresses,cards,user] = await Promise.all([get('/api/addresses'),get('/api/wallet/bank-cards'),get('/api/auth/me')]); state.addresses=addresses||[];state.user=user||state.user;
    $('app').innerHTML=`${pageHead('地址与钱包','余额以服务端账户数据为准',btn('刷新','refresh'))}<div class="grid two"><section><div class="row-between"><h2 class="section-title">收货地址</h2>${btn('新增地址','address-new')}</div>${state.editAddress!==null?addressForm(state.editAddress):''}${state.addresses.map(a=>`<article class="item-card"><div class="row-between"><strong>${esc(a.name)} · ${esc(a.phone)} ${a.isDefault?'<span class="tag">默认</span>':''}</strong><div class="td-actions">${!a.isDefault?btn('设为默认','address-default',a.id,'small'):''}${btn('编辑','address-edit',a.id,'small')}${btn('删除','address-delete',a.id,'small danger')}</div></div><div class="subtle" style="margin-top:6px">${esc(a.detail)}</div></article>`).join('')||empty('暂无地址')}</section><section><h2 class="section-title">账户余额</h2><div class="metric"><div class="metric-label">可用余额</div><div class="metric-value">¥${cash(user?.balance)}</div><div class="subtle">余额支付由服务端事务扣款</div></div><form data-form="recharge" class="inline-form"><div class="form-grid"><label class="field">演示充值金额<input class="input" name="amount" type="number" min="1" max="500" step="1" value="20" required></label></div><div class="form-actions"><button class="btn primary">充值</button></div></form><div class="row-between section"><h2 class="section-title">银行卡</h2>${btn('绑定银行卡','bank-add')}</div>${(cards||[]).map(c=>`<article class="item-card row-between"><div><strong>${esc(c.bankName)}</strong><div class="subtle">${esc(c.cardType)} · ${esc(c.cardNoMasked)}</div></div><div class="td-actions">${btn('查看卡号','bank-reveal',c.id,'small')}${btn('解绑','bank-delete',c.id,'small danger')}</div></article>`).join('')||empty('暂无绑定银行卡')}<p class="help-text">银行卡完整号码仅在添加时提交，服务端只返回掩码号码。</p></section></div>`;
  };
  const renderSettings = async () => { const user=await get('/api/auth/me');state.user=user; $('app').innerHTML=`${pageHead('个人设置')}<div class="grid two"><section class="page-panel"><h2 class="section-title">个人资料</h2><form data-form="profile" class="field-stack"><label class="field">用户名<input class="input" name="username" required value="${esc(user.username)}"></label><label class="field">手机号<input class="input" name="phone" required value="${esc(user.phone)}"></label><label class="field">邮箱<input class="input" name="email" type="email" value="${esc(user.email||'')}"></label><label class="field">当前密码验证<input class="input" name="currentPassword" type="password"></label><button class="btn primary">保存资料</button></form></section><section class="page-panel"><h2 class="section-title">账号安全</h2><form data-form="password" class="field-stack"><label class="field">当前密码<input class="input" name="oldPassword" type="password" required></label><label class="field">新密码<input class="input" name="newPassword" type="password" minlength="8" required></label><button class="btn primary">修改密码</button></form><div class="muted-sep"></div><form data-form="payment-password" class="field-stack"><label class="field">登录密码<input class="input" name="loginPassword" type="password" required></label><label class="field">支付密码（6 位数字）<input class="input" name="paymentPassword" type="password" inputmode="numeric" pattern="[0-9]{6}" required></label><button class="btn">设置支付密码</button></form><div class="muted-sep"></div><h2 class="section-title">隐私与协议</h2><details><summary>隐私政策</summary><p class="subtle">本演示应用将账号、地址、订单和购物车保存在项目服务端。仅用于体验，不要输入真实支付信息。</p></details></section></div>`; };
  const renderAssistant = () => { $('app').innerHTML=`${pageHead('智能客服','回答内容由现有服务端助手生成')}<div class="page-panel"><div id="chatHistory" class="field-stack" style="min-height:220px;max-height:55vh;overflow:auto">${state.assistantHistory.map(m=>`<div class="surface"><strong>${m.role==='user'?'我':'客服'}</strong><div>${esc(m.content)}</div></div>`).join('')||empty('你好，有什么可以帮你？')}</div><form data-form="assistant" class="form-grid section"><label class="field full">输入问题<textarea class="textarea" name="question" required placeholder="例如：我的订单什么时候送达？"></textarea></label><div class="form-actions full"><button class="btn primary">发送</button></div></form></div>`; };
  const loadMerchantStores = async () => { state.merchantStores = await get('/api/merchant/stores') || []; if (!state.activeStoreId && state.merchantStores.length) state.activeStoreId = state.merchantStores[0].id; };
  const merchantStoreSelect = () => `<select class="select" id="merchantStoreSelect">${state.merchantStores.map(s=>`<option value="${s.id}" ${Number(s.id)===Number(state.activeStoreId)?'selected':''}>${esc(s.name)}</option>`).join('')}</select>`;
  const renderMerchant = async (page) => {
    await loadMerchantStores();
    if (page === 'overview') {
      const stats = await get(`/api/merchant/stats?storeId=${state.activeStoreId || 0}`);
      $('app').innerHTML=`${pageHead('经营概况','门店营业和结算统计',state.merchantStores.length?merchantStoreSelect():'')}${!state.merchantStores.length?empty('账号尚未关联门店'):`<div class="grid four"><div class="metric"><div class="metric-label">今日订单</div><div class="metric-value">${stats.todayOrderCount ?? stats.todayCount ?? 0}</div></div><div class="metric"><div class="metric-label">今日收入</div><div class="metric-value">¥${cash(stats.todayIncome)}</div></div><div class="metric"><div class="metric-label">本月订单</div><div class="metric-value">${stats.monthOrderCount ?? stats.monthCount ?? 0}</div></div><div class="metric"><div class="metric-label">累计收入</div><div class="metric-value">¥${cash(stats.totalIncome)}</div></div></div><div class="grid two section"><div class="page-panel"><h2 class="section-title">今日订单状态</h2>${(stats.todayStatus||[]).map((n,i)=>`<div class="row-between" style="padding:8px 0"><span>${['待接单','制作中','配送中','已完成','已取消'][i]||`状态${i}`}</span><strong>${n}</strong></div>`).join('')}</div><div class="page-panel"><h2 class="section-title">经营入口</h2><div class="toolbar">${btn('处理新订单','go','merchant-orders','primary')} ${btn('管理商品','go','catalog')} ${btn('查看评价','go','reviews')}</div></div></div>`}`;
      $('merchantStoreSelect')?.addEventListener('change',e=>{state.activeStoreId=Number(e.target.value);renderPage();}); return;
    }
    if (page === 'merchant-orders') {
      const orders = await get('/api/merchant/orders') || [];
      $('app').innerHTML=`${pageHead('订单处理','接单并标记出餐后，订单进入骑手待取餐池')}${orders.map(o=>orderCard(o,'merchant')).join('')||empty('暂无待处理订单')}`; return;
    }
    if (page === 'catalog') {
      if (!state.merchantStores.length) { $('app').innerHTML=`${pageHead('门店与商品')}<div class="page-panel"><h2 class="section-title">创建门店</h2>${merchantStoreForm()}</div>`; return; }
      const [goods,cats] = await Promise.all([get(`/api/merchant/stores/${state.activeStoreId}/goods`),get('/api/merchant/categories')]); state.merchantGoods=goods||[];
      const editingStore = state.merchantStoreEdit || null;
      $('app').innerHTML=`${pageHead('门店与商品','管理商品上下架、库存、规格和店内分类',`${merchantStoreSelect()} ${btn('新增门店','merchant-store-new')}`)}${state.editGoods==='store'||editingStore?`<div class="page-panel section"><h2 class="section-title">${editingStore?'编辑门店':'创建门店'}</h2>${merchantStoreForm(editingStore)}</div>`:''}<div class="toolbar">${btn('新增商品','merchant-goods-new','', 'primary')} ${btn('店内分类','merchant-categories')} ${btn('套餐管理','merchant-setmeals')} ${btn('门店员工','merchant-employees')} ${btn('编辑门店','merchant-store-edit',state.activeStoreId)}</div>${state.editGoods&&state.editGoods!=='store'?merchantGoodsForm(state.editGoods,cats||[]):''}<div class="table-wrap"><table><thead><tr><th>商品</th><th>分类</th><th>售价</th><th>库存</th><th>销量</th><th>状态</th><th>操作</th></tr></thead><tbody>${state.merchantGoods.map(g=>`<tr><td><strong>${esc(g.name)}</strong><div class="subtle">${esc(g.description||'')}</div></td><td>${esc((cats||[]).find(c=>c.id===g.merchantCategoryId)?.name||'未分组')}</td><td>¥${cash(g.price)}</td><td>${g.stock}</td><td>${g.sales}</td><td>${statusTag(g.status===1?'上架':'下架',g.status===1?'good':'warn')}</td><td><div class="td-actions">${btn('编辑','merchant-goods-edit',g.id,'small')}${btn('规格','merchant-goods-specs',g.id,'small')}${btn(g.status===1?'下架':'上架','merchant-goods-toggle',g.id,'small')}${btn('删除','merchant-goods-delete',g.id,'small danger')}</div></td></tr>`).join('')||'<tr><td colspan="7">暂无商品</td></tr>'}</tbody></table></div>`;
      $('merchantStoreSelect')?.addEventListener('change',e=>{state.activeStoreId=Number(e.target.value);state.editGoods=null;renderPage();}); return;
    }
    if (page === 'reviews') {
      state.merchantReviews=await get('/api/merchant/reviews')||[];
      $('app').innerHTML=`${pageHead('评价回复','公开评价只通过商户回复接口提交')}${state.merchantReviews.map(r=>`<article class="item-card"><div class="row-between"><strong>${esc(r.userName||'用户')} · ${esc(r.storeName||'门店')}</strong><span class="rating">★ ${r.rating}</span></div><p>${esc(r.content)}</p><div class="subtle">${esc(r.createTime||'')} ${r.anonymous?'· 匿名':''}</div>${r.reply?`<div class="notice-line" style="margin:10px 0">当前回复：${esc(r.reply)}</div>`:''}<form data-form="merchant-reply" data-id="${r.id}" class="toolbar" style="margin-top:10px"><input class="input" name="reply" required placeholder="填写商家回复" value="${esc(r.reply||'')}"><button class="btn primary small">${r.reply?'更新回复':'回复'}</button></form></article>`).join('')||empty('暂无待回复评价')}`; return;
    }
    if (page === 'marketing') {
      if (!state.merchantStores.length) { $('app').innerHTML=`${pageHead('营销活动')}${empty('先创建门店')}`; return; }
      const [activities,seckills]=await Promise.all([get(`/api/merchant/activities?storeId=${state.activeStoreId}`),get(`/api/merchant/seckills?storeId=${state.activeStoreId}`)]);
      state.merchantActivities=activities||[];state.merchantSeckills=seckills||[];
      $('app').innerHTML=`${pageHead('营销活动','创建折扣/满减活动与限时秒杀',merchantStoreSelect())}<div class="grid two"><section><div class="row-between"><h2 class="section-title">优惠活动</h2>${btn('新增活动','merchant-activity-new','','small primary')}</div>${state.editGoods==='activity'?activityForm():''}${state.merchantActivities.map(a=>`<article class="item-card"><div class="row-between"><strong>${esc(a.title)}</strong>${statusTag(a.status?'进行中':'已暂停',a.status?'good':'warn')}</div><div class="subtle">${esc(a.type)} · ${esc(a.startTime)} 至 ${esc(a.endTime)}</div><div class="td-actions" style="margin-top:8px">${btn(a.status?'暂停':'启用','merchant-activity-status',a.id,'small')}${btn('删除','merchant-activity-delete',a.id,'small danger')}</div></article>`).join('')||empty('暂无活动')}</section><section><div class="row-between"><h2 class="section-title">限时秒杀</h2>${btn('新增秒杀','merchant-seckill-new','','small primary')}</div>${state.editGoods==='seckill'?seckillForm():''}${state.merchantSeckills.map(s=>`<article class="item-card"><strong>商品 #${s.goodsId} · ¥${cash(s.price)}</strong><div class="subtle">名额 ${s.sold}/${s.quota} · ${esc(s.startTime)} 至 ${esc(s.endTime)}</div><div class="td-actions" style="margin-top:8px">${btn(s.status?'暂停':'启用','merchant-seckill-status',s.id,'small')}${btn('删除','merchant-seckill-delete',s.id,'small danger')}</div></article>`).join('')||empty('暂无秒杀')}</section></div>`;
      $('merchantStoreSelect')?.addEventListener('change',e=>{state.activeStoreId=Number(e.target.value);state.editGoods=null;renderPage();}); return;
    }
  };
  const merchantStoreForm = (store = null) => `<form data-form="merchant-store" data-id="${store?.id||0}" class="form-grid"><label class="field">店铺名称<input class="input" name="name" required value="${esc(store?.name||'')}"></label><label class="field">平台分类 ID<input class="input" name="categoryId" type="number" required value="${store?.categoryId||1}"></label><label class="field">配送费<input class="input" name="deliveryFee" type="number" step="0.1" value="${store?.deliveryFee||0}"></label><label class="field">起送价<input class="input" name="minOrder" type="number" step="1" value="${store?.minOrder||0}"></label><label class="field">预计配送时间<input class="input" name="deliveryTime" value="${esc(store?.deliveryTime||'30分钟')}" required></label><label class="field">配送半径（米）<input class="input" name="deliveryRadius" type="number" value="${store?.deliveryRadius||25000}"></label><label class="field full">地址<input class="input" name="address" value="${esc(store?.address||'')}" required></label><label class="field">纬度<input class="input" name="latitude" type="number" step="any" value="${store?.latitude||0}"></label><label class="field">经度<input class="input" name="longitude" type="number" step="any" value="${store?.longitude||0}"></label><label class="field full">公告<input class="input" name="notice" value="${esc(store?.notice||'欢迎光临')}"></label><label class="field full">图片 URL<input class="input" name="image" value="${esc(store?.image||'')}" placeholder="/uploads/... 或完整 URL"></label><div class="form-actions full"><button class="btn primary">保存门店</button></div></form>`;
  const merchantGoodsForm = (g = null, cats = []) => `<form data-form="merchant-goods" data-id="${g?.id||0}" class="inline-form"><div class="form-grid"><label class="field">商品名称<input class="input" name="name" required value="${esc(g?.name||'')}"></label><label class="field">价格<input class="input" name="price" type="number" step="0.01" required value="${g?.price||0}"></label><label class="field">原价<input class="input" name="originalPrice" type="number" step="0.01" value="${g?.originalPrice||g?.price||0}"></label><label class="field">库存<input class="input" name="stock" type="number" value="${g?.stock||0}"></label><label class="field">平台分类 ID<input class="input" name="categoryId" type="number" value="${g?.categoryId||1}"></label><label class="field">店内分类<select class="select" name="merchantCategoryId"><option value="0">未分组</option>${cats.map(c=>`<option value="${c.id}" ${Number(g?.merchantCategoryId)===Number(c.id)?'selected':''}>${esc(c.name)}</option>`).join('')}</select></label><label class="field">标签<input class="input" name="tag" value="${esc(g?.tag||'')}"></label><label class="field">图片 URL<input class="input" name="image" value="${esc(g?.image||'')}"></label><label class="field full">描述<input class="input" name="description" value="${esc(g?.description||'')}"></label><label><input type="checkbox" name="special" ${g?.special?'checked':''}> 特价商品</label><div class="form-actions full"><button class="btn primary">${g?'保存商品':'创建商品'}</button><button class="btn" type="button" data-action="merchant-goods-form-close">取消</button></div></div></form>`;
  const activityForm = () => `<form data-form="merchant-activity" class="inline-form"><div class="form-grid"><label class="field">活动类型<select class="select" name="type"><option value="DISCOUNT">折扣</option><option value="NEW_USER">新客立减</option><option value="GIFT">满赠</option></select></label><label class="field">标题<input class="input" name="title" required></label><label class="field">折扣率<input class="input" name="discountRate" type="number" step="0.01" value="0.9"></label><label class="field">立减金额<input class="input" name="reduceAmount" type="number" step="0.01" value="0"></label><label class="field">满赠门槛<input class="input" name="threshold" type="number" value="0"></label><label class="field">赠品商品 ID<input class="input" name="giftGoodsId" type="number" value="0"></label><label class="field">开始时间<input class="input" name="startTime" placeholder="2026-10-19 18:00:00" required></label><label class="field">结束时间<input class="input" name="endTime" placeholder="2026-10-20 18:00:00" required></label><div class="form-actions full"><button class="btn primary">创建活动</button><button class="btn" type="button" data-action="merchant-goods-form-close">取消</button></div></div></form>`;
  const seckillForm = () => `<form data-form="merchant-seckill" class="inline-form"><div class="form-grid"><label class="field">商品 ID<input class="input" name="goodsId" type="number" required></label><label class="field">秒杀价<input class="input" name="price" type="number" step="0.01" required></label><label class="field">活动名额<input class="input" name="quota" type="number" required></label><label class="field">开始时间<input class="input" name="startTime" placeholder="2026-10-19 18:00:00" required></label><label class="field">结束时间<input class="input" name="endTime" placeholder="2026-10-20 18:00:00" required></label><div class="form-actions full"><button class="btn primary">创建秒杀</button><button class="btn" type="button" data-action="merchant-goods-form-close">取消</button></div></div></form>`;
  const renderRider = async (page) => {
    if (page === 'rider-profile') {
      state.rider = await get('/api/rider/profile'); const r=state.rider;
      $('app').innerHTML=`${pageHead('骑手资料','在线状态将影响是否可以抢单')}${!r?empty('暂时无法读取骑手资料'):`<div class="grid four"><div class="metric"><div class="metric-label">配送状态</div><div class="metric-value">${r.online?'在线':'离线'}</div><button class="btn ${r.online?'danger':'primary'}" style="margin-top:10px" data-action="rider-online" data-id="${r.online?0:1}">${r.online?'下线':'上线'}</button></div><div class="metric"><div class="metric-label">已完成配送</div><div class="metric-value">${r.totalOrders||0}</div></div><div class="metric"><div class="metric-label">累计配送收入</div><div class="metric-value">¥${cash(r.totalIncome)}</div></div><div class="metric"><div class="metric-label">账号状态</div><div class="metric-value">${r.status===1?'正常':'停用'}</div></div></div><div class="page-panel section"><h2 class="section-title">接单范围</h2><form data-form="rider-settings" class="form-grid"><label class="field">配送半径（米）<input class="input" name="radiusMeters" type="number" min="1000" max="100000" value="${r.deliveryRadius||25000}"></label><label class="field">接单位置<input class="input" name="address" value="${esc(r.locationAddress||'')}"></label><label class="field">纬度<input class="input" name="latitude" type="number" step="any" value="${r.latitude||0}"></label><label class="field">经度<input class="input" name="longitude" type="number" step="any" value="${r.longitude||0}"></label><div class="form-actions full"><button class="btn primary">保存接单范围</button></div></form></div>`}`; return;
    }
    if (page === 'rider-pool') {
      const [profile,pool]=await Promise.all([get('/api/rider/profile'),get('/api/rider/orders/pool')]); state.rider=profile;
      $('app').innerHTML=`${pageHead('待抢订单',profile?.online?'只显示配送范围内可抢订单':'请先上线后查看可抢订单',btn('刷新','refresh'))}${!profile?.online?`<div class="notice-line">当前处于离线状态。${btn('立即上线','rider-online','1','primary')}</div>`:(pool||[]).map(o=>`<article class="order-card"><div class="row-between"><div><strong>${esc(o.storeName)}</strong><div class="subtle">${esc(o.address?.detail||'')} · ${esc(o.createTime||'')}</div></div><strong>配送费 ¥${cash(o.deliveryFee)}</strong></div><div class="order-items">${(o.items||[]).map(i=>`${esc(i.goodsName)} ×${i.quantity}`).join('、')}</div>${btn('抢单','rider-grab',o.id,'primary')}</article>`).join('')||empty('当前没有可抢订单')}`; return;
    }
    if (page === 'rider-orders') {
      state.riderOrders=await get('/api/rider/orders')||[];
      $('app').innerHTML=`${pageHead('配送订单','抢单、取餐和送达状态与用户订单即时共享',btn('刷新','refresh'))}${state.riderOrders.map(o=>orderCard(o,'rider')).join('')||empty('暂无配送订单')}`; return;
    }
  };
  const renderAdmin = async (page) => {
    if (page === 'overview') {
      const d=await get('/api/admin/dashboard'); const m=d?.statistics||d?.overview||d||{};
      $('app').innerHTML=`${pageHead('平台总览','平台运营数据来自服务端',btn('刷新','refresh'))}<div class="grid four">${[['用户',m.totalUsers],['商户',m.totalMerchants],['店铺',m.totalStores],['商品',m.totalGoods],['累计订单',m.totalOrders],['累计 GMV',`¥${cash(m.totalGmv)}`],['今日订单',m.todayOrders],['待结算托管',`¥${cash(m.pendingEscrowAmount)}`]].map(([l,v])=>`<div class="metric"><div class="metric-label">${l}</div><div class="metric-value">${v??'--'}</div></div>`).join('')}</div><div class="grid two section"><div class="page-panel"><h2 class="section-title">快捷管理</h2><div class="toolbar">${btn('店铺审核','go','stores')} ${btn('退款审批','go','refunds')} ${btn('全平台订单','go','admin-orders')}</div></div><div class="page-panel"><h2 class="section-title">热门商品</h2>${(m.hotGoods||[]).slice(0,6).map(g=>`<div class="row-between" style="padding:7px 0"><span>${esc(g.goodsName)} · ${esc(g.storeName)}</span><strong>销量 ${g.sales}</strong></div>`).join('')||empty('暂无统计')}</div></div>`; return;
    }
    if (page === 'categories') {
      state.adminCategories=await get('/api/admin/categories')||[];
      $('app').innerHTML=`${pageHead('分类管理','平台分类由服务端统一维护',btn('新增分类','admin-category-new','','primary'))}${state.editGoods==='category'?`<form class="inline-form" data-form="admin-category"><div class="form-grid"><label class="field">分类名称<input class="input" name="name" required></label><label class="field">图标<input class="input" name="icon" value="🍽️"></label><label class="field">颜色<input class="input" name="color" value="#C74B1B"></label><div class="form-actions"><button class="btn primary">保存</button></div></div></form>`:''}<div class="table-wrap"><table><thead><tr><th>ID</th><th>名称</th><th>图标</th><th>类型</th><th>操作</th></tr></thead><tbody>${state.adminCategories.map(c=>`<tr><td>${c.id}</td><td>${esc(c.name)}</td><td>${esc(c.icon||'')}</td><td>${esc(c.type||'平台')}</td><td>${btn('删除','admin-category-delete',c.id,'small danger')}</td></tr>`).join('')||'<tr><td colspan="5">暂无分类</td></tr>'}</tbody></table></div>`; return;
    }
    if (page === 'stores') {
      state.adminStores=await get('/api/admin/stores')||[];
      $('app').innerHTML=`${pageHead('店铺审核','控制店铺营业状态与首页推荐')}${table(['店铺','分类','评分 / 月售','状态','推荐','操作'],state.adminStores.map(s=>[`<strong>${esc(s.name)}</strong><div class="subtle">${esc(s.address||'')}</div>`,esc(s.categoryName||s.categoryId),`${s.rating} / ${s.monthlySales}`,statusTag(s.status?'营业中':'已下架',s.status?'good':'warn'),s.recommended?'是':'否',`${btn(s.status?'下架':'通过','admin-store-status',`${s.id}:${s.status?0:1}`,'small')} ${btn(s.recommended?'取消推荐':'设为推荐','admin-store-recommend',`${s.id}:${s.recommended?0:1}`,'small')}`]))}`; return;
    }
    if (page === 'admin-orders') {
      const data=await get('/api/admin/orders/page?page=1&pageSize=100');state.adminOrders=data?.list||[];
      $('app').innerHTML=`${pageHead('全平台订单','平台订单状态以服务端为准',btn('刷新','refresh'))}${state.adminOrders.map(o=>orderCard(o,'admin')).join('')||empty('暂无订单')}`;return;
    }
    if (page === 'refunds') {
      const data=await get('/api/admin/refunds/page?page=1&pageSize=100');state.adminRefunds=data?.list||[];
      $('app').innerHTML=`${pageHead('退款审批','退款状态和资金变化由服务端事务处理')}<div class="table-wrap"><table><thead><tr><th>退款单</th><th>订单</th><th>原因</th><th>金额</th><th>状态</th><th>时间</th><th>操作</th></tr></thead><tbody>${state.adminRefunds.map(r=>`<tr><td>${r.id}</td><td>${r.orderId}</td><td>${esc(r.reason||r.reasonType)}</td><td>¥${cash(r.amount)}</td><td>${esc(r.status)}</td><td>${esc(r.applyTime)}</td><td>${r.status==='PENDING'?`${btn('同意','refund-approve',r.id,'small primary')} ${btn('拒绝','refund-reject',r.id,'small danger')}`:'-'}</td></tr>`).join('')||'<tr><td colspan="7">暂无退款申请</td></tr>'}</tbody></table></div>`;return;
    }
    if (page === 'users') {
      const [users,products]=await Promise.all([get('/api/admin/users/page?page=1&pageSize=100'),get('/api/admin/products?page=1&pageSize=100')]);state.adminUsers=users?.list||[];state.adminProducts=products?.list||[];
      $('app').innerHTML=`${pageHead('用户与商品管理')}<div class="tabs"><button class="tab active" data-action="admin-subtab" data-id="users">用户</button><button class="tab" data-action="admin-subtab" data-id="products">商品</button></div><section id="adminSubtab" class="section">${adminUsersTable()}</section>`;return;
    }
    if (page === 'riders') {
      state.adminRiders=await get('/api/admin/riders')||[];
      $('app').innerHTML=`${pageHead('骑手管理','启停账号，骑手上线状态由骑手端自己维护')}<div class="table-wrap"><table><thead><tr><th>骑手</th><th>手机号</th><th>配送状态</th><th>累计单量</th><th>累计收入</th><th>账号</th><th>操作</th></tr></thead><tbody>${state.adminRiders.map(r=>`<tr><td>${esc(r.name)}</td><td>${esc(r.phone)}</td><td>${r.online?'在线':'离线'}</td><td>${r.totalOrders}</td><td>¥${cash(r.totalIncome)}</td><td>${r.status?'启用':'停用'}</td><td>${btn(r.status?'停用':'启用','admin-rider-status',`${r.id}:${r.status?0:1}`,'small')}</td></tr>`).join('')||'<tr><td colspan="7">暂无骑手</td></tr>'}</tbody></table></div>`;return;
    }
    if (page === 'content') {
      const [banners,ann]=await Promise.all([get('/api/admin/banners'),get('/api/admin/announcements')]);state.adminBanners=banners||[];state.adminAnnouncements=ann||[];
      $('app').innerHTML=`${pageHead('内容管理','管理首页轮播和公告')}<div class="grid two"><section><div class="row-between"><h2 class="section-title">轮播 Banner</h2>${btn('新增 Banner','admin-banner-new','','small primary')}</div>${state.editGoods==='banner'?bannerForm():''}${state.adminBanners.map(b=>`<article class="item-card row-between"><div><strong>${esc(b.title)}</strong><div class="subtle">${esc(b.subtitle||'')}</div></div><div class="td-actions">${btn(b.status?'下架':'发布','admin-banner-status',`${b.id}:${b.status?0:1}`,'small')}${btn('删除','admin-banner-delete',b.id,'small danger')}</div></article>`).join('')||empty('暂无 Banner')}</section><section><div class="row-between"><h2 class="section-title">公告</h2>${btn('新增公告','admin-announcement-new','','small primary')}</div>${state.editGoods==='announcement'?announcementForm():''}${state.adminAnnouncements.map(a=>`<article class="item-card"><div class="row-between"><strong>${esc(a.title)}</strong><div class="td-actions">${btn(a.status?'下架':'发布','admin-announcement-status',`${a.id}:${a.status?0:1}`,'small')}${btn('删除','admin-announcement-delete',a.id,'small danger')}</div></div><div class="subtle">${esc(a.content)}</div></article>`).join('')||empty('暂无公告')}</section></div>`;return;
    }
    if (page === 'employees') {
      state.adminEmployees=await get('/api/admin/employees')||[];
      $('app').innerHTML=`${pageHead('员工管理','平台员工账号与状态',btn('新增员工','admin-employee-new','','primary'))}${state.editGoods==='employee'?employeeForm():''}<div class="table-wrap"><table><thead><tr><th>员工</th><th>手机号</th><th>角色</th><th>店铺数</th><th>状态</th><th>操作</th></tr></thead><tbody>${state.adminEmployees.map(e=>`<tr><td>${esc(e.username)}</td><td>${esc(e.phone)}</td><td>${e.role}</td><td>${e.storeCount||0}</td><td>${e.status?'启用':'停用'}</td><td>${btn(e.status?'停用':'启用','admin-employee-status',`${e.id}:${e.status?0:1}`,'small')}</td></tr>`).join('')||'<tr><td colspan="6">暂无员工</td></tr>'}</tbody></table></div>`;return;
    }
    if (page === 'audit') {
      const data=await get('/api/admin/audit-logs?page=1&pageSize=100');const logs=data?.list||[];
      $('app').innerHTML=`${pageHead('操作日志','最近 100 条平台审计记录')}<div class="table-wrap"><table><thead><tr><th>时间</th><th>操作人</th><th>动作</th><th>对象</th><th>结果</th><th>来源</th></tr></thead><tbody>${logs.map(l=>`<tr><td>${esc(l.createTime||l.time)}</td><td>${esc(l.username||l.operatorName||'')}</td><td>${esc(l.action||l.operation||'')}</td><td>${esc(l.target||l.detail||'')}</td><td>${esc(l.result||'')}</td><td>${esc(l.ip||'')}</td></tr>`).join('')||'<tr><td colspan="6">暂无日志</td></tr>'}</tbody></table></div>`;return;
    }
    if (page === 'admin-marketing') {
      const [activities,seckills]=await Promise.all([get('/api/admin/marketing/activities'),get('/api/admin/marketing/seckills')]);state.adminActivities=activities||[];state.adminSeckills=seckills||[];
      $('app').innerHTML=`${pageHead('营销监管','查看、暂停或移除商户营销活动')}<div class="grid two"><section><h2 class="section-title">活动</h2>${state.adminActivities.map(a=>`<article class="item-card row-between"><div><strong>${esc(a.title)}</strong><div class="subtle">店铺 ${a.storeId} · ${esc(a.type)} · ${esc(a.startTime)} - ${esc(a.endTime)}</div></div><div class="td-actions">${btn(a.status?'暂停':'启用','admin-activity-status',`${a.id}:${a.status?0:1}`,'small')}${btn('删除','admin-activity-delete',a.id,'small danger')}</div></article>`).join('')||empty('暂无活动')}</section><section><h2 class="section-title">秒杀</h2>${state.adminSeckills.map(s=>`<article class="item-card row-between"><div><strong>商品 ${s.goodsId} · ¥${cash(s.price)}</strong><div class="subtle">店铺 ${s.storeId} · ${s.sold}/${s.quota}</div></div><div class="td-actions">${btn(s.status?'暂停':'启用','admin-seckill-status',`${s.id}:${s.status?0:1}`,'small')}${btn('删除','admin-seckill-delete',s.id,'small danger')}</div></article>`).join('')||empty('暂无秒杀')}</section></div>`;return;
    }
  };
  const adminUsersTable = () => `<div class="table-wrap"><table><thead><tr><th>用户</th><th>手机号</th><th>角色</th><th>余额</th><th>状态</th><th>注册时间</th><th>操作</th></tr></thead><tbody>${state.adminUsers.map(u=>`<tr><td>${esc(u.username)}</td><td>${esc(u.phone)}</td><td>${['用户','商户','管理员','骑手'][u.role]||u.role}</td><td>¥${cash(u.balance)}</td><td>${u.status?'启用':'停用'}</td><td>${esc(u.createTime||'')}</td><td>${btn(u.status?'停用':'启用','admin-user-status',`${u.id}:${u.status?0:1}`,'small')}</td></tr>`).join('')||'<tr><td colspan="7">暂无用户</td></tr>'}</tbody></table></div>`;
  const adminProductsTable = () => `<div class="table-wrap"><table><thead><tr><th>商品</th><th>店铺</th><th>价格</th><th>库存</th><th>销量</th><th>状态</th><th>操作</th></tr></thead><tbody>${state.adminProducts.map(p=>`<tr><td>${esc(p.name)}</td><td>${esc(p.storeName)}</td><td>¥${cash(p.price)}</td><td>${p.stock}</td><td>${p.sales}</td><td>${p.status?'上架':'下架'}</td><td>${btn(p.status?'下架':'上架','admin-product-status',`${p.id}:${p.status?0:1}`,'small')} ${btn('删除','admin-product-delete',p.id,'small danger')}</td></tr>`).join('')||'<tr><td colspan="7">暂无商品</td></tr>'}</tbody></table></div>`;
  const table = (headers, rows) => `<div class="table-wrap"><table><thead><tr>${headers.map(h=>`<th>${h}</th>`).join('')}</tr></thead><tbody>${rows.map(row=>`<tr>${row.map(c=>`<td>${c}</td>`).join('')}</tr>`).join('')||`<tr><td colspan="${headers.length}">暂无数据</td></tr>`}</tbody></table></div>`;
  const bannerForm = () => `<form data-form="admin-banner" class="inline-form"><div class="form-grid"><label class="field">标题<input class="input" name="title" required></label><label class="field">副标题<input class="input" name="subtitle"></label><label class="field">图片 URL<input class="input" name="image"></label><label class="field">主题色<input class="input" name="color" value="#C74B1B"></label><label class="field">链接类型<input class="input" name="linkType" value="NONE"></label><label class="field">链接值<input class="input" name="linkValue"></label><label class="field">排序<input class="input" name="sort" type="number" value="0"></label><div class="form-actions"><button class="btn primary">创建</button></div></div></form>`;
  const announcementForm = () => `<form data-form="admin-announcement" class="inline-form"><div class="form-grid"><label class="field">标题<input class="input" name="title" required></label><label class="field full">内容<textarea class="textarea" name="content" required></textarea></label><div class="form-actions full"><button class="btn primary">发布公告</button></div></div></form>`;
  const employeeForm = () => `<form data-form="admin-employee" class="inline-form"><div class="form-grid"><label class="field">用户名<input class="input" name="username" required></label><label class="field">手机号<input class="input" name="phone" required></label><label class="field">初始密码<input class="input" name="password" type="password" required minlength="8"></label><div class="form-actions"><button class="btn primary">创建员工</button></div></div></form>`;
  const addressForm = (a = null) => `<form data-form="address" data-id="${a?.id||0}" class="inline-form"><div class="form-grid">
    <div class="notice-line full" role="note">当前网页不支持自动获取位置，请手动搜索地点或输入完整收货地址。</div>
    <label class="field full">搜索收货地点<input class="input" name="locationKeyword" maxlength="80" placeholder="例如：北京市中关村广场"></label>
    <div class="full"><button class="btn" type="button" data-action="address-search">搜索地点</button></div>
    <div class="full" data-location-results aria-live="polite"></div>
    <label class="field">联系人<input class="input" name="name" required value="${esc(a?.name||'')}"></label><label class="field">手机号<input class="input" name="phone" required value="${esc(a?.phone||'')}"></label>
    <label class="field full">详细地址<input class="input" name="detail" required placeholder="省市区、街道、小区及楼栋门牌号" value="${esc(a?.detail||a?.address||'')}"><span class="help-text">可直接输入完整地址；选择搜索结果后，请补充楼栋和门牌号。</span></label>
    <label><input type="checkbox" name="isDefault" ${a?.isDefault?'checked':''}> 设为默认地址</label><div class="form-actions"><button class="btn primary">保存地址</button><button class="btn" type="button" data-action="address-form-close">取消</button></div></div></form>`;
  const bindForms = () => {
    document.querySelectorAll('#app form[data-form]').forEach(form => form.onsubmit = async (event) => {
      event.preventDefault(); const f = new FormData(form); const data = Object.fromEntries(f.entries()); const name=form.dataset.form;
      try {
        if (name === 'recharge') { state.user = await send('/api/auth/recharge','POST',{ amount:Number(data.amount) }); toast('充值成功'); await renderPage(); }
        else if (name === 'profile') { state.user=await send('/api/auth/me','PUT',{username:data.username,phone:data.phone,email:data.email||'',currentPassword:data.currentPassword||''}); toast('资料已保存'); renderShell(); await renderPage(); }
        else if (name === 'password') { await send('/api/auth/password','PUT',{oldPassword:data.oldPassword,newPassword:data.newPassword}); toast('密码已修改，请重新登录'); await logout(); }
        else if (name === 'payment-password') { await send('/api/auth/payment-password','POST',{loginPassword:data.loginPassword,paymentPassword:data.paymentPassword}); toast('支付密码已设置'); }
        else if (name === 'address') { const id=Number(form.dataset.id||0); const payload={name:data.name,phone:data.phone,detail:data.detail,isDefault:f.get('isDefault')?'1':'0'}; await send(id?`/api/addresses/${id}`:'/api/addresses',id?'PUT':'POST',payload); state.editAddress=null;toast('地址已保存');await renderPage(); }
        else if (name === 'merchant-store') { const p={name:data.name,categoryId:Number(data.categoryId),deliveryFee:Number(data.deliveryFee),minOrder:Number(data.minOrder),deliveryTime:data.deliveryTime,notice:data.notice,address:data.address,latitude:Number(data.latitude||0),longitude:Number(data.longitude||0),image:data.image||'',deliveryRadius:Number(data.deliveryRadius||0)}; const id=Number(form.dataset.id||0); await send(id?`/api/merchant/stores/${id}`:'/api/merchant/stores',id?'PUT':'POST',id?{...p,status:-1}:p); state.editGoods=null;state.merchantStoreEdit=null;toast('门店已保存');await renderPage(); }
        else if (name === 'merchant-goods') { const p={name:data.name,description:data.description||'',price:Number(data.price),originalPrice:Number(data.originalPrice||data.price),image:data.image||'',categoryId:Number(data.categoryId),merchantCategoryId:Number(data.merchantCategoryId||0),stock:Number(data.stock||0),tag:data.tag||'',special:f.get('special')===null?false:true,status:1}; const id=Number(form.dataset.id||0); await send(id?`/api/merchant/goods/${id}`:`/api/merchant/stores/${state.activeStoreId}/goods`,id?'PUT':'POST',p);state.editGoods=null;toast('商品已保存');await renderPage(); }
        else if (name === 'merchant-activity') { await send(`/api/merchant/activities?storeId=${state.activeStoreId}`,'POST',{type:data.type,title:data.title,discountRate:Number(data.discountRate||0),reduceAmount:Number(data.reduceAmount||0),threshold:Number(data.threshold||0),giftGoodsId:Number(data.giftGoodsId||0),startTime:data.startTime,endTime:data.endTime,status:1});state.editGoods=null;toast('活动已创建');await renderPage(); }
        else if (name === 'merchant-seckill') { await send(`/api/merchant/seckills?storeId=${state.activeStoreId}`,'POST',{goodsId:Number(data.goodsId),price:Number(data.price),quota:Number(data.quota),startTime:data.startTime,endTime:data.endTime,status:1});state.editGoods=null;toast('秒杀已创建');await renderPage(); }
        else if (name === 'merchant-reply') { await send(`/api/merchant/reviews/${form.dataset.id}`,'PUT',{reply:data.reply});toast('回复已保存');await renderPage(); }
        else if (name === 'rider-settings') { await send('/api/rider/range/radius','PUT',{radiusMeters:Number(data.radiusMeters)});await send('/api/rider/range/location','PUT',{latitude:Number(data.latitude||0),longitude:Number(data.longitude||0),address:data.address||''});toast('配送范围已保存');await renderPage(); }
        else if (name === 'admin-category') { await send('/api/admin/categories','POST',{name:data.name,icon:data.icon||'',color:data.color||''});state.editGoods=null;toast('分类已创建');await renderPage(); }
        else if (name === 'admin-banner') { await send('/api/admin/banners','POST',{title:data.title,subtitle:data.subtitle||'',image:data.image||'',color:data.color||'',linkType:data.linkType||'NONE',linkValue:data.linkValue||'',sort:Number(data.sort||0)});state.editGoods=null;toast('Banner 已创建');await renderPage(); }
        else if (name === 'admin-announcement') { await send('/api/admin/announcements','POST',{title:data.title,content:data.content});state.editGoods=null;toast('公告已创建');await renderPage(); }
        else if (name === 'admin-employee') { await send('/api/admin/employees','POST',{username:data.username,phone:data.phone,password:data.password});state.editGoods=null;toast('员工已创建');await renderPage(); }
        else if (name === 'assistant') { const question=data.question;state.assistantHistory.push({role:'user',content:question});const answer=await send('/api/assistant/chat','POST',{question,history:state.assistantHistory.map(x=>({role:x.role,content:x.content}))});state.assistantHistory.push({role:'assistant',content:answer?.answer||answer?.content||'暂时无法回答'});await renderPage(); }
      } catch(error) { toast(error.message,true); }
    });
  };
  const formData = (selector) => { const form=$(selector); return form ? Object.fromEntries(new FormData(form).entries()) : {}; };
  const handleAction = async (action, id, el) => {
    try {
      if (action === 'login') return openAuth();
      if (action === 'auth-switch') return openAuth(id);
      if (action === 'send-code') { const f=el.closest('form');const data=Object.fromEntries(new FormData(f).entries());const r=await send('/api/auth/email-code','POST',{phone:data.phone,email:data.email,purpose:'register',username:data.username});toast(r?.code||'验证码已发送');return; }
      if (action === 'go') return navigate(id);
      if (action === 'refresh') return renderPage();
      if (action === 'search') { state.search=$('storeSearch')?.value?.trim()||'';state.page='discover';return renderPage(); }
      if (action === 'open-store') { state.storeId=Number(id);return navigate('store'); }
      if (action === 'add-cart') { if(!requireUser())return;const spec=document.querySelector(`[data-spec-for="${id}"]`);await send('/api/cart/items','POST',{goodsId:Number(id),specId:Number(spec?.value||0),quantity:1});toast('已加入服务端购物车');return; }
      if (action === 'favorite') { await send(`/api/favorites/toggle?storeId=${id}`,'POST');toast('收藏状态已更新');return renderPage(); }
      if (action === 'cart-inc'||action === 'cart-dec') { const item=state.cart.find(x=>Number(x.goodsId)===Number(id)&&Number(x.specId||0)===Number(el.dataset.spec||0));if(!item)return;const q=item.quantity+(action==='cart-inc'?1:-1);if(q>0)await send(`/api/cart/items/${id}?specId=${el.dataset.spec||0}`,'PUT',{quantity:q});else await send(`/api/cart/items/${id}?specId=${el.dataset.spec||0}`,'DELETE');return renderPage(); }
      if (action === 'cart-clear') { for(const item of state.cart.filter(x=>Number(x.storeId)===Number(id))) await send(`/api/cart/items/${item.goodsId}?specId=${item.specId||0}`,'DELETE');return renderPage(); }
      if (action === 'checkout') { state.cart=await get('/api/cart')||[];return navigate('checkout'); }
      if (action === 'place-order') { const storeId=Number(el.dataset.store);const items=state.cart.filter(x=>Number(x.storeId)===storeId);const addressId=Number(document.querySelector('input[name="addressId"]:checked')?.value||0);if(!addressId){toast('请先添加并选择地址',true);return;}const couponId=Number($('checkoutCoupon')?.value||0);const order=await send('/api/orders','POST',{storeId,items:items.map(x=>({goodsId:x.goodsId,goodsName:x.goods.name,price:x.price,quantity:x.quantity,image:x.goods.image||'',specId:x.specId||0,specName:x.specName||''})),addressId,couponId,remark:$('checkoutRemark')?.value||'',checkoutGoodsIds:items.map(x=>x.goodsId),expectTime:'',idempotencyKey:`web-${Date.now()}-${Math.random().toString(16).slice(2)}`,setmeals:[],deliveryType:document.querySelector('input[name="deliveryType"]:checked')?.value||'DELIVERY'});toast(`订单 ${order.orderNo||order.id} 已创建`);return navigate('orders'); }
      if (action === 'pay') { await send(`/api/orders/${id}/pay?channel=BALANCE&mode=QR`,'POST');toast('余额支付成功');return renderPage(); }
      if (action === 'alipay-pay') { const result=await send(`/api/orders/${id}/pay?channel=ALIPAY&mode=QR`,'POST'); if(result?.paymentUrl){ window.prompt('请在支付宝沙箱中扫描或复制此支付链接，支付后回到订单点击刷新：',result.paymentUrl); } else { toast('支付宝沙箱预支付已创建，请刷新订单'); } return renderPage(); }
      if (action === 'alipay-query') { const result=await send(`/api/orders/${id}/payment/query`,'POST'); toast(result?.status===1?'支付宝支付已确认':'支付宝尚未完成支付'); return renderPage(); }
      if (action === 'cancel-order') { await send(`/api/orders/${id}/cancel`,'PUT');toast('订单已取消');return renderPage(); }
      if (action === 'confirm-order') { await send(`/api/orders/${id}/confirm`,'PUT');toast('已确认收货');return renderPage(); }
      if (action === 'refund') { const reason=window.prompt('请输入退款原因','商品/配送问题');if(reason)await send(`/api/orders/${id}/refund`,'POST',{reasonType:'OTHER',reason});toast('退款申请已提交');return renderPage(); }
      if (action === 'review') { const content=window.prompt('请输入评价内容','味道很好，配送很快');if(content)await send(`/api/orders/${id}/review`,'POST',{goodsId:state.orders.find(o=>Number(o.id)===Number(id))?.items?.[0]?.goodsId||0,rating:5,content,tags:['味道好'],images:[],anonymous:0});toast('评价已提交');return renderPage(); }
      if (action === 'address-new') { state.editAddress={};return renderPage(); }
      if (action === 'address-search') {
        const form = el.closest('form');
        const keyword = form.elements.locationKeyword.value.trim();
        const results = form.querySelector('[data-location-results]');
        if (!keyword) { results.textContent = '请输入城市、小区或街道名称，也可以直接填写下方详细地址。'; form.elements.locationKeyword.focus(); return; }
        el.disabled = true; results.textContent = '正在搜索地点…';
        try {
          const data = await get(`/api/location/search?keyword=${encodeURIComponent(keyword)}`);
          if (data?.status !== '1') throw new Error('地点搜索暂不可用，请直接输入完整收货地址。');
          const pois = Array.isArray(data.pois) ? data.pois : [];
          results.innerHTML = pois.map(p => {
            const address = [p.pname, p.cityname === p.pname ? '' : p.cityname, p.adname, p.address, p.name].filter(v => typeof v === 'string' && v).join('');
            return `<button class="btn" type="button" data-action="address-select" data-address="${esc(address)}" style="display:block;width:100%;text-align:left;margin-bottom:8px">${esc(address)}</button>`;
          }).join('') || '<p class="help-text">未找到地点，请补充城市名称重新搜索，或直接输入完整收货地址。</p>';
        } catch (_) { results.textContent = '地点搜索暂不可用，请直接输入完整收货地址。'; }
        finally { el.disabled = false; }
        return;
      }
      if (action === 'address-select') {
        const form = el.closest('form');
        form.elements.detail.value = el.dataset.address;
        form.querySelector('[data-location-results]').textContent = '已选择地点，请在详细地址中补充楼栋和门牌号。';
        form.elements.detail.focus(); return;
      }
      if (action === 'address-edit') { state.editAddress=state.addresses.find(a=>Number(a.id)===Number(id))||{};return renderPage(); }
      if (action === 'address-form-close') { state.editAddress=null;return renderPage(); }
      if (action === 'address-default') { await send(`/api/addresses/${id}/default`,'PUT');toast('默认地址已更新');return renderPage(); }
      if (action === 'address-delete') { await send(`/api/addresses/${id}`,'DELETE');toast('地址已删除');return renderPage(); }
      if (action === 'bank-add') { const bankName=window.prompt('银行名称','中国工商银行');const cardType=window.prompt('卡类型','储蓄卡');const fullCardNumber=window.prompt('完整卡号（仅本次提交）','');if(bankName&&cardType&&fullCardNumber)await send('/api/wallet/bank-cards','POST',{bankName,cardType,fullCardNumber});return renderPage(); }
      if (action === 'bank-reveal') { const paymentPassword=window.prompt('请输入支付密码以查看完整卡号','');if(paymentPassword){const result=await send(`/api/wallet/bank-cards/${id}/reveal`,'POST',{paymentPassword});if(result?.cardNumber)toast(`完整卡号：${result.cardNumber}`);else toast('支付密码校验失败',true);}return; }
      if (action === 'bank-delete') { await send(`/api/wallet/bank-cards/${id}`,'DELETE');return renderPage(); }
      if (action === 'claim-coupon') { await send('/api/coupons/claim','POST',{storeId:0,name:'网页领取券',threshold:Number(el.dataset.threshold),amount:Number(el.dataset.amount)});toast('优惠券已领取');return renderPage(); }
      if (action === 'rank-stores') { state.search='';state.page='discover';state.stores=await get('/api/rankings/stores?limit=20');return renderPage(); }
      if (action === 'rank-goods') { const goods=await get('/api/rankings/goods?limit=20');$('browseResult').innerHTML=`<h2 class="section-title">热销菜品</h2><div class="grid two">${goods.map(x=>`<article class="item-card row-between"><div><strong>${esc(x.goods.name)}</strong><div class="subtle">${esc(x.storeName)} · 月售 ${x.goods.sales||0}</div></div><span class="price">¥${cash(x.goods.price)}</span></article>`).join('')}</div>`;return; }
      if (action === 'specials') { const goods=await get('/api/goods/special?limit=20');$('browseResult').innerHTML=`<h2 class="section-title">特价专区</h2><div class="grid two">${goods.map(x=>`<article class="item-card row-between"><div><strong>${esc(x.goods.name)}</strong><div class="subtle">${esc(x.storeName)}</div></div><span class="price">¥${cash(x.goods.price)}</span></article>`).join('')}</div>`;return; }
      if (action === 'seckills') { const items=await get('/api/seckills?limit=20');$('browseResult').innerHTML=`<h2 class="section-title">限时秒杀</h2><div class="grid two">${items.map(x=>`<article class="item-card row-between"><div><strong>${esc(x.goodsName)}</strong><div class="subtle">${esc(x.storeName)} · 剩余 ${x.quota-x.sold}</div></div><span class="price">¥${cash(x.price)}</span></article>`).join('')}</div>`;return; }
      if (action === 'merchant-store-new') { state.editGoods='store';state.merchantStoreEdit=null;return renderPage(); }
      if (action === 'merchant-store-edit') { state.editGoods=null;state.merchantStoreEdit=state.merchantStores.find(s=>Number(s.id)===Number(id));return renderPage(); }
      if (action === 'merchant-goods-new') { state.editGoods={};return renderPage(); }
      if (action === 'merchant-goods-edit') { state.editGoods=state.merchantGoods.find(g=>Number(g.id)===Number(id))||{};return renderPage(); }
      if (action === 'merchant-goods-form-close') { state.editGoods=null;return renderPage(); }
      if (action === 'merchant-goods-toggle') {const g=state.merchantGoods.find(x=>Number(x.id)===Number(id));await send(`/api/merchant/goods/${id}`,'PUT',{name:g.name,description:g.description||'',price:g.price,originalPrice:g.originalPrice||g.price,image:g.image||'',categoryId:g.categoryId,merchantCategoryId:g.merchantCategoryId||0,stock:g.stock||0,tag:g.tag||'',special:g.special||false,status:g.status===1?0:1});toast('商品状态已更新');return renderPage();}
      if (action === 'merchant-goods-delete') {await send(`/api/merchant/goods/${id}`,'DELETE');return renderPage();}
      if (action === 'merchant-activity-new') {state.editGoods='activity';return renderPage();}
      if (action === 'merchant-seckill-new') {state.editGoods='seckill';return renderPage();}
      if (action === 'merchant-activity-status') {const a=state.merchantActivities.find(x=>Number(x.id)===Number(id));await send(`/api/merchant/activities/${id}/status?storeId=${state.activeStoreId}`,'PUT',{status:a.status?0:1});return renderPage();}
      if (action === 'merchant-activity-delete') {await send(`/api/merchant/activities/${id}?storeId=${state.activeStoreId}`,'DELETE');return renderPage();}
      if (action === 'merchant-seckill-status') {const s=state.merchantSeckills.find(x=>Number(x.id)===Number(id));await send(`/api/merchant/seckills/${id}/status?storeId=${state.activeStoreId}`,'PUT',{status:s.status?0:1});return renderPage();}
      if (action === 'merchant-seckill-delete') {await send(`/api/merchant/seckills/${id}?storeId=${state.activeStoreId}`,'DELETE');return renderPage();}
      if (action === 'merchant-categories') { const categories=await get('/api/merchant/categories')||[]; const name=window.prompt(`当前分类：${categories.map(c=>c.name).join('、')||'暂无'}\n输入新分类名称，取消则不创建`,''); if(name&&name.trim()) { await send('/api/merchant/categories','POST',{name:name.trim(),sort:categories.length}); toast('店内分类已创建'); } return renderPage(); }
      if (action === 'merchant-goods-specs') { const goods=state.merchantGoods.find(g=>Number(g.id)===Number(id));const current=(goods?.specs||[]).map(s=>`${s.name}:${s.price}:${s.stock}`).join(',');const text=window.prompt('规格格式：名称:价格:库存，多个用英文逗号分隔',current);if(text!==null){const specs=text.split(',').map((part,index)=>{const [name,price,stock]=part.split(':');return {id:goods?.specs?.[index]?.id||0,name:(name||'').trim(),price:Number(price||0),stock:Number(stock||0)};}).filter(s=>s.name);await send(`/api/merchant/goods/${id}/specs`,'PUT',{specs});toast('规格已保存');}return renderPage(); }
      if (action === 'merchant-setmeals') { const setmeals=await get(`/api/merchant/setmeals?storeId=${state.activeStoreId}`)||[];const name=window.prompt(`当前套餐：${setmeals.map(s=>s.name).join('、')||'暂无'}\n输入新套餐名称，取消则不创建`,'');if(name&&name.trim()){const goodsIds=window.prompt('输入套餐商品 ID，英文逗号分隔','');const items=(goodsIds||'').split(',').map(gid=>({id:0,setmealId:0,goodsId:Number(gid.trim()),goodsName:'',quantity:1})).filter(x=>x.goodsId>0);if(items.length)await send(`/api/merchant/setmeals?storeId=${state.activeStoreId}`,'POST',{name:name.trim(),description:'网页创建套餐',price:Number(window.prompt('套餐价格','20')||20),originalPrice:Number(window.prompt('套餐原价','25')||25),image:'',items});toast('套餐已创建');}return renderPage(); }
      if (action === 'merchant-employees') { const employees=await get(`/api/merchant/employees?storeId=${state.activeStoreId}`)||[];const userId=window.prompt(`当前员工：${employees.map(e=>e.username).join('、')||'暂无'}\n输入要添加的用户 ID，取消则不添加`,'');if(userId) {const roleName=window.prompt('员工角色','STAFF')||'STAFF';await send(`/api/merchant/employees?storeId=${state.activeStoreId}`,'POST',{userId:Number(userId),roleName});toast('员工已添加');}return renderPage(); }
      if (action === 'merchant-flow') {const [oid,flow]=String(id).split(':');await send(`/api/merchant/orders/${oid}/${flow}`,'PUT');toast('订单状态已更新');return renderPage();}
      if (action === 'rider-online') {state.rider=await send('/api/rider/status','PUT',{online:Number(id)});toast(Number(id)?'已上线':'已下线');return renderPage();}
      if (action === 'rider-grab') {await send(`/api/rider/orders/${id}/grab`,'POST');toast('抢单成功');return renderPage();}
      if (action === 'rider-pickup') {await send(`/api/rider/orders/${id}/pickup`,'PUT');return renderPage();}
      if (action === 'rider-deliver') {await send(`/api/rider/orders/${id}/deliver`,'PUT');return renderPage();}
      if (action === 'admin-category-new') {state.editGoods='category';return renderPage();}
      if (action === 'admin-category-delete') {await send(`/api/admin/categories/${id}`,'DELETE');return renderPage();}
      if (action === 'admin-store-status') {const [sid,status]=String(id).split(':');await send(`/api/admin/stores/${sid}/status`,'PUT',{status:Number(status)});return renderPage();}
      if (action === 'admin-store-recommend') {const [sid,recommended]=String(id).split(':');await send(`/api/admin/stores/${sid}/recommend`,'PUT',{recommended:Number(recommended)});return renderPage();}
      if (action === 'admin-refund-order') {await send(`/api/admin/orders/${id}/refund`,'PUT');return renderPage();}
      if (action === 'refund-approve') {await send(`/api/admin/refunds/${id}/approve`,'POST');return renderPage();}
      if (action === 'refund-reject') {const reason=window.prompt('拒绝原因','不符合退款条件');if(reason)await send(`/api/admin/refunds/${id}/reject`,'POST',{rejectReason:reason});return renderPage();}
      if (action === 'admin-subtab') {el.parentElement.querySelectorAll('.tab').forEach(x=>x.classList.remove('active'));el.classList.add('active');$('adminSubtab').innerHTML=id==='products'?adminProductsTable():adminUsersTable();return;}
      if (action === 'admin-user-status') {const [uid,status]=String(id).split(':');await send(`/api/admin/users/${uid}/status`,'PUT',{status:Number(status)});return renderPage();}
      if (action === 'admin-product-status') {const [pid,status]=String(id).split(':');await send(`/api/admin/products/${pid}/status`,'PUT',{status:Number(status)});return renderPage();}
      if (action === 'admin-product-delete') {await send(`/api/admin/products/${id}`,'DELETE');return renderPage();}
      if (action === 'admin-rider-status') {const [rid,status]=String(id).split(':');await send(`/api/admin/riders/${rid}/status`,'PUT',{status:Number(status)});return renderPage();}
      if (action === 'admin-banner-new') {state.editGoods='banner';return renderPage();}
      if (action === 'admin-announcement-new') {state.editGoods='announcement';return renderPage();}
      if (action === 'admin-banner-status') {const [bid,status]=String(id).split(':');await send(`/api/admin/banners/${bid}/status`,'PUT',{status:Number(status)});return renderPage();}
      if (action === 'admin-banner-delete') {await send(`/api/admin/banners/${id}`,'DELETE');return renderPage();}
      if (action === 'admin-announcement-status') {const [aid,status]=String(id).split(':');await send(`/api/admin/announcements/${aid}/status`,'PUT',{status:Number(status)});return renderPage();}
      if (action === 'admin-announcement-delete') {await send(`/api/admin/announcements/${id}`,'DELETE');return renderPage();}
      if (action === 'admin-employee-new') {state.editGoods='employee';return renderPage();}
      if (action === 'admin-employee-status') {const [eid,status]=String(id).split(':');await send(`/api/admin/employees/${eid}/status`,'PUT',{status:Number(status)});return renderPage();}
      if (action === 'admin-activity-status') {const [aid,status]=String(id).split(':');await send(`/api/admin/marketing/activities/${aid}/status`,'PUT',{status:Number(status)});return renderPage();}
      if (action === 'admin-activity-delete') {await send(`/api/admin/marketing/activities/${id}`,'DELETE');return renderPage();}
      if (action === 'admin-seckill-status') {const [sid,status]=String(id).split(':');await send(`/api/admin/marketing/seckills/${sid}/status`,'PUT',{status:Number(status)});return renderPage();}
      if (action === 'admin-seckill-delete') {await send(`/api/admin/marketing/seckills/${id}`,'DELETE');return renderPage();}
    } catch(error) { toast(error.message,true); }
  };
  document.addEventListener('click', e => { const target=e.target.closest('[data-action]'); if(target) handleAction(target.dataset.action,target.dataset.id,target); const nav=e.target.closest('[data-page]'); if(nav) navigate(nav.dataset.page); const close=e.target.closest('[data-close]'); if(close) $(close.dataset.close).hidden=true; });
  $('authForm').addEventListener('submit', async e => { e.preventDefault(); const f=new FormData(e.currentTarget);const data=Object.fromEntries(f.entries());try{if(e.currentTarget.dataset.mode==='register'){const r=await send('/api/auth/register','POST',{username:data.username,phone:data.phone,email:data.email,code:data.code,password:data.password,role:0});toast(`注册成功，请使用 ${r.phone} 登录`);openAuth('login');}else await loginWith({phone:data.phone,password:data.password,loginType:data.loginType});}catch(error){toast(error.message,true);}});
  const boot = async () => { renderShell(); if (state.token) { try { state.user=await get('/api/auth/me');state.role=Number(state.user.role); } catch (_) { state.token=''; } } renderShell(); await renderPage(); };
  boot();
})();

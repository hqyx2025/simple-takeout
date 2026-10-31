(() => {
  'use strict';
  // 清除旧版长期凭证；当前标签页会话通过 sessionStorage 跨刷新恢复。
  localStorage.removeItem('takeout.demo.token'); localStorage.removeItem('takeout.demo.refresh');
  const SESSION_KEY = 'takeout.session';
  const saveSession = () => sessionStorage.setItem(SESSION_KEY, JSON.stringify({token:state.token,refreshToken:state.refreshToken}));

  const ROLE = { 0: 'CUSTOMER', 1: 'MERCHANT', 2: 'ADMIN', 3: 'RIDER' };
  const STATUS = ['待付款', '待接单', '制作中', '配送中', '已送达', '已取消', '退款中'];
  const MARKETING_LABELS = { DISCOUNT: '折扣', NEW_USER: '新客立减', GIFT: '满赠' };
  const NAV = {
    0: [['首页', 'home', '⌂'], ['搜索与榜单', 'discover', '⌕'], ['购物车', 'cart', '▣'], ['我的订单', 'orders', '▤'], ['收藏与优惠券', 'perks', '♡'], ['地址与钱包', 'account', '◎'], ['个人设置', 'settings', '⚙'], ['智能客服', 'assistant', '?']],
    1: [['经营概况', 'overview', '▦'], ['订单处理', 'merchant-orders', '▤'], ['门店与商品', 'catalog', '▣'], ['采购与库存', 'erp', '▤'], ['评价回复', 'reviews', '☆'], ['营销活动', 'marketing', '◇'], ['售后待偿账目', 'after-sales-ledger', '↩']],
    2: [['平台总览', 'overview', '▦'], ['分类管理', 'categories', '▦'], ['店铺审核', 'stores', '⌂'], ['全平台订单', 'admin-orders', '▤'], ['退款审批', 'refunds', '↩'], ['配送异常', 'delivery-issues', '⚑'], ['用户与商品', 'users', '♙'], ['骑手管理', 'riders', '➤'], ['内容管理', 'content', '▧'], ['员工管理', 'employees', '♧'], ['采购与库存', 'erp', '▤'], ['操作日志', 'audit', '≡'], ['营销监管', 'admin-marketing', '◇']],
    3: [['待抢订单', 'rider-pool', '⌖'], ['配送订单', 'rider-orders', '➤'], ['骑手资料', 'rider-profile', '♙']]
  };
  const TITLES = {
    home: '首页', discover: '搜索与榜单', cart: '购物车', checkout: '确认订单', orders: '我的订单', perks: '收藏与优惠券', account: '地址与钱包', settings: '个人设置', assistant: '智能客服',
    'after-sales-ledger': '售后待偿账目', 'delivery-issues': '配送异常', erp: '采购与库存', overview: '经营概况', 'merchant-orders': '订单处理', catalog: '门店与商品', reviews: '评价回复', marketing: '营销活动',
    categories: '分类管理', stores: '店铺审核', 'admin-orders': '全平台订单', refunds: '退款审批', users: '用户与商品', riders: '骑手管理', content: '内容管理', employees: '员工管理', audit: '操作日志', 'admin-marketing': '营销监管',
    'rider-pool': '待抢订单', 'rider-orders': '配送订单', 'rider-profile': '骑手资料'
  };
  const state = {
    token: '', refreshToken: '',
    sidebarCollapsed: localStorage.getItem('takeout.demo.sidebarCollapsed') === '1',
    user: null, role: 0, page: 'home', search: '', categoryId: 0, stores: [], categories: [], storeId: 0, checkoutStoreId: 0,
    location: null, locationLabel: '', locating: false, locationVersion: 0,
    goods: [], cart: [], addresses: [], coupons: [], orders: [], favorites: [], rider: null, riderOrders: [], riderPool: [],
    merchantStores: [], activeStoreId: 0, merchantGoods: [], merchantOrders: [], editGoods: null, editAddress: null, reviewOrder: null,
    adminUsers: [], adminProducts: [], adminStores: [], adminCategories: [], adminOrders: [], adminRefunds: [],
    adminOrdersPage: 1, adminOrdersTotal: 0, adminOrdersHasMore: false, adminOrderQuery: '',
    adminRefundsPage: 1, adminRefundsTotal: 0, adminRefundsHasMore: false, adminRefundFilter: 'PENDING',
    adminRiders: [], adminBanners: [], adminAnnouncements: [], adminEmployees: [], adminActivities: [], adminSeckills: [],
    merchantActivities: [], merchantSeckills: [], merchantReviews: [], assistantHistory: [],
    checkoutIntentKey: '', checkoutIntentStoreId: 0, checkoutSubmitting: false,
    checkoutDrafts: {}, checkoutReturnStoreId: 0, checkoutView: null, riderActions: {}, ledgerPage: 1, deliveryIssuesPage: 1, deliveryIssueFilter: 'OPEN', deliveryIssues: []
  };
  let renderVersion = 0;
  let authRequestVersion = 0;
  let activeRefundDialog = null;
  function closeRefundDialog() { activeRefundDialog?.close('cancel'); }
  const resetCheckoutIntent = () => {
    state.checkoutStoreId = 0;
    state.checkoutIntentKey = '';
    state.checkoutIntentStoreId = 0;
    state.checkoutSubmitting = false;
    state.checkoutView = null;
  };
  const resetAccountState = (invalidateAuth = true) => {
    closeRefundDialog();
    if (invalidateAuth) authRequestVersion++;
    renderVersion++;
    state.locationVersion++;
    Object.assign(state, {
      token: '', refreshToken: '', user: null, role: 0, page: 'home',
      search: '', categoryId: 0, stores: [], categories: [], storeId: 0, goods: [],
      location: null, locationLabel: '', locating: false,
      cart: [], addresses: [], coupons: [], orders: [], favorites: [],
      rider: null, riderOrders: [], riderPool: [], merchantStores: [], activeStoreId: 0,
      merchantGoods: [], merchantOrders: [], merchantStoreEdit: null, editGoods: null, editAddress: null, reviewOrder: null,
      adminUsers: [], adminProducts: [], adminStores: [], adminCategories: [], adminOrders: [], adminRefunds: [],
      adminOrdersPage: 1, adminOrdersTotal: 0, adminOrdersHasMore: false, adminOrderQuery: '',
      adminRefundsPage: 1, adminRefundsTotal: 0, adminRefundsHasMore: false, adminRefundFilter: 'PENDING',
      adminRiders: [], adminBanners: [], adminAnnouncements: [], adminEmployees: [], adminActivities: [], adminSeckills: [],
      merchantActivities: [], merchantSeckills: [], merchantReviews: [], assistantHistory: [],
      checkoutDrafts: {}, checkoutReturnStoreId: 0, riderActions: {}, ledgerPage: 1, deliveryIssuesPage: 1, deliveryIssueFilter: 'OPEN', deliveryIssues: []
    });
    resetCheckoutIntent();
    sessionStorage.removeItem(SESSION_KEY);
    localStorage.removeItem('takeout.demo.token');
    localStorage.removeItem('takeout.demo.refresh');
    const notice = document.getElementById('notice');
    if (notice) { clearTimeout(toast.timer); notice.textContent = ''; notice.hidden = true; }
  };
  const $ = (id) => document.getElementById(id);
  const systemTheme = window.matchMedia('(prefers-color-scheme: dark)');
  const themeKey = () => `takeout.theme.${state.role}.${state.user.id}`;
  const applyTheme = () => {
    const logged = Boolean(state.user && state.token);
    const saved = logged ? localStorage.getItem(themeKey()) : 'light';
    const preference = ['light', 'dark', 'system'].includes(saved) ? saved : 'light';
    document.documentElement.dataset.theme = preference === 'system' ? (systemTheme.matches ? 'dark' : 'light') : preference;
    $('themeControl').hidden = !logged;
    $('themeSelect').value = preference;
  };
  systemTheme.addEventListener('change', applyTheme);
  $('themeSelect').addEventListener('change', e => {
    if (!state.user || !state.token) return;
    localStorage.setItem(themeKey(), e.target.value);
    applyTheme();
  });
  const esc = (v) => String(v ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
  const cash = (v) => Number(v || 0).toFixed(2);
  const toast = (message, error = false) => { const el = $('notice'); el.textContent = message; el.classList.toggle('error', error); el.hidden = false; clearTimeout(toast.timer); toast.timer = setTimeout(() => { el.hidden = true; }, 3600); };
  const api = async (path, options = {}) => {
    const requestToken = state.token;
    const { keepSessionOnUnauthorized = false, ...requestOptions } = options;
    const headers = { ...(options.body instanceof FormData ? {} : { 'Content-Type': 'application/json' }), ...(options.headers || {}) };
    if (requestToken) headers.Authorization = `Bearer ${requestToken}`;
    let response;
    try {
      response = await fetch(TakeoutUrls.localPath(path, document.baseURI), { cache: 'no-store', ...requestOptions, headers });
    } catch (cause) {
      if (cause && typeof cause === 'object' && !['TypeError', 'AbortError'].includes(cause.name)) {
        cause.responseReceived = false;
        throw cause;
      }
      const error = new Error('网络请求未完成，请检查连接后重试核对结果');
      error.responseReceived = false;
      throw error;
    }
    let body;
    try { body = await response.json(); }
    catch (_) {
      if (response.status !== 401) {
        const error = new Error('响应未完整读取，处理结果待确认，请重试核对');
        error.responseReceived = response.status >= 400 && response.status < 500
          && ![408,409,429].includes(response.status);
        throw error;
      }
      body = {};
    }
    if (response.status === 401) {
      if (!keepSessionOnUnauthorized && requestToken && requestToken === state.token) { resetAccountState(); renderShell(); void renderPage(); }
      const error = new Error('登录已过期，请重新登录');
      error.status = 401;
      throw error;
    }
    if (!body || !Number.isInteger(body.code) || body.code < 100 || body.code > 599) {
      throw new Error('响应内容不完整，处理结果待确认，请重试核对');
    }
    if (!response.ok || body.code !== 200) {
      const error = new Error(body.message || `请求失败 (${response.status})`);
      error.responseReceived = (response.ok || (response.status >= 400 && response.status < 500))
        && response.status !== 429 && body.code >= 400 && body.code < 500 && body.code !== 429
        && !/订单正在提交中|订单可能已提交/.test(String(body.message||''));
      throw error;
    }
    return body.data;
  };
  const get = (path) => api(path);
  const send = (path, method, data) => api(path, { method, body: data === undefined ? undefined : JSON.stringify(data) });
  const secureLocationLink = () => !window.isSecureContext ? '<a class="btn" href="https://hqyx.website/takeout/">打开 HTTPS 精确定位入口</a>' : '';
  const locationNotice = () => `<section class="surface section" data-browse-location>
    <div class="row-between location-heading"><div><strong>${esc(state.locationLabel || '全部店铺')}</strong><div class="help-text">展示全部营业店铺，位置和距离不影响浏览。下单时需定位收货地址，超出商家配送范围无法下单。</div></div><div class="td-actions"><button class="btn primary" type="button" data-action="location-change" aria-expanded="false" aria-controls="browseLocationPicker">更换位置</button>${btn('获取当前位置','locate-device')}${state.locationLabel ? btn('清除位置','location-clear') : ''}</div></div>
    <div data-location-status role="status" class="help-text"></div>
    <form id="browseLocationPicker" data-form="browse-location" class="inline-form" hidden>
      <label class="field">搜索其他位置<input class="input" name="locationKeyword" maxlength="80" placeholder="例如：武汉市光谷广场、北京市中关村广场" autocomplete="off"></label>
      <p class="help-text">输入城市、小区或街道名称选择位置，店铺列表始终展示全部地区。</p>
      <div class="form-actions"><button class="btn" type="button" data-action="location-change">取消</button><button class="btn primary" type="submit">搜索地点</button></div>
      <div class="location-results" data-location-results aria-live="polite"></div>
    </form></section>`;
  async function searchPlaces(form) {
    const keyword = form.elements.locationKeyword.value.trim();
    const results = form.querySelector('[data-location-results]');
    const token = state.token;
    const request = String(Number(form.dataset.locationRequest || 0) + 1);
    form.dataset.locationRequest = request;
    if (!keyword) { results.textContent = '请输入城市、小区或街道名称。'; form.elements.locationKeyword.focus(); return; }
    const buttons = form.querySelectorAll('[data-action="address-search"],button[type="submit"]');
    buttons.forEach(button => { button.disabled = true; }); results.textContent = '正在搜索地点…';
    const active = () => token === state.token && form.isConnected && !form.hidden && form.dataset.locationRequest === request;
    try {
      const data = await get(`/api/location/search?keyword=${encodeURIComponent(keyword)}`);
      if (!active()) return;
      if (data?.status !== '1') throw new Error('地点搜索暂不可用，请稍后重试。');
      const places = (Array.isArray(data.pois) ? data.pois : []).map(TakeoutLocation.place).filter(Boolean);
      const action = form.dataset.form === 'browse-location' ? 'location-select' : 'address-select';
      results.innerHTML = places.map(place => `<button class="btn location-result" type="button" data-action="${action}" data-address="${esc(place.address)}" data-longitude="${place.longitude}" data-latitude="${place.latitude}">${esc(place.address)}</button>`).join('') || '<p class="help-text">未找到可定位地点，请补充城市名称后重新搜索。</p>';
    } catch (error) { if (active()) results.textContent = error.message || '地点搜索失败，请稍后重试。'; }
    finally { buttons.forEach(button => { button.disabled = false; }); }
  }
  async function locate(el) {
    if (state.locating) return;
    const form = el.closest('form');
    const container = form || $('app');
    const status = container.querySelector('[data-location-status]');
    const token = state.token;
    const version = ++state.locationVersion;
    const active = () => token === state.token && state.locationVersion === version && container.isConnected && status?.isConnected;
    state.locating = true; el.disabled = true;
    if (status) status.textContent = '正在获取设备位置，请在浏览器提示中选择允许…';
    try {
        const position = await TakeoutLocation.devicePosition(window);
        if (!active()) return;
        if (status) status.textContent = '已获取坐标，正在解析地址…';
        const location = await get(`/api/location/reverse?longitude=${position.longitude}&latitude=${position.latitude}`);
        if (!active()) return;
        const coordinate = TakeoutLocation.coordinates(location.longitude, location.latitude);
        if (!coordinate || !location.address) throw new Error('定位结果无效，请重试或搜索地点。');
        if (form) {
          form.elements.latitude.value = coordinate.latitude; form.elements.longitude.value = coordinate.longitude;
          const address = form.dataset.form === 'address'
            ? form.elements.mapAddress
            : form.elements.detail || form.elements.address;
          if (address) address.value = location.address;
          if (form.dataset.form === 'address') form.dataset.coordinateAddress = location.address;
          status.textContent = `已填入当前位置${Number.isFinite(position.accuracy) ? `，设备精度约 ${Math.ceil(position.accuracy)} 米` : ''}。请核对地址并补充门牌号，点击保存后生效。`;
        } else {
          state.location = coordinate; state.locationLabel = location.address;
          await renderPage();
        }
    } catch (error) { if (active() && status) status.textContent = error.message; }
    finally { if (state.locationVersion === version) state.locating = false; el.disabled = false; }
  }
  const pageHead = (title, description = '', actions = '') => `<div class="page-head"><div><h1>${esc(title)}</h1>${description ? `<p>${esc(description)}</p>` : ''}</div><div class="head-actions">${actions}</div></div>`;
  const empty = (text) => `<div class="empty">${esc(text)}</div>`;
  const btn = (label, action, value = '', style = '') => `<button class="btn ${style}" data-action="${esc(action)}" data-id="${esc(value)}">${esc(label)}</button>`;
  const pagination = (action, page, total, hasMore) => `<div class="toolbar section" aria-label="分页"><span class="subtle">第${page}页 / 共${total}条</span><button class="btn small" data-action="${action}" data-id="${page-1}" ${page<=1?'disabled':''}>上一页</button><button class="btn small" data-action="${action}" data-id="${page+1}" ${hasMore?'':'disabled'}>下一页</button></div>`;
  const statusTag = (value, kind = '') => `<span class="status ${kind}">${esc(value)}</span>`;
  const assetURL = value => TakeoutUrls.localPath(value, document.baseURI);
  const storeImage = (store) => store.image ? `<img loading="lazy" decoding="async" src="${esc(assetURL(store.image))}" alt="">` : '食';
  const orderStatus = (o) => o.cancelSource === 'MERCHANT' ? '商家未能接单' : (o.escrowStatus === 2 ? '已退款' : (o.status === 4 && o.escrowStatus === 1 ? '已完成' : (STATUS[o.status] || '未知')));
  const moneyCents = value => {
    const [amount, exponent='0'] = String(Number(value) || 0).split('e');
    return Math.round(Number(`${amount}e${Number(exponent)+2}`));
  };
  const checkoutAmounts = (subtotal, deliveryFee, discount = 0) => {
    const goods = Math.max(0, moneyCents(subtotal));
    const delivery = Math.max(0, moneyCents(deliveryFee));
    const coupon = Math.max(0, moneyCents(discount));
    return { subtotal: goods / 100, deliveryFee: delivery / 100, discount: coupon / 100, payable: (goods + delivery - coupon) / 100 };
  };
  const couponUnavailableReason = (coupon, storeId, subtotal, deliveryFee = 0, now = Date.now()) => {
    const expiry = String(coupon.expireTime || '');
    const expiresAt = /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/.test(expiry) ? Date.parse(expiry.replace(' ', 'T')) : NaN;
    if (Number(coupon.status) !== 0) return Number(coupon.status) === 1 ? '已使用' : '已失效';
    if (Number(coupon.storeId) && Number(coupon.storeId) !== Number(storeId)) return '不适用于本店';
    if (!Number.isFinite(expiresAt)) return '有效期信息异常，请刷新';
    if (expiresAt < now) return '已过期';
    if (moneyCents(coupon.threshold) > moneyCents(subtotal)) return `商品还差 ¥${cash((moneyCents(coupon.threshold)-moneyCents(subtotal))/100)} 达到门槛`;
    const payable = checkoutAmounts(subtotal, deliveryFee, coupon.amount).payable;
    if (payable < 0) return '券额超过本单商品与配送费合计';
    if (payable === 0) return '抵扣后实付为 0，请换一张券';
    return '';
  };
  const couponEligible = (coupon, storeId, subtotal, deliveryFee = 0, now = Date.now()) => !couponUnavailableReason(coupon, storeId, subtotal, deliveryFee, now);
  const checkoutDraft = storeId => {
    const key = `${Number(state.user?.id || 0)}:${Number(storeId)}`;
    return state.checkoutDrafts[key] ||= { storeId:Number(storeId), addressId:0, couponId:0, couponManual:false, remark:'', intentKey:`web-${Date.now()}-${Math.random().toString(16).slice(2)}`, reviewMessage:'', submittedPayload:null };
  };
  const captureCheckoutDraft = () => {
    if (!state.checkoutView || state.page !== 'checkout') return;
    const draft = checkoutDraft(state.checkoutView.storeId);
    if (draft.submittedPayload) return;
    draft.remark = $('checkoutRemark')?.value || '';
    draft.addressId = Number(document.querySelector('input[name="addressId"]:checked')?.value || 0);
  };
  const checkoutSnapshot = (items, store, address, coupon) => JSON.stringify({
    items:items.map(item=>[Number(item.goodsId),Number(item.specId||0),Number(item.quantity),moneyCents(item.price)]).sort((a,b)=>a[0]-b[0]||a[1]-b[1]),
    deliveryFee:moneyCents(store?.deliveryFee), minOrder:moneyCents(store?.minOrder),
    address:address ? [Number(address.id),address.name,address.phone,addressText(address)] : null,
    coupon:coupon ? [Number(coupon.id),moneyCents(coupon.amount),moneyCents(coupon.threshold)] : null
  });
  const checkoutData = (storeId, cart, addresses, coupons, store, draft) => {
    const items = cart.filter(item=>Number(item.storeId)===Number(storeId));
    const subtotal = items.reduce((sum,item)=>sum+moneyCents(item.price)*Number(item.quantity||0),0)/100;
    const deliveryFee = Number(store?.deliveryFee || 0);
    const available = coupons.filter(coupon=>couponEligible(coupon,storeId,subtotal,deliveryFee));
    if (!draft.couponManual) draft.couponId = Number(available.filter(coupon=>moneyCents(coupon.amount)>0).sort((a,b)=>moneyCents(b.amount)-moneyCents(a.amount)||Number(a.id)-Number(b.id))[0]?.id||0);
    const selectedCoupon = available.find(coupon=>Number(coupon.id)===Number(draft.couponId));
    if (draft.couponId && !selectedCoupon) {
      const oldCoupon = coupons.find(coupon=>Number(coupon.id)===Number(draft.couponId));
      draft.reviewMessage = `原选优惠券已不可用：${oldCoupon?couponUnavailableReason(oldCoupon,storeId,subtotal,deliveryFee):'优惠券信息已变化'}。已改为不使用，请核对金额。`;
      draft.couponId = 0; draft.couponManual = true;
    }
    let address = addresses.find(item=>Number(item.id)===Number(draft.addressId));
    if (!address && draft.addressId) draft.reviewMessage = '原选地址已删除，请重新选择收货地址。';
    if (!address) address = addresses.find(item=>item.isDefault) || addresses[0];
    draft.addressId = Number(address?.id||0);
    return {storeId,items,addresses,coupons,store,subtotal,deliveryFee,available,address,selectedCoupon,
      signature:checkoutSnapshot(items,store,address,selectedCoupon)};
  };
  const canOrder = (order, action, legacy = false) => order && Object.prototype.hasOwnProperty.call(order,'capabilities')
    ? Array.isArray(order.capabilities?.allowedActions) && order.capabilities.allowedActions.every(item=>typeof item==='string')
      && order.capabilities.allowedActions.includes(action) : legacy;
  const canRefund = order => canOrder(order, 'REFUND', Number(order?.status) === 4 && Number(order?.escrowStatus || 0) === 0);
  const evidenceField = '<label class="field">证据图片（选填，最多9张）<input class="input" name="evidenceFiles" type="file" accept="image/*" multiple><span class="help-text">上传实际餐品、包装或配送凭证。</span></label>';
  const evidenceLinks = (label, images) => (images || []).filter(url => typeof url === 'string' && /^\/uploads\/[^?#]+$/.test(url)).map((url,index) => `<a class="btn small" href="${esc(assetURL(url))}" target="_blank" rel="noopener">${esc(label)} ${index+1}</a>`).join('');
  const uploadEvidence = async (form, active) => {
    const input = form.querySelector('[name="evidenceFiles"]');
    const files = Array.from(input?.files || []);
    if (files.length > 9) throw new Error('证据图片最多9张');
    const images = [];
    for (const file of files) {
      if (!file.type?.startsWith('image/')) throw new Error('请选择图片文件');
      if (!active()) throw staleRender;
      const data = new FormData(); data.append('file', file);
      const result = await api('/api/upload', { method: 'POST', body: data });
      if (!active()) throw staleRender;
      const url = typeof result === 'string' ? result : result?.url;
      if (!/^\/uploads\/[^?#]+$/.test(url || '')) throw new Error('图片上传未返回有效本地地址，请重试');
      images.push(url);
    }
    return images;
  };
  const requestBusinessForm = (title, fields, path, method, payload) => {
    const view = createRefundDialog(title, `<form class="field-stack">${fields}<p role="alert" data-business-error></p><div class="form-actions"><button class="btn" type="button" data-business-cancel>取消</button><button class="btn primary" type="submit" data-business-submit>确认提交</button></div></form>`);
    const {dialog, active} = view, form = dialog.querySelector('form');
    const error = form.querySelector('[data-business-error]'), submit = form.querySelector('[data-business-submit]');
    let busy = false, pending = null;
    form.querySelector('[data-business-cancel]').addEventListener('click', () => { if (!busy) dialog.close('cancel'); });
    dialog.addEventListener('cancel', event => { if (busy) event.preventDefault(); });
    form.addEventListener('submit', async event => {
      event.preventDefault(); if (busy || !active()) return;
      busy = true; submit.disabled = true; error.textContent = '';
      try {
        if (!pending) pending = await payload(Object.fromEntries(new FormData(form).entries()), form, active);
        if (!active()) return;
        const result = await send(path, method, pending);
        if (!active()) return;
        dialog.result = result || {ok:true}; dialog.close('success');
      } catch (failure) {
        if (!active()) return;
        if (failure.responseReceived) pending = null;
        error.textContent = pending ? `提交结果待核对：${failure.message}。再次提交将核对原请求，请勿重复新建。` : failure.message;
      } finally { if (active()) { busy = false; submit.disabled = false; } }
    });
    view.show(); return view.closed;
  };
  const noteField = (name, label, max = 500) => `<label class="field">${label}<textarea class="textarea" name="${name}" required maxlength="${max}" placeholder="例如：联系收货人多次未接通，请平台协助核实"></textarea></label>`;
  const requireNote = (value, max = 500) => { const text = String(value || '').trim(); if (!text || text.length > max) throw new Error(`请填写${max}字以内的说明`); return text; };
  const REFUND_REASONS = { NOT_RECEIVED: '未收到餐', QUALITY_ISSUE: '餐品质量问题', WRONG_ITEM: '商品不符或缺漏', DONOT_WANT: '不想要了', OTHER: '其他原因' };
  const refundStatus = record => ({ PENDING: '待审批', APPROVED: '已同意，退款处理中', REFUNDED: '已退款', REJECTED: '已拒绝' }[record.status] || '状态待确认');
  const refundDetails = record => `<dl class="refund-details"><div><dt>退款申请编号</dt><dd>${esc(record.id)}</dd></div><div><dt>订单编号</dt><dd>${esc(record.orderId)}</dd></div><div><dt>申请类型</dt><dd>${esc(REFUND_REASONS[record.reasonType] || record.reasonType || '其他原因')}</dd></div><div><dt>补充说明</dt><dd>${esc(record.reason || '未填写')}</dd></div><div><dt>退款金额</dt><dd>¥${cash(record.amount)}</dd></div><div><dt>处理状态</dt><dd>${esc(refundStatus(record))}</dd></div><div><dt>申请时间</dt><dd>${esc(record.applyTime || '暂无记录')}</dd></div><div><dt>处理时间</dt><dd>${esc(record.processTime || '尚未处理')}</dd></div>${record.rejectReason ? `<div><dt>拒绝原因</dt><dd>${esc(record.rejectReason)}</dd></div>` : ''}</dl><div class="toolbar">${evidenceLinks('申请证据',record.evidenceImages)}</div>${record.merchantResponse?`<p>商家举证：${esc(record.merchantResponse)}</p>`:''}<div class="toolbar">${evidenceLinks('商家证据',record.merchantEvidenceImages)}</div>${record.appealReason?`<p>申诉（${Number(record.appealCount||0)}次）：${esc(record.appealReason)}</p>`:''}<div class="toolbar">${evidenceLinks('申诉证据',record.appealImages)}</div>`;
  const refundFeedback = record => {
    if (record?.status === 'REFUNDED') return '款项已按原支付渠道退回，可在退款记录查看详情';
    if (record?.status === 'REJECTED') return `该申请已被拒绝：${record.rejectReason || '请查看退款记录中的处理说明'}`;
    if (record?.status === 'PENDING') return '退款申请已提交，等待平台审批，可在退款记录查看进度';
    return '申请状态已更新，请在退款记录查看处理结果';
  };
  const createRefundDialog = (title, content) => {
    closeRefundDialog();
    const context = asyncContext();
    const dialog = document.createElement('dialog');
    dialog.className = 'dialog refund-dialog';
    dialog.setAttribute('aria-labelledby', 'refundDialogTitle');
    dialog.innerHTML = `<div class="field-stack" data-refund-dialog><h2 id="refundDialogTitle">${esc(title)}</h2>${content}</div>`;
    let resolve;
    const closed = new Promise(done => { resolve = done; });
    dialog.addEventListener('close', () => {
      if (activeRefundDialog === dialog) activeRefundDialog = null;
      dialog.remove(); resolve(dialog.result || null);
    }, { once: true });
    const active = () => activeRefundDialog === dialog && dialog.open && isCurrentContext(context);
    activeRefundDialog = dialog;
    return { dialog, closed, active, show() { document.body.append(dialog); dialog.showModal(); } };
  };
  const ISSUE_TYPES = {NO_RIDER:'长时间无人接单',CUSTOMER_UNREACHABLE:'无法联系收货人',ADDRESS_PROBLEM:'地址异常',FOOD_DAMAGED:'餐品损坏',OTHER:'其他异常'};
  const issuePath = id => '/api/' + ({0:'orders',1:'merchant/orders',3:'rider/orders'}[state.role] || 'orders') + '/' + id + '/issues';
  const issueDetails = issue => '<section class="surface"><strong>异常 #' + esc(issue.id) + ' · 订单 ' + esc(issue.orderId) + '</strong><p>' + esc(ISSUE_TYPES[issue.type] || issue.type) + '：' + esc(issue.note) + '</p><p class="subtle">' + esc(issue.status==='OPEN'?'待平台处理':'已处理') + ' · ' + esc(issue.createTime) + '</p>' + (issue.resolveNote?'<p>处理说明：' + esc(issue.resolveNote) + '</p>':'') + '</section>';
  const showOrderIssues = async orderId => {
    const path = issuePath(orderId);
    const view = createRefundDialog('配送异常记录','<div data-issue-history role="status">正在读取…</div><button class="btn" type="button" data-refund-close>关闭</button>');
    const {dialog,active} = view, content = dialog.querySelector('[data-issue-history]');
    let busy = false;
    const load = async () => {
      if (busy || !active()) return; busy = true;
      try { const records = await get(path); if(active())content.innerHTML = records?.length ? records.map(issueDetails).join('') : '<p>暂无异常记录。</p>'; }
      catch(error) { if(active())content.innerHTML = '<p role="alert">读取失败：' + esc(error.message) + '</p><button class="btn" type="button" data-issue-retry>重试</button>'; }
      finally {busy = false;}
    };
    content.addEventListener('click', event => {if(event.target.closest('[data-issue-retry]'))void load();});
    dialog.querySelector('[data-refund-close]').addEventListener('click',()=>dialog.close('cancel'));
    view.show(); await load();
  };
  const canAppeal = record => {
    const processed = Date.parse(String(record.processTime || '').replace(' ','T'));
    return record.status === 'REJECTED' && Number(record.appealCount || 0) === 0 && Number.isFinite(processed) && Date.now() <= processed + 48*60*60*1000;
  };
  const showRefundHistory = async orderId => {
    const merchant = state.role === 1;
    const context = asyncContext();
    let records = [];
    const view = createRefundDialog('退款记录', '<div data-refund-history role="status">正在读取退款记录…</div><div class="form-actions"><button class="btn" type="button" data-refund-close>关闭</button></div>');
    const { dialog, active } = view;
    const content = dialog.querySelector('[data-refund-history]');
    let loading = false;
    const loadHistory = async () => {
      if (loading || !active()) return;
      loading = true; content.textContent = '正在读取退款记录…';
      try {
        records = await get(`/api/${merchant ? 'merchant/orders' : 'orders'}/${orderId}/refunds`);
        if (!active()) return;
        content.innerHTML = records?.length ? records.map(record => `<section class="refund-record" aria-label="退款申请 ${esc(record.id)}">${refundDetails(record)}${merchant && record.status === 'PENDING' ? btn('提交商家举证','merchant-evidence',record.id) : !merchant && canAppeal(record) ? btn('提交一次申诉','refund-appeal',record.id) : ''}</section>`).join('') : '<p>此订单暂无退款申请。</p>';
      } catch (error) {
        if (active()) content.innerHTML = `<p role="alert">退款记录读取失败：${esc(error.message || '网络暂不可用')}。请重试。</p><button class="btn" type="button" data-refund-retry>重新读取</button>`;
      } finally { loading = false; }
    };
    dialog.querySelector('[data-refund-close]').addEventListener('click', () => dialog.close('cancel'));
    content.addEventListener('click', async event => {
      if (event.target.closest('[data-refund-retry]')) { await loadHistory(); return; }
      const button = event.target.closest('[data-action]'); if (!button || !active()) return;
      const record = records.find(item => Number(item.id) === Number(button.dataset.id)); if (!record) return;
      let result;
      if (button.dataset.action === 'merchant-evidence' && merchant && record.status === 'PENDING') {
        result = await requestBusinessForm('商家举证', refundDetails(record) + noteField('response','商家说明',1000) + evidenceField, '/api/after-sales/' + record.id + '/merchant-evidence', 'POST', async (data,form,valid) => ({response:requireNote(data.response,1000),evidenceImages:await uploadEvidence(form,valid)}));
      } else if (button.dataset.action === 'refund-appeal' && !merchant && canAppeal(record)) {
        result = await requestBusinessForm('提交一次申诉', '<p class="help-text">驳回后48小时内可申诉一次，由平台重新裁决。</p>' + refundDetails(record) + noteField('reason','申诉说明',255) + evidenceField, '/api/orders/' + orderId + '/refunds/' + record.id + '/appeal', 'POST', async (data,form,valid) => ({reason:requireNote(data.reason,255),evidenceImages:await uploadEvidence(form,valid)}));
      } else return;
      if (isCurrentContext(context)) { if(result) toast('处理已提交，请核对最新售后记录'); await showRefundHistory(orderId); }
    });
    view.show(); await loadHistory();
  };
  const requestRefund = order => {
    const key = `web-refund-${Date.now()}-${Math.random().toString(16).slice(2)}`;
    const view = createRefundDialog('申请退款', `<p class="help-text">订单 ${esc(order.orderNo || order.id)}，实付 ¥${cash(order.payAmount)}。送达后48小时内可申请部分或全额售后，确认收到、评价后仍可申请；由平台审批。${order.capabilities?.afterSalesDeadline ? `售后截止 ${esc(order.capabilities.afterSalesDeadline)}，剩余可退 ¥${cash(order.capabilities.refundRemaining)}。` : ''}处理结果可在“退款记录”查看。</p><form class="field-stack" data-refund-apply-form><label class="field">退款金额（元，留空退剩余全额）<input class="input" name="amount" type="number" min="0.01" step="0.01" ${order.capabilities ? `max="${esc(order.capabilities.refundRemaining)}"` : ''} placeholder="例如：5.50"></label>${evidenceField}<label class="field">退款原因<select class="select" name="reasonType" required><option value="">请选择实际遇到的问题</option>${Object.entries(REFUND_REASONS).map(([code,label]) => `<option value="${code}">${esc(label)}</option>`).join('')}</select></label><label class="field"><span data-refund-note-label>补充说明（选填）</span><textarea class="textarea" name="reason" maxlength="200" placeholder="例如：缺少一份米饭，或餐盒破损漏汤"></textarea></label><p class="help-text" data-refund-error role="alert"></p><div class="form-actions"><button class="btn" type="button" data-refund-cancel>暂不申请</button><button class="btn primary" type="submit" data-refund-submit>提交退款申请</button></div></form>`);
    const { dialog, active } = view;
    const form = dialog.querySelector('form');
    const error = form.querySelector('[data-refund-error]');
    const submit = form.querySelector('[data-refund-submit]');
    const cancel = form.querySelector('[data-refund-cancel]');
    let submitting = false, pendingPayload = null;
    form.elements.reasonType.addEventListener('change', () => {
      const required = form.elements.reasonType.value === 'OTHER';
      form.elements.reason.required = required;
      form.querySelector('[data-refund-note-label]').textContent = required ? '补充说明（必填）' : '补充说明（选填）';
      error.textContent = '';
    });
    cancel.addEventListener('click', () => { if (!submitting) dialog.close('cancel'); });
    dialog.addEventListener('cancel', event => { if (submitting) event.preventDefault(); });
    form.addEventListener('submit', async event => {
      event.preventDefault();
      if (submitting || !active()) return;
      const reasonType = form.elements.reasonType.value;
      const reason = form.elements.reason.value.trim();
      if (!REFUND_REASONS[reasonType]) { error.textContent = '请选择退款原因'; form.elements.reasonType.focus(); return; }
      if (reasonType === 'OTHER' && !reason) { error.textContent = '请填写具体问题，方便平台核实'; form.elements.reason.focus(); return; }
      submitting = true; submit.disabled = true; cancel.disabled = true; submit.textContent = '提交中…'; error.textContent = '';
      try {
        if (!pendingPayload) {
          const text = String(form.querySelector('[name="amount"]').value || '').trim();
          const amount = text ? Number(text) : undefined;
          if (text && (!/^\d+(\.\d{1,2})?$/.test(text) || !Number.isFinite(amount) || amount <= 0 || (order.capabilities && moneyCents(amount) > moneyCents(order.capabilities.refundRemaining)))) throw new Error('退款金额须大于0且不超过剩余可退金额，最多两位小数');
          const evidenceImages = await uploadEvidence(form,active);
          pendingPayload = { reasonType, reason, idempotencyKey:key, ...(amount === undefined ? {} : {amount}), evidenceImages };
        }
        if (!active()) return;
        const record = await send('/api/orders/' + order.id + '/refund', 'POST', pendingPayload);
        if (!active()) return;
        dialog.result = record; dialog.close('success');
      } catch (requestError) {
        if (requestError.responseReceived) pendingPayload = null;
        if (active()) error.textContent = `提交结果暂未确认：${requestError.message || '网络暂不可用'}。可保留当前内容重试；同一次申请不会重复创建。`;
      } finally {
        if (active()) { submitting = false; submit.disabled = false; cancel.disabled = false; submit.textContent = '重新提交退款申请'; }
      }
    });
    view.show(); form.elements.reasonType.focus(); return view.closed;
  };
  const requestRefundDecision = (refundId, approve) => {
    const view = createRefundDialog(approve ? '核对并同意退款' : '核对并拒绝退款', '<div data-refund-decision-details role="status">正在读取申请详情…</div><form class="field-stack" data-refund-decision-form hidden><p class="notice-line">按原支付渠道退款，餐品不恢复为库存。待付款取消释放优惠券；商家/平台取消退回仍有效券，已付用户主动取消不返券；制作或配送取消不恢复可售库存。</p>' + (approve ? '<label class="refund-ack"><input type="checkbox" name="acknowledged" required> 我已核对申请原因与退款金额</label>' : '<label class="field">拒绝原因<textarea class="textarea" name="rejectReason" maxlength="200" required placeholder="请说明核实情况和拒绝依据，用户将看到此内容"></textarea></label>') + '<p class="help-text" data-refund-error role="alert"></p><div class="form-actions"><button class="btn" type="button" data-refund-cancel>暂不处理</button><button class="btn primary" type="submit" data-refund-submit>确认' + (approve ? '同意退款' : '拒绝退款') + '</button></div></form><div class="form-actions" data-refund-load-actions><button class="btn" type="button" data-refund-close>关闭</button><button class="btn" type="button" data-refund-retry hidden>重新读取</button></div>');
    const { dialog, active } = view;
    const details = dialog.querySelector('[data-refund-decision-details]');
    const form = dialog.querySelector('form');
    const error = form.querySelector('[data-refund-error]');
    const submit = form.querySelector('[data-refund-submit]');
    const cancel = form.querySelector('[data-refund-cancel]');
    const retry = dialog.querySelector('[data-refund-retry]');
    let record = null, loading = false, submitting = false;
    const loadDetail = async () => {
      if (loading || !active()) return;
      loading = true; retry.hidden = true; details.textContent = '正在读取申请详情…';
      try {
        const result = await get(`/api/admin/refunds/${refundId}`);
        if (!active()) return;
        record = result; details.innerHTML = refundDetails(record);
        form.hidden = record.status !== 'PENDING';
        if (form.hidden) dialog.result = record;
        dialog.querySelector('[data-refund-load-actions]').hidden = !form.hidden;
        if (!form.hidden) (approve ? form.elements.acknowledged : form.elements.rejectReason).focus();
      } catch (requestError) {
        if (active()) { details.textContent = `申请详情读取失败：${requestError.message || '请稍后重试'}。核对详情后才能审批。`; retry.hidden = false; }
      } finally { loading = false; }
    };
    retry.addEventListener('click', () => void loadDetail());
    dialog.querySelector('[data-refund-close]').addEventListener('click', () => { if (!submitting) dialog.close('cancel'); });
    cancel.addEventListener('click', () => { if (!submitting) dialog.close('cancel'); });
    dialog.addEventListener('cancel', event => { if (submitting) event.preventDefault(); });
    form.addEventListener('submit', async event => {
      event.preventDefault();
      if (submitting || !active() || record?.status !== 'PENDING') return;
      const rejectReason = approve ? '' : form.elements.rejectReason.value.trim();
      if (approve && !form.elements.acknowledged.checked) { error.textContent = '请先核对申请原因与退款金额，再勾选确认'; return; }
      if (!approve && !rejectReason) { error.textContent = '请填写具体拒绝原因，不能只输入空格'; form.elements.rejectReason.focus(); return; }
      submitting = true; submit.disabled = true; cancel.disabled = true; submit.textContent = '处理中…'; error.textContent = '';
      try {
        const result = await send(`/api/admin/refunds/${refundId}/${approve ? 'approve' : 'reject'}`, 'POST', approve ? undefined : { rejectReason });
        if (!active()) return;
        dialog.result = result; dialog.close('success');
      } catch (requestError) {
        if (!active()) return;
        try {
          const current = await get(`/api/admin/refunds/${refundId}`);
          if (!active()) return;
          if (current.status !== 'PENDING') { dialog.result = current; dialog.close('success'); return; }
        } catch (_) { /* 保留表单和重试入口，等待网络恢复后核对结果。 */ }
        if (active()) error.textContent = `处理结果暂未确认：${requestError.message || '请稍后重试'}。请保留当前内容重试，或关闭后刷新状态。`;
      } finally {
        if (active()) { submitting = false; submit.disabled = false; cancel.disabled = false; submit.textContent = approve ? '确认同意退款' : '确认拒绝退款'; }
      }
    });
    view.show(); void loadDetail(); return view.closed;
  };
  const requestPaymentPassword = () => new Promise(resolve => {
    const dialog = document.createElement('dialog');
    dialog.className = 'dialog';
    dialog.setAttribute('aria-label', '余额支付确认');
    dialog.innerHTML = '<form method="dialog" class="field-stack"><h2>余额支付确认</h2><label class="field">支付密码<input class="input" name="pin" type="password" inputmode="numeric" autocomplete="off" pattern="[0-9]{6}" maxlength="6" required placeholder="请输入 6 位数字支付密码"></label><p class="help-text">未设置支付密码，请先前往个人设置。</p><div class="form-actions"><button class="btn" value="cancel" formnovalidate>取消</button><button class="btn primary" value="pay">确认支付</button></div></form>';
    dialog.addEventListener('close', () => {
      const input = dialog.querySelector('input');
      const password = dialog.returnValue === 'pay' ? input.value : null;
      input.value = ''; dialog.remove(); resolve(password);
    }, { once: true });
    document.body.append(dialog); dialog.showModal();
  });
  const requestReview = (order) => new Promise(resolve => {
    const goods = [...new Map((order?.items || []).filter(item => Number(item.goodsId) > 0)
      .map(item => [Number(item.goodsId), item.goodsName || item.name || `商品 ${item.goodsId}`])).entries()];
    if (!goods.length) { resolve(null); return; }
    const dialog = document.createElement('dialog');
    dialog.className = 'dialog';
    dialog.setAttribute('aria-labelledby', 'reviewDialogTitle');
    dialog.innerHTML = `<form method="dialog" class="field-stack"><h2 id="reviewDialogTitle">评价商品</h2><label class="field">商品<select class="select" name="goodsId" required>${goods.map(([id,name])=>`<option value="${id}">${esc(name)}</option>`).join('')}</select></label><label class="field">评分<select class="select" name="rating" required><option value="">请选择 1–5 星</option>${[1,2,3,4,5].map(rating=>`<option value="${rating}">${rating} 星</option>`).join('')}</select></label><fieldset><legend>标签（可选）</legend><div class="toolbar">${['味道好','分量足','包装好','需要改进'].map(tag=>`<label><input type="checkbox" name="tags" value="${tag}"> ${tag}</label>`).join('')}</div></fieldset><label class="field">评价内容（可选）<textarea class="textarea" name="content" maxlength="512" placeholder="说说这道商品的实际体验"></textarea></label><div class="form-actions"><button class="btn" value="cancel" formnovalidate>取消</button><button class="btn primary" value="submit">提交评价</button></div></form>`;
    dialog.addEventListener('close', () => {
      if (dialog.returnValue !== 'submit') { dialog.remove(); resolve(null); return; }
      const data = new FormData(dialog.querySelector('form'));
      const result = { goodsId: Number(data.get('goodsId')), rating: Number(data.get('rating')),
        content: String(data.get('content') || '').trim(), tags: data.getAll('tags').map(String),
        images: [], anonymous: 0 };
      dialog.remove(); resolve(result);
    }, { once: true });
    document.body.append(dialog); dialog.showModal(); dialog.querySelector('[name="goodsId"]')?.focus();
  });
  const merchantRejectPayload = (data) => {
    const reasonCode = String(data.reasonCode || '');
    if (!['ITEM_UNAVAILABLE','STORE_OVER_CAPACITY','STORE_TEMPORARILY_CLOSED','OTHER'].includes(reasonCode)) {
      throw new Error('请选择无法接单原因');
    }
    const payload = { reasonCode };
    const note = String(data.note || '').trim();
    if (note) payload.note = note;
    if (reasonCode === 'ITEM_UNAVAILABLE') {
      const [goodsId, specId] = String(data.goodsKey || '').split(':').map(Number);
      if (!Number.isInteger(goodsId) || goodsId <= 0 || !Number.isInteger(specId) || specId < 0) {
        throw new Error('请选择缺货餐品');
      }
      payload.goodsId = goodsId; payload.specId = specId;
    }
    return payload;
  };
  const requestMerchantReject = (order) => new Promise(resolve => {
    const items = order?.items || [];
    const dialog = document.createElement('dialog');
    dialog.className = 'dialog';
    dialog.setAttribute('aria-labelledby', 'merchantRejectTitle');
    dialog.innerHTML = `<form class="field-stack" data-merchant-reject-form><div><h2 id="merchantRejectTitle">无法接单</h2><p class="help-text">订单 ${esc(order?.orderNo || order?.id)}。请按实际情况选择原因，提交后用户会看到处理结果。</p></div><label class="field">无法接单原因<select class="select" name="reasonCode" required><option value="">请选择原因</option><option value="ITEM_UNAVAILABLE">餐品缺货</option><option value="STORE_OVER_CAPACITY">订单已满，无法按时完成</option><option value="STORE_TEMPORARILY_CLOSED">门店临时歇业</option><option value="OTHER">其他原因</option></select></label><fieldset class="reject-items" data-reject-items hidden><legend>选择缺货餐品</legend>${items.map(item=>{const goodsId=Number(item.goodsId||item.id||0),specId=Number(item.specId||0);const name=item.goodsName||item.name||`商品 ${goodsId}`;return `<label class="address-option"><input type="radio" name="goodsKey" value="${goodsId}:${specId}"> <span>${esc(name)}${item.specName?`（${esc(item.specName)}）`:''} ×${Number(item.quantity||0)}</span></label>`;}).join('')}</fieldset><label class="field">补充说明（选填）<textarea class="textarea" name="note" maxlength="100" placeholder="例如：原料临时售罄，预计晚餐时段恢复"></textarea></label><p class="help-text" data-reject-error role="alert"></p><div class="form-actions"><button class="btn" type="button" data-reject-cancel>暂不处理</button><button class="btn danger" type="submit" data-reject-submit>确认无法接单</button></div></form>`;
    const form = dialog.querySelector('form');
    const itemField = form.querySelector('[data-reject-items]');
    const error = form.querySelector('[data-reject-error]');
    const submitButton = form.querySelector('[data-reject-submit]');
    const cancelButton = form.querySelector('[data-reject-cancel]');
    let submitting = false;
    form.elements.reasonCode.addEventListener('change', () => {
      itemField.hidden = form.elements.reasonCode.value !== 'ITEM_UNAVAILABLE';
      error.textContent = '';
    });
    cancelButton.addEventListener('click', () => { if (!submitting) dialog.close('cancel'); });
    dialog.addEventListener('cancel', event => { if (submitting) event.preventDefault(); });
    dialog.addEventListener('close', () => { const accepted=dialog.returnValue==='success';dialog.remove();resolve(accepted); }, { once: true });
    form.addEventListener('submit', async event => {
      event.preventDefault();
      if (submitting) return;
      let payload;
      try { payload=merchantRejectPayload(Object.fromEntries(new FormData(form).entries())); }
      catch (validationError) { error.textContent=validationError.message;return; }
      submitting=true;submitButton.disabled=true;cancelButton.disabled=true;submitButton.textContent='提交中…';error.textContent='';
      try {
        await send(`/api/merchant/orders/${order.id}/reject`,'POST',payload);
        dialog.close('success');
      } catch (requestError) {
        error.textContent=requestError.message||'提交失败，请稍后重试';
        submitting=false;submitButton.disabled=false;cancelButton.disabled=false;submitButton.textContent='确认无法接单';
      }
    });
    document.body.append(dialog);dialog.showModal();form.elements.reasonCode.focus();
  });
  let authReturnFocus = null;
  let authReturnHash = '';
  let authViewVersion = 0;
  let captchaVersion = 0;
  let usernameCheckVersion = 0, usernameCheckTimer = null;
  let checkedUsername = '', usernameAvailable = null, usernameError = '';
  const emailCooldowns = new Map();
  const authModeFromUrl = () => /^#\/register$/.test(window.location.hash) ? 'register'
    : /^#\/login(?:\?method=email)?$/.test(window.location.hash) ? (window.location.hash.includes('method=email') ? 'email' : 'login') : '';
  const authVisibility = visible => {
    $('authPage').hidden = !visible;
    $('siteHeader').hidden = visible;
    $('appLayout').hidden = visible;
  };
  const closeAuth = (updateRoute = true) => {
    authViewVersion++; authRequestVersion++;
    clearTimeout(updateCodeButton.timer);
    resetUsernameCheck();
    authVisibility(false);
    $('authForm').innerHTML = '';
    $('authForm').dataset.mode = '';
    document.title = '简单外卖';
    if (updateRoute && authModeFromUrl()) window.history.replaceState(null, '', window.location.pathname + window.location.search + authReturnHash);
    authReturnFocus?.focus?.();
    authReturnFocus = null;
  };
  const authIcon = name => '<svg class="auth-icon" aria-hidden="true"><use href="auth-icons.svg#' + name + '"></use></svg>';
  const resetUsernameCheck = () => {
    usernameCheckVersion++; clearTimeout(usernameCheckTimer);
    checkedUsername = ''; usernameAvailable = null; usernameError = '';
  };
  const renderUsernameError = () => {
    const form = $('authForm'), input = form.querySelector('[name="username"]');
    if (form.dataset.mode !== 'register' || !input) return;
    input.setAttribute('aria-invalid', String(Boolean(usernameError)));
    const error = $('authField-username');
    error.textContent = usernameError; error.hidden = !usernameError;
  };
  const checkAuthUsername = async value => {
    clearTimeout(usernameCheckTimer);
    const form = $('authForm'), name = String(value ?? new FormData(form).get('username') ?? '').trim();
    if (!name || form.dataset.mode !== 'register') return false;
    if (name === checkedUsername && usernameAvailable !== null) { renderUsernameError(); return usernameAvailable; }
    const view = authViewVersion, version = ++usernameCheckVersion;
    try {
      const available = await get('/api/auth/username-availability?username=' + encodeURIComponent(name));
      if (view !== authViewVersion || version !== usernameCheckVersion || $('authPage').hidden
        || name !== String(new FormData(form).get('username') ?? '').trim()) return false;
      if (typeof available !== 'boolean') throw new Error('用户名暂时无法校验，请重试');
      checkedUsername = name; usernameAvailable = available;
      usernameError = available ? '' : '用户名已重复'; renderUsernameError();
      return available;
    } catch (error) {
      if (view === authViewVersion && version === usernameCheckVersion && !$('authPage').hidden) {
        usernameError = error.message || '用户名暂时无法校验，请重试'; renderUsernameError();
      }
      return false;
    }
  };
  // 图片校对码只在获取邮箱验证码时校验，最终提交不需要再次填写。
  const authInput = (label, name, placeholder, type = 'text', attributes = '', icon = 'user', required = name !== 'captchaCode') =>
    `<label class="field"><span>${label}</span><span class="auth-input">${authIcon(icon)}<input class="input" name="${name}" type="${type}" ${required ? 'required' : ''} placeholder="${placeholder}" ${attributes}></span></label>`;
  const PASSWORD_SYMBOLS = '!@#$%^&*._+-=?';
  const newPasswordError = value => !value || value.length < 6 || value.length > 64 ? '密码长度需为 6 至 64 位，请重新输入。'
    : /[^A-Za-z0-9!@#$%^&*._+=?\-]/.test(value) ? '密码仅支持数字、英文字母和 ' + PASSWORD_SYMBOLS + '，不含空格或其他字符。' : '';
  const updatePasswordFeedback = () => {
    if ($('authForm').dataset.mode !== 'register') return;
    const value = $('authPassword').value;
    const invalid = /[^A-Za-z0-9!@#$%^&*._+=?\-]/.test(value);
    const strength = !value || invalid ? 0 : value.length < 6 || !/[0-9]/.test(value) || !/[A-Za-z]/.test(value) ? 1 : /[!@#$%^&*._+=?\-]/.test(value) ? 3 : 2;
    $('authStrength').hidden = !value;
    $('authStrength').dataset.level = String(strength);
    $('authStrengthLabel').textContent = invalid ? '字符无效' : ['', '弱', '中', '强'][strength];
    $('authPasswordRules').hidden = document.activeElement !== $('authPassword');
  };
  const openAuth = (mode = 'login', route = 'push') => {
    if (!['login', 'email', 'register'].includes(mode)) mode = 'login';
    if ($('authPage').hidden) {
      authReturnFocus = document.activeElement;
      authReturnHash = authModeFromUrl() ? '' : window.location.hash;
    }
    const form = $('authForm'), previous = Object.fromEntries(new FormData(form).entries());
    authViewVersion++; authRequestVersion++; clearTimeout(updateCodeButton.timer);
    resetUsernameCheck();
    const registration = mode === 'register';
    const hash = registration ? '#/register' : '#/login' + (mode === 'email' ? '?method=email' : '');
    if (route !== 'none' && window.location.hash !== hash) window.history[route === 'replace' ? 'replaceState' : 'pushState']({authMode:mode}, '', hash);
    $('authTitle').textContent = registration ? '注册' : '登录';
    document.title = (registration ? '注册' : '登录') + ' · 简单外卖';
    $('authBack').textContent = registration ? '返回登录' : '返回浏览';
    $('authBack').dataset.action = registration ? 'auth-switch' : 'auth-close';
    $('authBack').dataset.id = 'login';
    $('authSuccess').textContent = ''; $('authSuccess').hidden = true;
    form.dataset.mode = mode;
    const phone = authInput('手机号', 'phone', '请输入 11 位手机号', 'tel', 'maxlength="11" pattern="1[0-9]{10}" autocomplete="tel"', 'phone');
    const email = authInput(registration ? '邮箱' : '绑定邮箱', 'email', '例如：name@example.com', 'email', 'maxlength="254" autocomplete="email"');
    const password = authInput('密码', 'password', registration ? '请输入 6 至 64 位密码' : '请输入密码', 'password',
      registration ? 'id="authPassword" minlength="6" maxlength="64" autocomplete="new-password" aria-describedby="authPasswordRules"' : 'autocomplete="current-password"', 'lock');
    const verification = `<div class="auth-captcha">${authInput('图片校对码', 'captchaCode', '输入右图 5 位字符', 'text', 'maxlength="5" autocomplete="off"')}<button class="btn captcha-image" type="button" data-action="captcha-refresh" aria-label="更换图片校对码"><img id="authCaptchaImage" alt="图片校对码" hidden><span id="authCaptchaLabel">点击加载</span></button><input type="hidden" name="captchaId"></div><div class="auth-code-row">${authInput('邮箱验证码', 'code', '请输入 6 位验证码', 'text', 'inputmode="numeric" pattern="[0-9]{6}" maxlength="6" autocomplete="one-time-code"')}<button class="btn" type="button" data-action="send-code">获取验证码</button></div><p id="authCodeStatus" class="help-text" role="status"></p>`;
    const roles = [['CUSTOMER','用户点餐','user'],['MERCHANT','商户管理','store'],['RIDER','骑手配送','rider'],['ADMIN','管理端','shield']];
    const selected = previous.loginType || 'CUSTOMER';
    const roleSelector = '<fieldset class="auth-roles"><legend>选择登录身份</legend><input type="hidden" name="loginType" value="' + esc(selected) + '"><div>' + roles.map(([role,label,icon]) => `<button type="button" class="auth-role" data-action="auth-role" data-id="${role}" aria-pressed="${role === selected}">${authIcon(icon)}${label}</button>`).join('') + '</div></fieldset>';
    const methods = '<div class="auth-tabs" aria-label="登录方式"><button class="btn ' + (mode === 'email' ? '' : 'active') + '" type="button" data-action="auth-switch" data-id="login" aria-pressed="' + (mode !== 'email') + '">密码登录</button><button class="btn ' + (mode === 'email' ? 'active' : '') + '" type="button" data-action="auth-switch" data-id="email" aria-pressed="' + (mode === 'email') + '">验证码登录</button></div>';
    form.innerHTML = '<div class="auth-fields">' + (registration
      ? authInput('用户名','username','例如：小王','text','maxlength="64" autocomplete="username"') + email + phone + verification + password
        + '<div class="auth-strength" id="authStrength" hidden aria-live="polite"><i></i><i></i><i></i><span id="authStrengthLabel"></span></div><p class="auth-rules" id="authPasswordRules" hidden>6 至 64 位，支持数字、英文字母和 ' + PASSWORD_SYMBOLS + '</p>'
        + authInput('确认密码','confirmPassword','请再次输入相同密码','password','id="authConfirmPassword" minlength="6" maxlength="64" autocomplete="new-password"','lock')
      : roleSelector + methods + phone + (mode === 'email' ? email + verification : password))
      + '</div><div class="form-actions"><button class="btn primary" type="submit">' + (registration ? '注册' : '登录') + authIcon('arrow') + '</button>'
      + (registration ? '' : '<button class="auth-link" type="button" data-action="auth-switch" data-id="register">还没有账号？去注册</button>') + '</div>';
    form.querySelectorAll('.field .input').forEach(input => {
      const label = input.closest('.field');
      label.insertAdjacentHTML('beforeend', '<span class="auth-field-error" id="authField-' + input.name + '" role="alert" hidden></span>');
      input.setAttribute('aria-describedby', ((input.getAttribute('aria-describedby') || '') + ' authField-' + input.name).trim());
    });
    for (const name of ['phone', 'email']) {
      const input = form.querySelector('[name="' + name + '"]');
      if (input && previous[name]) input.value = previous[name];
    }
    showAuthError(''); authVisibility(true);
    form.querySelector('input:not([type="hidden"])')?.focus();
    if (mode === 'email' || registration) { updateCodeButton(); void refreshAuthCaptcha(); }
  };
  const applyAuthRoute = () => {
    const mode = authModeFromUrl();
    if (mode && !state.token) {
      if ($('authPage').hidden || $('authForm').dataset.mode !== mode) openAuth(mode, 'none');
      return true;
    }
    if (!$('authPage').hidden || mode) closeAuth(Boolean(mode));
    return false;
  };
  window.addEventListener('popstate', applyAuthRoute);
  window.addEventListener('hashchange', applyAuthRoute);
  const updateCodeButton = () => {
    clearTimeout(updateCodeButton.timer);
    const button = $('authForm').querySelector('[data-action="send-code"]');
    if (!button || $('authPage').hidden) return;
    const email = $('authForm').querySelector('[name="email"]').value.trim().toLowerCase();
    const seconds = Math.max(0, Math.ceil(((emailCooldowns.get(email) || 0) - Date.now()) / 1000));
    button.disabled = button.dataset.sending === 'true' || seconds > 0;
    button.textContent = button.dataset.sending === 'true' ? '发送中…' : seconds > 0 ? seconds + ' 秒后重发' : '获取验证码';
    if (seconds > 0) updateCodeButton.timer = setTimeout(updateCodeButton, 1000);
  };
  const refreshAuthCaptcha = async () => {
    const view = authViewVersion, request = ++captchaVersion, form = $('authForm');
    const id = form.querySelector('[name="captchaId"]');
    if (!id) return;
    id.value = ''; form.querySelector('[name="captchaCode"]').value = '';
    $('authCaptchaImage').hidden = true; $('authCaptchaLabel').hidden = false; $('authCaptchaLabel').textContent = '加载中…';
    try {
      const result = await get('/api/auth/captcha');
      if (view !== authViewVersion || request !== captchaVersion || $('authPage').hidden) return;
      if (!result?.id || !/^data:image\/png;base64,[A-Za-z0-9+/=]+$/.test(result.image || '')) throw new Error('校对码加载失败，请点击图片重试');
      id.value = result.id; $('authCaptchaImage').src = result.image;
      $('authCaptchaImage').hidden = false; $('authCaptchaLabel').hidden = true;
    } catch (error) {
      if (view !== authViewVersion || request !== captchaVersion || $('authPage').hidden) return;
      $('authCaptchaLabel').textContent = '点击重试'; showAuthError(error.message, 'captchaCode');
    }
  };
  const sendAuthCode = async () => {
    const form = $('authForm'), version = authViewVersion, button = form.querySelector('[data-action="send-code"]');
    if (!button || button.disabled) return;
    showAuthError('');
    renderUsernameError();
    const data = Object.fromEntries(new FormData(form).entries());
    for (const name of [...(form.dataset.mode === 'register' ? ['username'] : []), 'phone', 'email']) {
      if (!form.querySelector('[name="' + name + '"]').reportValidity()) return;
    }
    if (!data.captchaId || !/^[A-Za-z0-9]{5}$/.test(data.captchaCode || '')) {
      showAuthError('请先输入图片中的 5 位校对码，再获取邮箱验证码。', 'captchaCode');
      form.querySelector('[name="captchaCode"]').focus(); return;
    }
    button.dataset.sending = 'true'; updateCodeButton();
    let requested = false;
    try {
      if (form.dataset.mode === 'register' && !await checkAuthUsername(data.username)) return;
      requested = true;
      const result = await send('/api/auth/email-code', 'POST', {phone:data.phone,email:data.email,purpose:form.dataset.mode === 'register' ? 'register' : 'signin',username:data.username || '',captchaId:data.captchaId,captchaCode:data.captchaCode});
      emailCooldowns.set(data.email.trim().toLowerCase(), Date.now() + 60000);
      if (version !== authViewVersion || $('authPage').hidden) return;
      $('authCodeStatus').textContent = result?.mock && result.code ? '开发模式验证码：' + result.code : '验证码已发送至邮箱，15 分钟内有效。';
      form.querySelector('[name="code"]').focus();
    } catch (error) {
      if (version === authViewVersion && !$('authPage').hidden) showAuthError(error.message);
    } finally {
      button.dataset.sending = 'false';
      if (version === authViewVersion && !$('authPage').hidden) { updateCodeButton(); if (requested) void refreshAuthCaptcha(); }
    }
  };
  const loginWith = async (payload, endpoint = '/api/auth/login') => {
    const requestVersion = ++authRequestVersion;
    const data = await send(endpoint, 'POST', payload);
    if (requestVersion !== authRequestVersion) return;
    resetAccountState(false);
    state.token = data.token; state.refreshToken = data.refreshToken || '';
    state.user = data.user; state.role = Number(data.user.role); state.page = state.role === 0 ? 'home' : state.role === 3 ? 'rider-pool' : 'overview';
    saveSession();
    closeAuth(); renderShell(); await Promise.all([loadCartCount(), renderPage()]);
  };
  const logout = async () => {
    const request = send('/api/auth/logout', 'POST', { refreshToken: state.refreshToken, pushToken: '' }).catch(() => {});
    resetAccountState(); renderShell(); await renderPage();
    toast('已退出登录');
    void request;
  };
  const requireUser = (message = '请先登录') => { if (!state.token) { openAuth(); toast(message); return false; } return true; };
  function renderShell() {
    applyTheme();
    updateCartCount();
    $('appLayout').classList.toggle('sidebar-collapsed', state.sidebarCollapsed);
    const toggle = $('sidebarToggle');
    const toggleLabel = state.sidebarCollapsed ? '展开侧边栏' : '收起侧边栏';
    toggle.setAttribute('aria-expanded', String(!state.sidebarCollapsed));
    toggle.setAttribute('aria-label', toggleLabel); toggle.title = toggleLabel;
    const logged = Boolean(state.user && state.token);
    $('topLogin').hidden = logged; $('topLogout').hidden = !logged; $('topCart').hidden = !logged || state.role !== 0;
    $('userMeta').textContent = logged ? `${state.user.username || state.user.phone} · ${['用户','商户','管理','骑手'][state.role] || '用户'}` : '';
    $('navCaption').textContent = logged ? ({ 0: '用户服务', 1: '商户工作台', 2: '平台管理', 3: '配送工作台' }[state.role] || '工作台') : '浏览';
    let nav = logged ? (NAV[state.role] || NAV[0]) : [['首页', 'home', '⌂'], ['搜索与榜单', 'discover', '⌕']];
    if (!logged && state.role === 0 && !nav.some(x => x[1] === 'home')) nav = NAV[0].slice(0, 2);
    $('nav').innerHTML = nav.map(([label, page, icon]) => `<button class="nav-item ${state.page === page ? 'active' : ''}" data-page="${page}" title="${esc(label)}" aria-label="${esc(label)}"><span class="nav-icon" aria-hidden="true">${icon}</span><span class="nav-label">${esc(label)}</span></button>`).join('');
    $('topCart').onclick = () => { if (requireUser()) navigate('cart'); };
    $('topLogin').onclick = () => openAuth(); $('topLogout').onclick = logout;
  }
  const updateCartCount = () => {
    const count = state.cart.reduce((sum, item) => sum + Number(item.quantity || 0), 0);
    $('cartCount').textContent = String(count);
    $('topCart').setAttribute('aria-label', `购物车，共 ${count} 件商品`);
    $('topCart').title = '';
  };
  const setCart = items => { state.cart = items || []; updateCartCount(); };
  const refreshCart = async (load = get) => {
    const token = state.token;
    const items = await load('/api/cart');
    if (token !== state.token) throw staleRender;
    setCart(items);
  };
  const loadCartCount = async () => {
    if (!state.user || state.role !== 0) return;
    const token = state.token;
    try { await refreshCart(); }
    catch (error) {
      if (error === staleRender || token !== state.token) return;
      $('cartCount').textContent = '—';
      $('topCart').title = '购物车数量加载失败，点击购物车重试';
      $('topCart').setAttribute('aria-label', $('topCart').title);
    }
  };
  const navigate = async (page) => {
    if (!['home', 'discover', 'store'].includes(page) && !requireUser()) return;
    const allowed = (NAV[state.role] || NAV[0]).some(item => item[1] === page);
    if (!allowed && page !== 'store' && page !== 'checkout') { toast('当前账号无此页面权限', true); return; }
    if (state.page === 'checkout' && page !== 'checkout') {
      captureCheckoutDraft(); state.checkoutReturnStoreId = state.checkoutStoreId; resetCheckoutIntent();
    }
    state.page = page; renderShell(); await renderPage(); window.scrollTo({ top: 0, behavior: 'smooth' });
  };
  let storeObserver = null;
  let visibleStoreCount = 0;
  let browseVersion = 0;
  const browseViews = [
    ['browse-all', '全部店铺', ''],
    ['rank-stores', '热销榜', '/api/rankings/stores?limit=50'],
    ['rank-goods', '热销菜品', '/api/rankings/goods?limit=20'],
    ['specials', '特价专区', '/api/goods/special?limit=20'],
    ['seckills', '限时秒杀', '/api/seckills?limit=20']
  ];
  const staleRender = Symbol('stale-render');
  const isCurrentRender = (version, page, role) =>
    version === renderVersion && page === state.page && role === state.role;
  const asyncContext = () => ({
    version: renderVersion, page: state.page, role: state.role, token: state.token,
    userId: Number(state.user?.id || 0)
  });
  const isCurrentContext = context => isCurrentRender(context.version, context.page, context.role)
    && context.token === state.token && context.userId === Number(state.user?.id || 0);
  const guarded = async (promise, context, connected = null) => {
    try {
      const result = await promise;
      if (!isCurrentContext(context) || (connected && !connected())) throw staleRender;
      return result;
    } catch (error) {
      if (!isCurrentContext(context) || (connected && !connected())) throw staleRender;
      throw error;
    }
  };
  const renderPage = async () => {
    closeRefundDialog();
    captureCheckoutDraft();
    const version = ++renderVersion;
    const page = state.page;
    const role = state.role;
    storeObserver?.disconnect(); storeObserver = null;
    state.locationVersion++; state.locating = false;
    const app = $('app'); app.innerHTML = empty('正在读取服务端数据…');
    const load = async path => {
      const data = await get(path);
      if (!isCurrentRender(version, page, role)) throw staleRender;
      return data;
    };
    try {
      if (page === 'erp' && state.user && [1,2].includes(role)) {
        const token=state.token;
        const stores=await load(role===1?'/api/merchant/stores':'/api/admin/stores');
        await TakeoutErp.mount({root:app,api,toast,role,ownerId:Number(state.user.id),stores:stores||[],live:()=>isCurrentRender(version,page,role) && state.token===token});
      }
      else if (role === 0 || !state.user) await renderCustomer(page, load);
      else if (role === 1) await renderMerchant(page, load);
      else if (role === 2) await renderAdmin(page, load);
      else if (role === 3) await renderRider(page, load);
      if (!isCurrentRender(version, page, role)) return;
      bindForms();
    } catch (error) {
      if (error === staleRender || !isCurrentRender(version, page, role)) return;
      app.innerHTML = `${pageHead(TITLES[page] || '工作台')}<div class="notice-line">${esc(error.message || '加载失败')}</div><div class="form-actions">${btn('重试', 'refresh')}</div>`;
    }
  };
  const renderCustomer = async (page, load = get) => {
    if (page === 'home' || page === 'discover') return renderBrowse(page, load);
    if (page === 'store') return renderStore(load);
    if (page === 'cart') return renderCart(load);
    if (page === 'checkout') return renderCheckout(load);
    if (page === 'orders') return renderOrders(load);
    if (page === 'perks') return renderPerks(load);
    if (page === 'account') return renderAccount(load);
    if (page === 'settings') return renderSettings(load);
    if (page === 'assistant') return renderAssistant();
  };
  const renderBrowse = async (page, load = get) => {
    ++browseVersion;
    const [categories, stores, banners, announcements] = await Promise.all([
      load('/api/categories'), load(page === 'discover' && state.search.trim() ? `/api/search?keyword=${encodeURIComponent(state.search.trim())}` : state.categoryId ? `/api/stores?categoryId=${state.categoryId}` : '/api/stores'),
      load('/api/banners').catch(error => error === staleRender ? Promise.reject(error) : []),
      load('/api/announcements').catch(error => error === staleRender ? Promise.reject(error) : [])
    ]);
    state.categories = categories || [];
    state.stores = (stores || []).filter(store => !state.categoryId || Number(store.categoryId) === state.categoryId || (store.categoryIds || []).map(Number).includes(state.categoryId));
    const shortcuts = `<div class="toolbar" id="browseShortcuts" role="group" aria-label="浏览专区">${browseViews.map(([action, label]) => `<button class="btn ${action === 'browse-all' ? 'primary' : ''}" type="button" data-action="${action}" aria-pressed="${action === 'browse-all'}">${label}</button>`).join('')}${state.user ? btn('优惠券','go','perks') : ''}</div>`;
    const bannersHtml = (banners || []).filter(b => b.status === 1).slice(0, 3).map(b => `<div class="surface"><strong>${esc(b.title)}</strong><div class="subtle">${esc(b.subtitle || '')}</div></div>`).join('');
    const annHtml = (announcements || []).filter(a => a.status === 1).slice(0, 3).map(a => `<div class="notice-line" style="margin-bottom:8px"><strong>${esc(a.title)}</strong> · ${esc(a.content)}</div>`).join('');
    $('app').innerHTML = `${pageHead(page === 'home' ? '全部店铺' : '发现好味道', '', `${state.user ? btn('我的订单','go','orders') : btn('登录点餐','login','','primary')}`)}${annHtml}${bannersHtml ? `<div class="grid section">${bannersHtml}</div>` : ''}<form class="toolbar section" id="storeSearchForm" role="search"><input class="input" id="storeSearch" name="keyword" aria-label="搜索店铺或菜品" placeholder="搜索店铺或菜品" value="${esc(state.search)}"><button class="btn primary" type="submit">搜索</button><select class="select" id="categoryFilter" aria-label="店铺分类" style="max-width:220px"><option value="0">全部分类</option>${state.categories.map(c => `<option value="${c.id}" ${Number(state.categoryId) === Number(c.id) ? 'selected' : ''}>${esc(c.name)}</option>`).join('')}</select></form>${shortcuts}<section class="section" id="browseResult" aria-label="浏览结果" aria-live="polite"></section><div class="grid" id="storeGrid"></div><div class="form-actions"><button class="btn" id="storeLoadMore" data-action="stores-more" type="button">加载更多店铺</button></div>`;
    $('storeGrid').insertAdjacentHTML('beforebegin', locationNotice() + secureLocationLink());
    $('storeSearchForm').onsubmit = async event => {
      event.preventDefault(); state.search = $('storeSearch').value.trim(); await navigate('discover');
    };
    $('categoryFilter').onchange = async (e) => { state.categoryId = Number(e.target.value); await renderPage(); };
    resetStoreCards();
  };
  const renderStoreCards = (stores) => (stores || []).map(s => `<article class="store-card"><div class="store-image">${storeImage(s)}</div><div class="store-body"><h3>${esc(s.name)}</h3><div class="subtle">★ ${Number(s.rating || 0).toFixed(1)} · 月售 ${Number(s.monthlySales || 0)} · ${esc(s.deliveryTime || '配送信息待更新')}</div><div class="tag-list">${(s.tags || []).slice(0,3).map(t=>`<span class="tag">${esc(t)}</span>`).join('')}</div><div class="row-between"><span class="subtle">起送 ¥${cash(s.minOrder)} · 配送 ¥${cash(s.deliveryFee)}</span><button class="btn small primary" data-action="open-store" data-id="${s.id}">进店</button></div></div></article>`).join('') || empty('暂时没有符合条件的店铺');
  const appendStoreCards = () => {
    const grid = $('storeGrid'), more = $('storeLoadMore');
    if (!grid || !more) return;
    const batch = state.stores.slice(visibleStoreCount, visibleStoreCount + 24);
    if (batch.length) grid.insertAdjacentHTML('beforeend', renderStoreCards(batch));
    else if (!visibleStoreCount) grid.innerHTML = empty('暂时没有符合条件的店铺');
    visibleStoreCount += batch.length;
    more.hidden = visibleStoreCount >= state.stores.length;
    more.textContent = `加载更多店铺（已显示 ${visibleStoreCount} / ${state.stores.length}）`;
    if (more.hidden) storeObserver?.disconnect();
  };
  const resetStoreCards = () => {
    storeObserver?.disconnect(); storeObserver = null;
    visibleStoreCount = 0; $('storeGrid').innerHTML = '';
    appendStoreCards();
    if ('IntersectionObserver' in window && !$('storeLoadMore').hidden) {
      const observer = new IntersectionObserver(entries => {
        if (storeObserver === observer && entries.some(entry => entry.isIntersecting)) appendStoreCards();
      }, { rootMargin: '400px' });
      storeObserver = observer; observer.observe($('storeLoadMore'));
    }
  };
  const renderStore = async (load = get) => {
    if (!state.storeId) { state.page = 'home'; return renderPage(); }
    const [store, goods, categories, reviews] = await Promise.all([load(`/api/stores/${state.storeId}`), load(`/api/stores/${state.storeId}/goods`), load(`/api/stores/${state.storeId}/categories`), load(`/api/stores/${state.storeId}/reviews`)]);
    state.goods = goods || [];
    $('app').innerHTML = `${pageHead(store.name, store.notice || store.address || '', `${btn('返回首页','go','home')} ${state.user ? btn('收藏店铺','favorite',store.id) : ''}`)}<div class="grid four"><div class="metric"><div class="metric-label">评分</div><div class="metric-value">★ ${Number(store.rating || 0).toFixed(1)}</div></div><div class="metric"><div class="metric-label">月售</div><div class="metric-value">${Number(store.monthlySales || 0)}</div></div><div class="metric"><div class="metric-label">配送费</div><div class="metric-value">¥${cash(store.deliveryFee)}</div></div><div class="metric"><div class="metric-label">起送价</div><div class="metric-value">¥${cash(store.minOrder)}</div></div></div><div class="section">${categories?.length ? `<div class="toolbar">${categories.map(c=>`<span class="tag">${esc(c.name)}</span>`).join('')}</div>`:''}<div class="page-panel">${state.goods.map(g=>`<div class="food-row"><div class="food-image">${g.image?`<img loading="lazy" decoding="async" src="${esc(assetURL(g.image))}" alt="">`:'食'}</div><div class="food-info"><h3>${esc(g.name)} ${g.special?'<span class="tag">特价</span>':''}</h3><p>${esc(g.description || g.tag || '今日推荐')} · 月售 ${g.sales || 0} · 库存 ${g.stock ?? '-'}</p><div class="price">¥${cash(g.price)} ${g.originalPrice>g.price?`<del class="subtle">¥${cash(g.originalPrice)}</del>`:''}</div></div><div class="food-actions">${(g.specs||[]).length?`<select class="select" data-spec-for="${g.id}" style="max-width:150px">${g.specs.map(s=>`<option value="${s.id}">${esc(s.name)} ¥${cash(s.price)}</option>`).join('')}</select>`:''}<button class="btn primary small" data-action="add-cart" data-id="${g.id}">加入购物车</button></div></div>`).join('') || empty('暂时没有上架商品')}</div></div><section class="section"><h2 class="section-title">顾客评价 (${reviews.length})</h2><div class="grid two">${reviews.slice(0,20).map(r=>`<div class="surface"><div class="row-between"><strong>${esc(r.userName || '顾客')}</strong><span class="rating">★ ${r.rating}</span></div><p>${esc(r.content || '')}</p><div class="subtle">${esc(r.createTime || '')}</div>${r.reply?`<div class="notice-line" style="margin-top:8px">商家回复：${esc(r.reply)}</div>`:''}</div>`).join('') || empty('暂无评价')}</div></section>`;
  };
  const renderCart = async (load = get) => {
    await refreshCart(load);
    const groups = Object.groupBy ? Object.groupBy(state.cart, x=>x.storeId) : state.cart.reduce((a,x)=>((a[x.storeId] ||= []).push(x),a),{});
    const total = state.cart.reduce((s,x)=>s+Number(x.price||0)*x.quantity,0);
    $('app').innerHTML = `${pageHead('购物车','')}${state.cart.length ? Object.values(groups).map(items=>`<section class="page-panel section"><div class="row-between"><h2 class="section-title">${esc(items[0].storeName)}</h2><span class="subtle">同一店铺商品一次结算</span></div>${items.map(x=>`<div class="cart-row"><div class="row-main"><strong>${esc(x.goods?.name || '商品')}</strong><small>${esc(x.specName||'')} · ¥${cash(x.price)}</small></div><div class="stepper"><button class="btn small" data-action="cart-dec" data-id="${x.goodsId}" data-spec="${x.specId||0}">−</button><b>${x.quantity}</b><button class="btn small" data-action="cart-inc" data-id="${x.goodsId}" data-spec="${x.specId||0}">+</button></div></div>`).join('')}<div class="form-actions">${btn('清空本店','cart-clear',items[0].storeId,'danger')} ${btn('去结算','checkout',items[0].storeId,'primary')}</div></section>`).join('') : empty('购物车为空，请先选择店铺和商品')}<div class="panel-foot"><strong>全部商品合计 ¥${cash(total)}</strong></div>`;
  };
  const renderCheckout = async (load = get) => {
    const existingDraft = state.checkoutStoreId ? checkoutDraft(state.checkoutStoreId) : null;
    if (!existingDraft?.submittedPayload) await refreshCart(load);
    const storeId = Number(state.checkoutStoreId || state.cart[0]?.storeId || 0);
    const draft = checkoutDraft(storeId);
    state.checkoutStoreId = storeId; state.checkoutIntentKey = draft.intentKey; state.checkoutIntentStoreId = storeId;
    const [addresses,coupons,store] = draft.submittedPayload
      ? [draft.viewData.addresses,draft.viewData.coupons,draft.viewData.store]
      : await Promise.all([load('/api/addresses'),load('/api/coupons'),load(`/api/stores/${storeId}`)]);
    state.addresses = addresses || []; state.coupons = coupons || [];
    const pending = Boolean(draft.submittedPayload);
    const data = pending ? draft.viewData : checkoutData(storeId,state.cart,state.addresses,state.coupons,store,draft);
    const {items,subtotal,deliveryFee,available} = data;
    if (!items.length) { state.checkoutView=null; $('app').innerHTML = `${pageHead('确认订单','',btn('返回购物车','go','cart'))} ${empty('该店铺的购物车商品已失效，请返回购物车重新选择')}`; return; }
    if (!pending && draft.signature && draft.signature !== data.signature) draft.reviewMessage ||= '商品、配送费、地址或优惠已变化。请核对清单与金额后再次提交。';
    draft.signature = data.signature; state.checkoutView = data;
    const amounts = checkoutAmounts(subtotal,deliveryFee,data.selectedCoupon?.amount||0);
    const unavailable = data.coupons.filter(c=>!couponEligible(c,storeId,subtotal,deliveryFee));
    const disabled = pending ? 'disabled' : '';
    const message = pending ? '上次提交结果尚未确认。请按原信息重试以核对结果，避免重复创建订单。' : draft.reviewMessage;
    $('app').innerHTML = `${pageHead('确认订单',`店铺：${items[0].storeName||store?.name||storeId}`,btn('返回购物车','go','cart'))}
      ${message?`<div class="notice-line section" role="status">${esc(message)}</div>`:''}
      <form id="checkoutForm" class="grid two"><section class="page-panel"><h2 class="section-title">收货方式</h2><p>外卖配送</p><h2 class="section-title">配送时间</h2><p>立即配送</p><p class="help-text">当前仅支持立即配送</p>
      <h2 class="section-title">收货地址</h2>${data.addresses.map(a=>`<label class="address-option ${Number(a.id)===draft.addressId?'selected':''}" style="display:block;margin:8px 0"><input type="radio" name="addressId" value="${a.id}" ${Number(a.id)===draft.addressId?'checked':''} ${disabled} required> <strong>${esc(a.name)} ${esc(a.phone)}</strong><div class="subtle" style="margin-left:23px">${esc(addressText(a))}</div></label>`).join('') || empty('请在“地址与钱包”添加收货地址')}
      <p class="help-text">下单前请为收货地址定位，配送距离按收货地址计算；超出商家配送范围无法下单。</p><button class="btn" type="button" data-action="go" data-id="account" ${disabled}>管理地址</button></section>
      <section class="page-panel"><h2 class="section-title">商品清单</h2>${items.map(x=>`<div class="row-between" style="padding:8px 0"><span>${esc(x.goods?.name)} ${x.specName?`· ${esc(x.specName)}`:''} × ${x.quantity}</span><strong>¥${cash(moneyCents(x.price)*Number(x.quantity)/100)}</strong></div>`).join('')}
      <div class="muted-sep"></div><label class="field">优惠券<select class="select" id="checkoutCoupon" ${disabled}><option value="0" ${!draft.couponId?'selected':''}>不使用</option>${available.map(c=>`<option value="${c.id}" ${Number(c.id)===draft.couponId?'selected':''}>${esc(c.name)} · 满${cash(c.threshold)}减${cash(c.amount)}</option>`).join('')}</select></label>
      <p class="help-text">${draft.couponManual&&!draft.couponId?'已保留“不使用优惠券”的选择，可随时改选。':available.length?'默认推荐本单可用券中预计实付最低的一张，可改选或不使用。':'本单暂无可用优惠券。'}</p>${unavailable.length?`<details><summary>${unavailable.length} 张券本单不可用</summary>${unavailable.map(c=>`<p class="help-text">${esc(c.name)}：${esc(couponUnavailableReason(c,storeId,subtotal,deliveryFee))}</p>`).join('')}</details>`:''}
      <div class="muted-sep"></div><div id="checkoutSummary" aria-live="polite"><div class="row-between"><span>商品小计</span><span>¥${cash(subtotal)}</span></div><div class="row-between"><span>配送费</span><span>¥${cash(deliveryFee)}</span></div><div class="row-between"><span>优惠券抵扣</span><span>-¥<b id="checkoutDiscount">${cash(amounts.discount)}</b></span></div><div class="row-between" style="margin-top:8px"><strong>预计应付</strong><strong>¥<span id="checkoutPayable">${cash(amounts.payable)}</span></strong></div><p class="help-text">预估金额，活动与最终金额以创建订单后的服务端计算为准，付款前可核对。优惠顺序：最优折扣→新客立减→优惠券；赠品门槛按折扣后商品金额。新客指本店首次成功支付，下单时占用名额，取消未支付订单释放。</p></div>
      <label class="field" style="margin-top:12px">给商家的备注<textarea class="textarea" id="checkoutRemark" maxlength="255" placeholder="例如：少辣、不放香菜" aria-describedby="checkoutRemarkHint" ${disabled}>${esc(draft.remark)}</textarea><span class="help-text" id="checkoutRemarkHint">仅供商家备餐参考，最多 255 字。收货地点请填写在地址中。</span></label><div class="form-actions"><button class="btn primary" id="checkoutSubmit" type="submit" data-store="${storeId}" ${state.checkoutSubmitting?'disabled':''}>${state.checkoutSubmitting?'提交中…':pending?'核对上次提交结果':draft.reviewMessage?'确认变更并提交待付款订单':'提交待付款订单'}</button></div></section></form>`;
    $('checkoutCoupon').value = String(draft.couponId); $('checkoutRemark').value = draft.remark;
    const updateSelection = event => {
      captureCheckoutDraft();
      draft.couponId = Number($('checkoutCoupon').value||0);
      if(!event || event.target?.id==='checkoutCoupon') draft.couponManual = true;
      const selected = data.available.find(c=>Number(c.id)===draft.couponId);
      data.selectedCoupon = selected; data.address = data.addresses.find(a=>Number(a.id)===draft.addressId);
      $('checkoutForm').querySelectorAll('[name="addressId"]').forEach(input=>input.closest('.address-option')?.classList.toggle('selected',input.checked));
      data.signature = checkoutSnapshot(data.items,data.store,data.address,selected); draft.signature = data.signature;
      const updated = checkoutAmounts(subtotal, deliveryFee, selected?.amount||0);
      $('checkoutDiscount').textContent = cash(updated.discount); $('checkoutPayable').textContent = cash(updated.payable);
    };
    $('checkoutCoupon').onchange = updateSelection;
    $('checkoutRemark').oninput = captureCheckoutDraft;
    $('checkoutForm').onchange = updateSelection;
    $('checkoutForm').onsubmit = async event => { event.preventDefault(); await handleAction('place-order','',$('checkoutSubmit')); };
  };
  const orderCard = (o, role = 'user') => {
    const actions = [];
    if (role === 'user') {
      actions.push(btn('退款记录','refund-history',o.id));
      if (canOrder(o,'PAY',o.status===0)) actions.push(btn('余额支付','pay',o.id,'primary'),btn('支付宝沙箱','alipay-pay',o.id),o.paymentChannel==='ALIPAY'&&o.outTradeNo?btn('查询支付','alipay-query',o.id):'');
      if (canOrder(o,'CANCEL',[0,1].includes(o.status))) actions.push(btn('取消订单','cancel-order',o.id));
      if (canOrder(o,'CONFIRM',o.status===4&&o.escrowStatus===0)) actions.push(btn('确认收到','confirm-order',o.id,'primary'));
      if (canRefund(o)) actions.push(btn('申请退款','refund',o.id));
      if (canOrder(o,'REVIEW',o.status===4&&o.escrowStatus===1&&!o.reviewed)) actions.push(btn('评价','review',o.id));
    }
    if (role === 'merchant') {
      actions.push(btn('售后记录与举证','refund-history',o.id));
      if (canOrder(o,'MERCHANT_REJECT',o.status===1)) actions.push(btn('无法接单','merchant-reject',o.id,'danger'));
      if (canOrder(o,'MERCHANT_ACCEPT',o.status===1)) actions.push(btn('接单','merchant-flow',o.id+':accept','primary'));
      if (canOrder(o,'MERCHANT_READY',o.status===2&&!o.readyTime)) actions.push(btn('出餐完成','merchant-flow',o.id+':ready','primary'));
      if (canOrder(o,'MERCHANT_DELIVER')) actions.push(btn('开始自配送','merchant-flow',o.id+':deliver','primary'));
      if (canOrder(o,'MERCHANT_COMPLETE')) actions.push(btn('自配送已送达','merchant-flow',o.id+':complete','primary'));
    }
    if (role === 'admin' && canOrder(o,'CANCEL',[1,2,3].includes(Number(o.status)))) actions.push(o.status===0?btn('平台取消','admin-cancel-order',o.id,'danger'):btn('平台退款','admin-refund-order',o.id,'danger'));
    if (role === 'rider') {
      if (canOrder(o,'RIDER_PICKUP',o.status===2)) actions.push(btn('确认取餐','rider-pickup',o.id,'primary'));
      if (canOrder(o,'RIDER_DELIVER',o.status===3)) actions.push(btn('送达','rider-deliver',o.id,'primary'));
    }
    if (['user','merchant','rider'].includes(role)) {
      actions.push(btn('配送异常记录','order-issues',o.id));
      if (canOrder(o,'REPORT_ISSUE',[1,2,3].includes(Number(o.status)))) actions.push(btn('上报配送异常','report-issue',o.id));
    }
    const riderCanSeeRecipient = role === 'rider' && [2,3].includes(Number(o.status));
    const recipientPhone = riderCanSeeRecipient ? String(o.address?.phone || '').trim() : '';
    const dialPhone = recipientPhone.replace(/[^\d+]/g, '');
    const destination = role === 'rider'
      ? riderCanSeeRecipient
        ? `<div><div class="td-actions"><strong>收货人：${esc(o.address?.name || '未填写')}</strong>${dialPhone?`<a class="btn small" href="tel:${esc(dialPhone)}">拨打 ${esc(recipientPhone)}</a>`:''}</div><div class="subtle">${esc(addressText(o.address) || '收货地址待补充')}</div><div class="td-actions">${addressText(o.address)?btn('复制收货地址','rider-copy-address',o.id):''}${o.storeId?btn('查看门店地址','rider-store-address',o.id):''}</div></div>`
        : '<span class="subtle">订单已结束，收货信息已隐藏</span>'
      : `<span>${esc(o.address?.detail || (o.deliveryType==='PICKUP'?'到店自取':''))}</span>`;
    const supportHint = role === 'user' && (o.status === 2 || o.status === 3)
      ? `<p class="help-text">${o.status===2?'订单已进入制作，如需处理请联系平台':'订单已进入配送，如需处理请联系平台'}</p>` : '';
    const merchantHint = role === 'merchant' && o.status === 2
      ? '<p class="help-text">制作中如有异常，请联系平台处理。</p>' : '';
    const riderHint = role === 'rider' && o.status === 2 ? '<p class="help-text">请前往门店，确认拿到餐品后再点“确认取餐”。</p>'
      : role === 'rider' && o.status === 3 ? '<p class="help-text">已取餐，请送往收货地址。交给用户或放到约定地点后再确认送达。</p>' : '';
    const rejectHint = role === 'user' && o.cancelSource === 'MERCHANT'
      ? `<div class="notice-line"><strong>商家未能接单</strong><div>${esc(o.cancelReason || '商家无法承接本次订单')}</div></div>` : '';
    const displayStatus = role==='rider' && o.status===2 ? '待取餐' : role==='rider' && o.status===3 ? '已取餐 · 配送中' : orderStatus(o);
    return `<article class="order-card"><div class="row-between"><div><strong>${esc(o.storeName || `订单 ${o.id}`)}</strong><div class="subtle">${esc(o.orderNo || o.id)} · ${esc(o.createTime || '')}</div></div>${statusTag(displayStatus,o.status===0?'warn':o.status===5?'bad':o.status===4?'good':'')}</div><div class="order-items">${(o.items||[]).map(i=>`${esc(i.goodsName || i.name)}${i.specName?` · ${esc(i.specName)}`:''} ×${i.quantity}`).join('、')}<div class="row-between" style="margin-top:8px">${destination}<strong>实付 ¥${cash(o.payAmount)}</strong></div>${o.capabilities?.fulfillmentMode?`<div>配送方式：${o.capabilities.fulfillmentMode==='MERCHANT'?'商家自配送':'骑手配送'}</div>`:''}${o.riderName?`<div>骑手：${esc(o.riderName)} ${esc(o.riderPhone||'')}</div>`:''}</div>${rejectHint}${supportHint}${merchantHint}${riderHint}${actions.length?`<div class="td-actions">${actions.join('')}</div>`:''}</article>`;
  };
  const adminOrdersHtml = () => {
    const query = state.adminOrderQuery.trim().toLowerCase();
    const orders = query ? state.adminOrders.filter(o => String(o.orderNo || o.id).toLowerCase().includes(query)) : state.adminOrders;
    return orders.map(o=>orderCard(o,'admin')).join('') || empty(query ? '当前页没有匹配订单' : '暂无订单');
  };
  const renderOrders = async (load = get) => { state.orders = await load('/api/orders') || []; $('app').innerHTML = `${pageHead('我的订单','')}<div class="toolbar"><button class="btn" data-action="refresh">刷新订单</button><select id="orderFilter" class="select" style="max-width:200px"><option value="">全部状态</option>${STATUS.map((s,i)=>`<option value="${i}">${s}</option>`).join('')}</select></div><div id="orderList">${state.orders.map(o=>orderCard(o)).join('') || empty('暂无订单')}</div>`; $('orderFilter').onchange=()=>{ const v=$('orderFilter').value; $('orderList').innerHTML=state.orders.filter(o=>v===''||o.status===Number(v)).map(o=>orderCard(o)).join('')||empty('没有匹配订单'); }; };
  const renderPerks = async (load = get) => {
    const [favs, coupons, activities] = await Promise.all([load('/api/favorites'),load('/api/coupons'),load('/api/coupons/activities')]); state.favorites=favs||[];state.coupons=coupons||[];
    $('app').innerHTML=`${pageHead('收藏与优惠券')}<div class="grid two"><section><h2 class="section-title">我的收藏</h2>${state.favorites.map(s=>`<article class="item-card row-between"><div><strong>${esc(s.name)}</strong><div class="subtle">★ ${Number(s.rating||0).toFixed(1)} · 月售 ${s.monthlySales||0}</div></div><div class="td-actions"><button class="btn small" data-action="open-store" data-id="${s.id}">进店</button><button class="btn small danger" data-action="favorite" data-id="${s.id}">取消收藏</button></div></article>`).join('')||empty('暂无收藏')}</section><section><h2 class="section-title">我的优惠券</h2>${state.coupons.map(c=>`<article class="item-card row-between"><div><strong>${esc(c.name)}</strong><div class="subtle">满 ¥${cash(c.threshold)} 减 ¥${cash(c.amount)} · ${esc(c.expireTime||'')}</div></div>${statusTag(c.status===0?'可使用':c.status===1?'已使用':'已失效',c.status===0?'good':'')}</article>`).join('')||empty('暂无优惠券')}<h2 class="section-title section">领券中心</h2>${(activities||[]).map(c=>`<article class="item-card row-between"><div><strong>${esc(c.name)}</strong><div class="subtle">满 ¥${cash(c.threshold)} 减 ¥${cash(c.amount)}</div></div><button class="btn small primary" data-action="claim-coupon" data-threshold="${c.threshold}" data-amount="${c.amount}">领取</button></article>`).join('')||empty('暂无可领优惠券')}</section></div>`;
  };
  const renderAccount = async (load = get) => {
    const [addresses,cards,user] = await Promise.all([load('/api/addresses'),load('/api/wallet/bank-cards'),load('/api/auth/me')]); state.addresses=addresses||[];state.user=user||state.user;
    $('app').innerHTML=`${pageHead('地址与钱包','',`${state.checkoutReturnStoreId?btn('继续确认订单','checkout',state.checkoutReturnStoreId,'primary'):''}${btn('刷新','refresh')}`)}<div class="grid two"><section><div class="row-between"><h2 class="section-title">收货地址</h2>${btn('新增地址','address-new')}</div>${state.editAddress!==null?addressForm(state.editAddress):''}${state.addresses.map(a=>`<article class="item-card"><div class="row-between"><strong>${esc(a.name)} · ${esc(a.phone)} ${a.tag?`<span class="tag">${esc(a.tag)}</span>`:''} ${a.isDefault?'<span class="tag">默认</span>':''}</strong><div class="td-actions">${!a.isDefault?btn('设为默认','address-default',a.id,'small'):''}${btn('编辑','address-edit',a.id,'small')}${btn('删除','address-delete',a.id,'small danger')}</div></div><div class="subtle" style="margin-top:6px">${esc(addressText(a))}</div></article>`).join('')||empty('暂无地址')}</section><section><h2 class="section-title">账户余额</h2><div class="metric"><div class="metric-label">可用余额</div><div class="metric-value">¥${cash(user?.balance)}</div><div class="subtle">可用于订单余额支付</div></div><p class="help-text">演示充值已停用，余额不足时请选择支付宝支付。</p><div class="row-between section"><h2 class="section-title">银行卡</h2>${btn('绑定银行卡','bank-add')}</div>${(cards||[]).map(c=>`<article class="item-card row-between"><div><strong>${esc(c.bankName)}</strong><div class="subtle">${esc(c.cardType)} · ${esc(c.cardNoMasked)}</div></div><div class="td-actions">${btn('查看卡号','bank-reveal',c.id,'small')}${btn('解绑','bank-delete',c.id,'small danger')}</div></article>`).join('')||empty('暂无绑定银行卡')}<p class="help-text">银行卡完整号码仅在添加时提交，服务端只返回掩码号码。</p></section></div>`;
  };
  const renderSettings = async (load = get) => { const user=await load('/api/auth/me');state.user=user; $('app').innerHTML=`${pageHead('个人设置')}<div class="grid two"><section class="page-panel"><h2 class="section-title">个人资料</h2><form data-form="profile" class="field-stack"><label class="field">用户名<input class="input" name="username" required value="${esc(user.username)}"></label><label class="field">手机号<input class="input" name="phone" required value="${esc(user.phone)}"></label><label class="field">邮箱<input class="input" name="email" type="email" value="${esc(user.email||'')}"></label><label class="field">当前密码验证<input class="input" name="currentPassword" type="password"></label><button class="btn primary">保存资料</button></form></section><section class="page-panel"><h2 class="section-title">账号安全</h2><form data-form="password" class="field-stack"><label class="field">当前密码<input class="input" name="oldPassword" type="password" required></label><label class="field">新密码<input class="input" name="newPassword" type="password" minlength="8" required></label><button class="btn primary">修改密码</button></form><div class="muted-sep"></div><form data-form="payment-password" class="field-stack"><label class="field">登录密码<input class="input" name="loginPassword" type="password" required></label><label class="field">支付密码（6 位数字）<input class="input" name="paymentPassword" type="password" inputmode="numeric" pattern="[0-9]{6}" required></label><button class="btn">设置支付密码</button></form><div class="muted-sep"></div><h2 class="section-title">隐私与协议</h2><details><summary>隐私政策</summary><p class="subtle">本演示应用将账号、地址、订单和购物车保存在项目服务端。仅用于体验，不要输入真实支付信息。</p></details></section></div>`; };
  const renderAssistant = () => { $('app').innerHTML=`${pageHead('智能客服','自动回答，退款与售后结果以订单状态为准')}<div class="page-panel"><div id="chatHistory" class="field-stack" style="min-height:220px;max-height:55vh;overflow:auto">${state.assistantHistory.map(m=>`<div class="surface"><strong>${m.role==='user'?'我':'智能助手'}</strong><div>${esc(m.content)}</div></div>`).join('')||empty('你好，有什么可以帮你？')}</div><form data-form="assistant" class="form-grid section"><label class="field full">输入问题<textarea class="textarea" name="question" required placeholder="例如：我的订单什么时候送达？"></textarea></label><div class="form-actions full"><button class="btn primary">发送</button></div></form></div>`; };
  const loadMerchantStores = async (load = get) => {
    state.merchantStores = await load('/api/merchant/stores') || [];
    if (!state.merchantStores.some(store => Number(store.id) === Number(state.activeStoreId))) {
      state.activeStoreId = Number(state.merchantStores[0]?.id || 0);
    }
  };
  const merchantStoreSelect = () => `<select class="select" id="merchantStoreSelect">${state.merchantStores.map(s=>`<option value="${s.id}" ${Number(s.id)===Number(state.activeStoreId)?'selected':''}>${esc(s.name)}</option>`).join('')}</select>`;
  const renderMerchant = async (page, load = get) => {
    if (page === 'after-sales-ledger') {
      const data = await load('/api/merchant/after-sales/ledger?page=' + state.ledgerPage + '&pageSize=20');
      const last = Math.max(1,Math.ceil(Number(data.total||0)/Number(data.pageSize||20)));
      if(state.ledgerPage>last){state.ledgerPage=last;return renderMerchant(page,load);}
      state.ledgerPage=Number(data.page||state.ledgerPage);
      $('app').innerHTML = pageHead('售后待偿账目','已结算售后按实际责任记账，骑手收入不扣回；余额不足部分记待偿债务',btn('刷新','refresh')) + '<div class="notice-line">当前待偿 ¥' + cash(data.debtAmount) + '</div>' + table(['退款/订单','商家承担','钱包已扣','本次记债','平台承担','时间'],(data.list||[]).map(row=>[esc(row.refundId)+' / '+esc(row.orderId),'¥'+cash(row.merchantAmount),'¥'+cash(row.walletDeducted),'¥'+cash(row.debtAmount),'¥'+cash(row.platformAmount),esc(row.createTime)])) + pagination('ledger-page',state.ledgerPage,Number(data.total||0),Boolean(data.hasMore)); return;
    }
    await loadMerchantStores(load);
    if (page === 'overview') {
      const stats = await load(`/api/merchant/stats?storeId=${state.activeStoreId || 0}`);
      $('app').innerHTML=`${pageHead('经营概况','门店营业和结算统计',state.merchantStores.length?merchantStoreSelect():'')}${!state.merchantStores.length?empty('账号尚未关联门店'):`<div class="grid four"><div class="metric"><div class="metric-label">今日订单</div><div class="metric-value">${stats.todayOrderCount ?? stats.todayCount ?? 0}</div></div><div class="metric"><div class="metric-label">今日收入</div><div class="metric-value">¥${cash(stats.todayIncome)}</div></div><div class="metric"><div class="metric-label">本月订单</div><div class="metric-value">${stats.monthOrderCount ?? stats.monthCount ?? 0}</div></div><div class="metric"><div class="metric-label">累计收入</div><div class="metric-value">¥${cash(stats.totalIncome)}</div></div></div><div class="grid two section"><div class="page-panel"><h2 class="section-title">今日订单状态</h2>${(stats.todayStatus||[]).map((n,i)=>`<div class="row-between" style="padding:8px 0"><span>${['待接单','制作中','配送中','已完成','已取消'][i]||`状态${i}`}</span><strong>${n}</strong></div>`).join('')}</div><div class="page-panel"><h2 class="section-title">经营入口</h2><div class="toolbar">${btn('处理新订单','go','merchant-orders','primary')} ${btn('管理商品','go','catalog')} ${btn('查看评价','go','reviews')}</div></div></div>`}`;
      $('merchantStoreSelect')?.addEventListener('change',e=>{state.activeStoreId=Number(e.target.value);renderPage();}); return;
    }
    if (page === 'merchant-orders') {
      const orders = await load('/api/merchant/orders') || [];
      state.merchantOrders = orders;
      $('app').innerHTML=`${pageHead('订单处理','骑手配送单出餐后进入待取餐池；商家自配送单出餐后由商家开始配送、确认送达')}${orders.map(o=>orderCard(o,'merchant')).join('')||empty('暂无待处理订单')}`; return;
    }
    if (page === 'catalog') {
      if (!state.merchantStores.length) { $('app').innerHTML=`${pageHead('门店与商品')}<div class="page-panel"><h2 class="section-title">创建门店</h2>${merchantStoreForm()}</div>`; return; }
      const [goods,cats] = await Promise.all([load(`/api/merchant/stores/${state.activeStoreId}/goods`),load('/api/merchant/categories')]); state.merchantGoods=goods||[];
      const editingStore = state.merchantStoreEdit || null;
      $('app').innerHTML=`${pageHead('门店与商品','管理商品上下架、库存、规格和店内分类',`${merchantStoreSelect()} ${btn('新增门店','merchant-store-new')}`)}${state.editGoods==='store'||editingStore?`<div class="page-panel section"><h2 class="section-title">${editingStore?'编辑门店':'创建门店'}</h2>${merchantStoreForm(editingStore)}</div>`:''}<div class="toolbar">${btn('新增商品','merchant-goods-new','', 'primary')} ${btn('店内分类','merchant-categories')} ${btn('套餐管理','merchant-setmeals')} ${btn('门店员工','merchant-employees')} ${btn('编辑门店','merchant-store-edit',state.activeStoreId)} ${btn('配送方式','merchant-fulfillment',state.activeStoreId)}</div>${state.editGoods&&state.editGoods!=='store'?merchantGoodsForm(state.editGoods,cats||[]):''}<div class="table-wrap"><table><thead><tr><th>商品</th><th>分类</th><th>售价</th><th>库存</th><th>销量</th><th>状态</th><th>操作</th></tr></thead><tbody>${state.merchantGoods.map(g=>`<tr><td><strong>${esc(g.name)}</strong><div class="subtle">${esc(g.description||'')}</div></td><td>${esc((cats||[]).find(c=>c.id===g.merchantCategoryId)?.name||'未分组')}</td><td>¥${cash(g.price)}</td><td>${g.stock}</td><td>${g.sales}</td><td>${statusTag(g.status===1?'上架':'下架',g.status===1?'good':'warn')}</td><td><div class="td-actions">${btn('编辑','merchant-goods-edit',g.id,'small')}${btn('规格','merchant-goods-specs',g.id,'small')}${btn(g.status===1?'下架':'上架','merchant-goods-toggle',g.id,'small')}${btn('删除','merchant-goods-delete',g.id,'small danger')}</div></td></tr>`).join('')||'<tr><td colspan="7">暂无商品</td></tr>'}</tbody></table></div>`;
      $('merchantStoreSelect')?.addEventListener('change',e=>{state.activeStoreId=Number(e.target.value);state.editGoods=null;renderPage();}); return;
    }
    if (page === 'reviews') {
      state.merchantReviews=await load('/api/merchant/reviews')||[];
      $('app').innerHTML=`${pageHead('评价回复','')}${state.merchantReviews.map(r=>`<article class="item-card"><div class="row-between"><strong>${esc(r.userName||'用户')} · ${esc(r.storeName||'门店')}</strong><span class="rating">★ ${r.rating}</span></div><p>${esc(r.content)}</p><div class="subtle">${esc(r.createTime||'')} ${r.anonymous?'· 匿名':''}</div>${r.reply?`<div class="notice-line" style="margin:10px 0">当前回复：${esc(r.reply)}</div>`:''}<form data-form="merchant-reply" data-id="${r.id}" class="toolbar" style="margin-top:10px"><input class="input" name="reply" required placeholder="填写商家回复" value="${esc(r.reply||'')}"><button class="btn primary small">${r.reply?'更新回复':'回复'}</button></form></article>`).join('')||empty('暂无待回复评价')}`; return;
    }
    if (page === 'marketing') {
      if (!state.merchantStores.length) { $('app').innerHTML=`${pageHead('营销活动')}${empty('先创建门店')}`; return; }
      const [activities,seckills]=await Promise.all([load(`/api/merchant/activities?storeId=${state.activeStoreId}`),load(`/api/merchant/seckills?storeId=${state.activeStoreId}`)]);
      state.merchantActivities=activities||[];state.merchantSeckills=seckills||[];
      $('app').innerHTML=`${pageHead('营销活动','最优折扣→新客立减→优惠券；满赠按折扣后商品金额。新客为本店首次成功支付，下单占用，取消未支付释放',merchantStoreSelect())}<div class="grid two"><section><div class="row-between"><h2 class="section-title">优惠活动</h2>${btn('新增活动','merchant-activity-new','','small primary')}</div>${state.editGoods==='activity'?activityForm():''}${state.merchantActivities.map(a=>`<article class="item-card"><div class="row-between"><strong>${esc(a.title)}</strong>${statusTag(a.status?'进行中':'已暂停',a.status?'good':'warn')}</div><div class="subtle">${esc(MARKETING_LABELS[a.type] || '其他活动')} · ${esc(a.startTime)} 至 ${esc(a.endTime)}</div><div class="td-actions" style="margin-top:8px">${btn(a.status?'暂停':'启用','merchant-activity-status',a.id,'small')}${btn('删除','merchant-activity-delete',a.id,'small danger')}</div></article>`).join('')||empty('暂无活动')}</section><section><div class="row-between"><h2 class="section-title">限时秒杀</h2>${btn('新增秒杀','merchant-seckill-new','','small primary')}</div>${state.editGoods==='seckill'?seckillForm():''}${state.merchantSeckills.map(s=>`<article class="item-card"><strong>商品 #${s.goodsId} · ¥${cash(s.price)}</strong><div class="subtle">名额 ${s.sold}/${s.quota} · ${esc(s.startTime)} 至 ${esc(s.endTime)}</div><div class="td-actions" style="margin-top:8px">${btn(s.status?'暂停':'启用','merchant-seckill-status',s.id,'small')}${btn('删除','merchant-seckill-delete',s.id,'small danger')}</div></article>`).join('')||empty('暂无秒杀')}</section></div>`;
      $('merchantStoreSelect')?.addEventListener('change',e=>{state.activeStoreId=Number(e.target.value);state.editGoods=null;renderPage();}); return;
    }
  };
  const merchantStoreForm = (store = null) => `<form data-form="merchant-store" data-id="${store?.id||0}" class="form-grid"><label class="field">店铺名称<input class="input" name="name" required value="${esc(store?.name||'')}"></label><label class="field">平台分类 ID<input class="input" name="categoryId" type="number" required value="${store?.categoryId||1}"></label><label class="field">配送费<input class="input" name="deliveryFee" type="number" step="0.1" value="${store?.deliveryFee||0}"></label><label class="field">起送价<input class="input" name="minOrder" type="number" step="1" value="${store?.minOrder||0}"></label><label class="field">预计配送时间<input class="input" name="deliveryTime" value="${esc(store?.deliveryTime||'30分钟')}" required></label><label class="field">配送半径（米）<input class="input" name="deliveryRadius" type="number" value="${store?.deliveryRadius||25000}"></label><label class="field full">地址<input class="input" name="address" value="${esc(store?.address||'')}" required></label><label class="field">纬度<input class="input" name="latitude" type="number" step="any" value="${store?.latitude||0}"></label><label class="field">经度<input class="input" name="longitude" type="number" step="any" value="${store?.longitude||0}"></label><label class="field full">公告<input class="input" name="notice" value="${esc(store?.notice||'欢迎光临')}"></label><label class="field full">图片 URL<input class="input" name="image" value="${esc(store?.image||'')}" placeholder="/uploads/... 或完整 URL"></label><div class="form-actions full"><button class="btn primary">保存门店</button></div></form>`;
  const merchantGoodsForm = (g = null, cats = []) => `<form data-form="merchant-goods" data-id="${g?.id||0}" class="inline-form"><div class="form-grid"><label class="field">商品名称<input class="input" name="name" required value="${esc(g?.name||'')}"></label><label class="field">价格<input class="input" name="price" type="number" step="0.01" required value="${g?.price||0}"></label><label class="field">原价<input class="input" name="originalPrice" type="number" step="0.01" value="${g?.originalPrice||g?.price||0}"></label><label class="field">库存<input class="input" name="stock" type="number" value="${g?.stock||0}"></label><label class="field">平台分类 ID<input class="input" name="categoryId" type="number" value="${g?.categoryId||1}"></label><label class="field">店内分类<select class="select" name="merchantCategoryId"><option value="0">未分组</option>${cats.map(c=>`<option value="${c.id}" ${Number(g?.merchantCategoryId)===Number(c.id)?'selected':''}>${esc(c.name)}</option>`).join('')}</select></label><label class="field">标签<input class="input" name="tag" value="${esc(g?.tag||'')}"></label><label class="field">图片 URL<input class="input" name="image" value="${esc(g?.image||'')}"></label><label class="field full">描述<input class="input" name="description" value="${esc(g?.description||'')}"></label><label><input type="checkbox" name="special" ${g?.special?'checked':''}> 特价商品</label><div class="form-actions full"><button class="btn primary">${g?'保存商品':'创建商品'}</button><button class="btn" type="button" data-action="merchant-goods-form-close">取消</button></div></div></form>`;
  const activityForm = () => `<form data-form="merchant-activity" class="inline-form"><div class="form-grid"><label class="field">活动类型<select class="select" name="type"><option value="DISCOUNT">折扣</option><option value="NEW_USER">新客立减</option><option value="GIFT">满赠</option></select></label><label class="field">标题<input class="input" name="title" required></label><label class="field">折扣率<input class="input" name="discountRate" type="number" step="0.01" value="0.9"></label><label class="field">立减金额<input class="input" name="reduceAmount" type="number" step="0.01" value="0"></label><label class="field">满赠门槛<input class="input" name="threshold" type="number" value="0"></label><label class="field">赠品商品 ID<input class="input" name="giftGoodsId" type="number" value="0"></label><label class="field">开始时间<input class="input" name="startTime" placeholder="2026-10-19 18:00:00" required></label><label class="field">结束时间<input class="input" name="endTime" placeholder="2026-10-20 18:00:00" required></label><div class="form-actions full"><button class="btn primary">创建活动</button><button class="btn" type="button" data-action="merchant-goods-form-close">取消</button></div></div></form>`;
  const seckillForm = () => `<form data-form="merchant-seckill" class="inline-form"><div class="form-grid"><label class="field">商品 ID<input class="input" name="goodsId" type="number" required></label><label class="field">秒杀价<input class="input" name="price" type="number" step="0.01" required></label><label class="field">活动名额<input class="input" name="quota" type="number" required></label><label class="field">开始时间<input class="input" name="startTime" placeholder="2026-10-19 18:00:00" required></label><label class="field">结束时间<input class="input" name="endTime" placeholder="2026-10-20 18:00:00" required></label><div class="form-actions full"><button class="btn primary">创建秒杀</button><button class="btn" type="button" data-action="merchant-goods-form-close">取消</button></div></div></form>`;
  const renderRider = async (page, load = get) => {
    if (page === 'rider-profile') {
      state.rider = await load('/api/rider/profile'); const r=state.rider;
      $('app').innerHTML=`${pageHead('骑手资料','在线状态将影响是否可以抢单')}${!r?empty('暂时无法读取骑手资料'):`<div class="grid four"><div class="metric"><div class="metric-label">配送状态</div><div class="metric-value">${r.online?'在线':'离线'}</div><button class="btn ${r.online?'danger':'primary'}" style="margin-top:10px" data-action="rider-online" data-id="${r.online?0:1}">${r.online?'下线':'上线'}</button></div><div class="metric"><div class="metric-label">已完成配送</div><div class="metric-value">${r.totalOrders||0}</div></div><div class="metric"><div class="metric-label">累计配送收入</div><div class="metric-value">¥${cash(r.totalIncome)}</div></div><div class="metric"><div class="metric-label">账号状态</div><div class="metric-value">${r.status===1?'正常':'停用'}</div></div></div><div class="page-panel section"><h2 class="section-title">接单范围</h2><form data-form="rider-settings" class="form-grid"><label class="field">配送半径（米）<input class="input" name="radiusMeters" type="number" min="1000" max="100000" value="${r.deliveryRadius||25000}"></label><label class="field">接单位置<input class="input" name="address" value="${esc(r.locationAddress||'')}"></label><label class="field">纬度<input class="input" name="latitude" type="number" step="any" value="${r.latitude||0}"></label><label class="field">经度<input class="input" name="longitude" type="number" step="any" value="${r.longitude||0}"></label><div class="form-actions full"><button class="btn primary">保存接单范围</button></div></form></div>`}`; return;
    }
    if (page === 'rider-pool') {
      const [profile,pool]=await Promise.all([load('/api/rider/profile'),load('/api/rider/orders/pool')]); state.rider=profile;state.riderPool=pool||[];
      $('app').innerHTML=`${pageHead('待抢订单',profile?.online?'只显示配送范围内可抢订单':'请先上线后查看可抢订单',btn('刷新','refresh'))}${!profile?.online?`<div class="notice-line">当前处于离线状态。${btn('立即上线','rider-online','1','primary')}</div>`:(pool||[]).map(o=>`<article class="order-card"><div class="row-between"><div><strong>${esc(o.storeName)}</strong><div class="subtle">抢单后可查看收货地址 · ${esc(o.createTime||'')}</div></div><strong>配送费 ¥${cash(o.deliveryFee)}</strong></div><div class="order-items">收货人、电话和完整门牌将在抢单成功后显示。</div>${canOrder(o,'RIDER_GRAB',true)?btn('抢单','rider-grab',o.id,'primary'):''}</article>`).join('')||empty('当前没有可抢订单')}`; return;
    }
    if (page === 'rider-orders') {
      state.riderOrders=await load('/api/rider/orders')||[];
      $('app').innerHTML=`${pageHead('配送订单','抢单、取餐和送达状态与用户订单即时共享',btn('刷新','refresh'))}${state.riderOrders.map(o=>orderCard(o,'rider')).join('')||empty('暂无配送订单')}`; return;
    }
  };
  const renderAdmin = async (page, load = get) => {
    if (page === 'delivery-issues') {
      const data = await load('/api/admin/delivery-issues?status=' + state.deliveryIssueFilter + '&page=' + state.deliveryIssuesPage + '&pageSize=30');
      const last = Math.max(1,Math.ceil(Number(data.total||0)/Number(data.pageSize||30)));
      if(state.deliveryIssuesPage>last){state.deliveryIssuesPage=last;return renderAdmin(page,load);}
      state.deliveryIssues=data.list||[];state.deliveryIssuesPage=Number(data.page||state.deliveryIssuesPage);
      $('app').innerHTML = pageHead('配送异常','改派仅限骑手取餐前；继续履约或取消均保留处理记录',btn('刷新','refresh')) + '<div class="toolbar">' + [['OPEN','待处理'],['RESOLVED','已处理'],['ALL','全部']].map(([code,label])=>btn(label,'delivery-issue-filter',code,state.deliveryIssueFilter===code?'primary':'')).join('') + '</div>' + state.deliveryIssues.map(issue=>issueDetails(issue)+(issue.status==='OPEN'?'<div class="toolbar">'+btn('改派','resolve-issue',issue.id+':REASSIGN')+btn('继续履约','resolve-issue',issue.id+':RESUME')+btn('取消订单','resolve-issue',issue.id+':CANCEL','danger')+'</div>':'')).join('') + (state.deliveryIssues.length?'':empty('暂无配送异常')) + pagination('delivery-issues-page',state.deliveryIssuesPage,Number(data.total||0),Boolean(data.hasMore)); return;
    }
    if (page === 'overview') {
      const d=await load('/api/admin/dashboard'); const m=d?.statistics||d?.overview||d||{};
      $('app').innerHTML=`${pageHead('平台总览','',btn('刷新','refresh'))}<div class="grid four">${[['用户',m.totalUsers],['商户',m.totalMerchants],['店铺',m.totalStores],['商品',m.totalGoods],['累计订单',m.totalOrders],['累计 GMV',`¥${cash(m.totalGmv)}`],['今日订单',m.todayOrders],['待结算托管',`¥${cash(m.pendingEscrowAmount)}`]].map(([l,v])=>`<div class="metric"><div class="metric-label">${l}</div><div class="metric-value">${v??'--'}</div></div>`).join('')}</div><div class="grid two section"><div class="page-panel"><h2 class="section-title">快捷管理</h2><div class="toolbar">${btn('店铺审核','go','stores')} ${btn('退款审批','go','refunds')} ${btn('全平台订单','go','admin-orders')}</div></div><div class="page-panel"><h2 class="section-title">热门商品</h2>${(m.hotGoods||[]).slice(0,6).map(g=>`<div class="row-between" style="padding:7px 0"><span>${esc(g.goodsName)} · ${esc(g.storeName)}</span><strong>销量 ${g.sales}</strong></div>`).join('')||empty('暂无统计')}</div></div>`; return;
    }
    if (page === 'categories') {
      state.adminCategories=await load('/api/admin/categories')||[];
      $('app').innerHTML=`${pageHead('分类管理','',btn('新增分类','admin-category-new','','primary'))}${state.editGoods==='category'?`<form class="inline-form" data-form="admin-category"><div class="form-grid"><label class="field">分类名称<input class="input" name="name" required></label><label class="field">图标<input class="input" name="icon" value="🍽️"></label><label class="field">颜色<input class="input" name="color" value="#C74B1B"></label><div class="form-actions"><button class="btn primary">保存</button></div></div></form>`:''}<div class="table-wrap"><table><thead><tr><th>ID</th><th>名称</th><th>图标</th><th>类型</th><th>操作</th></tr></thead><tbody>${state.adminCategories.map(c=>`<tr><td>${c.id}</td><td>${esc(c.name)}</td><td>${esc(c.icon||'')}</td><td>${esc(c.type||'平台')}</td><td>${btn('删除','admin-category-delete',c.id,'small danger')}</td></tr>`).join('')||'<tr><td colspan="5">暂无分类</td></tr>'}</tbody></table></div>`; return;
    }
    if (page === 'stores') {
      state.adminStores=await load('/api/admin/stores')||[];
      $('app').innerHTML=`${pageHead('店铺审核','控制店铺营业状态与首页推荐')}${table(['店铺','分类','评分 / 月售','状态','推荐','操作'],state.adminStores.map(s=>[`<strong>${esc(s.name)}</strong><div class="subtle">${esc(s.address||'')}</div>`,esc(s.categoryName||s.categoryId),`${s.rating} / ${s.monthlySales}`,statusTag(s.status?'营业中':'已下架',s.status?'good':'warn'),s.recommended?'是':'否',`${btn(s.status?'下架':'通过','admin-store-status',`${s.id}:${s.status?0:1}`,'small')} ${btn(s.recommended?'取消推荐':'设为推荐','admin-store-recommend',`${s.id}:${s.recommended?0:1}`,'small')}`]))}`; return;
    }
    if (page === 'admin-orders') {
      const data=await load(`/api/admin/orders/page?page=${state.adminOrdersPage}&pageSize=20`);const total=Number(data?.total||0);const pageSize=Number(data?.pageSize||20);const lastPage=Math.max(1,Math.ceil(total/pageSize));
      if(state.adminOrdersPage>lastPage){state.adminOrdersPage=lastPage;return renderAdmin(page,load);}
      state.adminOrders=data?.list||[];state.adminOrdersPage=Number(data?.page||state.adminOrdersPage);state.adminOrdersTotal=total;state.adminOrdersHasMore=Boolean(data?.hasMore);
      $('app').innerHTML=`${pageHead('全平台订单','',btn('刷新','refresh'))}<div class="toolbar"><label class="field">筛选当前页订单号<input class="input" id="adminOrderFilter" value="${esc(state.adminOrderQuery)}" placeholder="输入订单号，仅筛选当前页"></label></div><div id="adminOrderList">${adminOrdersHtml()}</div>${pagination('admin-orders-page',state.adminOrdersPage,state.adminOrdersTotal,state.adminOrdersHasMore)}`;
      $('adminOrderFilter').oninput=e=>{state.adminOrderQuery=e.target.value;$('adminOrderList').innerHTML=adminOrdersHtml();};return;
    }
    if (page === 'refunds') {
      const status=state.adminRefundFilter?`status=${state.adminRefundFilter}&`:'';const data=await load(`/api/admin/refunds/page?${status}page=${state.adminRefundsPage}&pageSize=20`);const total=Number(data?.total||0);const pageSize=Number(data?.pageSize||20);const lastPage=Math.max(1,Math.ceil(total/pageSize));
      if(state.adminRefundsPage>lastPage){state.adminRefundsPage=lastPage;return renderAdmin(page,load);}
      state.adminRefunds=data?.list||[];state.adminRefundsPage=Number(data?.page||state.adminRefundsPage);state.adminRefundsTotal=total;state.adminRefundsHasMore=Boolean(data?.hasMore);
      $('app').innerHTML=`${pageHead('退款审批','先核对申请详情，再决定是否退款；处理结果同步给用户')}<div class="tabs"><button class="tab ${state.adminRefundFilter==='PENDING'?'active':''}" data-action="admin-refund-filter" data-id="PENDING">待审批</button><button class="tab ${state.adminRefundFilter===''?'active':''}" data-action="admin-refund-filter" data-id="ALL">全部</button></div><div class="table-wrap section"><table><thead><tr><th>退款单</th><th>订单</th><th>原因</th><th>金额</th><th>处理结果</th><th>时间</th><th>操作</th></tr></thead><tbody>${state.adminRefunds.map(r=>`<tr><td>${r.id}</td><td>${r.orderId}</td><td>${esc(REFUND_REASONS[r.reasonType]||r.reasonType||'其他原因')}<div class="subtle">${esc(r.reason||'未填写补充说明')}</div></td><td>¥${cash(r.amount)}</td><td>${esc(refundStatus(r))}${r.rejectReason?`<div class="subtle">拒绝原因：${esc(r.rejectReason)}</div>`:''}</td><td><div>申请：${esc(r.applyTime||'暂无记录')}</div><div class="subtle">处理：${esc(r.processTime||'尚未处理')}</div></td><td>${r.status==='PENDING'?`${btn('核对并同意','refund-approve',r.id,'small primary')} ${btn('核对并拒绝','refund-reject',r.id,'small danger')}`:'-'}</td></tr>`).join('')||'<tr><td colspan="7">暂无退款申请</td></tr>'}</tbody></table></div>${pagination('admin-refunds-page',state.adminRefundsPage,state.adminRefundsTotal,state.adminRefundsHasMore)}`;return;
    }
    if (page === 'users') {
      const [users,products]=await Promise.all([load('/api/admin/users/page?page=1&pageSize=100'),load('/api/admin/products?page=1&pageSize=100')]);state.adminUsers=users?.list||[];state.adminProducts=products?.list||[];
      $('app').innerHTML=`${pageHead('用户与商品管理')}<div class="tabs"><button class="tab active" data-action="admin-subtab" data-id="users">用户</button><button class="tab" data-action="admin-subtab" data-id="products">商品</button></div><section id="adminSubtab" class="section">${adminUsersTable()}</section>`;return;
    }
    if (page === 'riders') {
      state.adminRiders=await load('/api/admin/riders')||[];
      $('app').innerHTML=`${pageHead('骑手管理','启停账号，骑手上线状态由骑手端自己维护')}<div class="table-wrap"><table><thead><tr><th>骑手</th><th>手机号</th><th>配送状态</th><th>累计单量</th><th>累计收入</th><th>账号</th><th>操作</th></tr></thead><tbody>${state.adminRiders.map(r=>`<tr><td>${esc(r.name)}</td><td>${esc(r.phone)}</td><td>${r.online?'在线':'离线'}</td><td>${r.totalOrders}</td><td>¥${cash(r.totalIncome)}</td><td>${r.status?'启用':'停用'}</td><td>${btn(r.status?'停用':'启用','admin-rider-status',`${r.id}:${r.status?0:1}`,'small')}</td></tr>`).join('')||'<tr><td colspan="7">暂无骑手</td></tr>'}</tbody></table></div>`;return;
    }
    if (page === 'content') {
      const [banners,ann]=await Promise.all([load('/api/admin/banners'),load('/api/admin/announcements')]);state.adminBanners=banners||[];state.adminAnnouncements=ann||[];
      $('app').innerHTML=`${pageHead('内容管理','管理首页轮播和公告')}<div class="grid two"><section><div class="row-between"><h2 class="section-title">轮播 Banner</h2>${btn('新增 Banner','admin-banner-new','','small primary')}</div>${state.editGoods==='banner'?bannerForm():''}${state.adminBanners.map(b=>`<article class="item-card row-between"><div><strong>${esc(b.title)}</strong><div class="subtle">${esc(b.subtitle||'')}</div></div><div class="td-actions">${btn(b.status?'下架':'发布','admin-banner-status',`${b.id}:${b.status?0:1}`,'small')}${btn('删除','admin-banner-delete',b.id,'small danger')}</div></article>`).join('')||empty('暂无 Banner')}</section><section><div class="row-between"><h2 class="section-title">公告</h2>${btn('新增公告','admin-announcement-new','','small primary')}</div>${state.editGoods==='announcement'?announcementForm():''}${state.adminAnnouncements.map(a=>`<article class="item-card"><div class="row-between"><strong>${esc(a.title)}</strong><div class="td-actions">${btn(a.status?'下架':'发布','admin-announcement-status',`${a.id}:${a.status?0:1}`,'small')}${btn('删除','admin-announcement-delete',a.id,'small danger')}</div></div><div class="subtle">${esc(a.content)}</div></article>`).join('')||empty('暂无公告')}</section></div>`;return;
    }
    if (page === 'employees') {
      state.adminEmployees=await load('/api/admin/employees')||[];
      $('app').innerHTML=`${pageHead('员工管理','平台员工账号与状态',btn('新增员工','admin-employee-new','','primary'))}${state.editGoods==='employee'?employeeForm():''}<div class="table-wrap"><table><thead><tr><th>员工</th><th>手机号</th><th>角色</th><th>店铺数</th><th>状态</th><th>操作</th></tr></thead><tbody>${state.adminEmployees.map(e=>`<tr><td>${esc(e.username)}</td><td>${esc(e.phone)}</td><td>${e.role}</td><td>${e.storeCount||0}</td><td>${e.status?'启用':'停用'}</td><td>${btn(e.status?'停用':'启用','admin-employee-status',`${e.id}:${e.status?0:1}`,'small')}</td></tr>`).join('')||'<tr><td colspan="6">暂无员工</td></tr>'}</tbody></table></div>`;return;
    }
    if (page === 'audit') {
      const data=await load('/api/admin/audit-logs?page=1&pageSize=100');const logs=data?.list||[];
      $('app').innerHTML=`${pageHead('操作日志','最近 100 条平台审计记录')}<div class="table-wrap"><table><thead><tr><th>时间</th><th>操作人</th><th>动作</th><th>对象</th><th>结果</th><th>来源</th></tr></thead><tbody>${logs.map(l=>`<tr><td>${esc(l.createTime||l.time)}</td><td>${esc(l.username||l.operatorName||'')}</td><td>${esc(l.action||l.operation||'')}</td><td>${esc(l.target||l.detail||'')}</td><td>${esc(l.result||'')}</td><td>${esc(l.ip||'')}</td></tr>`).join('')||'<tr><td colspan="6">暂无日志</td></tr>'}</tbody></table></div>`;return;
    }
    if (page === 'admin-marketing') {
      const [activities,seckills]=await Promise.all([load('/api/admin/marketing/activities'),load('/api/admin/marketing/seckills')]);state.adminActivities=activities||[];state.adminSeckills=seckills||[];
      $('app').innerHTML=`${pageHead('营销监管','查看、暂停或移除商户营销活动')}<div class="grid two"><section><h2 class="section-title">活动</h2>${state.adminActivities.map(a=>`<article class="item-card row-between"><div><strong>${esc(a.title)}</strong><div class="subtle">店铺 ${a.storeId} · ${esc(MARKETING_LABELS[a.type] || '其他活动')} · ${esc(a.startTime)} - ${esc(a.endTime)}</div></div><div class="td-actions">${btn(a.status?'暂停':'启用','admin-activity-status',`${a.id}:${a.status?0:1}`,'small')}${btn('删除','admin-activity-delete',a.id,'small danger')}</div></article>`).join('')||empty('暂无活动')}</section><section><h2 class="section-title">秒杀</h2>${state.adminSeckills.map(s=>`<article class="item-card row-between"><div><strong>商品 ${s.goodsId} · ¥${cash(s.price)}</strong><div class="subtle">店铺 ${s.storeId} · ${s.sold}/${s.quota}</div></div><div class="td-actions">${btn(s.status?'暂停':'启用','admin-seckill-status',`${s.id}:${s.status?0:1}`,'small')}${btn('删除','admin-seckill-delete',s.id,'small danger')}</div></article>`).join('')||empty('暂无秒杀')}</section></div>`;return;
    }
  };
  const adminUsersTable = () => `<div class="table-wrap"><table><thead><tr><th>用户</th><th>手机号</th><th>角色</th><th>余额</th><th>状态</th><th>注册时间</th><th>操作</th></tr></thead><tbody>${state.adminUsers.map(u=>`<tr><td>${esc(u.username)}</td><td>${esc(u.phone)}</td><td>${['用户','商户','管理员','骑手'][u.role]||u.role}</td><td>¥${cash(u.balance)}</td><td>${u.status?'启用':'停用'}</td><td>${esc(u.createTime||'')}</td><td>${btn(u.status?'停用':'启用','admin-user-status',`${u.id}:${u.status?0:1}`,'small')}</td></tr>`).join('')||'<tr><td colspan="7">暂无用户</td></tr>'}</tbody></table></div>`;
  const adminProductsTable = () => `<div class="table-wrap"><table><thead><tr><th>商品</th><th>店铺</th><th>价格</th><th>库存</th><th>销量</th><th>状态</th><th>操作</th></tr></thead><tbody>${state.adminProducts.map(p=>`<tr><td>${esc(p.name)}</td><td>${esc(p.storeName)}</td><td>¥${cash(p.price)}</td><td>${p.stock}</td><td>${p.sales}</td><td>${p.status?'上架':'下架'}</td><td>${btn(p.status?'下架':'上架','admin-product-status',`${p.id}:${p.status?0:1}`,'small')} ${btn('删除','admin-product-delete',p.id,'small danger')}</td></tr>`).join('')||'<tr><td colspan="7">暂无商品</td></tr>'}</tbody></table></div>`;
  const table = (headers, rows) => `<div class="table-wrap"><table><thead><tr>${headers.map(h=>`<th>${h}</th>`).join('')}</tr></thead><tbody>${rows.map(row=>`<tr>${row.map(c=>`<td>${c}</td>`).join('')}</tr>`).join('')||`<tr><td colspan="${headers.length}">暂无数据</td></tr>`}</tbody></table></div>`;
  const bannerForm = () => `<form data-form="admin-banner" class="inline-form"><div class="form-grid"><label class="field">标题<input class="input" name="title" required></label><label class="field">副标题<input class="input" name="subtitle"></label><label class="field">图片 URL<input class="input" name="image"></label><label class="field">主题色<input class="input" name="color" value="#C74B1B"></label><label class="field">链接类型<input class="input" name="linkType" value="NONE"></label><label class="field">链接值<input class="input" name="linkValue"></label><label class="field">排序<input class="input" name="sort" type="number" value="0"></label><div class="form-actions"><button class="btn primary">创建</button></div></div></form>`;
  const announcementForm = () => `<form data-form="admin-announcement" class="inline-form"><div class="form-grid"><label class="field">标题<input class="input" name="title" required></label><label class="field full">内容<textarea class="textarea" name="content" required></textarea></label><div class="form-actions full"><button class="btn primary">发布公告</button></div></div></form>`;
  const employeeForm = () => `<form data-form="admin-employee" class="inline-form"><div class="form-grid"><label class="field">用户名<input class="input" name="username" required></label><label class="field">手机号<input class="input" name="phone" required></label><label class="field">初始密码<input class="input" name="password" type="password" required minlength="8"></label><div class="form-actions"><button class="btn primary">创建员工</button></div></div></form>`;
  const addressText = a => {
    const mapAddress = String(a?.mapAddress || '').trim();
    const doorDetail = String(a?.doorDetail || '').trim();
    return mapAddress ? [mapAddress,doorDetail].filter(Boolean).join(' ') : String(a?.detail || a?.address || '').trim();
  };
  const addressPayload = (data, isDefault) => {
    const mapAddress = String(data.mapAddress || '').trim();
    const doorDetail = String(data.doorDetail || '').trim();
    return {name:String(data.name||'').trim(),phone:String(data.phone||'').trim(),detail:[mapAddress,doorDetail].filter(Boolean).join(' '),mapAddress,doorDetail,tag:String(data.tag||'').trim(),isDefault:isDefault?1:0,...TakeoutLocation.coordinates(data.longitude,data.latitude)};
  };
  const addressForm = (a = null) => {
    const mapAddress = String(a?.mapAddress || a?.detail || a?.address || '').trim();
    const doorDetail = a?.mapAddress ? String(a?.doorDetail || '').trim() : '';
    const selectedTag = String(a?.tag || '');
    return `<form data-form="address" data-id="${a?.id||0}" data-coordinate-address="${esc(mapAddress)}" class="inline-form"><div class="form-grid">
    <div class="notice-line full" role="note">${window.isSecureContext ? '点击获取当前位置后，请允许浏览器访问位置。' : '当前 HTTP 页面不支持设备定位，请使用 HTTPS 安全入口，或手动搜索地点。'}</div>
    <div class="full td-actions"><button class="btn" type="button" data-action="locate-device">获取当前位置</button>${secureLocationLink()}</div>
    <div class="full help-text" data-location-status role="status"></div>
    <input type="hidden" name="latitude" value="${esc(a?.latitude ?? '')}"><input type="hidden" name="longitude" value="${esc(a?.longitude ?? '')}">
    <label class="field full">搜索地图位置<input class="input" name="locationKeyword" maxlength="80" placeholder="例如：北京市中关村广场"></label>
    <div class="full"><button class="btn" type="button" data-action="address-search">搜索地点</button></div>
    <div class="full" data-location-results aria-live="polite"></div>
    <label class="field">联系人<input class="input" name="name" required maxlength="64" autocomplete="name" value="${esc(a?.name||'')}"></label><label class="field">手机号<input class="input" name="phone" required inputmode="tel" maxlength="11" pattern="1[0-9]{10}" autocomplete="tel" value="${esc(a?.phone||'')}"></label>
    <label class="field full">地图位置<input class="input" name="mapAddress" required maxlength="255" placeholder="例如：中关村广场" value="${esc(mapAddress)}"><span class="help-text">用于判断配送范围；换地点后请重新搜索或定位。</span></label>
    <label class="field full">楼栋、楼层与门牌<input class="input" name="doorDetail" maxlength="120" placeholder="例如：3 栋 1206，东门进入" value="${esc(doorDetail)}"><span class="help-text">请写到骑手能找到的位置；确无门牌可留空。</span></label>
    <label class="field">地址标签<select class="select" name="tag"><option value="" ${selectedTag?'':'selected'}>不设置</option>${['家','公司','学校','其他'].map(tag=>`<option value="${tag}" ${selectedTag===tag?'selected':''}>${tag}</option>`).join('')}</select></label>
    <label><input type="checkbox" name="isDefault" ${a?.isDefault?'checked':''}> 设为默认地址</label><div class="form-actions"><button class="btn primary">保存地址</button><button class="btn" type="button" data-action="address-form-close">取消</button></div></div></form>`;
  };
  const bindForms = () => {
    document.querySelectorAll('form[data-form="merchant-store"],form[data-form="rider-settings"]').forEach(form => {
      if (!form.querySelector('[data-location-status]')) form.insertAdjacentHTML('afterbegin', `<div class="full td-actions"><button class="btn" type="button" data-action="locate-device">获取当前位置</button>${secureLocationLink()}</div><div class="full help-text" data-location-status role="status"></div>`);
    });
    document.querySelectorAll('#app form[data-form]').forEach(form => form.onsubmit = async (event) => {
      event.preventDefault(); const f = new FormData(form); const data = Object.fromEntries(f.entries()); const name=form.dataset.form;
      const context = asyncContext();
      const formSend = (...args) => guarded(send(...args), context, () => form.isConnected);
      const submitter = event.submitter || form.querySelector('button[type="submit"],button:not([type])');
      if (submitter?.disabled) return;
      if (submitter) submitter.disabled = true;
      try {
        if (name === 'browse-location') { await searchPlaces(form); }
        else if (name === 'profile') { state.user=await formSend('/api/auth/me','PUT',{username:data.username,phone:data.phone,email:data.email||'',currentPassword:data.currentPassword||''}); toast('资料已保存'); renderShell(); await renderPage(); }
        else if (name === 'password') { await formSend('/api/auth/password','PUT',{oldPassword:data.oldPassword,newPassword:data.newPassword}); toast('密码已修改，请重新登录'); await logout(); }
        else if (name === 'payment-password') { await formSend('/api/auth/payment-password','POST',{loginPassword:data.loginPassword,paymentPassword:data.paymentPassword}); await logout();toast('支付密码已设置，请重新登录'); }
        else if (name === 'address') { const id=Number(form.dataset.id||0); const payload=addressPayload(data,f.get('isDefault')!==null); await formSend(id?`/api/addresses/${id}`:'/api/addresses',id?'PUT':'POST',payload); state.editAddress=null;toast('地址已保存');await renderPage(); }
        else if (name === 'merchant-store') { const p={name:data.name,categoryId:Number(data.categoryId),deliveryFee:Number(data.deliveryFee),minOrder:Number(data.minOrder),deliveryTime:data.deliveryTime,notice:data.notice,address:data.address,latitude:Number(data.latitude||0),longitude:Number(data.longitude||0),image:data.image||'',deliveryRadius:Number(data.deliveryRadius||0)}; const id=Number(form.dataset.id||0); await formSend(id?`/api/merchant/stores/${id}`:'/api/merchant/stores',id?'PUT':'POST',id?{...p,status:-1}:p); state.editGoods=null;state.merchantStoreEdit=null;toast('门店已保存');await renderPage(); }
        else if (name === 'merchant-goods') { const p={name:data.name,description:data.description||'',price:Number(data.price),originalPrice:Number(data.originalPrice||data.price),image:data.image||'',categoryId:Number(data.categoryId),merchantCategoryId:Number(data.merchantCategoryId||0),stock:Number(data.stock||0),tag:data.tag||'',special:f.get('special')===null?false:true,status:1}; const id=Number(form.dataset.id||0); await formSend(id?`/api/merchant/goods/${id}`:`/api/merchant/stores/${state.activeStoreId}/goods`,id?'PUT':'POST',p);state.editGoods=null;toast('商品已保存');await renderPage(); }
        else if (name === 'merchant-activity') { await formSend(`/api/merchant/activities?storeId=${state.activeStoreId}`,'POST',{type:data.type,title:data.title,discountRate:Number(data.discountRate||0),reduceAmount:Number(data.reduceAmount||0),threshold:Number(data.threshold||0),giftGoodsId:Number(data.giftGoodsId||0),startTime:data.startTime,endTime:data.endTime,status:1});state.editGoods=null;toast('活动已创建');await renderPage(); }
        else if (name === 'merchant-seckill') { await formSend(`/api/merchant/seckills?storeId=${state.activeStoreId}`,'POST',{goodsId:Number(data.goodsId),price:Number(data.price),quota:Number(data.quota),startTime:data.startTime,endTime:data.endTime,status:1});state.editGoods=null;toast('秒杀已创建');await renderPage(); }
        else if (name === 'merchant-reply') { await formSend(`/api/merchant/reviews/${form.dataset.id}`,'PUT',{reply:data.reply});toast('回复已保存');await renderPage(); }
        else if (name === 'rider-settings') { await formSend('/api/rider/range/radius','PUT',{radiusMeters:Number(data.radiusMeters)});await formSend('/api/rider/range/location','PUT',{latitude:Number(data.latitude||0),longitude:Number(data.longitude||0),address:data.address||''});toast('配送范围已保存');await renderPage(); }
        else if (name === 'admin-category') { await formSend('/api/admin/categories','POST',{name:data.name,icon:data.icon||'',color:data.color||''});state.editGoods=null;toast('分类已创建');await renderPage(); }
        else if (name === 'admin-banner') { await formSend('/api/admin/banners','POST',{title:data.title,subtitle:data.subtitle||'',image:data.image||'',color:data.color||'',linkType:data.linkType||'NONE',linkValue:data.linkValue||'',sort:Number(data.sort||0)});state.editGoods=null;toast('Banner 已创建');await renderPage(); }
        else if (name === 'admin-announcement') { await formSend('/api/admin/announcements','POST',{title:data.title,content:data.content});state.editGoods=null;toast('公告已创建');await renderPage(); }
        else if (name === 'admin-employee') { await formSend('/api/admin/employees','POST',{username:data.username,phone:data.phone,password:data.password});state.editGoods=null;toast('员工已创建');await renderPage(); }
        else if (name === 'assistant') { const question=data.question;state.assistantHistory.push({role:'user',content:question});const answer=await formSend('/api/assistant/chat','POST',{question,history:state.assistantHistory.map(x=>({role:x.role,content:x.content}))});state.assistantHistory.push({role:'assistant',content:answer?.answer||answer?.content||'暂时无法回答'});await renderPage(); }
      } catch(error) { if (error !== staleRender) toast(error.message,true); }
      finally { if (submitter?.isConnected && isCurrentContext(context)) submitter.disabled = false; }
    });
  };
  const formData = (selector) => { const form=$(selector); return form ? Object.fromEntries(new FormData(form).entries()) : {}; };
  document.addEventListener('input', e => {
    if (e.target.matches('[name="locationKeyword"]')) {
      const form = e.target.form;
      form.dataset.locationRequest = String(Number(form.dataset.locationRequest || 0) + 1);
      form.querySelector('[data-location-results]').textContent = '';
    }
    if (e.target.matches('form[data-form="address"] [name="mapAddress"]')) {
      const form = e.target.form;
      const base = form.dataset.coordinateAddress || state.editAddress?.mapAddress || state.editAddress?.detail || '';
      if (!base || e.target.value.trim() !== base.trim()) {
        form.elements.longitude.value = ''; form.elements.latitude.value = '';
        form.querySelector('[data-location-status]').textContent = '地图位置已修改，请重新搜索或定位以更新坐标。';
      }
    }
  });
  const handleAction = async (action, id, el) => {
    const context = asyncContext();
    const connected = () => !el || el.isConnected !== false;
    const actionSend = (...args) => guarded(send(...args), context, connected);
    const actionLoad = path => guarded(get(path), context, connected);
    try {
      const oid = Number(String(id).split(':')[0]);
      const currentOrder = (state.role===1 ? state.merchantOrders : state.role===2 ? state.adminOrders : state.role===3 ? (action==='rider-grab'?state.riderPool:state.riderOrders) : state.orders).find(item=>Number(item.id)===oid);
      const actionRule = {'pay':'PAY','alipay-pay':'PAY','alipay-query':'PAY','cancel-order':'CANCEL','confirm-order':'CONFIRM','refund':'REFUND','review':'REVIEW','merchant-reject':'MERCHANT_REJECT','rider-grab':'RIDER_GRAB','rider-pickup':'RIDER_PICKUP','rider-deliver':'RIDER_DELIVER','admin-refund-order':'CANCEL','admin-cancel-order':'CANCEL','report-issue':'REPORT_ISSUE'}[action]
        || (action==='merchant-flow' ? {accept:'MERCHANT_ACCEPT',ready:'MERCHANT_READY',deliver:'MERCHANT_DELIVER',complete:'MERCHANT_COMPLETE'}[String(id).split(':')[1]] : '');
      if (actionRule && currentOrder && !canOrder(currentOrder,actionRule,true)) { toast('服务端未允许此操作，请刷新订单后重试',true); return; }
      if (action === 'login') return openAuth();
      if (action === 'sidebar-toggle') {
        state.sidebarCollapsed = !state.sidebarCollapsed;
        localStorage.setItem('takeout.demo.sidebarCollapsed', state.sidebarCollapsed ? '1' : '0');
        renderShell(); return;
      }
      if (action === 'auth-switch') return openAuth(id);
      if (action === 'auth-close') return closeAuth();
      if (action === 'auth-role') {
        if (!['CUSTOMER','MERCHANT','RIDER','ADMIN'].includes(id)) return;
        $('authForm').querySelector('[name="loginType"]').value = id;
        $('authForm').querySelectorAll('[data-action="auth-role"]').forEach(button => button.setAttribute('aria-pressed', String(button.dataset.id === id)));
        showAuthError(''); return;
      }
      if (action === 'send-code') return sendAuthCode();
      if (action === 'captcha-refresh') return refreshAuthCaptcha();
      if (action === 'go') return navigate(id);
      if (action === 'refresh') return renderPage();
      if (action === 'ledger-page' && state.role===1) {state.ledgerPage=Math.max(1,Number(id)||1);return renderPage();}
      if (action === 'delivery-issues-page' && state.role===2) {state.deliveryIssuesPage=Math.max(1,Number(id)||1);return renderPage();}
      if (action === 'delivery-issue-filter' && state.role===2 && ['OPEN','RESOLVED','ALL'].includes(id)) {state.deliveryIssueFilter=id;state.deliveryIssuesPage=1;return renderPage();}
      if (action === 'merchant-fulfillment' && state.role===1) {
        const result = await actionLoad('/api/merchant/stores/' + id + '/fulfillment');
        const fields = '<p class="help-text">仅影响新订单，已创建订单沿用下单时配送方式。骑手配送单必须由骑手履约；商家自配送单出餐后由商家配送和确认送达。</p><label class="field">配送方式<select class="select" name="mode"><option value="RIDER" ' + (result.mode==='RIDER'?'selected':'') + '>骑手配送</option><option value="MERCHANT" ' + (result.mode==='MERCHANT'?'selected':'') + '>商家自配送</option></select></label>';
        const changed = await guarded(requestBusinessForm('门店配送方式',fields,'/api/merchant/stores/' + id + '/fulfillment','PUT',data=>{if(!['RIDER','MERCHANT'].includes(data.mode))throw new Error('请选择配送方式');return {mode:data.mode};}),context,connected);
        if(changed){toast('配送方式已保存，将用于新订单');return renderPage();}return;
      }
      if (action === 'order-issues' && [0,1,3].includes(state.role)) return showOrderIssues(Number(id));
      if (action === 'report-issue' && [0,1,3].includes(state.role)) {
        if(!currentOrder || !canOrder(currentOrder,'REPORT_ISSUE',[1,2,3].includes(Number(currentOrder.status)))){toast('当前订单不能上报配送异常，请刷新',true);return;}
        const key='web-issue-' + Date.now() + '-' + Math.random().toString(16).slice(2);
        const fields='<label class="field">异常类型<select class="select" name="type" required><option value="">请选择</option>' + Object.entries(ISSUE_TYPES).map(([code,label])=>'<option value="'+code+'">'+label+'</option>').join('') + '</select></label>' + noteField('note','异常说明');
        const result=await guarded(requestBusinessForm('上报配送异常',fields,issuePath(id),'POST',data=>{if(!ISSUE_TYPES[data.type])throw new Error('请选择异常类型');return {type:data.type,note:requireNote(data.note),idempotencyKey:key};}),context,connected);
        if(result){toast('异常已上报，等待平台处理');await showOrderIssues(Number(id));}return;
      }
      if (action === 'resolve-issue' && state.role===2) {
        const [issueId,resolution]=String(id).split(':');const issue=state.deliveryIssues.find(item=>Number(item.id)===Number(issueId));
        if(!issue || issue.status!=='OPEN' || !['REASSIGN','RESUME','CANCEL'].includes(resolution))return;
        const fields=issueDetails(issue)+'<p class="notice-line">'+(resolution==='CANCEL'?'取消后原渠道退款，退回仍有效优惠券；制作或配送取消不恢复可售库存。':resolution==='REASSIGN'?'仅骑手配送且取餐前可改派，将回到待抢单池。':'确认核实后继续履约。')+'</p>'+noteField('note','处理说明');
        const result=await guarded(requestBusinessForm('处理配送异常',fields,'/api/admin/delivery-issues/'+issueId+'/resolve','POST',data=>({action:resolution,note:requireNote(data.note)})),context,connected);
        if(result){toast('配送异常已处理');return renderPage();}return;
      }
      if (action === 'locate-device') return locate(el);
      if (action === 'location-change') {
        const form = $('browseLocationPicker');
        state.locationVersion++; state.locating = false;
        form.hidden = !form.hidden;
        form.dataset.locationRequest = String(Number(form.dataset.locationRequest || 0) + 1);
        form.querySelector('[data-location-results]').textContent = '';
        const section = form.closest('[data-browse-location]');
        section.querySelector('[data-location-status]').textContent = '';
        section.querySelector('[data-action="locate-device"]').disabled = false;
        document.querySelector('[aria-controls="browseLocationPicker"]').setAttribute('aria-expanded', String(!form.hidden));
        if (!form.hidden) form.elements.locationKeyword.focus();
        return;
      }
      if (action === 'location-select') {
        const coordinate = TakeoutLocation.coordinates(el.dataset.longitude, el.dataset.latitude);
        if (!coordinate || !el.dataset.address) throw new Error('所选地点坐标无效，请重新搜索。');
        state.locationVersion++;
        state.location = coordinate; state.locationLabel = el.dataset.address;
        toast('浏览位置已切换'); return renderPage();
      }
      if (action === 'location-clear') { state.locationVersion++; state.location = null; state.locationLabel = ''; return renderPage(); }
      if (action === 'stores-more') return appendStoreCards();
      if (action === 'open-store') { state.storeId=Number(id);return navigate('store'); }
      if (action === 'add-cart') { if(!requireUser())return;const spec=document.querySelector(`[data-spec-for="${id}"]`);await actionSend('/api/cart/items','POST',{goodsId:Number(id),specId:Number(spec?.value||0),quantity:1});await refreshCart(actionLoad);toast('已加入服务端购物车');return; }
      if (action === 'favorite') { await actionSend(`/api/favorites/toggle?storeId=${id}`,'POST');toast('收藏状态已更新');return renderPage(); }
      if (action === 'cart-inc'||action === 'cart-dec') { const item=state.cart.find(x=>Number(x.goodsId)===Number(id)&&Number(x.specId||0)===Number(el.dataset.spec||0));if(!item)return;const q=item.quantity+(action==='cart-inc'?1:-1);if(q>0)await actionSend(`/api/cart/items/${id}?specId=${el.dataset.spec||0}`,'PUT',{quantity:q});else await actionSend(`/api/cart/items/${id}?specId=${el.dataset.spec||0}`,'DELETE');return renderPage(); }
      if (action === 'cart-clear') {
        const items=state.cart.filter(x=>Number(x.storeId)===Number(id));if(!items.length)return;
        const pieces=items.reduce((sum,item)=>sum+Number(item.quantity||0),0);
        if(!window.confirm(`确认清空“${items[0].storeName||'该店铺'}”的 ${items.length} 项、共 ${pieces} 件商品？此操作无法撤销。`))return;
        const goodsIds=[...new Set(items.map(item=>Number(item.goodsId)).filter(Number.isFinite))];
        try { await actionSend(`/api/cart/items?goodsIds=${encodeURIComponent(goodsIds.join(','))}`,'DELETE');toast('本店商品已清空'); }
        catch(error) { if(error===staleRender)return;toast(`清空失败：${error.message||'请稍后重试'}，已刷新购物车`,true);await renderPage();return; }
        return renderPage();
      }
      if (action === 'checkout') {
        const storeId=Number(id); const draft=checkoutDraft(storeId);
        state.checkoutStoreId=storeId;state.checkoutIntentStoreId=storeId;state.checkoutIntentKey=draft.intentKey;state.checkoutSubmitting=false;
        return navigate('checkout');
      }
      if (action === 'place-order') {
        const storeId=Number(el.dataset.store);if(state.checkoutSubmitting)return;
        if(!state.checkoutView||state.checkoutView.storeId!==storeId){await renderPage();toast('请核对当前订单后提交',true);return;}
        captureCheckoutDraft(); const draft=checkoutDraft(storeId);
        if(draft.remark.length>255){toast('给商家的备注最多 255 字，请精简后提交',true);$('checkoutRemark').focus();return;}
        const intentKey=draft.intentKey;
        state.checkoutSubmitting=true;el.disabled=true;el.textContent='提交中…';
        const controls=$('checkoutForm').querySelectorAll('input,select,textarea,button');
        controls.forEach(control=>{control.disabled=true;});
        try {
          if(!draft.submittedPayload){
            const [cart,addresses,coupons,store]=await Promise.all([actionLoad('/api/cart'),actionLoad('/api/addresses'),actionLoad('/api/coupons'),actionLoad(`/api/stores/${storeId}`)]);
            const fresh=checkoutData(storeId,cart||[],addresses||[],coupons||[],store,draft);
            setCart(cart);state.addresses=addresses||[];state.coupons=coupons||[];
            if(fresh.signature!==state.checkoutView.signature){
              draft.reviewMessage ||= '商品、配送费、地址或优惠已变化。请核对清单与金额后再次提交。';
              state.checkoutSubmitting=false;await renderPage();return;
            }
            if(!fresh.address){toast('请先添加并选择地址',true);return;}
            if(!fresh.items.length||moneyCents(fresh.subtotal)<moneyCents(store?.minOrder)){toast(`本店商品需满 ¥${cash(store?.minOrder)} 起送，请返回购物车补充商品`,true);return;}
            if(checkoutAmounts(fresh.subtotal,fresh.deliveryFee,fresh.selectedCoupon?.amount||0).payable<=0){toast('预计实付需大于 0，请更换优惠券',true);return;}
            draft.viewData=state.checkoutView;
            draft.submittedPayload={storeId,items:fresh.items.map(x=>({goodsId:x.goodsId,goodsName:x.goods?.name||'',price:x.price,quantity:x.quantity,image:x.goods?.image||'',specId:x.specId||0,specName:x.specName||''})),addressId:draft.addressId,couponId:draft.couponId,remark:draft.remark,checkoutGoodsIds:fresh.items.map(x=>x.goodsId),expectTime:'',idempotencyKey:intentKey,setmeals:[],deliveryType:'DELIVERY'};
          }
          const order=await actionSend('/api/orders','POST',draft.submittedPayload);
          if(!order||!Number.isInteger(Number(order.id))||Number(order.id)<=0)throw new Error('订单结果尚未完整返回，请按原信息重试核对');
          delete state.checkoutDrafts[`${Number(state.user?.id||0)}:${storeId}`];state.checkoutReturnStoreId=0;
          resetCheckoutIntent();
          await loadCartCount();
          if (!isCurrentContext(context)) return;
          toast(Number(order.status)===0?`订单 ${order.orderNo||order.id} 已创建，请核对服务端金额后付款`:`已核对到原订单 ${order.orderNo||order.id}，当前状态：${orderStatus(order)}，请查看详情`);
          return navigate('orders');
        } catch(error) {
          if(error===staleRender)return;
          if(error.responseReceived)draft.submittedPayload=null;
          state.checkoutSubmitting=false;
          if(draft.submittedPayload)await renderPage();
          throw error;
        } finally {
          if(state.checkoutIntentKey===intentKey){state.checkoutSubmitting=false;el.disabled=false;el.textContent=draft.submittedPayload?'核对上次提交结果':draft.reviewMessage?'确认变更并提交待付款订单':'提交待付款订单';}
          if(!draft.submittedPayload)controls.forEach(control=>{if(control.isConnected)control.disabled=false;});
        }
      }
      if (action === 'pay') { const paymentPassword=await guarded(requestPaymentPassword(),context,connected);if(paymentPassword===null)return;await actionSend(`/api/orders/${id}/pay?channel=BALANCE&mode=QR`,'POST',{paymentPassword});toast('余额支付成功');return renderPage(); }
      if (action === 'alipay-pay') { const result=await actionSend(`/api/orders/${id}/pay?channel=ALIPAY&mode=QR`,'POST'); if(result?.paymentUrl){ window.prompt('请在支付宝沙箱中扫描或复制此支付链接，支付后回到订单点击刷新：',result.paymentUrl); } else { toast('支付宝沙箱预支付已创建，请刷新订单'); } return renderPage(); }
      if (action === 'alipay-query') { const result=await actionSend(`/api/orders/${id}/payment/query`,'POST'); toast(result?.status===1?'支付宝支付已确认':'支付宝尚未完成支付'); return renderPage(); }
      if (action === 'cancel-order') {
        const order=state.orders.find(item=>Number(item.id)===Number(id));
        if(!order){toast('订单信息已更新，请刷新后重试',true);return;}
        if(Number(order.status)===2||Number(order.status)===3){toast(Number(order.status)===2?'订单已进入制作，如需处理请联系平台':'订单已进入配送，如需处理请联系平台',true);return;}
        if(![0,1].includes(Number(order.status))){toast('当前订单不可取消',true);return;}
        const unpaid=Number(order.status)===0;
        const message=unpaid
          ? '该订单为待付款，平台尚未扣款；取消后将释放库存和优惠券，确定取消吗？'
          : '该订单尚未由商家接单，取消后支付金额将按原支付渠道全额退回；已支付订单由用户主动取消不返优惠券，确定取消吗？';
        if(!window.confirm(message))return;
        await actionSend(`/api/orders/${id}/cancel`,'PUT');
        toast(unpaid?'订单已取消，平台未扣款；库存和优惠券已释放':`订单已取消，¥${cash(order.payAmount)} 已按原支付渠道全额退回；用户主动取消不返优惠券`);
        return renderPage();
      }
      if (action === 'confirm-order') { if(!window.confirm('确认已经收到餐品？确认后订单款项将结算；送达后48小时内仍可申请部分或全额售后，评价不影响售后期。'))return;await actionSend(`/api/orders/${id}/confirm`,'PUT');toast('已确认收到，订单已完成');return renderPage(); }
      if (action === 'refund-history') return showRefundHistory(Number(id));
      if (action === 'refund') { const order=state.orders.find(item=>Number(item.id)===Number(id));if(!order||!canRefund(order)){toast('当前订单不可申请退款，请刷新订单或查看退款记录',true);return;}const record=await guarded(requestRefund(order),context,connected);if(!record)return;toast(refundFeedback(record),record.status==='REJECTED');return renderPage(); }
      if (action === 'review') { const order=state.orders.find(o=>Number(o.id)===Number(id));const review=await guarded(requestReview(order),context,connected);if(!review)return;await actionSend(`/api/orders/${id}/review`,'POST',review);toast('评价已提交');return renderPage(); }
      if (action === 'address-new') { state.editAddress={};return renderPage(); }
      if (action === 'address-search') {
        return searchPlaces(el.closest('form'));
      }
      if (action === 'address-select') {
        const form = el.closest('form');
        state.locationVersion++; state.locating = false;
        form.querySelector('[data-action="locate-device"]').disabled = false;
        form.elements.mapAddress.value = el.dataset.address;
        form.dataset.coordinateAddress = el.dataset.address;
        const coordinate = TakeoutLocation.coordinates(el.dataset.longitude, el.dataset.latitude);
        form.elements.latitude.value = coordinate?.latitude ?? ''; form.elements.longitude.value = coordinate?.longitude ?? '';
        form.querySelector('[data-location-results]').textContent = '已选择地图位置，请继续填写楼栋、楼层与门牌。';
        form.elements.doorDetail.focus(); return;
      }
      if (action === 'address-edit') { state.editAddress=state.addresses.find(a=>Number(a.id)===Number(id))||{};return renderPage(); }
      if (action === 'address-form-close') { state.editAddress=null;return renderPage(); }
      if (action === 'address-default') { await actionSend(`/api/addresses/${id}/default`,'PUT');toast('默认地址已更新');return renderPage(); }
      if (action === 'address-delete') { await actionSend(`/api/addresses/${id}`,'DELETE');toast('地址已删除');return renderPage(); }
      if (action === 'bank-add') { const bankName=window.prompt('银行名称','中国工商银行');const cardType=window.prompt('卡类型','储蓄卡');const fullCardNumber=window.prompt('完整卡号（仅本次提交）','');if(bankName&&cardType&&fullCardNumber)await actionSend('/api/wallet/bank-cards','POST',{bankName,cardType,fullCardNumber});return renderPage(); }
      if (action === 'bank-reveal') { const paymentPassword=window.prompt('请输入支付密码以查看完整卡号','');if(paymentPassword){const result=await actionSend(`/api/wallet/bank-cards/${id}/reveal`,'POST',{paymentPassword});if(result?.cardNumber)toast(`完整卡号：${result.cardNumber}`);else toast('支付密码校验失败',true);}return; }
      if (action === 'bank-delete') { await actionSend(`/api/wallet/bank-cards/${id}`,'DELETE');return renderPage(); }
      if (action === 'claim-coupon') { await actionSend('/api/coupons/claim','POST',{storeId:0,name:'网页领取券',threshold:Number(el.dataset.threshold),amount:Number(el.dataset.amount)});toast('优惠券已领取');return renderPage(); }
      const browseView = browseViews.find(view => view[0] === action);
      if (browseView) {
        if (action === 'browse-all') return renderPage();
        const version = ++browseVersion;
        const [, title, path] = browseView;
        const result = $('browseResult');
        const heading = `<h2 class="section-title">${title}</h2>`;
        storeObserver?.disconnect(); storeObserver = null;
        $('storeGrid').hidden = true; $('storeLoadMore').hidden = true;
        $('browseShortcuts').querySelectorAll('button[data-action]').forEach(button => {
          const selected = button.dataset.action === action;
          button.setAttribute('aria-pressed', String(selected));
          button.classList.toggle('primary', selected);
        });
        result.innerHTML = heading + empty('正在加载…');
        result.setAttribute('aria-busy', 'true');
        try {
          const items = await actionLoad(path);
          if (version !== browseVersion) return;
          if (action === 'rank-stores') {
            state.stores = items || [];
            result.innerHTML = heading;
            $('storeGrid').hidden = false; resetStoreCards();
          } else {
            result.innerHTML = heading + `<div class="grid two">${(items || []).map(item => {
              const goods = item.goods || item;
              const storeId = Number(goods.storeId || item.storeId);
              const name = goods.name || item.goodsName;
              const photo = goods.image ? `<img data-product-image loading="lazy" decoding="async" src="${esc(assetURL(goods.image))}" alt="${esc(name)}">` : '暂无图片';
              const detail = action === 'rank-goods' ? ` · 月售 ${Number(goods.sales || 0)}` : action === 'seckills' ? ` · 剩余 ${Math.max(0, Number(item.quota || 0) - Number(item.sold || 0))}` : '';
              return `<article class="item-card browse-good"><div class="food-image">${photo}</div><div class="food-info"><strong>${esc(name)}</strong><div class="subtle">${esc(item.storeName)}${detail}</div></div><div class="td-actions"><span class="price">¥${cash(goods.price)}</span>${storeId > 0 ? btn('进店', 'open-store', storeId, 'small primary') : ''}</div></article>`;
            }).join('') || empty('暂无' + title + '，可以切换其他专区或查看全部店铺')}</div>`;
          }
        } catch (error) {
          if (error === staleRender || version !== browseVersion) return;
          result.innerHTML = heading + `<div class="notice-line">${esc(error.message || '加载失败，请重试')}</div><div class="form-actions">${btn('重试', action)}</div>`;
        } finally {
          if (version === browseVersion && isCurrentContext(context)) result.setAttribute('aria-busy', 'false');
        }
        return;
      }
      if (action === 'merchant-store-new') { state.editGoods='store';state.merchantStoreEdit=null;return renderPage(); }
      if (action === 'merchant-store-edit') { state.editGoods=null;state.merchantStoreEdit=state.merchantStores.find(s=>Number(s.id)===Number(id));return renderPage(); }
      if (action === 'merchant-goods-new') { state.editGoods={};return renderPage(); }
      if (action === 'merchant-goods-edit') { state.editGoods=state.merchantGoods.find(g=>Number(g.id)===Number(id))||{};return renderPage(); }
      if (action === 'merchant-goods-form-close') { state.editGoods=null;return renderPage(); }
      if (action === 'merchant-goods-toggle') {const g=state.merchantGoods.find(x=>Number(x.id)===Number(id));await actionSend(`/api/merchant/goods/${id}`,'PUT',{name:g.name,description:g.description||'',price:g.price,originalPrice:g.originalPrice||g.price,image:g.image||'',categoryId:g.categoryId,merchantCategoryId:g.merchantCategoryId||0,stock:g.stock||0,tag:g.tag||'',special:g.special||false,status:g.status===1?0:1});toast('商品状态已更新');return renderPage();}
      if (action === 'merchant-goods-delete') {await actionSend(`/api/merchant/goods/${id}`,'DELETE');return renderPage();}
      if (action === 'merchant-activity-new') {state.editGoods='activity';return renderPage();}
      if (action === 'merchant-seckill-new') {state.editGoods='seckill';return renderPage();}
      if (action === 'merchant-activity-status') {const a=state.merchantActivities.find(x=>Number(x.id)===Number(id));await actionSend(`/api/merchant/activities/${id}/status?storeId=${state.activeStoreId}`,'PUT',{status:a.status?0:1});return renderPage();}
      if (action === 'merchant-activity-delete') {await actionSend(`/api/merchant/activities/${id}?storeId=${state.activeStoreId}`,'DELETE');return renderPage();}
      if (action === 'merchant-seckill-status') {const s=state.merchantSeckills.find(x=>Number(x.id)===Number(id));await actionSend(`/api/merchant/seckills/${id}/status?storeId=${state.activeStoreId}`,'PUT',{status:s.status?0:1});return renderPage();}
      if (action === 'merchant-seckill-delete') {await actionSend(`/api/merchant/seckills/${id}?storeId=${state.activeStoreId}`,'DELETE');return renderPage();}
      if (action === 'merchant-categories') { const categories=await actionLoad('/api/merchant/categories')||[]; const name=window.prompt(`当前分类：${categories.map(c=>c.name).join('、')||'暂无'}\n输入新分类名称，取消则不创建`,''); if(name&&name.trim()) { await actionSend('/api/merchant/categories','POST',{name:name.trim(),sort:categories.length}); toast('店内分类已创建'); } return renderPage(); }
      if (action === 'merchant-goods-specs') { const goods=state.merchantGoods.find(g=>Number(g.id)===Number(id));const current=(goods?.specs||[]).map(s=>`${s.name}:${s.price}:${s.stock}`).join(',');const text=window.prompt('规格格式：名称:价格:库存，多个用英文逗号分隔',current);if(text!==null){const specs=text.split(',').map((part,index)=>{const [name,price,stock]=part.split(':');return {id:goods?.specs?.[index]?.id||0,name:(name||'').trim(),price:Number(price||0),stock:Number(stock||0)};}).filter(s=>s.name);await actionSend(`/api/merchant/goods/${id}/specs`,'PUT',{specs});toast('规格已保存');}return renderPage(); }
      if (action === 'merchant-setmeals') { const setmeals=await actionLoad(`/api/merchant/setmeals?storeId=${state.activeStoreId}`)||[];const name=window.prompt(`当前套餐：${setmeals.map(s=>s.name).join('、')||'暂无'}\n输入新套餐名称，取消则不创建`,'');if(name&&name.trim()){const goodsIds=window.prompt('输入套餐商品 ID，英文逗号分隔','');const items=(goodsIds||'').split(',').map(gid=>({id:0,setmealId:0,goodsId:Number(gid.trim()),goodsName:'',quantity:1})).filter(x=>x.goodsId>0);if(items.length)await actionSend(`/api/merchant/setmeals?storeId=${state.activeStoreId}`,'POST',{name:name.trim(),description:'网页创建套餐',price:Number(window.prompt('套餐价格','20')||20),originalPrice:Number(window.prompt('套餐原价','25')||25),image:'',items});toast('套餐已创建');}return renderPage(); }
      if (action === 'merchant-employees') { const employees=await actionLoad(`/api/merchant/employees?storeId=${state.activeStoreId}`)||[];const userId=window.prompt(`当前员工：${employees.map(e=>e.username).join('、')||'暂无'}\n输入要添加的用户 ID，取消则不添加`,'');if(userId) {const roleName=window.prompt('员工角色','STAFF')||'STAFF';await actionSend(`/api/merchant/employees?storeId=${state.activeStoreId}`,'POST',{userId:Number(userId),roleName});toast('员工已添加');}return renderPage(); }
      if (action === 'merchant-flow') {const [oid,flow]=String(id).split(':');if(['deliver','complete'].includes(flow)&&(!currentOrder||!canOrder(currentOrder,flow==='deliver'?'MERCHANT_DELIVER':'MERCHANT_COMPLETE'))){toast('此订单当前不可由商家配送，请刷新后重试',true);return;}if(flow==='complete'&&!window.confirm('确认自配送餐品已交给用户或放到约定地点？'))return;await actionSend(`/api/merchant/orders/${oid}/${flow}`,'PUT');toast('订单状态已更新');return renderPage();}
      if (action === 'merchant-reject') {const order=state.merchantOrders.find(item=>Number(item.id)===Number(id));if(!order){toast('订单状态已变化，请刷新后重试',true);return;}if(Number(order.status)!==1){toast('仅待接单订单可以拒绝',true);return;}if(await requestMerchantReject(order)){toast('已通知用户，款项已按原支付渠道退回');return renderPage();}return;}
      if (action === 'rider-online') {state.rider=await actionSend('/api/rider/status','PUT',{online:Number(id)});toast(Number(id)?'已上线':'已下线');return renderPage();}
      if (action === 'rider-copy-address' || action === 'rider-store-address') {
        const order=state.riderOrders.find(item=>Number(item.id)===Number(id));
        if(state.role!==3||!order||![2,3].includes(Number(order.status))){toast('订单已结束或信息已更新，请刷新订单',true);return;}
        if(action==='rider-store-address'){
          const store=await actionLoad(`/api/stores/${order.storeId}`);
          if(!store?.address){toast('门店暂未提供取餐地址，请联系平台确认',true);return;}
          window.prompt(`${store.name||order.storeName||'取餐门店'}的地址（可选中复制）`,store.address);return;
        }
        const address=addressText(order.address);if(!address){toast('收货地址待补充，请联系用户确认',true);return;}
        try {
          if(!window.navigator?.clipboard?.writeText)throw new Error('clipboard-unavailable');
          await guarded(window.navigator.clipboard.writeText(address),context,connected);toast('收货地址已复制');
        }catch(error){if(error===staleRender)return;window.prompt('浏览器未能自动复制，请选中以下收货地址手动复制',address);}
        return;
      }
      if (['rider-grab','rider-pickup','rider-deliver'].includes(action)) {
        if(state.role!==3||state.riderActions[id])return;
        const order=state.riderOrders.find(item=>Number(item.id)===Number(id));
        if(action!=='rider-grab'&&(!order||Number(order.status)!==(action==='rider-pickup'?2:3))){toast('订单状态已变化，请刷新本人配送订单',true);return;}
        if(action==='rider-deliver'&&!window.confirm('确认已将餐品交给用户，或放到与用户约定的地点？请勿提前确认送达。'))return;
        const flow=action.slice(6);const label={grab:'抢单',pickup:'取餐',deliver:'送达'}[flow];
        state.riderActions[id]=true;if(el){el.disabled=true;el.textContent='处理中…';}
        try {
          await actionSend(`/api/rider/orders/${id}/${flow}`,flow==='grab'?'POST':'PUT');
          toast(`${label}已确认`);await renderPage();
        }catch(error){
          if(error===staleRender)return;
          try {
            const orders=await actionLoad('/api/rider/orders');state.riderOrders=orders||[];
            const latest=state.riderOrders.find(item=>Number(item.id)===Number(id));
            const confirmed=latest&&(flow==='grab'?[2,3,4].includes(Number(latest.status)):flow==='pickup'?[3,4].includes(Number(latest.status)):Number(latest.status)===4);
            toast(confirmed?`${label}已确认，已核对本人配送订单`:`暂未确认${label}成功，已刷新本人配送订单，请核对后再试`,!confirmed);
            await renderPage();
          }catch(reconcileError){if(reconcileError!==staleRender)toast(`${label}结果尚未确认，请刷新本人配送订单后核对`,true);}
        }finally{delete state.riderActions[id];if(el?.isConnected&&isCurrentContext(context)){el.disabled=false;el.textContent=flow==='grab'?'抢单':flow==='pickup'?'确认取餐':'送达';}}
        return;
      }
      if (action === 'admin-category-new') {state.editGoods='category';return renderPage();}
      if (action === 'admin-category-delete') {await actionSend(`/api/admin/categories/${id}`,'DELETE');return renderPage();}
      if (action === 'admin-store-status') {const [sid,status]=String(id).split(':');await actionSend(`/api/admin/stores/${sid}/status`,'PUT',{status:Number(status)});return renderPage();}
      if (action === 'admin-store-recommend') {const [sid,recommended]=String(id).split(':');await actionSend(`/api/admin/stores/${sid}/recommend`,'PUT',{recommended:Number(recommended)});return renderPage();}
      if (action === 'admin-orders-page') {state.adminOrdersPage=Math.max(1,Number(id)||1);return renderPage();}
      if (action === 'admin-refunds-page') {state.adminRefundsPage=Math.max(1,Number(id)||1);return renderPage();}
      if (action === 'admin-refund-filter') {state.adminRefundFilter=id==='ALL'?'':'PENDING';state.adminRefundsPage=1;return renderPage();}
      if (action === 'admin-cancel-order' && state.role===2) {if(!currentOrder||Number(currentOrder.status)!==0||!canOrder(currentOrder,'CANCEL'))return;if(!window.confirm('该订单尚未付款；平台取消将释放库存、优惠券和新客名额，确定继续？'))return;await actionSend('/api/admin/orders/'+id+'/cancel','PUT');toast('未支付订单已由平台取消');return renderPage();}
      if (action === 'admin-refund-order') {const order=state.adminOrders.find(o=>Number(o.id)===Number(id));if(!order||![1,2,3].includes(Number(order.status))){toast('当前订单不可直接退款，请使用退款审批流程',true);return;}await actionSend(`/api/admin/orders/${id}/refund`,'PUT');return renderPage();}
      if (action === 'refund-approve'||action === 'refund-reject') {if(!state.adminRefunds.some(record=>Number(record.id)===Number(id)&&record.status==='PENDING')){toast('该申请已变化，请刷新后查看',true);return;}const record=await guarded(requestRefundDecision(Number(id),action==='refund-approve'),context,connected);if(!record)return;toast(record.status==='REJECTED'?`已拒绝退款，处理原因已同步给用户${record.rejectReason?`：${record.rejectReason}`:''}`:refundFeedback(record));return renderPage();}
      if (action === 'admin-subtab') {el.parentElement.querySelectorAll('.tab').forEach(x=>x.classList.remove('active'));el.classList.add('active');$('adminSubtab').innerHTML=id==='products'?adminProductsTable():adminUsersTable();return;}
      if (action === 'admin-user-status') {const [uid,status]=String(id).split(':');await actionSend(`/api/admin/users/${uid}/status`,'PUT',{status:Number(status)});return renderPage();}
      if (action === 'admin-product-status') {const [pid,status]=String(id).split(':');await actionSend(`/api/admin/products/${pid}/status`,'PUT',{status:Number(status)});return renderPage();}
      if (action === 'admin-product-delete') {await actionSend(`/api/admin/products/${id}`,'DELETE');return renderPage();}
      if (action === 'admin-rider-status') {const [rid,status]=String(id).split(':');await actionSend(`/api/admin/riders/${rid}/status`,'PUT',{status:Number(status)});return renderPage();}
      if (action === 'admin-banner-new') {state.editGoods='banner';return renderPage();}
      if (action === 'admin-announcement-new') {state.editGoods='announcement';return renderPage();}
      if (action === 'admin-banner-status') {const [bid,status]=String(id).split(':');await actionSend(`/api/admin/banners/${bid}/status`,'PUT',{status:Number(status)});return renderPage();}
      if (action === 'admin-banner-delete') {await actionSend(`/api/admin/banners/${id}`,'DELETE');return renderPage();}
      if (action === 'admin-announcement-status') {const [aid,status]=String(id).split(':');await actionSend(`/api/admin/announcements/${aid}/status`,'PUT',{status:Number(status)});return renderPage();}
      if (action === 'admin-announcement-delete') {await actionSend(`/api/admin/announcements/${id}`,'DELETE');return renderPage();}
      if (action === 'admin-employee-new') {state.editGoods='employee';return renderPage();}
      if (action === 'admin-employee-status') {const [eid,status]=String(id).split(':');await actionSend(`/api/admin/employees/${eid}/status`,'PUT',{status:Number(status)});return renderPage();}
      if (action === 'admin-activity-status') {const [aid,status]=String(id).split(':');await actionSend(`/api/admin/marketing/activities/${aid}/status`,'PUT',{status:Number(status)});return renderPage();}
      if (action === 'admin-activity-delete') {await actionSend(`/api/admin/marketing/activities/${id}`,'DELETE');return renderPage();}
      if (action === 'admin-seckill-status') {const [sid,status]=String(id).split(':');await actionSend(`/api/admin/marketing/seckills/${sid}/status`,'PUT',{status:Number(status)});return renderPage();}
      if (action === 'admin-seckill-delete') {await actionSend(`/api/admin/marketing/seckills/${id}`,'DELETE');return renderPage();}
    } catch(error) { if (error !== staleRender) toast(error.message,true); }
  };
  document.addEventListener('error', e => {
    if (e.target?.matches?.('img[data-product-image]')) e.target.parentElement.textContent = '暂无图片';
  }, true);
  document.addEventListener('click', e => { const target=e.target.closest('[data-action]'); if(target) handleAction(target.dataset.action,target.dataset.id,target); const nav=e.target.closest('[data-page]'); if(nav) navigate(nav.dataset.page); const close=e.target.closest('[data-close]'); if(close) close.dataset.close==='authPage'?closeAuth():$(close.dataset.close).hidden=true; });
  const showAuthError = (message, field = '') => {
    const form = $('authForm');
    form.querySelectorAll('[aria-invalid="true"]').forEach(input => input.setAttribute('aria-invalid', 'false'));
    form.querySelectorAll('.auth-field-error').forEach(error => { error.textContent = ''; error.hidden = true; });
    field ||= /校对码/.test(message) ? 'captchaCode' : /验证码/.test(message) ? 'code'
      : /登录端|角色/.test(message) ? 'loginType' : /两次|确认密码/.test(message) ? 'confirmPassword'
      : /密码/.test(message) ? 'password' : /邮箱/.test(message) ? 'email'
      : /手机号/.test(message) ? 'phone' : /账号名|用户名/.test(message) ? 'username' : '';
    let inlineError = false;
    if (message && field) {
      form.querySelector('[name="' + field + '"]')?.setAttribute('aria-invalid', 'true');
      const error = $('authField-' + field);
      if (error) { error.textContent = message; error.hidden = false; inlineError = true; }
    }
    $('authError').textContent = message ? '操作未完成：' + message : '';
    $('authError').hidden = !message || inlineError;
    if (usernameError && field !== 'username') renderUsernameError();
  };
  $('authForm').addEventListener('input', e => {
    if (e.target.name === 'username') resetUsernameCheck();
    showAuthError(''); updateCodeButton();
    if ($('authForm').dataset.mode !== 'register') return;
    renderUsernameError();
    if (e.target.name === 'username') {
      if (e.isComposing) return;
      const name = e.target.value.trim();
      if (name) usernameCheckTimer = setTimeout(() => { void checkAuthUsername(name); }, 400);
      return;
    }
    updatePasswordFeedback();
    const confirm = $('authConfirmPassword');
    const mismatch = Boolean(confirm.value && confirm.value !== $('authPassword').value);
    confirm.setAttribute('aria-invalid', String(mismatch));
    if (mismatch) showAuthError('两次输入的密码不一致，请重新输入确认密码。');
  });
  $('authForm').addEventListener('focusin', updatePasswordFeedback);
  $('authForm').addEventListener('focusout', e => {
    if (e.target.name === 'username') void checkAuthUsername(e.target.value);
    setTimeout(updatePasswordFeedback, 0);
  });
  $('authForm').addEventListener('invalid', e => showAuthError(e.target.validationMessage, e.target.name), true);
  $('authForm').addEventListener('submit', async e => {
    e.preventDefault();
    const form = e.currentTarget, version = authViewVersion, mode = form.dataset.mode;
    const data = Object.fromEntries(new FormData(form).entries());
    showAuthError('');
    renderUsernameError();
    if (form.dataset.mode === 'register') {
      const passwordError = newPasswordError(data.password);
      if (passwordError) { showAuthError(passwordError); $('authPassword').focus(); return; }
      if (data.password !== data.confirmPassword) {
        showAuthError('两次输入的密码不一致，请重新输入确认密码。');
        $('authConfirmPassword').setAttribute('aria-invalid', 'true'); $('authConfirmPassword').focus(); return;
      }
    }
    const submit = form.querySelector('button.primary');
    if (submit.disabled) return;
    submit.disabled = true;
    try {
      if (form.dataset.mode === 'register') {
        if (!await checkAuthUsername(data.username)) {
          form.querySelector('[name="username"]')?.focus(); return;
        }
        const r = await send('/api/auth/register', 'POST', {username:data.username,phone:data.phone,email:data.email,code:data.code,password:data.password,role:0});
        if (version !== authViewVersion || $('authPage').hidden) return;
        openAuth('login', 'replace');
        form.querySelector('[name="phone"]').value = r.phone || data.phone;
        form.querySelector('[name="loginType"]').value = 'CUSTOMER';
        $('authSuccess').textContent = '注册成功，已保留手机号，请重新输入密码登录。';
        $('authSuccess').hidden = false;
        form.querySelector('[name="password"]').focus();
      } else if (mode === 'email') {
        await loginWith({phone:data.phone,email:data.email,code:data.code,loginType:data.loginType}, '/api/auth/login/email');
      } else await loginWith({phone:data.phone,password:data.password,loginType:data.loginType});
    } catch (error) {
      if (version === authViewVersion && !$('authPage').hidden) {
        showAuthError(error.message);
        const invalid = form.querySelector('[aria-invalid="true"]');
        invalid?.focus(); invalid?.scrollIntoView?.({block:'center'});
      }
    }
    finally { submit.disabled = false; }
  });
  const boot = async () => {
    renderShell();
    const version = authRequestVersion;
    let saved;
    try { saved = JSON.parse(sessionStorage.getItem(SESSION_KEY) || 'null'); }
    catch (_) { sessionStorage.removeItem(SESSION_KEY); }
    if (saved && typeof saved.token === 'string' && saved.token) {
      state.token = saved.token;
      state.refreshToken = typeof saved.refreshToken === 'string' ? saved.refreshToken : '';
      try {
        let user;
        try { user = await api('/api/auth/me', {keepSessionOnUnauthorized:true}); }
        catch (error) {
          if (version !== authRequestVersion) return;
          if (error.status !== 401 || !state.refreshToken) throw error;
          const renewed = await api('/api/auth/refresh', {method:'POST',body:JSON.stringify({refreshToken:state.refreshToken}),keepSessionOnUnauthorized:true});
          if (version !== authRequestVersion) return;
          state.token = renewed.token; state.refreshToken = renewed.refreshToken;
          saveSession();
          user = await api('/api/auth/me', {keepSessionOnUnauthorized:true});
        }
        if (version !== authRequestVersion) return;
        state.user = user; state.role = Number(user.role);
        state.page = state.role === 0 ? 'home' : state.role === 3 ? 'rider-pool' : 'overview';
      } catch (error) {
        if (version !== authRequestVersion) return;
        if (error.status === 401) resetAccountState();
        else { state.token = ''; state.refreshToken = ''; state.user = null; }
        toast(error.status === 401 ? error.message : '暂时无法恢复登录，请检查网络后刷新重试。', true);
      }
    }
    renderShell();
    applyAuthRoute();
    await Promise.all([loadCartCount(), renderPage()]);
  };
  boot();
})();

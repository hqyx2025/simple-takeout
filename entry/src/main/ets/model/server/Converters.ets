import { ApiResponse } from '../../service/HttpClient'

import { User, UserRole, StoreItem, GoodsItem, Order, OrderPageData, CartItem, Address, Coupon, Review, Rider, Banner, Announcement, BankCard, GoodsSpec } from '../Models'

import { ServerStore, ServerGoodsSpec, ServerGoods, ServerOrderItem, ServerCartItem, ServerOrder, ServerOrderPage, ServerUser, ServerCoupon, ServerAddress, ServerBankCard, ServerReview, ServerRider, ServerBanner, ServerAnnouncement, MerchantGoodsRequest, SpecInputRequest } from './Contracts'

// ==================== 购物车（需登录） ====================

export function toCartItem(item: ServerCartItem): CartItem {
  const goods: GoodsItem = toGoodsItem(item.goods)
  return {
    goods: goods,
    quantity: item.quantity,
    storeId: item.storeId,
    storeName: item.storeName,
    specId: item.specId ?? 0,
    specName: item.specName ?? '',
    price: item.price ?? goods.price,
    stock: item.stock ?? goods.stock
  }
}

export function toMerchantGoodsRequest(goods: GoodsItem, status: number): MerchantGoodsRequest {
  const req: MerchantGoodsRequest = {
    name: goods.name, description: goods.description, price: goods.price,
    originalPrice: goods.originalPrice !== undefined ? goods.originalPrice : goods.price, image: goods.image,
    categoryId: goods.categoryId, tag: goods.tag || '', status: status,
    merchantCategoryId: goods.merchantCategoryId || 0, stock: goods.stock ?? 999,
    special: goods.isSpecial === true
  }
  // 多规格：仅在有规格时随商品一起提交；清空规格走专用接口，避免误删商户已维护的规格
  if (goods.specs !== undefined && goods.specs.length > 0) {
    req.specs = toSpecInputs(goods.specs)
  }
  return req
}

export function toSpecInputs(specs: GoodsSpec[]): SpecInputRequest[] {
  return specs.map((s: GoodsSpec): SpecInputRequest => {
    const input: SpecInputRequest = { id: s.id, name: s.name, price: s.price, stock: s.stock }
    return input
  })
}

export function toBankCard(card: ServerBankCard): BankCard {
  const result: BankCard = {
    id: card.id,
    bankName: card.bankName,
    cardType: card.cardType,
    cardNoMasked: card.cardNoMasked,
    isDefault: card.isDefault === 1,
    createTime: card.createTime
  }
  return result
}

// ==================== 模型转换 ====================

/**
 * 前端角色 → 服务端角色码（0=用户 1=商户 2=管理端 3=骑手）。
 * 与 toUser() 必须成对覆盖全部四种角色：只用「是商户吗」二分会让骑手注册成 role=0，
 * 注册虽然返回成功，但注册后的自动登录带 loginType=RIDER，服务端按角色校验直接 403，
 * 表现为「骑手注册成功却始终进不去骑手端」。
 */
export function toServerRole(role: UserRole): number {
  return role === UserRole.MERCHANT ? 1
    : role === UserRole.ADMIN ? 2
    : role === UserRole.RIDER ? 3
    : 0
}

export function toUser(u: ServerUser): User {
  const user: User = {
    id: u.id,
    username: u.username,
    avatar: u.avatar,
    phone: u.phone,
    email: u.email ?? '',
    password: '',
    // 角色映射必须覆盖骑手（role=3）：漏掉时骑手会被当成普通用户，
    // 登录页的角色校验（user.role !== 期望角色）随即 logout()，骑手端完全进不去。
    role: u.role === 2 ? UserRole.ADMIN
      : u.role === 1 ? UserRole.MERCHANT
      : u.role === 3 ? UserRole.RIDER
      : UserRole.CUSTOMER,
    balance: u.balance,
    coupons: [],
    orders: [],
    storeIds: []
  }
  return user
}

export function toStoreItem(s: ServerStore): StoreItem {
  const store: StoreItem = {
    id: s.id,
    name: s.name,
    image: s.image,
    rating: s.rating,
    monthlySales: s.monthlySales,
    deliveryFee: s.deliveryFee,
    minOrder: s.minOrder,
    deliveryTime: s.deliveryTime,
    distance: s.distance,
    tags: s.tags || [],
    notice: s.notice,
    address: s.address || '',
    latitude: s.latitude,
    longitude: s.longitude,
    categoryId: s.categoryId,
    categoryIds: s.categoryIds || [],
    ownerId: s.ownerId,
    recommended: s.recommended || 0,
    deliveryRadius: s.deliveryRadius ?? 0,
    deliverable: s.deliverable === true
  }
  return store
}

export function toGoodsItem(g: ServerGoods): GoodsItem {
  const goods: GoodsItem = {
    id: g.id,
    storeId: g.storeId,
    name: g.name,
    description: g.description,
    price: g.price,
    originalPrice: g.originalPrice,
    image: g.image,
    categoryId: g.categoryId,
    merchantCategoryId: g.merchantCategoryId,
    stock: g.stock,
    sales: g.sales,
    rating: g.rating,
    tag: g.tag,
    isSpecial: g.special === true,
    isOnShelf: g.status === 1,
    specs: (g.specs || []).map((s: ServerGoodsSpec): GoodsSpec => {
      const spec: GoodsSpec = {
        id: s.id,
        goodsId: s.goodsId,
        name: s.name,
        price: s.price,
        stock: s.stock,
        sort: s.sort,
        status: s.status
      }
      return spec
    })
  }
  return goods
}

export function toOrder(o: ServerOrder): Order {
  const items: CartItem[] = (o.items || []).map((it: ServerOrderItem) => {
    const goods: GoodsItem = {
      id: it.goodsId,
      name: it.goodsName,
      description: '',
      price: it.price,
      image: it.image,
      categoryId: 1,
      sales: 0,
      rating: 4.5
    }
    const cart: CartItem = {
      goods: goods,
      quantity: it.quantity,
      storeId: o.storeId,
      storeName: o.storeName,
      specId: it.specId ?? 0,
      specName: it.specName ?? '',
      price: it.price
    }
    return cart
  })
  const addr: Address = {
    id: o.address !== null && o.address !== undefined ? o.address.addressId : 0,
    name: o.address !== null && o.address !== undefined ? o.address.name : '',
    phone: o.address !== null && o.address !== undefined ? o.address.phone : '',
    address: '',
    detail: o.address !== null && o.address !== undefined ? o.address.detail : '',
    isDefault: false
  }
  const order: Order = {
    id: o.id,
    storeId: o.storeId,
    storeName: o.storeName,
    storeImage: '',
    items: items,
    totalPrice: o.goodsAmount,
    deliveryFee: o.deliveryFee,
    discountAmount: o.discount,
    payAmount: o.payAmount,
    status: o.status,
    escrowStatus: o.escrowStatus,
    reviewed: o.reviewed,
    createTime: o.createTime,
    payTime: o.payTime,
    deliverTime: o.deliverTime,
    completeTime: o.completeTime,
    expectTime: o.expectTime || '',
    payDeadline: o.payDeadline || '',
    payDeadlineEpochMs: o.payDeadlineEpochMs ?? 0,
    serverNowEpochMs: o.serverNowEpochMs ?? 0,
    couponId: o.couponId ?? 0,
    orderNo: o.orderNo || '',
    riderName: o.riderName || '',
    riderPhone: o.riderPhone || '',
    deliveryType: o.deliveryType ?? 'DELIVERY',
    readyTime: o.readyTime || '',
    paymentChannel: o.paymentChannel ?? '',
    outTradeNo: o.outTradeNo ?? '',
    paymentUrl: o.paymentUrl ?? '',
    appOrderInfo: o.appOrderInfo ?? '',
    paymentMode: o.paymentMode ?? '',
    paymentSandbox: o.paymentSandbox ?? false,
    cancelSource: o.cancelSource ?? '',
    cancelReasonCode: o.cancelReasonCode ?? '',
    cancelReason: o.cancelReason ?? '',
    rejectGoodsId: o.rejectGoodsId ?? 0,
    rejectSpecId: o.rejectSpecId ?? 0,
    address: addr,
    remark: o.remark
  }
  return order
}

export function toOrderPageData(resp: ApiResponse<ServerOrderPage>, requestedPage: number,
  requestedPageSize: number): OrderPageData {
  if (resp.code !== 200 || resp.data === null || resp.data === undefined) {
    return { list: [], total: 0, page: requestedPage, pageSize: requestedPageSize, hasMore: false }
  }
  return {
    list: resp.data.list.map((order: ServerOrder) => toOrder(order)),
    total: resp.data.total,
    page: resp.data.page,
    pageSize: resp.data.pageSize,
    hasMore: resp.data.hasMore
  }
}

export function toCoupon(c: ServerCoupon): Coupon {
  const coupon: Coupon = {
    id: c.id,
    amount: c.amount,
    minOrder: c.threshold,
    startTime: c.createTime,
    endTime: c.expireTime,
    // 券状态 0=可用 1=已使用 2=已过期失效：只有 0 才可用，
    // 否则过期券会被列进「可用券」，选中后下单必被后端拒绝（提示还与券列表自相矛盾）
    used: c.status !== 0,
    storeId: c.storeId,
    storeName: '',
    condition: `满${Math.round(c.threshold)}减${Math.round(c.amount)}`
  }
  return coupon
}

export function toAddress(a: ServerAddress): Address {
  const mapAddress: string = (a.mapAddress ?? '').trim()
  const doorDetail: string = (a.doorDetail ?? '').trim()
  const addr: Address = {
    id: a.id,
    name: a.name,
    phone: a.phone,
    // 新服务端返回结构化字段；旧服务端只有 detail 时仍按完整地址兼容展示。
    address: mapAddress === '' ? a.detail : mapAddress,
    detail: mapAddress === '' ? '' : doorDetail,
    isDefault: a.isDefault === 1,
    tag: (a.tag ?? '').trim(),
    latitude: a.latitude,
    longitude: a.longitude
  }
  return addr
}

export function toReview(r: ServerReview): Review {
  const review: Review = {
    id: r.id,
    orderId: r.orderId || 0,
    storeId: r.storeId,
    goodsId: r.goodsId || 0,
    userId: r.userId,
    username: r.userName,
    rating: r.rating,
    content: r.content,
    tags: r.tags || [],
    images: r.images || [],
    anonymous: r.anonymous || 0,
    reply: r.reply || '',
    replyTime: r.replyTime || '',
    createTime: r.createTime
  }
  return review
}

export function toRider(r: ServerRider): Rider {
  const rider: Rider = {
    id: r.id,
    userId: r.userId,
    name: r.name,
    phone: r.phone,
    online: r.online,
    totalOrders: r.totalOrders,
    totalIncome: r.totalIncome,
    status: r.status,
    deliveryRadius: r.deliveryRadius ?? 0,
    latitude: r.latitude,
    longitude: r.longitude,
    locationAddress: r.locationAddress ?? '',
    createTime: r.createTime
  }
  return rider
}

export function toBanner(b: ServerBanner): Banner {
  const banner: Banner = {
    id: b.id,
    title: b.title,
    subtitle: b.subtitle || '',
    image: b.image || '',
    color: b.color || '#FF6B35',
    linkType: b.linkType || 'NONE',
    linkValue: b.linkValue || '',
    sort: b.sort || 0,
    status: b.status,
    createTime: b.createTime
  }
  return banner
}

export function toAnnouncement(a: ServerAnnouncement): Announcement {
  const announcement: Announcement = {
    id: a.id,
    title: a.title,
    content: a.content,
    status: a.status,
    createTime: a.createTime
  }
  return announcement
}

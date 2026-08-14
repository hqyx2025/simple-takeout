/**
 * 模拟数据服务 - 提供本地模拟数据
 */
import { Category, StoreItem, GoodsItem, Address, Coupon, Order, CartItem, User, UserRole, Review, Favorite, DeliveryStep } from '../model/Models'

// ============ 分类数据 ============
export function getCategories(): Category[] {
  return [
    { id: 1, name: '美食', icon: '🍔', color: '#FF6B35' },
    { id: 2, name: '快餐', icon: '🍟', color: '#FFB74D' },
    { id: 3, name: '饮品', icon: '🧋', color: '#4FC3F7' },
    { id: 4, name: '甜品', icon: '🍰', color: '#F06292' },
    { id: 5, name: '火锅', icon: '🍲', color: '#E53935' },
    { id: 6, name: '烧烤', icon: '🍢', color: '#FF7043' },
    { id: 7, name: '面食', icon: '🍜', color: '#FFA726' },
    { id: 8, name: '寿司', icon: '🍣', color: '#66BB6A' },
  ]
}

// ============ 店铺数据 ============
export function getStores(categoryId?: number): StoreItem[] {
  let stores: StoreItem[] = [
    {
      id: 1,
      name: '黄焖鸡米饭',
      image: 'https://img.52z.com/upload/img/2020/06/10/m5edcaa28a4da7a32.jpg',
      rating: 4.8,
      monthlySales: 2356,
      deliveryFee: 3,
      minOrder: 20,
      deliveryTime: '28分钟',
      distance: '1.2km',
      tags: ['满减', '新客立减'],
      notice: '本店所有菜品现做现卖，保证新鲜',
      categoryId: 1,
      categoryIds: [1, 2, 7],
      ownerId: 100,
    },
    {
      id: 2,
      name: '星巴克咖啡',
      image: 'https://img.52z.com/upload/img/2020/06/10/m5edcaa28a4da7a32.jpg',
      rating: 4.9,
      monthlySales: 5621,
      deliveryFee: 5,
      minOrder: 30,
      deliveryTime: '35分钟',
      distance: '2.1km',
      tags: ['品牌连锁', '优惠活动'],
      notice: '新品冰摇系列上市',
      categoryId: 3,
      categoryIds: [3],
      ownerId: 100,
    },
    {
      id: 3,
      name: '张亮麻辣烫',
      image: 'https://img.52z.com/upload/img/2020/06/10/m5edcaa28a4da7a32.jpg',
      rating: 4.6,
      monthlySales: 1890,
      deliveryFee: 2,
      minOrder: 15,
      deliveryTime: '25分钟',
      distance: '0.8km',
      tags: ['满减', '准时达'],
      notice: '新鲜食材，当日采购',
      categoryId: 1,
      categoryIds: [1, 5],
      ownerId: 100,
    },
    {
      id: 4,
      name: '肯德基',
      image: 'https://img.52z.com/upload/img/2020/06/10/m5edcaa28a4da7a32.jpg',
      rating: 4.7,
      monthlySales: 8900,
      deliveryFee: 6,
      minOrder: 25,
      deliveryTime: '30分钟',
      distance: '1.5km',
      tags: ['品牌连锁', '疯狂星期四'],
      notice: '疯狂星期四V我50',
      categoryId: 2,
      categoryIds: [2],
      ownerId: 100,
    },
    {
      id: 5,
      name: '一点点奶茶',
      image: 'https://img.52z.com/upload/img/2020/06/10/m5edcaa28a4da7a32.jpg',
      rating: 4.5,
      monthlySales: 3200,
      deliveryFee: 3,
      minOrder: 15,
      deliveryTime: '22分钟',
      distance: '0.5km',
      tags: ['满减', '下单送杯'],
      notice: '秋天的第一杯奶茶等你',
      categoryId: 3,
      categoryIds: [3],
      ownerId: 100,
    },
    {
      id: 6,
      name: '重庆老火锅',
      image: 'https://img.52z.com/upload/img/2020/06/10/m5edcaa28a4da7a32.jpg',
      rating: 4.8,
      monthlySales: 980,
      deliveryFee: 4,
      minOrder: 50,
      deliveryTime: '45分钟',
      distance: '3.0km',
      tags: ['满减', '好评返现'],
      notice: '正宗重庆味道，麻辣鲜香',
      categoryId: 5,
      categoryIds: [5],
      ownerId: 101,
    },
    {
      id: 7,
      name: '兰州拉面',
      image: 'https://img.52z.com/upload/img/2020/06/10/m5edcaa28a4da7a32.jpg',
      rating: 4.4,
      monthlySales: 1560,
      deliveryFee: 2,
      minOrder: 12,
      deliveryTime: '20分钟',
      distance: '0.6km',
      tags: ['新店特惠'],
      notice: '一清二白三红四绿五黄',
      categoryId: 7,
      categoryIds: [7, 1],
      ownerId: 101,
    },
    {
      id: 8,
      name: '小郡肝串串香',
      image: 'https://img.52z.com/upload/img/2020/06/10/m5edcaa28a4da7a32.jpg',
      rating: 4.6,
      monthlySales: 2100,
      deliveryFee: 3,
      minOrder: 30,
      deliveryTime: '35分钟',
      distance: '1.8km',
      tags: ['满减', '夜宵专区'],
      notice: '精选食材，现穿现烤',
      categoryId: 6,
      categoryIds: [6, 5],
      ownerId: 101,
    },
    {
      id: 9,
      name: '好利来蛋糕',
      image: 'https://img.52z.com/upload/img/2020/06/10/m5edcaa28a4da7a32.jpg',
      rating: 4.9,
      monthlySales: 4500,
      deliveryFee: 5,
      minOrder: 30,
      deliveryTime: '40分钟',
      distance: '2.5km',
      tags: ['品牌连锁', '生日蛋糕'],
      notice: '新鲜烘焙，当日送达',
      categoryId: 4,
      categoryIds: [4],
      ownerId: 102,
    },
    {
      id: 10,
      name: '食其家牛丼饭',
      image: 'https://img.52z.com/upload/img/2020/06/10/m5edcaa28a4da7a32.jpg',
      rating: 4.5,
      monthlySales: 1200,
      deliveryFee: 3,
      minOrder: 20,
      deliveryTime: '25分钟',
      distance: '1.0km',
      tags: ['日式快餐', '满减'],
      notice: '日式风味，快速配送',
      categoryId: 2,
      categoryIds: [2, 1],
      ownerId: 102,
    },
  ]

  if (categoryId !== undefined && categoryId !== 0) {
    stores = stores.filter(s => s.categoryId === categoryId ||
      (s.categoryIds && s.categoryIds.includes(categoryId)))
  }
  // 扩充至30家店铺（追加生成店铺）
  stores = stores.concat(buildExtraStores())
  return stores
}

// ============ 商品数据 ============
export function getGoodsByStore(storeId: number): GoodsItem[] {
  const goodsMap: Record<number, GoodsItem[]> = {
    1: [
      { id: 101, name: '黄焖鸡米饭(大份)', description: '精选鸡肉，秘制酱料，配米饭', price: 28, originalPrice: 32, image: '', categoryId: 1, sales: 890, rating: 4.9, tag: '招牌' },
      { id: 102, name: '黄焖鸡米饭(中份)', description: '精选鸡肉，秘制酱料，配米饭', price: 22, image: '', categoryId: 1, sales: 1200, rating: 4.8 },
      { id: 103, name: '黄焖排骨米饭', description: '精选排骨，软烂入味', price: 32, image: '', categoryId: 1, sales: 560, rating: 4.7, tag: '新品' },
      { id: 104, name: '黄焖豆腐米饭', description: '素食优选，鲜嫩豆腐', price: 18, image: '', categoryId: 1, sales: 340, rating: 4.5 },
      { id: 105, name: '土豆排骨煲', description: '土豆软糯，排骨香嫩', price: 36, image: '', categoryId: 1, sales: 420, rating: 4.8 },
      { id: 106, name: '番茄鸡蛋汤', description: '酸甜可口，营养丰富', price: 8, image: '', categoryId: 1, sales: 780, rating: 4.6 },
      { id: 107, name: '紫菜蛋花汤', description: '清淡爽口，暖胃养身', price: 6, image: '', categoryId: 1, sales: 650, rating: 4.4 },
      { id: 108, name: '加饭(小份)', description: '额外加一碗米饭', price: 2, image: '', categoryId: 1, sales: 2000, rating: 5.0 },
    ],
    2: [
      { id: 201, name: '美式咖啡(大杯)', description: '浓郁醇厚，唤醒精神', price: 28, image: '', categoryId: 3, sales: 3200, rating: 4.9, tag: '招牌' },
      { id: 202, name: '拿铁(大杯)', description: '丝滑奶香，经典之选', price: 32, image: '', categoryId: 3, sales: 2800, rating: 4.8 },
      { id: 203, name: '卡布奇诺(大杯)', description: '奶泡绵密，层次分明', price: 32, image: '', categoryId: 3, sales: 1500, rating: 4.7 },
      { id: 204, name: '焦糖玛奇朵(大杯)', description: '甜蜜焦糖，香浓咖啡', price: 35, image: '', categoryId: 3, sales: 1200, rating: 4.8, tag: '新品' },
      { id: 205, name: '星冰乐(大杯)', description: '冰爽怡人，夏日必备', price: 38, originalPrice: 42, image: '', categoryId: 3, sales: 2000, rating: 4.6 },
      { id: 206, name: '抹茶星冰乐', description: '日式抹茶，清凉一夏', price: 38, image: '', categoryId: 3, sales: 900, rating: 4.5 },
      { id: 207, name: '芝士蛋糕', description: '浓郁芝士，入口即化', price: 28, image: '', categoryId: 4, sales: 1100, rating: 4.9 },
      { id: 208, name: '巧克力牛角包', description: '外酥内软，巧克力香浓', price: 18, image: '', categoryId: 4, sales: 800, rating: 4.7 },
    ],
    3: [
      { id: 301, name: '麻辣烫(大碗)', description: '自选食材，麻辣鲜香', price: 25, image: '', categoryId: 1, sales: 680, rating: 4.6, tag: '招牌' },
      { id: 302, name: '麻辣烫(中碗)', description: '自选食材，麻辣鲜香', price: 18, image: '', categoryId: 1, sales: 900, rating: 4.5 },
      { id: 303, name: '冒菜套餐', description: '精选配菜，搭配米饭', price: 22, image: '', categoryId: 1, sales: 450, rating: 4.7 },
      { id: 304, name: '番茄牛腩烫', description: '酸甜番茄，软烂牛腩', price: 28, image: '', categoryId: 1, sales: 320, rating: 4.8, tag: '新品' },
      { id: 305, name: '酸辣粉', description: '酸辣爽滑，地道川味', price: 12, image: '', categoryId: 1, sales: 560, rating: 4.4 },
      { id: 306, name: '凉面', description: '清爽凉面，夏日之选', price: 10, image: '', categoryId: 7, sales: 340, rating: 4.3 },
    ],
    4: [
      { id: 401, name: '香辣鸡腿堡套餐', description: '汉堡+薯条+可乐', price: 32, originalPrice: 38, image: '', categoryId: 2, sales: 5600, rating: 4.7, tag: '招牌' },
      { id: 402, name: '原味鸡', description: '多汁鲜嫩，经典原味', price: 15, image: '', categoryId: 2, sales: 3200, rating: 4.6 },
      { id: 403, name: '烤翅(5只)', description: '外焦里嫩，香气四溢', price: 19, image: '', categoryId: 2, sales: 2800, rating: 4.8 },
      { id: 404, name: '葡式蛋挞(2只)', description: '酥皮嫩心，香甜可口', price: 16, image: '', categoryId: 4, sales: 4500, rating: 4.9 },
      { id: 405, name: '土豆泥', description: '细腻绵密，奶香浓郁', price: 8, image: '', categoryId: 2, sales: 2100, rating: 4.5 },
      { id: 406, name: '玉米沙拉', description: '新鲜玉米，健康清爽', price: 12, image: '', categoryId: 2, sales: 1800, rating: 4.4, tag: '新品' },
      { id: 407, name: '全家桶', description: '5块吮指原味鸡+3个烤翅', price: 69, originalPrice: 89, image: '', categoryId: 2, sales: 1200, rating: 4.8 },
    ],
    5: [
      { id: 501, name: '波霸奶茶', description: '经典波波，Q弹有嚼劲', price: 14, image: '', categoryId: 3, sales: 2100, rating: 4.7, tag: '招牌' },
      { id: 502, name: '四季春奶茶', description: '清新茶香，醇厚奶味', price: 12, image: '', categoryId: 3, sales: 1800, rating: 4.5 },
      { id: 503, name: '红茶玛奇朵', description: '绵密奶盖，红茶醇香', price: 16, image: '', categoryId: 3, sales: 1500, rating: 4.6 },
      { id: 504, name: '乌龙奶茶', description: '高山乌龙，回甘无穷', price: 14, image: '', categoryId: 3, sales: 1200, rating: 4.5 },
      { id: 505, name: '水果茶', description: '鲜果现做，清甜爽口', price: 18, originalPrice: 22, image: '', categoryId: 3, sales: 900, rating: 4.8, tag: '新品' },
      { id: 506, name: '咖啡奶茶', description: '双重享受，提神醒脑', price: 16, image: '', categoryId: 3, sales: 800, rating: 4.4 },
    ],
    6: [
      { id: 601, name: '鸳鸯锅(小)', description: '麻辣+清汤，一锅两味', price: 68, image: '', categoryId: 5, sales: 450, rating: 4.8, tag: '招牌' },
      { id: 602, name: '牛油锅底', description: '正宗牛油，麻辣过瘾', price: 48, image: '', categoryId: 5, sales: 380, rating: 4.7 },
      { id: 603, name: '番茄锅底', description: '酸甜浓郁，开胃下饭', price: 38, image: '', categoryId: 5, sales: 320, rating: 4.6 },
      { id: 604, name: '精品肥牛卷', description: '雪花肥牛，鲜嫩多汁', price: 58, image: '', categoryId: 5, sales: 520, rating: 4.9 },
      { id: 605, name: '鲜毛肚', description: '鲜脆爽口，火锅必点', price: 42, image: '', categoryId: 5, sales: 480, rating: 4.8 },
      { id: 606, name: '鸭血豆腐拼盘', description: '鸭血+豆腐+豆皮', price: 28, image: '', categoryId: 5, sales: 350, rating: 4.5 },
      { id: 607, name: '手切羊肉', description: '现切羊肉，鲜嫩不膻', price: 52, image: '', categoryId: 5, sales: 400, rating: 4.7, tag: '新品' },
      { id: 608, name: '菌菇拼盘', description: '多种菌菇，营养丰富', price: 32, image: '', categoryId: 5, sales: 280, rating: 4.6 },
    ],
    7: [
      { id: 701, name: '牛肉拉面(大碗)', description: '一清二白三红四绿五黄', price: 22, image: '', categoryId: 7, sales: 890, rating: 4.7, tag: '招牌' },
      { id: 702, name: '牛肉拉面(小碗)', description: '经典兰州拉面', price: 16, image: '', categoryId: 7, sales: 1100, rating: 4.6 },
      { id: 703, name: '肉蛋双飞拉面', description: '牛肉+鸡蛋+拉面', price: 26, image: '', categoryId: 7, sales: 560, rating: 4.8 },
      { id: 704, name: '炸酱面', description: '京味炸酱，劲道面条', price: 15, image: '', categoryId: 7, sales: 430, rating: 4.5 },
      { id: 705, name: '凉皮', description: '爽滑筋道，酸辣可口', price: 10, image: '', categoryId: 7, sales: 680, rating: 4.4, tag: '新品' },
      { id: 706, name: '牛肉盖浇饭', description: '大块牛肉，浇在米饭上', price: 20, image: '', categoryId: 1, sales: 350, rating: 4.5 },
    ],
    8: [
      { id: 801, name: '串串香(30串)', description: '自选荤素搭配', price: 39, originalPrice: 45, image: '', categoryId: 6, sales: 780, rating: 4.7, tag: '招牌' },
      { id: 802, name: '串串香(50串)', description: '自选荤素搭配', price: 59, originalPrice: 68, image: '', categoryId: 6, sales: 520, rating: 4.6 },
      { id: 803, name: '钵钵鸡(大份)', description: '红油飘香，鲜嫩入味', price: 32, image: '', categoryId: 6, sales: 450, rating: 4.8 },
      { id: 804, name: '烤脑花', description: '香辣入味，口感嫩滑', price: 18, image: '', categoryId: 6, sales: 320, rating: 4.5 },
      { id: 805, name: '烤茄子', description: '蒜香浓郁，软糯可口', price: 12, image: '', categoryId: 6, sales: 280, rating: 4.4 },
      { id: 806, name: '锡纸花甲', description: '蒜蓉粉丝，鲜美多汁', price: 22, image: '', categoryId: 6, sales: 380, rating: 4.6, tag: '新品' },
    ],
    9: [
      { id: 901, name: '半熟芝士', description: '入口即化，奶香浓郁', price: 28, image: '', categoryId: 4, sales: 2200, rating: 4.9, tag: '招牌' },
      { id: 902, name: '提拉米苏', description: '经典意式，咖啡奶香', price: 32, image: '', categoryId: 4, sales: 1800, rating: 4.8 },
      { id: 903, name: '草莓奶油蛋糕', description: '新鲜草莓，绵密奶油', price: 38, image: '', categoryId: 4, sales: 1500, rating: 4.7 },
      { id: 904, name: '黑森林蛋糕', description: '巧克力+樱桃，经典组合', price: 35, image: '', categoryId: 4, sales: 900, rating: 4.6 },
      { id: 905, name: '泡芙(6只)', description: '酥皮泡芙，奶油馅心', price: 22, image: '', categoryId: 4, sales: 1600, rating: 4.8 },
      { id: 906, name: '肉松小贝(4只)', description: '肉松外裹，沙拉酱心', price: 18, image: '', categoryId: 4, sales: 1300, rating: 4.7, tag: '新品' },
    ],
    10: [
      { id: 1001, name: '牛丼饭(大)', description: '牛肉洋葱盖饭，日式经典', price: 28, image: '', categoryId: 2, sales: 680, rating: 4.6, tag: '招牌' },
      { id: 1002, name: '牛丼饭(中)', description: '牛肉洋葱盖饭', price: 22, image: '', categoryId: 2, sales: 520, rating: 4.5 },
      { id: 1003, name: '咖喱猪排饭', description: '浓郁咖喱，酥脆猪排', price: 26, image: '', categoryId: 2, sales: 380, rating: 4.7 },
      { id: 1004, name: '照烧鸡排饭', description: '照烧酱汁，鲜嫩鸡排', price: 24, image: '', categoryId: 2, sales: 420, rating: 4.5 },
      { id: 1005, name: '日式拉面', description: '浓厚豚骨汤底，劲道面条', price: 25, image: '', categoryId: 7, sales: 340, rating: 4.6, tag: '新品' },
      { id: 1006, name: '味噌汤', description: '日式味噌，暖胃舒心', price: 6, image: '', categoryId: 1, sales: 280, rating: 4.3 },
    ],
  }

  // 每家店扩充至30个商品（不足部分由生成函数补齐）
  const baseGoods: GoodsItem[] = goodsMap[storeId] || []
  return baseGoods.concat(buildExtraGoods(storeId, baseGoods.length))
}

// ============ 地址数据 ============
export function getDefaultAddresses(): Address[] {
  const addresses: Address[] = [
    {
      id: 1,
      name: '张三',
      phone: '13800138000',
      address: '北京市海淀区',
      detail: '中关村大街1号 清华大学学生公寓3号楼205',
      isDefault: true,
      tag: '学校',
    },
    {
      id: 2,
      name: '张三',
      phone: '13800138000',
      address: '北京市朝阳区',
      detail: '望京SOHO T3 1208室',
      isDefault: false,
      tag: '公司',
    },
    {
      id: 3,
      name: '张三',
      phone: '13800138000',
      address: '北京市丰台区',
      detail: '丰台科技园8号楼1单元501',
      isDefault: false,
      tag: '家',
    },
  ]
  // 扩充至30条地址
  return addresses.concat(buildExtraAddresses())
}

// ============ 优惠券数据 ============
export function getDefaultCoupons(): Coupon[] {
  const coupons: Coupon[] = [
    { id: 1, amount: 5, minOrder: 20, startTime: '2026-01-01', endTime: '2026-12-31', used: false, condition: '满20元可用', storeName: '通用券' },
    { id: 2, amount: 10, minOrder: 35, startTime: '2026-01-01', endTime: '2026-12-31', used: false, condition: '满35元可用', storeName: '通用券' },
    { id: 3, amount: 15, minOrder: 50, startTime: '2026-01-01', endTime: '2026-12-31', used: false, condition: '满50元可用', storeName: '通用券' },
    { id: 4, amount: 8, minOrder: 25, startTime: '2026-01-01', endTime: '2026-12-31', used: false, condition: '满25元可用', storeId: 2, storeName: '星巴克咖啡' },
    { id: 5, amount: 3, minOrder: 15, startTime: '2026-01-01', endTime: '2026-12-31', used: false, condition: '满15元可用', storeId: 5, storeName: '一点点奶茶' },
  ]
  // 扩充至30张优惠券
  return coupons.concat(buildExtraCoupons())
}

// ============ 订单数据 ============
export function getDefaultOrders(): Order[] {
  const orders: Order[] = [
    {
      id: 10001,
      storeId: 1,
      storeName: '黄焖鸡米饭',
      storeImage: '',
      items: [
        { goods: getGoodsByStore(1)[0], quantity: 1, storeId: 1, storeName: '黄焖鸡米饭' },
        { goods: getGoodsByStore(1)[5], quantity: 1, storeId: 1, storeName: '黄焖鸡米饭' },
      ],
      totalPrice: 36,
      deliveryFee: 3,
      discountAmount: 5,
      payAmount: 34,
      status: 4,
      createTime: '2026-07-04 12:30:00',
      payTime: '2026-07-04 12:31:00',
      deliverTime: '2026-07-04 12:33:00',
      completeTime: '2026-07-04 12:58:00',
      address: getDefaultAddresses()[0],
      remark: '不要辣',
    },
    {
      id: 10002,
      storeId: 2,
      storeName: '星巴克咖啡',
      storeImage: '',
      items: [
        { goods: getGoodsByStore(2)[0], quantity: 2, storeId: 2, storeName: '星巴克咖啡' },
      ],
      totalPrice: 56,
      deliveryFee: 5,
      discountAmount: 8,
      payAmount: 53,
      status: 3,
      createTime: '2026-07-05 09:15:00',
      payTime: '2026-07-05 09:16:00',
      deliverTime: '2026-07-05 09:18:00',
      address: getDefaultAddresses()[1],
      remark: '少冰',
    },
    {
      id: 10003,
      storeId: 4,
      storeName: '肯德基',
      storeImage: '',
      items: [
        { goods: getGoodsByStore(4)[0], quantity: 1, storeId: 4, storeName: '肯德基' },
        { goods: getGoodsByStore(4)[3], quantity: 2, storeId: 4, storeName: '肯德基' },
      ],
      totalPrice: 64,
      deliveryFee: 6,
      discountAmount: 10,
      payAmount: 60,
      status: 1,
      createTime: '2026-07-05 11:45:00',
      payTime: '2026-07-05 11:46:00',
      address: getDefaultAddresses()[0],
      remark: '',
    },
  ]
  // 扩充至30条订单
  return orders.concat(buildExtraOrders())
}

// ============ 默认用户 ============
// 模拟用户列表（用于登录验证）
export function getMockUsers(): User[] {
  return [
    {
      id: 1,
      username: '美食家小张',
      avatar: '',
      phone: '13800138000',
      password: '123456',
      role: UserRole.CUSTOMER,
      balance: 58.5,
      coupons: getDefaultCoupons(),
      orders: getDefaultOrders(),
      storeIds: [],
    },
    {
      id: 2,
      username: '小王',
      avatar: '',
      phone: '13900139000',
      password: '123456',
      role: UserRole.CUSTOMER,
      balance: 30.0,
      coupons: getDefaultCoupons(),
      orders: getDefaultOrders(),
      storeIds: [],
    },
    {
      id: 100,
      username: '黄焖鸡老板',
      avatar: '',
      phone: '13600136000',
      password: '123456',
      role: UserRole.MERCHANT,
      balance: 1200.0,
      coupons: [],
      orders: [],
      storeIds: [1, 2, 3, 4, 5],
    },
    {
      id: 101,
      username: '串串香老板',
      avatar: '',
      phone: '13700137000',
      password: '123456',
      role: UserRole.MERCHANT,
      balance: 800.0,
      coupons: [],
      orders: [],
      storeIds: [6, 7, 8, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20],
    },
    {
      id: 102,
      username: '甜品店老板',
      avatar: '',
      phone: '13500135000',
      password: '123456',
      role: UserRole.MERCHANT,
      balance: 600.0,
      coupons: [],
      orders: [],
      storeIds: [9, 10, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30],
    },
  ]
}

// 默认用户：未登录状态（id=0，不占用真实账号）
export function getDefaultUser(): User {
  return {
    id: 0,
    username: '未登录',
    avatar: '',
    phone: '',
    password: '',
    role: UserRole.CUSTOMER,
    balance: 0,
    coupons: [],
    orders: [],
    storeIds: [],
  }
}

// ============ 搜索热门词 ============
export function getHotSearchWords(): string[] {
  return ['黄焖鸡', '奶茶', '肯德基', '麻辣烫', '拉面', '炸鸡', '火锅', '咖啡', '烤鸭', '川菜', '汉堡', '披萨', '蛋糕', '水果茶', '烧烤', '串串', '寿司', '面条', '饺子', '米饭', '小龙虾', '水煮鱼', '酸菜鱼', '宫保鸡丁', '蛋炒饭', '凉皮', '包子', '粥', '甜品', '夜宵']
}

// ============ 获取商品分类(店铺内) ============
export function getGoodsCategories(storeId: number): string[] {
  const goods = getGoodsByStore(storeId)
  const categories: string[] = []
  const categoryNames: Record<number, string> = {
    1: '热销菜', 2: '快餐', 3: '饮品', 4: '甜品', 5: '火锅', 6: '烧烤', 7: '面食'
  }
  goods.forEach(g => {
    const name = categoryNames[g.categoryId] || '其他'
    if (!categories.includes(name)) {
      categories.push(name)
    }
  })
  return categories.length > 0 ? categories : ['全部']
}

// ============ 格式化销量 ============
export function formatSales(sales: number): string {
  if (sales >= 10000) {
    return (sales / 10000).toFixed(1) + '万'
  }
  return sales.toString()
}

// ============ 评价数据 ============
export function getDefaultReviews(): Review[] {
  let reviews: Review[] = []
  reviews.push({
    id: 1, orderId: 10001, storeId: 1, userId: 1, username: '美食家小张',
    rating: 5, content: '黄焖鸡很入味，米饭也香，配送速度快！',
    tags: ['味道好', '配送快', '会回购'], createTime: '2026-07-04 13:05:00'
  })
  reviews.push({
    id: 2, orderId: 10002, storeId: 2, userId: 1, username: '美食家小张',
    rating: 4, content: '咖啡不错，就是配送稍慢',
    tags: ['味道好', '分量足'], createTime: '2026-07-05 09:30:00'
  })
  reviews.push({
    id: 3, orderId: 10003, storeId: 4, userId: 2, username: '小王',
    rating: 5, content: '肯德基永远的神，疯狂星期四太香了',
    tags: ['味道好', '推荐', '会回购'], createTime: '2026-07-05 12:10:00'
  })
  reviews.push({
    id: 4, orderId: 10001, storeId: 1, userId: 2, username: '小王',
    rating: 4, content: '味道不错，就是有点咸',
    tags: ['味道好', '分量足'], createTime: '2026-07-03 18:20:00'
  })
  reviews.push({
    id: 5, orderId: 10002, storeId: 2, userId: 2, username: '小王',
    rating: 5, content: '星巴克的拿铁永远好喝',
    tags: ['味道好', '推荐', '干净卫生'], createTime: '2026-07-04 10:00:00'
  })
  // 扩充至30条评价
  return reviews.concat(buildExtraReviews())
}

// ============ 店铺评价数据 ============
export function getReviewsByStore(storeId: number): Review[] {
  return getDefaultReviews().filter(r => r.storeId === storeId)
}

// ============ 收藏数据 ============
export function getDefaultFavorites(): Favorite[] {
  let favorites: Favorite[] = []
  favorites.push({
    id: 1, userId: 1, storeId: 1, storeName: '黄焖鸡米饭', storeImage: '',
    createTime: '2026-07-01 10:00:00'
  })
  favorites.push({
    id: 2, userId: 1, storeId: 4, storeName: '肯德基', storeImage: '',
    createTime: '2026-07-02 14:30:00'
  })
  favorites.push({
    id: 3, userId: 1, storeId: 5, storeName: '一点点奶茶', storeImage: '',
    createTime: '2026-07-03 09:15:00'
  })
  // 扩充至30条收藏
  return favorites.concat(buildExtraFavorites())
}

// ============ 配送时间轴数据 ============
export function getDeliverySteps(orderStatus: number, createTime: string, payTime?: string, deliverTime?: string, completeTime?: string): DeliveryStep[] {
  let steps: DeliveryStep[] = []
  steps.push({
    status: 1, title: '已下单', time: createTime,
    completed: orderStatus >= 1
  })
  steps.push({
    status: 2, title: '商家接单', time: payTime || '',
    completed: orderStatus >= 2
  })
  steps.push({
    status: 3, title: '配送中', time: deliverTime || '',
    completed: orderStatus >= 3
  })
  steps.push({
    status: 4, title: '已送达', time: completeTime || '',
    completed: orderStatus >= 4
  })
  return steps
}

// ============ 可领取的优惠券 ============
export function getClaimableCoupons(): Coupon[] {
  let coupons: Coupon[] = []
  coupons.push({
    id: 101, amount: 2, minOrder: 10, startTime: '2026-01-01', endTime: '2026-12-31',
    used: false, condition: '满10元可用', storeName: '通用券'
  })
  coupons.push({
    id: 102, amount: 6, minOrder: 30, startTime: '2026-01-01', endTime: '2026-12-31',
    used: false, condition: '满30元可用', storeName: '通用券'
  })
  coupons.push({
    id: 103, amount: 12, minOrder: 45, startTime: '2026-01-01', endTime: '2026-12-31',
    used: false, condition: '满45元可用', storeName: '通用券'
  })
  coupons.push({
    id: 104, amount: 5, minOrder: 20, startTime: '2026-01-01', endTime: '2026-12-31',
    used: false, condition: '满20元可用', storeId: 4, storeName: '肯德基'
  })
  coupons.push({
    id: 105, amount: 4, minOrder: 15, startTime: '2026-01-01', endTime: '2026-12-31',
    used: false, condition: '满15元可用', storeId: 1, storeName: '黄焖鸡米饭'
  })
  // 扩充至30张可领取优惠券
  return coupons.concat(buildExtraClaimableCoupons())
}

// ================= 扩充数据生成（每种数据集30条，用于小规模数据量页面效果验证） =================

// 追加店铺名称池
const EXTRA_STORE_NAMES: string[] = [
  '老王烤鸭店', '川味居', '湘味小馆', '沙县小吃', '杨国福麻辣烫',
  '蜜雪冰城', '茶百道', '书亦烧仙草', '瑞幸咖啡', '必胜客',
  '海底捞外送', '呷哺呷哺', '鲜芋仙', '满记甜品', '绝味鸭脖',
  '周黑鸭', '正新鸡排', '汉堡王', '吉野家', '味千拉面'
]
const EXTRA_STORE_TAGS: string[] = ['满减', '新客立减', '准时达', '品牌连锁', '夜宵专区', '优惠活动', '好评返现', '新品上市']
const EXTRA_STORE_NOTICES: string[] = [
  '本店食材每日新鲜采购', '下单后30分钟内出餐', '欢迎光临，祝您用餐愉快',
  '支持备注口味，请提前说明', '门店新装开业，全场9折'
]
const EXTRA_STORE_IMAGE: string = 'https://img.52z.com/upload/img/2020/06/10/m5edcaa28a4da7a32.jpg'

// 生成扩充店铺（ID 11-30：11-20归商户101，21-30归商户102）
function buildExtraStores(): StoreItem[] {
  const stores: StoreItem[] = []
  const categoryOrder: number[] = [1, 2, 3, 4, 5, 6, 7, 8]
  for (let i = 0; i < EXTRA_STORE_NAMES.length; i++) {
    const id: number = 11 + i
    const catId: number = categoryOrder[i % categoryOrder.length]
    const ownerId: number = i < 10 ? 101 : 102
    stores.push({
      id: id,
      name: EXTRA_STORE_NAMES[i],
      image: EXTRA_STORE_IMAGE,
      rating: 4.0 + ((i * 7) % 10) / 10,
      monthlySales: 500 + ((i * 373) % 8500),
      deliveryFee: 2 + (i % 5),
      minOrder: 12 + ((i * 5) % 35),
      deliveryTime: `${20 + (i % 26)}分钟`,
      distance: `${(5 + (i * 3) % 25) / 10}km`,
      tags: [EXTRA_STORE_TAGS[i % EXTRA_STORE_TAGS.length], EXTRA_STORE_TAGS[(i + 3) % EXTRA_STORE_TAGS.length]],
      notice: EXTRA_STORE_NOTICES[i % EXTRA_STORE_NOTICES.length],
      categoryId: catId,
      categoryIds: [catId, (catId % 8) + 1],
      ownerId: ownerId,
    })
  }
  return stores
}

// 商品名模板池（60个通用菜名）
const EXTRA_GOODS_NAMES: string[] = [
  '宫保鸡丁', '鱼香肉丝', '麻婆豆腐', '红烧肉', '糖醋里脊', '清蒸鲈鱼',
  '干煸四季豆', '地三鲜', '木须肉', '回锅肉', '酸辣土豆丝', '手撕包菜',
  '蒜蓉西兰花', '蚝油生菜', '拍黄瓜', '凉拌木耳', '口水鸡', '夫妻肺片',
  '水煮鱼', '毛血旺', '番茄炒蛋', '韭菜炒蛋', '葱爆羊肉', '酱爆鸡丁',
  '香菇青菜', '冬瓜排骨汤', '玉米排骨汤', '酸菜鱼', '剁椒鱼头', '小炒黄牛肉',
  '梅菜扣肉', '粉蒸肉', '红烧茄子', '鱼香茄子', '干锅花菜', '铁板豆腐',
  '香煎豆腐', '可乐鸡翅', '红烧排骨', '白灼虾', '油焖大虾', '蒜蓉粉丝虾',
  '蒸蛋羹', '肉末粉丝', '京酱肉丝', '锅包肉', '溜肉段', '熘肝尖',
  '尖椒干豆腐', '老虎菜', '酸辣汤', '西湖牛肉羹', '皮蛋瘦肉粥', '小米粥',
  '蛋炒饭', '扬州炒饭', '葱油饼', '韭菜盒子', '肉夹馍', '凉面'
]

// 生成扩充商品：每家店补足到30个
function buildExtraGoods(storeId: number, startCount: number): GoodsItem[] {
  const goods: GoodsItem[] = []
  const storeCategoryId: number = getStorePrimaryCategoryId(storeId)
  for (let n = startCount; n < 30; n++) {
    const name: string = EXTRA_GOODS_NAMES[(storeId * 3 + n * 7) % EXTRA_GOODS_NAMES.length]
    goods.push({
      id: storeId * 100 + n + 1,
      name: name,
      description: `${name}，新鲜制作，美味可口`,
      price: 6 + ((storeId * 7 + n * 3) % 30),
      image: '',
      categoryId: storeCategoryId,
      sales: 100 + ((storeId * 11 + n * 5) % 4000),
      rating: 4.0 + ((storeId + n) % 10) / 10,
    })
  }
  return goods
}

function getStorePrimaryCategoryId(storeId: number): number {
  const store: StoreItem | undefined = getStores().find((item: StoreItem) => item.id === storeId)
  return store === undefined ? (storeId % 8) + 1 : store.categoryId
}

// 地址模板池
const EXTRA_DISTRICTS: string[] = ['海淀区', '朝阳区', '东城区', '西城区', '丰台区', '石景山区', '通州区', '昌平区', '大兴区', '顺义区']
const EXTRA_COMMUNITIES: string[] = ['幸福家园', '阳光小区', '翠湖花园', '锦绣前程', '金色家园', '梧桐苑', '百合公寓', '枫丹白露', '星海名城', '春晖园']
const EXTRA_ADDRESS_TAGS: string[] = ['学校', '家', '公司', '其他']

// 生成扩充地址（30条）
function buildExtraAddresses(): Address[] {
  const addresses: Address[] = []
  for (let i = 0; i < 27; i++) {
    addresses.push({
      id: 4 + i,
      name: '张三',
      phone: '13800138000',
      address: `北京市${EXTRA_DISTRICTS[i % EXTRA_DISTRICTS.length]}`,
      detail: `${EXTRA_COMMUNITIES[(i * 3) % EXTRA_COMMUNITIES.length]}${(i % 12) + 1}号楼${(i % 6) + 1}单元${100 + ((i * 7) % 800)}室`,
      isDefault: false,
      tag: EXTRA_ADDRESS_TAGS[i % EXTRA_ADDRESS_TAGS.length],
    })
  }
  return addresses
}

// 优惠券面额池
const EXTRA_COUPON_AMOUNTS: number[] = [5, 8, 10, 15, 20, 3, 6, 12, 18, 25]

// 生成扩充优惠券（30张）
function buildExtraCoupons(): Coupon[] {
  const coupons: Coupon[] = []
  for (let i = 0; i < 25; i++) {
    const amount: number = EXTRA_COUPON_AMOUNTS[i % EXTRA_COUPON_AMOUNTS.length]
    const minOrder: number = amount * 3 + 5
    const storeIndex: number = (i * 5) % 30
    const store: StoreItem | undefined = getStores()[storeIndex]
    coupons.push({
      id: 6 + i,
      amount: amount,
      minOrder: minOrder,
      startTime: '2026-01-01',
      endTime: '2026-12-31',
      used: i % 5 === 0,
      condition: `满${minOrder}元可用`,
      storeId: store !== undefined ? store.id : undefined,
      storeName: i % 3 === 0 ? '通用券' : (store !== undefined ? store.name : '通用券'),
    })
  }
  return coupons
}

// 订单状态池与备注池
const EXTRA_ORDER_STATUS: number[] = [0, 1, 2, 3, 4, 5, 6]
const EXTRA_ORDER_REMARKS: string[] = ['不要辣', '少冰', '多放香菜', '微辣', '不要香菜', '多加一份米饭', '', '尽快配送', '电话联系', '少油少盐']

// 生成扩充订单（30条，店铺循环覆盖1-30）
function buildExtraOrders(): Order[] {
  const orders: Order[] = []
  for (let i = 0; i < 27; i++) {
    const storeId: number = ((i + 3) % 30) + 1
    const store: StoreItem | undefined = getStores().find(s => s.id === storeId)
    const storeName: string = store !== undefined ? store.name : `店铺${storeId}`
    const goods: GoodsItem[] = getGoodsByStore(storeId)
    const g1: GoodsItem = goods[0]
    const g2: GoodsItem = goods.length > 1 ? goods[1] : goods[0]
    const total: number = g1.price + g2.price
    const deliveryFee: number = 2 + (storeId % 5)
    const discount: number = total >= 50 ? 10 : (total >= 30 ? 5 : 0)
    const status: number = EXTRA_ORDER_STATUS[i % EXTRA_ORDER_STATUS.length]
    const day: string = String((i % 28) + 1).padStart(2, '0')
    const hour: string = String(10 + (i % 10)).padStart(2, '0')
    const minute: string = String((i * 7) % 60).padStart(2, '0')
    const createTime: string = `2026-06-${day} ${hour}:${minute}:00`
    orders.push({
      id: 10004 + i,
      storeId: storeId,
      storeName: storeName,
      storeImage: '',
      items: [
        { goods: g1, quantity: (i % 3) + 1, storeId: storeId, storeName: storeName },
        { goods: g2, quantity: 1, storeId: storeId, storeName: storeName },
      ],
      totalPrice: total,
      deliveryFee: deliveryFee,
      discountAmount: discount,
      payAmount: total + deliveryFee - discount,
      status: status,
      createTime: createTime,
      payTime: status >= 1 ? `2026-06-${day} ${hour}:01:00` : undefined,
      deliverTime: status >= 3 ? `2026-06-${day} ${hour}:20:00` : undefined,
      completeTime: status >= 4 ? `2026-06-${day} ${hour}:55:00` : undefined,
      address: getDefaultAddresses()[i % getDefaultAddresses().length],
      remark: EXTRA_ORDER_REMARKS[i % EXTRA_ORDER_REMARKS.length],
    })
  }
  return orders
}

// 评价文案与标签池
const EXTRA_REVIEW_CONTENTS: string[] = [
  '味道很好，分量足', '配送速度快，包装好', '一般般，没有想象中好', '非常好吃，下次还会点',
  '性价比高，推荐', '老板人很好，服务周到', '食材新鲜，口味正宗', '有点咸，希望改进',
  '整体不错，就是等得久了点', '五星好评，强烈推荐'
]
const EXTRA_REVIEW_TAGS: string[][] = [
  ['味道好'], ['配送快'], ['分量足'], ['推荐'], ['会回购'], ['干净卫生'], ['服务好'], ['味道好', '配送快']
]

// 生成扩充评价（30条，店铺循环覆盖1-30）
function buildExtraReviews(): Review[] {
  const reviews: Review[] = []
  for (let i = 0; i < 25; i++) {
    const day: string = String((i % 28) + 1).padStart(2, '0')
    reviews.push({
      id: 6 + i,
      orderId: 10004 + i,
      storeId: (i % 30) + 1,
      userId: (i % 2) + 1,
      username: i % 2 === 0 ? '美食家小张' : '小王',
      rating: 3 + (i % 3),
      content: EXTRA_REVIEW_CONTENTS[i % EXTRA_REVIEW_CONTENTS.length],
      tags: EXTRA_REVIEW_TAGS[i % EXTRA_REVIEW_TAGS.length],
      createTime: `2026-06-${day} 12:${String((i * 11) % 60).padStart(2, '0')}:00`,
    })
  }
  return reviews
}

// 生成扩充收藏（30条，店铺循环覆盖4-30）
function buildExtraFavorites(): Favorite[] {
  const favorites: Favorite[] = []
  for (let i = 0; i < 27; i++) {
    const storeId: number = i + 4
    const store: StoreItem | undefined = getStores().find(s => s.id === storeId)
    const day: string = String((i % 28) + 1).padStart(2, '0')
    favorites.push({
      id: 4 + i,
      userId: 1,
      storeId: storeId,
      storeName: store !== undefined ? store.name : `店铺${storeId}`,
      storeImage: '',
      createTime: `2026-06-${day} 10:00:00`,
    })
  }
  return favorites
}

// 生成扩充可领取优惠券（30张）
function buildExtraClaimableCoupons(): Coupon[] {
  const coupons: Coupon[] = []
  for (let i = 0; i < 25; i++) {
    const amount: number = EXTRA_COUPON_AMOUNTS[(i + 3) % EXTRA_COUPON_AMOUNTS.length]
    const minOrder: number = amount * 3 + 5
    const storeIndex: number = (i * 7) % 30
    const store: StoreItem | undefined = getStores()[storeIndex]
    coupons.push({
      id: 106 + i,
      amount: amount,
      minOrder: minOrder,
      startTime: '2026-01-01',
      endTime: '2026-12-31',
      used: false,
      condition: `满${minOrder}元可用`,
      storeId: store !== undefined ? store.id : undefined,
      storeName: i % 3 === 0 ? '通用券' : (store !== undefined ? store.name : '通用券'),
    })
  }
  return coupons
}

/**
 * 主页面 - 简单外卖App
 * 包含：搜索栏、分类导航、店铺列表、店铺详情、购物车、订单列表、个人中心、底部Tab导航
 */
import { Category, StoreItem, GoodsItem, CartItem, Order, User, UserRole } from '../model/Models'
import { getCategories, formatSales } from '../service/MockDataService'
import { addToCart, updateCartItemQuantity, confirmOrder, initAppStorage, isLoggedIn, logout, getAllStoresList, getGoodsForStore } from '../service/AppStorageManager'
import { LoginPage } from './LoginPage'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS, getOrderStatusText, getOrderStatusColor } from '../common/Constants'

// 定义快捷入口和订单Tab的数据类型，解决 arkts-no-untyped-obj-literals 错误
class QuickEntryItem {
  icon: string = ''
  title: string = ''
  color: string = ''

  static create(icon: string, title: string, color: string): QuickEntryItem {
    let item = new QuickEntryItem()
    item.icon = icon
    item.title = title
    item.color = color
    return item
  }
}

class OrderTabItem {
  title: string = ''
  status: number = -1

  static create(title: string, status: number): OrderTabItem {
    let item = new OrderTabItem()
    item.title = title
    item.status = status
    return item
  }
}

@Entry
@Component
struct Index {
  @State currentTab: number = 0
  @State loggedIn: boolean = false
  @State showLogin: boolean = false
  private tabsController: TabsController = new TabsController()

  aboutToAppear() {
    // 初始化全局数据
    initAppStorage()
    this.loggedIn = isLoggedIn()
  }

  build() {
    Stack() {
      // 登录覆盖层
      if (this.showLogin) {
        LoginPage({
          onLoginSuccess: () => {
            this.showLogin = false
            this.loggedIn = true
          }
        })
      }

      Tabs({ controller: this.tabsController, barPosition: BarPosition.End }) {
      // 首页Tab
      TabContent() {
        HomePage({
          onStoreClick: (store: StoreItem) => {
            AppStorage.setOrCreate<number>('selectedStoreId', store.id)
            AppStorage.setOrCreate<string>('selectedStoreName', store.name)
            this.currentTab = 1
            this.tabsController.changeIndex(1)
          },
          onNavigateLogin: () => { this.showLogin = true }
        })
      }.tabBar(this.tabBuilder('首页', 0))

      // 发现Tab - 店铺详情
      TabContent() {
        DiscoverPage({
          onBack: () => {
            this.currentTab = 0
            this.tabsController.changeIndex(0)
          }
        })
      }.tabBar(this.tabBuilder('发现', 1))

      // 订单Tab
      TabContent() {
        OrderListMainPage()
      }.tabBar(this.tabBuilder('订单', 2))

      // 我的Tab
      TabContent() {
        ProfileMainPage({
          onNavigate: (tab: number) => {
            this.currentTab = tab
            this.tabsController.changeIndex(tab)
          },
          onNavigateLogin: () => { this.showLogin = true }
        })
      }.tabBar(this.tabBuilder('我的', 3))
    }
    .barHeight(50)
    .barBackgroundColor('#FFFFFF')
    .onChange((index: number) => { this.currentTab = index })
    .scrollable(false)
    .animationDuration(0)
    .width('100%')
    .height('100%')
    .backgroundColor(COLORS.BG_PRIMARY)
    }
  }

  @Builder
  tabBuilder(title: string, targetIndex: number) {
    Column({ space: 2 }) {
      Text(title)
        .fontSize(10)
        .fontColor(this.currentTab === targetIndex ? COLORS.PRIMARY : COLORS.TAB_INACTIVE)
        .fontWeight(this.currentTab === targetIndex ? FontWeight.Bold : FontWeight.Normal)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      this.currentTab = targetIndex
      this.tabsController.changeIndex(targetIndex)
    })
  }
}

// ===================== 首页 =====================
@Component
struct HomePage {
  @State categories: Category[] = []
  @State stores: StoreItem[] = []
  @State searchText: string = ''
  @State currentCategory: number = 0
  onStoreClick: (store: StoreItem) => void = () => {}
  onNavigateLogin: () => void = () => {}

  aboutToAppear() {
    this.categories = getCategories()
    this.stores = getAllStoresList()
  }

  build() {
    Column() {
      // 顶部地址栏 + 搜索
      Column() {
        Row({ space: 8 }) {
          Row({ space: 4 }) {
            Text('📍')
              .fontSize(14)
            Text('清华大学')
              .fontSize(FONT_SIZE.LG)
              .fontColor(COLORS.TEXT_PRIMARY)
              .fontWeight(FontWeight.Bold)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: 80 })
            Text('▼')
              .fontSize(10)
              .fontColor(COLORS.TEXT_SECONDARY)
          }
          Row({ space: 4 }) {
            Text('🔍')
              .fontSize(14)
            TextInput({ placeholder: '搜索美食、店铺', text: '' })
              .fontSize(FONT_SIZE.MD)
              .backgroundColor(Color.Transparent)
              .placeholderColor(COLORS.TEXT_HINT)
              .layoutWeight(1)
              .height(32)
              .onChange((value: string) => { this.searchText = value })
          }
          .padding({ left: 12, right: 12 })
          .height(32)
          .backgroundColor('#F0F0F0')
          .borderRadius(BORDER_RADIUS.ROUND)
          .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: SPACING.LG, right: SPACING.LG, top: 8, bottom: 8 })
      }
      .width('100%')
      .padding({ top: 40 })
      .backgroundColor(COLORS.BG_WHITE)

      Scroll() {
        Column() {
          // 分类导航
          Grid() {
            ForEach(this.categories, (cat: Category) => {
              GridItem() {
                Column({ space: 4 }) {
                  Text(cat.icon).fontSize(28)
                  Text(cat.name)
                    .fontSize(FONT_SIZE.SM)
                    .fontColor(this.currentCategory === cat.id ? COLORS.PRIMARY : COLORS.TEXT_PRIMARY)
                    .fontWeight(this.currentCategory === cat.id ? FontWeight.Bold : FontWeight.Normal)
                }
                .width('100%')
                .height('100%')
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)
                .onClick(() => {
                  if (this.currentCategory === cat.id) {
                    this.currentCategory = 0
                    this.stores = getAllStoresList()
                  } else {
                    this.currentCategory = cat.id
                    this.stores = getAllStoresList().filter(s => s.categoryId === cat.id ||
                      (s.categoryIds && s.categoryIds.includes(cat.id)))
                  }
                })
              }
            }, (item: Category) => item.id.toString())
          }
          .columnsTemplate('1fr 1fr 1fr 1fr 1fr')
          .rowsTemplate('1fr 1fr')
          .columnsGap(0)
          .rowsGap(4)
          .width('100%')
          .height(160)
          .padding({ top: SPACING.MD, bottom: SPACING.SM })
          .backgroundColor(COLORS.BG_WHITE)
          .margin({ top: SPACING.SM })
          .borderRadius({ topLeft: BORDER_RADIUS.LG, topRight: BORDER_RADIUS.LG })

          // Banner
          Swiper() {
            Text('新人专享 满20减15')
              .width('100%').height(120).fontSize(FONT_SIZE.XL)
              .fontColor(COLORS.TEXT_WHITE).backgroundColor(COLORS.PRIMARY)
              .borderRadius(BORDER_RADIUS.MD).textAlign(TextAlign.Center)
            Text('限时秒杀 全场8折')
              .width('100%').height(120).fontSize(FONT_SIZE.XL)
              .fontColor(COLORS.TEXT_WHITE).backgroundColor('#FF3B30')
              .borderRadius(BORDER_RADIUS.MD).textAlign(TextAlign.Center)
            Text('邀请好友 领大额红包')
              .width('100%').height(120).fontSize(FONT_SIZE.XL)
              .fontColor(COLORS.TEXT_WHITE).backgroundColor(COLORS.SUCCESS)
              .borderRadius(BORDER_RADIUS.MD).textAlign(TextAlign.Center)
          }
          .indicator(true).autoPlay(true).interval(3000).loop(true)
          .width('100%')
          .padding({ left: SPACING.LG, right: SPACING.LG })
          .margin({ top: SPACING.SM })

          // 快捷入口
          Row({ space: SPACING.XL }) {
            ForEach([
              QuickEntryItem.create('⏰', '限时抢购', COLORS.PRIMARY),
              QuickEntryItem.create('❤️', '收藏夹', '#FF3B30'),
              QuickEntryItem.create('🎫', '领券中心', '#FF9800'),
              QuickEntryItem.create('🏆', '排行榜', '#4CAF50'),
            ], (item: QuickEntryItem) => {
              Column({ space: 4 }) {
                Text(item.icon)
                  .width(40).height(40).fontSize(18)
                  .backgroundColor(item.color)
                  .borderRadius(BORDER_RADIUS.LG)
                  .textAlign(TextAlign.Center)
                Text(item.title)
                  .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
              }
              .alignItems(HorizontalAlign.Center)
            }, (item: QuickEntryItem) => item.title)
          }
          .width('100%')
          .padding({ left: SPACING.XL, right: SPACING.XL })
          .margin({ top: SPACING.MD })
          .justifyContent(FlexAlign.SpaceAround)

          // 附近好店标题
          Row() {
            Text('附近好店')
              .fontSize(FONT_SIZE.XL).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
            Blank()
            Text('查看全部 >')
              .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT)
          }
          .width('100%')
          .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.MD, bottom: SPACING.SM })

          // 店铺列表
          List({ space: SPACING.SM }) {
            ForEach(this.stores, (store: StoreItem) => {
              ListItem() {
                this.StoreCard(store)
              }
            }, (item: StoreItem) => item.id.toString())
          }
          .width('100%')
          .padding({ left: SPACING.LG, right: SPACING.LG, bottom: SPACING.LG })
          .divider({ strokeWidth: 0 })
        }
      }
      .scrollBar(BarState.Off)
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(COLORS.BG_PRIMARY)
  }

  @Builder
  StoreCard(store: StoreItem) {
    Row({ space: SPACING.MD }) {
      // 店铺图片占位
      Column() {
        Text(store.name.substring(0, 1))
          .fontSize(28).fontWeight(FontWeight.Bold).fontColor(Color.White)
      }
      .width(80).height(80)
      .backgroundColor(COLORS.PRIMARY)
      .borderRadius(BORDER_RADIUS.MD)
      .justifyContent(FlexAlign.Center)

      Column({ space: 4 }) {
        Text(store.name)
          .fontSize(FONT_SIZE.LG).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })

        Row({ space: 8 }) {
          Text(`${store.rating}分`)
            .fontSize(FONT_SIZE.SM).fontColor(COLORS.PRIMARY).fontWeight(FontWeight.Bold)
          Text(`月售${formatSales(store.monthlySales)}`)
            .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
          Text('|').fontSize(FONT_SIZE.SM).fontColor(COLORS.DIVIDER)
          Text(store.deliveryTime).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
        }

        Row({ space: 4 }) {
          Text(`配送¥${store.deliveryFee}`).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
          Text('|').fontSize(FONT_SIZE.SM).fontColor(COLORS.DIVIDER)
          Text(`${store.minOrder}元起送`).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
          Text('|').fontSize(FONT_SIZE.SM).fontColor(COLORS.DIVIDER)
          Text(store.distance).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
        }

        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(store.tags, (tag: string) => {
            Text(tag)
              .fontSize(FONT_SIZE.XS).fontColor(COLORS.TAG_TEXT).backgroundColor(COLORS.TAG_BG)
              .padding({ left: 4, right: 4, top: 2, bottom: 2 }).borderRadius(BORDER_RADIUS.SM)
          }, (tag: string) => tag)
        }
        .width('100%')
        .margin({ bottom: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(SPACING.MD)
    .backgroundColor(COLORS.BG_WHITE)
    .borderRadius(BORDER_RADIUS.LG)
    .onClick(() => { this.onStoreClick(store) })
  }
}

// ===================== 发现/店铺详情页 =====================
@Component
struct DiscoverPage {
  @StorageLink('selectedStoreId') selectedStoreId: number = 0
  @StorageLink('selectedStoreName') selectedStoreName: string = ''
  onBack: () => void = () => {}

  build() {
    Column() {
      // 导航栏
      Row() {
        Text('‹ 返回')
          .fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_PRIMARY)
          .onClick(() => { this.onBack() })
        Text(this.selectedStoreName || '发现')
          .fontSize(FONT_SIZE.LG).fontWeight(FontWeight.Bold)
          .layoutWeight(1).textAlign(TextAlign.Center)
        Text('   ').fontSize(FONT_SIZE.MD) // 占位
      }
      .width('100%').height(44)
      .padding({ left: SPACING.LG, right: SPACING.LG })
      .backgroundColor(COLORS.BG_WHITE)

      if (this.selectedStoreId > 0) {
        StoreDetailContent({ storeId: this.selectedStoreId })
      } else {
        Column() {
          Text('🔍')
            .fontSize(60).margin({ top: 80 })
          Text('搜索发现')
            .fontSize(FONT_SIZE.TITLE).fontWeight(FontWeight.Bold)
            .fontColor(COLORS.TEXT_HINT).margin({ top: 16 })
          Text('在首页点击店铺即可查看详情')
            .fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_HINT).margin({ top: 8 })
        }
        .width('100%').layoutWeight(1)
        .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%').height('100%')
    .backgroundColor(COLORS.BG_PRIMARY)
  }
}

// ===================== 店铺详情 =====================
@Component
struct StoreDetailContent {
  storeId: number = 0
  @State goodsList: GoodsItem[] = []
  @State storeName: string = ''
  @State storeRating: number = 0
  @State storeMonthlySales: number = 0
  @State storeDeliveryFee: number = 0
  @State storeDeliveryTime: string = ''
  @State storeDistance: string = ''
  @State storeMinOrder: number = 0
  @State storeTags: string[] = []
  @State storeNotice: string = ''
  @State cartCount: number = 0
  @State cartTotal: number = 0
  @StorageLink('cartItems') cartItems: CartItem[] = []

  aboutToAppear() {
    this.goodsList = getGoodsForStore(this.storeId)
    const store = getAllStoresList().find(s => s.id === this.storeId)
    if (store) {
      this.storeName = store.name
      this.storeRating = store.rating
      this.storeMonthlySales = store.monthlySales
      this.storeDeliveryFee = store.deliveryFee
      this.storeDeliveryTime = store.deliveryTime
      this.storeDistance = store.distance
      this.storeMinOrder = store.minOrder
      this.storeTags = store.tags
      this.storeNotice = store.notice
    }
    this.updateCartInfo()
  }

  updateCartInfo() {
    this.cartItems = AppStorage.get<CartItem[]>('cartItems') || []
    const sc = this.cartItems.filter(c => c.storeId === this.storeId)
    this.cartCount = sc.reduce((s, i) => s + i.quantity, 0)
    this.cartTotal = sc.reduce((s, i) => s + i.goods.price * i.quantity, 0)
  }

  build() {
    Column() {
      // 店铺信息
      Column({ space: 6 }) {
        Text(this.storeName)
          .fontSize(FONT_SIZE.XL).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
        Row({ space: 12 }) {
          Text(`${this.storeRating}分`).fontSize(FONT_SIZE.MD).fontColor(COLORS.PRIMARY).fontWeight(FontWeight.Bold)
          Text(`月售${formatSales(this.storeMonthlySales)}`).fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_SECONDARY)
          Text(`配送${this.storeDeliveryTime}`).fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_SECONDARY)
        }
        Row({ space: 12 }) {
          Text(`配送费¥${this.storeDeliveryFee}`).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
          Text(`${this.storeMinOrder}元起送`).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
          Text(this.storeDistance).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
        }
        Row({ space: 6 }) {
          ForEach(this.storeTags, (tag: string) => {
            Text(tag).fontSize(FONT_SIZE.XS).fontColor(COLORS.TAG_TEXT)
              .backgroundColor(COLORS.TAG_BG)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 }).borderRadius(BORDER_RADIUS.SM)
          }, (tag: string) => tag)
        }
        Row({ space: 4 }) {
          Text('公告：').fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT)
          Text(this.storeNotice).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        }
      }
      .width('100%')
      .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.MD, bottom: SPACING.MD })
      .backgroundColor(COLORS.BG_WHITE).margin({ top: SPACING.SM })

      // 分类Tab
      Scroll() {
        Row({ space: SPACING.SM }) {
          Text('全部').fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_WHITE)
            .backgroundColor(COLORS.PRIMARY)
            .padding({ left: 12, right: 12, top: 4, bottom: 4 }).borderRadius(BORDER_RADIUS.ROUND).height(28)
          Text('热销').fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_SECONDARY)
            .backgroundColor('#F5F5F5')
            .padding({ left: 12, right: 12, top: 4, bottom: 4 }).borderRadius(BORDER_RADIUS.ROUND).height(28)
          Text('优惠').fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_SECONDARY)
            .backgroundColor('#F5F5F5')
            .padding({ left: 12, right: 12, top: 4, bottom: 4 }).borderRadius(BORDER_RADIUS.ROUND).height(28)
        }
        .padding({ left: SPACING.LG, top: SPACING.SM, bottom: SPACING.SM })
      }
      .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      .width('100%').backgroundColor(COLORS.BG_WHITE)

      // 商品列表
      Stack({ alignContent: Alignment.Bottom }) {
        Scroll() {
          Column() {
            ForEach(this.goodsList, (goods: GoodsItem) => {
              Row({ space: SPACING.MD }) {
                // 商品图片
                Column() {
                  Text(goods.name.substring(0, 2))
                    .fontSize(16).fontColor(COLORS.TEXT_HINT)
                }
                .width(90).height(90).backgroundColor('#F0F0F0').borderRadius(BORDER_RADIUS.MD)
                .justifyContent(FlexAlign.Center)

                // 商品信息
                Column({ space: 4 }) {
                  Row({ space: 4 }) {
                    Text(goods.name)
                      .fontSize(FONT_SIZE.LG).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
                      .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    if (goods.tag) {
                      Text(goods.tag)
                        .fontSize(FONT_SIZE.XS).fontColor('#FF3B30')
                        .borderWidth(1).borderColor('#FF3B30')
                        .padding({ left: 2, right: 2, top: 1, bottom: 1 }).borderRadius(BORDER_RADIUS.SM)
                    }
                  }
                  Text(goods.description)
                    .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT)
                    .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                  Row({ space: 4 }) {
                    Text(`月售${formatSales(goods.sales)}`).fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT)
                    Text(`好评${goods.rating}%`).fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT)
                  }
                  Row() {
                    Row({ space: 2 }) {
                      Text('¥').fontSize(FONT_SIZE.SM).fontColor(COLORS.PRICE_RED).fontWeight(FontWeight.Bold)
                      Text(goods.price.toString()).fontSize(FONT_SIZE.XL).fontColor(COLORS.PRICE_RED).fontWeight(FontWeight.Bold)
                    }
                    if (goods.originalPrice) {
                      Text(`¥${goods.originalPrice}`).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT)
                        .decoration({ type: TextDecorationType.LineThrough }).margin({ left: 4 })
                    }
                    Blank()
                    this.AddMinusButton(goods)
                  }.width('100%')
                }
                .layoutWeight(1).alignItems(HorizontalAlign.Start)
              }
              .width('100%').padding(SPACING.MD)
            }, (item: GoodsItem) => item.id.toString())
          }
          .padding({ bottom: 60 })
        }
        .scrollBar(BarState.Off)
        .layoutWeight(1)

        // 购物车栏
        this.CartBar()
      }
      .layoutWeight(1)
    }
    .width('100%').height('100%')
  }

  @Builder
  AddMinusButton(goods: GoodsItem) {
    Row({ space: 0 }) {
      if (this.getQty(goods.id) > 0) {
        Text('-').width(24).height(24).fontSize(16).fontColor(COLORS.TEXT_WHITE)
          .backgroundColor(COLORS.PRIMARY).borderRadius(BORDER_RADIUS.CIRCLE)
          .textAlign(TextAlign.Center).onClick(() => {
            updateCartItemQuantity(goods.id, this.storeId, this.getQty(goods.id) - 1)
            this.updateCartInfo()
          })
        Text(this.getQty(goods.id).toString()).width(28).height(24).fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_PRIMARY).textAlign(TextAlign.Center)
      }
      Text('+').width(24).height(24).fontSize(16).fontColor(COLORS.TEXT_WHITE)
        .backgroundColor(COLORS.PRIMARY).borderRadius(BORDER_RADIUS.CIRCLE)
        .textAlign(TextAlign.Center).onClick(() => {
          addToCart({ goods: goods, quantity: 1, storeId: this.storeId, storeName: this.storeName })
          this.updateCartInfo()
        })
    }
  }

  @Builder
  CartBar() {
    Row() {
      Stack() {
        Text('🛒').width(50).height(50).fontSize(24)
          .backgroundColor(COLORS.TEXT_PRIMARY).borderRadius(BORDER_RADIUS.ROUND)
          .textAlign(TextAlign.Center)
        if (this.cartCount > 0) {
          Text(this.cartCount.toString())
            .fontSize(10).fontColor(Color.White).backgroundColor(COLORS.PRICE_RED)
            .borderRadius(BORDER_RADIUS.CIRCLE).textAlign(TextAlign.Center)
            .width(18).height(18)
        }
      }
      .alignContent(Alignment.TopEnd)
      Column({ space: 2 }) {
        Row({ space: 2 }) {
          Text('¥').fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_WHITE)
          Text(this.cartTotal.toFixed(2)).fontSize(FONT_SIZE.XL).fontColor(COLORS.TEXT_WHITE).fontWeight(FontWeight.Bold)
        }
        Text(`另需配送费¥${this.storeDeliveryFee}`).fontSize(FONT_SIZE.XS)
          .fontColor('rgba(255,255,255,0.7)')
      }
      .margin({ left: SPACING.SM }).alignItems(HorizontalAlign.Start)
      Blank()
      Button(this.cartCount > 0 ? `去结算(${this.cartCount})` : '去购物')
        .height(40).fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_WHITE)
        .backgroundColor(this.cartCount > 0 ? COLORS.PRIMARY : '#666666')
        .borderRadius({ topRight: BORDER_RADIUS.LG, bottomRight: BORDER_RADIUS.LG })
        .width(100).enabled(this.cartCount > 0)
        .onClick(() => {
          if (this.cartCount > 0) {
            // 下单：创建订单并清空购物车
            this.submitOrder()
          }
        })
    }
    .width('100%').height(56)
    .padding({ left: SPACING.LG, right: SPACING.SM })
    .backgroundColor(COLORS.TEXT_PRIMARY)
  }

  submitOrder() {
    const items = this.cartItems.filter(c => c.storeId === this.storeId)
    const total = items.reduce((s, i) => s + i.goods.price * i.quantity, 0)
    const now = new Date()
    const timeStr = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')} ${String(now.getHours()).padStart(2, '0')}:${String(now.getMinutes()).padStart(2, '0')}:${String(now.getSeconds()).padStart(2, '0')}`

    const order: Order = {
      id: Date.now(),
      storeId: this.storeId,
      storeName: this.storeName,
      storeImage: '',
      items: items,
      totalPrice: total,
      deliveryFee: this.storeDeliveryFee,
      discountAmount: 0,
      payAmount: total + this.storeDeliveryFee,
      status: 1, // 已付款
      createTime: timeStr,
      payTime: timeStr,
      address: {
        id: 1, name: '张三', phone: '13800138000',
        address: '北京市海淀区', detail: '清华大学学生公寓3号楼205',
        isDefault: true, tag: '学校'
      },
      remark: ''
    }

    // 添加订单
    const orders: Order[] = AppStorage.get<Order[]>('orderList') || []
    orders.unshift(order)
    AppStorage.setOrCreate('orderList', orders)

    // 清空该店铺购物车
    const remainCart = this.cartItems.filter(c => c.storeId !== this.storeId)
    AppStorage.setOrCreate('cartItems', remainCart)
    this.cartCount = 0
    this.cartTotal = 0
    this.cartItems = remainCart
  }

  getQty(goodsId: number): number {
    const item = this.cartItems.find(c => c.goods.id === goodsId && c.storeId === this.storeId)
    return item ? item.quantity : 0
  }
}

// ===================== 订单列表 =====================
@Component
struct OrderListMainPage {
  @StorageLink('orderList') orderList: Order[] = []
  @State currentStatus: number = -1

  build() {
    Column() {
      Row() {
        Text('我的订单')
          .fontSize(FONT_SIZE.XXL).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
      }
      .width('100%').height(56)
      .padding({ left: SPACING.LG, top: 40 })
      .backgroundColor(COLORS.BG_WHITE)

      Scroll() {
        Row({ space: 0 }) {
          ForEach([
            OrderTabItem.create('全部', -1),
            OrderTabItem.create('待付款', 0),
            OrderTabItem.create('待接单', 1),
            OrderTabItem.create('配送中', 3),
            OrderTabItem.create('已完成', 4),
          ], (item: OrderTabItem) => {
            Text(item.title)
              .fontSize(FONT_SIZE.MD)
              .fontColor(this.currentStatus === item.status ? COLORS.PRIMARY : COLORS.TEXT_SECONDARY)
              .fontWeight(this.currentStatus === item.status ? FontWeight.Bold : FontWeight.Normal)
              .padding({ left: SPACING.MD, right: SPACING.MD, top: SPACING.SM, bottom: SPACING.SM })
              .onClick(() => { this.currentStatus = item.status })
          }, (item: OrderTabItem) => item.title)
        }
        .padding({ left: SPACING.LG, right: SPACING.LG })
      }
      .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      .width('100%').backgroundColor(COLORS.BG_WHITE)

      if (this.filteredOrders.length === 0) {
        Column() {
          Text('📦').fontSize(60).margin({ top: 100 })
          Text('暂无订单').fontSize(FONT_SIZE.LG).fontColor(COLORS.TEXT_HINT).margin({ top: 16 })
          Text('快去点一份美味吧').fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_HINT).margin({ top: 8 })
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      } else {
        List({ space: SPACING.SM }) {
          ForEach(this.filteredOrders, (order: Order) => {
            ListItem() {
              this.OrderCard(order)
            }
          }, (item: Order) => item.id.toString())
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.SM, bottom: SPACING.LG })
        .scrollBar(BarState.Off).divider({ strokeWidth: 0 })
      }
    }
    .width('100%').height('100%')
    .backgroundColor(COLORS.BG_PRIMARY)
  }

  get filteredOrders(): Order[] {
    if (!this.orderList || this.orderList.length === 0) return []
    if (this.currentStatus === -1) return this.orderList
    return this.orderList.filter(o => o.status === this.currentStatus)
  }

  @Builder
  OrderCard(order: Order) {
    Column({ space: SPACING.SM }) {
      Row() {
        Text(order.storeName)
          .fontSize(FONT_SIZE.LG).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY).layoutWeight(1)
        Text(getOrderStatusText(order.status))
          .fontSize(FONT_SIZE.MD).fontColor(getOrderStatusColor(order.status)).fontWeight(FontWeight.Bold)
      }
      ForEach(order.items, (item: CartItem) => {
        Row() {
          Text(item.goods.name).fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_SECONDARY).layoutWeight(1)
          Text(`x${item.quantity}`).fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_HINT)
        }.width('100%')
      }, (item: CartItem) => `${item.goods.id}`)
      Row() {
        Text(`共${order.items.reduce((s, i) => s + i.quantity, 0)}件 实付`)
          .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
        Text(`¥${order.payAmount.toFixed(2)}`)
          .fontSize(FONT_SIZE.LG).fontColor(COLORS.PRICE_RED).fontWeight(FontWeight.Bold)
        Blank()
        if (order.status === 3) {
          Button('确认收货').height(32).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_WHITE)
            .backgroundColor(COLORS.PRIMARY).borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
            .onClick(() => { confirmOrder(order.id); this.orderList = AppStorage.get<Order[]>('orderList') || [] })
        } else if (order.status === 4) {
          Button('再来一单').height(32).fontSize(FONT_SIZE.SM).fontColor(COLORS.PRIMARY)
            .backgroundColor(Color.Transparent).borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
            .borderWidth(1).borderColor(COLORS.PRIMARY)
        } else if (order.status === 5) {
          Button('已取消').height(32).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT)
            .backgroundColor('#F5F5F5').borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
        }
      }.width('100%')
    }
    .width('100%').padding(SPACING.MD)
    .backgroundColor(COLORS.BG_WHITE).borderRadius(BORDER_RADIUS.LG)
  }
}

// ===================== 个人中心 =====================
@Component
struct ProfileMainPage {
  @StorageLink('isLoggedIn') loggedIn: boolean = false
  @StorageLink('user') user: User = {
    id: 0, username: '未登录', avatar: '', phone: '', password: '', role: UserRole.CUSTOMER,
    balance: 0, coupons: [], orders: [], storeIds: []
  }
  onNavigate: (tab: number) => void = () => {}
  onNavigateLogin: () => void = () => {}

  build() {
    Scroll() {
      Column() {
        // 头部用户信息
        Column() {
          Row({ space: SPACING.LG }) {
            Column() {
              Text(this.user.username.charAt(0))
                .fontSize(24).fontColor(Color.White).fontWeight(FontWeight.Bold)
            }
            .width(60).height(60).backgroundColor('rgba(255,255,255,0.3)')
            .borderRadius(BORDER_RADIUS.CIRCLE).justifyContent(FlexAlign.Center)
            Column({ space: 4 }) {
              Text(this.user.username)
                .fontSize(FONT_SIZE.XXL).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_WHITE)
              Text(this.loggedIn
                ? (this.user.role === UserRole.MERCHANT ? '商户账户' : this.user.phone)
                : '点击登录')
                .fontSize(FONT_SIZE.MD).fontColor('rgba(255,255,255,0.8)')
            }
            .alignItems(HorizontalAlign.Start).layoutWeight(1)
            if (this.loggedIn) {
              Button('退出')
                .height(32).fontSize(FONT_SIZE.SM)
                .fontColor(Color.White).backgroundColor('rgba(255,255,255,0.3)')
                .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
                .onClick(() => {
                  logout()
                  this.loggedIn = false
                })
            }
          }.width('100%')
          .onClick(() => {
            if (!this.loggedIn) {
              this.onNavigateLogin()
            }
          })
        }
        .width('100%')
        .padding({ left: SPACING.XL, right: SPACING.XL, top: 50, bottom: SPACING.XL })
        .linearGradient({
          direction: GradientDirection.RightBottom,
          colors: [[COLORS.PRIMARY, 0.0], [COLORS.PRIMARY_LIGHT, 1.0]]
        })
        .borderRadius({ bottomLeft: BORDER_RADIUS.XL, bottomRight: BORDER_RADIUS.XL })

        // 资产区域
        Row() {
          this.AssetItem(this.user.balance.toFixed(2), '余额')
          this.AssetItem(this.user.coupons.filter(c => !c.used).length.toString(), '优惠券')
          this.AssetItem(this.user.orders.length.toString(), '订单')
        }
        .width('100%').padding(SPACING.LG)
        .margin({ top: SPACING.SM })
        .backgroundColor(COLORS.BG_WHITE).borderRadius(BORDER_RADIUS.LG)

        // 订单快捷入口
        Row() {
          this.ProfileOrderEntry('⏳', '待付款')
          this.ProfileOrderEntry('📋', '待接单')
          this.ProfileOrderEntry('🚴', '配送中')
          this.ProfileOrderEntry('✅', '已完成')
        }
        .width('100%').padding(SPACING.LG)
        .margin({ top: SPACING.SM })
        .backgroundColor(COLORS.BG_WHITE).borderRadius(BORDER_RADIUS.LG)
        .justifyContent(FlexAlign.SpaceAround)

        // 功能菜单
        Column() {
          this.ProfileMenuRow('📍', '收货地址')
          this.ProfileMenuRow('❤️', '我的收藏')
          this.ProfileMenuRow('📞', '联系客服')
          this.ProfileMenuRow('⚙️', '设置')
        }
        .width('100%')
        .padding({ top: SPACING.SM })
        .margin({ top: SPACING.SM })
        .backgroundColor(COLORS.BG_WHITE).borderRadius(BORDER_RADIUS.LG)

        // 商户入口（仅商户角色显示）
        if (this.loggedIn && this.user.role === UserRole.MERCHANT) {
          Column() {
            Text('🏪 商户管理入口')
              .fontSize(FONT_SIZE.MD).fontWeight(FontWeight.Bold)
              .fontColor(COLORS.PRIMARY)
              .width('100%')
              .padding({ left: SPACING.LG, top: SPACING.SM, bottom: SPACING.SM })
            this.ProfileMenuRow('📋', '店铺管理')
            this.ProfileMenuRow('📦', '商品上架')
            this.ProfileMenuRow('📊', '订单管理')
            this.ProfileMenuRow('💰', '收入统计')
          }
          .width('100%')
          .padding({ top: SPACING.SM })
          .margin({ top: SPACING.SM })
          .backgroundColor('#FFF8F0')
          .borderRadius(BORDER_RADIUS.LG)
        }
      }
    }
    .scrollBar(BarState.Off)
    .width('100%').height('100%')
    .backgroundColor(COLORS.BG_PRIMARY)
  }

  @Builder
  AssetItem(value: string, label: string) {
    Column({ space: 4 }) {
      Text(value).fontSize(FONT_SIZE.XXL).fontWeight(FontWeight.Bold).fontColor(COLORS.PRIMARY)
      Text(label).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
    }
    .layoutWeight(1).alignItems(HorizontalAlign.Center)
  }

  @Builder
  ProfileOrderEntry(icon: string, title: string) {
    Column({ space: 4 }) {
      Text(icon).fontSize(28)
      Text(title).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
    }
    .onClick(() => { this.onNavigate(2) })
  }

  @Builder
  ProfileMenuRow(icon: string, title: string) {
    Row({ space: SPACING.MD }) {
      Text(icon).fontSize(18)
      Text(title).fontSize(FONT_SIZE.LG).fontColor(COLORS.TEXT_PRIMARY).layoutWeight(1)
      Text('›').fontSize(20).fontColor(COLORS.TEXT_HINT)
    }
    .width('100%').height(52)
    .padding({ left: SPACING.LG, right: SPACING.LG })
    .onClick(() => {})
  }
}
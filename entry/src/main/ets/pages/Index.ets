/**
 * 主页面 - 简单外卖App
 * 包含：搜索栏、分类导航、店铺列表、店铺详情、购物车、订单列表、个人中心、底部Tab导航
 */
import { Category, StoreItem, GoodsItem, CartItem, Order, User, UserRole, Review, Address, Coupon, Favorite, createEmptyUser } from '../model/Models'
import { addToCart, updateCartItemQuantity, initAppStorage, isLoggedIn, logout, getAllStoresList, getGoodsForStore, isFavorited, syncCategoriesFromServer, syncStoreReviewsRemote, syncStoresFromServer, syncGoodsFromServer, syncUserOrdersFromServer, toggleFavoriteRemote, confirmOrderRemote } from '../service/AppStorageManager'
import { LoginPage } from './LoginPage'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS, getOrderStatusText, getOrderStatusColor, formatSales } from '../common/Constants'
import { EmptyState } from '../components/EmptyState'
import { RatingStars } from '../components/RatingStars'
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { initLogger, logInfo, setPrivacyConsent } from '../service/AppLogger'
import { loadAllData, saveAllData } from '../service/DataPersistence'

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

// 店铺列表懒加载数据源（实现 IDataSource）
class StoreDataSource implements IDataSource {
  private list: StoreItem[] = []
  private listeners: DataChangeListener[] = []

  totalCount(): number {
    return this.list.length
  }

  getData(index: number): StoreItem {
    return this.list[index]
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    this.listeners.push(listener)
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((l: DataChangeListener) => l !== listener)
  }

  setData(data: StoreItem[]): void {
    this.list = data
    this.listeners.forEach((l: DataChangeListener) => l.onDataReloaded())
  }
}

// 订单列表懒加载数据源（实现 IDataSource）
class OrderDataSource implements IDataSource {
  private list: Order[] = []
  private listeners: DataChangeListener[] = []

  totalCount(): number {
    return this.list.length
  }

  getData(index: number): Order {
    return this.list[index]
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    this.listeners.push(listener)
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((l: DataChangeListener) => l !== listener)
  }

  setData(data: Order[]): void {
    this.list = data
    this.listeners.forEach((l: DataChangeListener) => l.onDataReloaded())
  }
}

@Entry
@Component
struct Index {
  @State currentTab: number = 0
  @StorageLink('isLoggedIn') loggedIn: boolean = false
  @State showLogin: boolean = false
  private tabsController: TabsController = new TabsController()

  aboutToAppear() {
    // 初始化全局数据
    initAppStorage()
    // 登录态恢复后同步当前用户与账号库数据（保证不同账号余额等数据独立正确）
    this.loggedIn = isLoggedIn()
    // 数据格式保险：校验 AppStorage 关键数据，异常（非数组/非对象）时重置，防止渲染崩溃
    this.sanitizeAppData()
  }

  // 校验并修复 AppStorage 关键数据的格式（兼容损坏/旧版数据）
  private sanitizeAppData(): void {
    const orders: Object = AppStorage.get<Object>('orderList') as Object
    if (orders !== undefined && orders !== null && !Array.isArray(orders)) {
      AppStorage.setOrCreate<Order[]>('orderList', [])
    }
    const cart: Object = AppStorage.get<Object>('cartItems') as Object
    if (cart !== undefined && cart !== null && !Array.isArray(cart)) {
      AppStorage.setOrCreate<CartItem[]>('cartItems', [])
    }
    const favorites: Object = AppStorage.get<Object>('favoriteList') as Object
    if (favorites !== undefined && favorites !== null && !Array.isArray(favorites)) {
      AppStorage.setOrCreate<Favorite[]>('favoriteList', [])
    }
    const coupons: Object = AppStorage.get<Object>('couponList') as Object
    if (coupons !== undefined && coupons !== null && !Array.isArray(coupons)) {
      AppStorage.setOrCreate<Coupon[]>('couponList', [])
    }
    const addresses: Object = AppStorage.get<Object>('addressList') as Object
    if (addresses !== undefined && addresses !== null && !Array.isArray(addresses)) {
      AppStorage.setOrCreate<Address[]>('addressList', [])
    }
    const user: Object = AppStorage.get<Object>('user') as Object
    if (user !== undefined && user !== null && (typeof user !== 'object' || Array.isArray(user))) {
      AppStorage.setOrCreate<User>('user', createEmptyUser())
    }
    // 未登录时强制重置为“未登录”用户，避免残留旧默认账号昵称（如美食家小张）
    const loggedInFlag: boolean = AppStorage.get<boolean>('isLoggedIn') || false
    if (!loggedInFlag) {
      AppStorage.setOrCreate<User>('user', createEmptyUser())
    }
  }

  // 从子路由页面（收藏页/搜索页）返回时，处理店铺详情跳转
  onPageShow() {
    logInfo('Page', '首页 Index onPageShow')
    if (!(AppStorage.get<boolean>('privacyConsent') || false)) {
      return
    }
    // 从后端拉取最新店铺/订单数据（真实后端模式）
    syncCategoriesFromServer()
    syncStoresFromServer()
    if (isLoggedIn()) {
      syncUserOrdersFromServer()
    }
    const storeId: number = AppStorage.get<number>('currentStoreId') || 0
    if (storeId > 0) {
      AppStorage.setOrCreate<number>('currentStoreId', 0)
      this.showStoreDetail(storeId)
    }
  }

  // 切换发现Tab并展示指定店铺详情
  private showStoreDetail(storeId: number): void {
    AppStorage.setOrCreate<number>('selectedStoreId', storeId)
    const store: StoreItem | undefined = getAllStoresList().find(s => s.id === storeId)
    if (store !== undefined) {
      AppStorage.setOrCreate<string>('selectedStoreName', store.name)
    }
    this.currentTab = 1
    this.tabsController.changeIndex(1)
  }

  build() {
    Stack() {
      Tabs({ controller: this.tabsController, barPosition: BarPosition.End }) {
      // 首页Tab
      TabContent() {
        HomePage({
          onStoreClick: (store: StoreItem) => {
            this.showStoreDetail(store.id)
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
          },
          onNavigateLogin: () => { this.showLogin = true }
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
    .onChange((index: number) => {
      this.currentTab = index
      logInfo('Page', `首页 Tab 切换 index=${index}`)
    })
    .scrollable(false)
    .animationDuration(0)
    .width('100%')
    .height('100%')
    .backgroundColor(COLORS.BG_PRIMARY)

      // 登录覆盖层（必须放在 Tabs 之后，确保在 Stack 中处于上层，否则会被 Tabs 遮挡无法显示/点击）
      if (this.showLogin) {
        LoginPage({
          onLoginSuccess: () => {
            this.showLogin = false
            this.loggedIn = true
          }
        })
      }
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
  @StorageLink('categoryList') categories: Category[] = []
  @State stores: StoreItem[] = []
  @State searchText: string = ''
  @State currentCategory: number = 0
  @State isRefreshing: boolean = false
  @StorageLink('currentAddress') currentAddress: Address | null = null
  @State isHeaderVisible: boolean = false
  @State showPrivacyDialog: boolean = false
  onStoreClick: (store: StoreItem) => void = () => {}
  onNavigateLogin: () => void = () => {}
  private storeDataSource: StoreDataSource = new StoreDataSource()

  // 首页定位栏只展示“市 + 区/县/旗”，完整地址仍保留在 currentAddress 中供结算和配送使用
  private getCityDistrict(address: string): string {
    const compactAddress: string = address.replace(/\s+/g, '').replace(/^中国/, '')
    if (compactAddress === '') {
      return ''
    }
    const cityMatch = compactAddress.match(/([^省自治区特别行政区]+市)/)
    if (cityMatch !== null) {
      const cityName: string = cityMatch[1]
      const cityIndex: number = compactAddress.indexOf(cityName)
      const remainingAddress: string = compactAddress.substring(cityIndex + cityName.length)
      const districtMatch = remainingAddress.match(/([^市]+?(?:区|县|旗))/)
      if (districtMatch !== null) {
        return `${cityName}${districtMatch[1]}`
      }
      return cityName
    }
    const districtMatch = compactAddress.match(/([^省市自治区特别行政区]+(?:区|县|旗))/)
    if (districtMatch !== null) {
      return districtMatch[1]
    }
    return compactAddress
  }

  private getDisplayAddress(): string {
    if (this.currentAddress === null) {
      return '未定位，点击定位'
    }
    const address: string = this.currentAddress.address.trim()
    const coordinatePattern: RegExp = /^\(-?\d+(\.\d+)?,\s*-?\d+(\.\d+)?\)$/
    if (address !== '' && !coordinatePattern.test(address)) {
      return this.getCityDistrict(address)
    }
    const detail: string = this.currentAddress.detail.trim()
    if (detail !== '' && !coordinatePattern.test(detail)) {
      return this.getCityDistrict(detail)
    }
    return '位置已获取，点击查看地址'
  }

  aboutToAppear() {
    this.isHeaderVisible = true
    this.showPrivacyDialog = !(AppStorage.get<boolean>('privacyConsent') || false)
    this.stores = this.getNearbyStores()
    this.storeDataSource.setData(this.stores)
    // 隐私同意前不发起网络请求；同意后由确认回调触发同步
    if (AppStorage.get<boolean>('privacyConsent') || false) {
      this.refreshStores()
    }
  }

  // 拉取后端店铺数据并刷新列表
  private async refreshStores(): Promise<void> {
    if (!(AppStorage.get<boolean>('privacyConsent') || false)) {
      return
    }
    await syncCategoriesFromServer()
    await syncStoresFromServer()
    this.stores = this.getNearbyStores()
    this.storeDataSource.setData(this.stores)
  }

  private hasCurrentLocation(): boolean {
    if (this.currentAddress === null) {
      return false
    }
    const address: Address = this.currentAddress as Address
    return address.address.trim() !== '' || address.detail.trim() !== '' ||
      (address.latitude !== undefined && address.longitude !== undefined)
  }

  private parseStoreDistance(distance: string): number {
    const match: RegExpMatchArray | null = distance.match(/([0-9]+(?:\.[0-9]+)?)/)
    return match === null ? Number.MAX_VALUE : Number.parseFloat(match[1])
  }

  private getNearbyStores(): StoreItem[] {
    if (!this.hasCurrentLocation()) {
      return []
    }
    return getAllStoresList().filter((store: StoreItem) => this.parseStoreDistance(store.distance) <= 2.0)
  }

  private openProductList(mode: string, categoryId: number, title: string): void {
    if ((mode === 'nearby' || mode === 'all') && !this.hasCurrentLocation()) {
      promptAction.showToast({ message: '请先定位，再查看附近商品', duration: 1500 })
      router.pushUrl({ url: 'pages/LocationPage' })
      return
    }
    AppStorage.setOrCreate<string>('productListMode', mode)
    AppStorage.setOrCreate<number>('productListCategoryId', categoryId)
    AppStorage.setOrCreate<string>('productListTitle', title)
    router.pushUrl({ url: 'pages/ProductListPage' })
  }

  build() {
    Column() {
      // 顶部地址栏 + 搜索
      Column({ space: SPACING.SM }) {
        Row({ space: 4 }) {
          Column(){
            // 地址
            Row({ space: 4 }) {
              Image($r('app.media.location_icon'))
                .width(20)
                .height(20)
              if (this.currentAddress !== null) {
                Text(this.getDisplayAddress())
                  .fontSize(FONT_SIZE.LG)
                  .fontColor(COLORS.TEXT_PRIMARY)
                  .fontWeight(FontWeight.Bold)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
              } else {
                // 未定位：显示提示并引导用户去定位
                Text('未定位，点击定位')
                  .fontSize(FONT_SIZE.MD)
                  .fontColor(COLORS.PRIMARY)
                  .fontWeight(FontWeight.Bold)
              }
              Image($r('app.media.chevron_down_icon'))
                .width(16)
                .height(16)
            }
            .onClick(() => {
              // 未定位时提示用户去定位，再进入定位选择页
              if (this.currentAddress === null) {
                promptAction.showToast({ message: '您尚未定位，请先选择配送位置', duration: 1500 })
              }
              router.pushUrl({ url: 'pages/LocationPage' })
            })
            .width('25%')

            // 搜索
            Row({ space: 4 }) {
              Image($r('app.media.search_icon'))
                .width(20)
                .height(20)
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
            .width('100%')
            .onClick(() => { router.pushUrl({ url: 'pages/SearchPage' }) })
          }
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .padding({ left: 0, right: 0 })
      }

      .width('100%')
      .padding({ left: SPACING.LG, right: SPACING.LG, top: 40, bottom: SPACING.MD })
      .backgroundColor(COLORS.BG_WHITE)
      .opacity(this.isHeaderVisible ? 1 : 0)
      .translate({ y: this.isHeaderVisible ? 0 : 8 })
      .animation({ duration: 260, curve: Curve.EaseInOut })

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
                  this.openProductList('category', cat.id, `${cat.name}商品`)
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
              .onClick(() => {
                if (item.title === '收藏夹') {
                  router.pushUrl({ url: 'pages/FavoriteListPage' })
                } else if (item.title === '领券中心') {
                  router.pushUrl({ url: 'pages/CouponCenterPage' })
                } else if (item.title === '排行榜') {
                  this.openProductList('ranking', 0, '排行榜商品')
                } else {
                  this.openProductList('special', 0, `${item.title}商品`)
                }
              })
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
          .onClick(() => {
            this.openProductList('all', 0, '附近全部商品')
          })

          // 店铺列表
          if (this.stores.length === 0) {
            EmptyState({ icon: '🏪', title: this.hasCurrentLocation() ? '暂无附近店铺' : '请先定位', description: this.hasCurrentLocation() ? '暂无符合条件的附近店铺' : '定位后即可查看附近商品' })
          } else {
            Refresh({ refreshing: this.isRefreshing }) {
              List({ space: SPACING.SM }) {
                LazyForEach(this.storeDataSource, (store: StoreItem) => {
                  ListItem() {
                    this.StoreCard(store)
                  }
                }, (item: StoreItem) => item.id.toString())
              }
              .width('100%')
              .padding({ left: SPACING.LG, right: SPACING.LG, bottom: SPACING.LG })
              .divider({ strokeWidth: 0 })
              .cachedCount(5)
            }
            .onRefreshing(() => {
              this.stores = this.getNearbyStores()
              this.storeDataSource.setData(this.stores)
              this.isRefreshing = false
            })
          }
          }
          .layoutWeight(1)
        }

      if (this.showPrivacyDialog) {
        Stack() {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('rgba(0,0,0,0.5)')
          Column({ space: SPACING.MD }) {
            Text('隐私政策提示')
              .fontSize(FONT_SIZE.XL)
              .fontWeight(FontWeight.Bold)
              .fontColor(COLORS.TEXT_PRIMARY)
            Text('为了提供登录、定位、配送和订单服务，我们需要按照隐私政策处理必要信息。请阅读并同意后继续使用。')
              .fontSize(FONT_SIZE.MD)
              .fontColor(COLORS.TEXT_SECONDARY)
              .textAlign(TextAlign.Center)
            Text('查看《隐私政策》')
              .fontSize(FONT_SIZE.MD)
              .fontColor(COLORS.PRIMARY)
              .onClick(() => { router.pushUrl({ url: 'pages/PrivacyPolicyPage' }) })
            Row({ space: SPACING.MD }) {
              Button('暂不同意')
                .layoutWeight(1)
                .height(44)
                .backgroundColor('#F5F5F5')
                .fontColor(COLORS.TEXT_SECONDARY)
                .borderRadius(BORDER_RADIUS.ROUND)
                .type(ButtonType.Capsule)
                .onClick(() => { promptAction.showToast({ message: '请先同意隐私政策后继续使用' }) })
              Button('同意并继续')
                .id('privacy-accept')
                .layoutWeight(1)
                .height(44)
                .backgroundColor(COLORS.PRIMARY)
                .fontColor(Color.White)
                .borderRadius(BORDER_RADIUS.ROUND)
                .type(ButtonType.Capsule)
                .onClick(async () => {
                  setPrivacyConsent(true)
                  AppStorage.setOrCreate<boolean>('privacyConsent', true)
                  initLogger()
                  await loadAllData()
                  await saveAllData()
                  this.showPrivacyDialog = false
                  await this.refreshStores()
                })
            }
            .width('100%')
          }
          .width('82%')
          .padding(SPACING.XL)
          .backgroundColor(COLORS.BG_WHITE)
          .borderRadius(BORDER_RADIUS.XL)
          .alignItems(HorizontalAlign.Center)
        }
        .width('100%')
        .height('100%')
        .alignContent(Alignment.Center)
      }
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
          RatingStars({ rating: store.rating, fontSize: FONT_SIZE.SM, showNumber: true })
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
              .padding({ left: 6, right: 6, top: 2, bottom: 2 }).borderRadius(BORDER_RADIUS.ROUND)
              .margin({ top: 2 })
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
  onNavigateLogin: () => void = () => {}

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
        StoreDetailContent({
          storeId: this.selectedStoreId,
          onNavigateLogin: this.onNavigateLogin
        })
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
  // 收藏页/搜索页返回后，父组件会复用详情组件实例；使用 @Prop + @Watch
  // 确保切换店铺时重新加载商品、评分和店铺信息，避免标题与内容错位。
  @Prop @Watch('onStoreIdChange') storeId: number = 0
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
  @State isFav: boolean = false
  @State storeReviews: Review[] = []
  @State currentCat: string = '全部'
  @State goodsCats: string[] = ['全部']
  @StorageLink('cartItems') cartItems: CartItem[] = []
  @StorageLink('categoryList') categoryList: Category[] = []
  onNavigateLogin: () => void = () => {}

  aboutToAppear() {
    this.loadStoreData()
  }

  onStoreIdChange(): void {
    this.loadStoreData()
  }

  private loadStoreData(): void {
    this.goodsList = getGoodsForStore(this.storeId)
    const store = getAllStoresList().find(s => s.id === this.storeId)
    if (store === undefined) {
      this.storeName = ''
      this.storeRating = 0
      this.storeMonthlySales = 0
      this.storeDeliveryFee = 0
      this.storeDeliveryTime = ''
      this.storeDistance = ''
      this.storeMinOrder = 0
      this.storeTags = []
      this.storeNotice = ''
    }
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
    this.isFav = isFavorited(this.storeId)
    this.storeReviews = []
    const cats: string[] = this.getGoodsCategoryNames(this.goodsList)
    this.goodsCats = ['全部', ...cats]
    this.currentCat = '全部'
    this.updateCartInfo()
    // 从后端拉取最新商品（真实后端模式）
    this.refreshGoods()
    this.refreshReviews()
  }

  // 拉取后端店铺商品并刷新
  private async refreshGoods(): Promise<void> {
    await syncGoodsFromServer(this.storeId)
    const goods: GoodsItem[] = getGoodsForStore(this.storeId)
    this.goodsList = goods
    const cats: string[] = this.getGoodsCategoryNames(goods)
    this.goodsCats = ['全部', ...cats]
    this.currentCat = '全部'
  }

  private async refreshReviews(): Promise<void> {
    await syncStoreReviewsRemote(this.storeId)
    this.storeReviews = AppStorage.get<Review[]>('reviewList') || []
  }

  private getGoodsCategoryNames(goods: GoodsItem[]): string[] {
    const names: string[] = []
    goods.forEach((item: GoodsItem) => {
      const category: Category | undefined = this.categoryList.find((cat: Category) => cat.id === item.categoryId)
      if (category !== undefined && names.indexOf(category.name) < 0) {
        names.push(category.name)
      }
    })
    return names
  }

  updateCartInfo() {
    this.cartItems = AppStorage.get<CartItem[]>('cartItems') || []
    const sc = (this.cartItems || []).filter(c => c.storeId === this.storeId)
    this.cartCount = sc.reduce((s, i) => s + i.quantity, 0)
    this.cartTotal = sc.reduce((s, i) => s + i.goods.price * i.quantity, 0)
  }

  // 按当前分类筛选商品，并过滤已下架商品
  get filteredGoods(): GoodsItem[] {
    const onShelfGoods: GoodsItem[] = this.goodsList.filter(g => g.isOnShelf !== false)
    if (this.currentCat === '全部') {
      return onShelfGoods
    }
    return onShelfGoods.filter(g => {
      const category: Category | undefined = this.categoryList.find((cat: Category) => cat.id === g.categoryId)
      return category !== undefined && category.name === this.currentCat
    })
  }

  // 生成评分星星字符串
  getStars(rating: number): string {
    let stars: string = ''
    for (let i = 0; i < rating; i++) {
      stars += '★'
    }
    return stars
  }

  build() {
    Column() {
      // 店铺信息
      Column({ space: 6 }) {
        Row() {
          Text(this.storeName)
            .fontSize(FONT_SIZE.XL).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
            .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.isFav ? '❤️' : '🤍')
            .fontSize(24)
            .onClick(async () => {
              if (!isLoggedIn()) {
                promptAction.showToast({
                  message: '请先登录后再收藏',
                  duration: 1500
                })
                this.onNavigateLogin()
                return
              }
              const fav: boolean = await toggleFavoriteRemote(this.storeId)
              this.isFav = fav
              promptAction.showToast({
                message: fav ? '已收藏' : '已取消收藏',
                duration: 2000
              })
            })
        }
        .width('100%')
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
          ForEach(this.goodsCats, (catName: string) => {
            Text(catName)
              .fontSize(FONT_SIZE.MD)
              .fontColor(this.currentCat === catName ? COLORS.TEXT_WHITE : COLORS.TEXT_SECONDARY)
              .backgroundColor(this.currentCat === catName ? COLORS.PRIMARY : '#F5F5F5')
              .padding({ left: 12, right: 12, top: 4, bottom: 4 })
              .borderRadius(BORDER_RADIUS.ROUND)
              .height(28)
              .onClick(() => { this.currentCat = catName })
          }, (catName: string) => catName)
        }
        .padding({ left: SPACING.LG, top: SPACING.SM, bottom: SPACING.SM })
      }
      .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      .width('100%').backgroundColor(COLORS.BG_WHITE)

      // 商品列表
      Stack({ alignContent: Alignment.Bottom }) {
        Scroll() {
          Column() {
            ForEach(this.filteredGoods, (goods: GoodsItem) => {
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

            // 用户评价列表区域
            this.ReviewsSection()
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
            AppStorage.setOrCreate<number>('checkoutStoreId', this.storeId)
            router.pushUrl({ url: 'pages/CheckoutPage' })
          }
        })
    }
    .width('100%').height(56)
    .padding({ left: SPACING.LG, right: SPACING.SM })
    .backgroundColor(COLORS.TEXT_PRIMARY)
  }

  @Builder
  ReviewsSection() {
    Column({ space: SPACING.SM }) {
      Text(`用户评价（${this.storeReviews.length}条）`)
        .fontSize(FONT_SIZE.LG).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
        .width('100%')

      if (this.storeReviews.length === 0) {
        Text('暂无评价')
          .fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_HINT)
          .width('100%').textAlign(TextAlign.Center)
          .padding({ top: SPACING.LG, bottom: SPACING.LG })
      } else {
        ForEach(this.storeReviews.slice(0, 3), (review: Review) => {
          Column({ space: 4 }) {
            Row({ space: 8 }) {
              Text(review.username)
                .fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_PRIMARY).fontWeight(FontWeight.Bold)
              Text(this.getStars(review.rating))
                .fontSize(FONT_SIZE.SM).fontColor(COLORS.WARNING)
            }
            .width('100%')
            Text(review.content)
              .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
              .width('100%')
            if (review.tags.length > 0) {
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(review.tags, (tag: string) => {
                  Text(tag)
                    .fontSize(FONT_SIZE.XS).fontColor(COLORS.TAG_TEXT).backgroundColor(COLORS.TAG_BG)
                    .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                    .borderRadius(BORDER_RADIUS.SM)
                    .margin({ right: 4, bottom: 4 })
                }, (tag: string) => tag)
              }
              .width('100%')
            }
            Text(review.createTime)
              .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT)
              .width('100%')
          }
          .width('100%')
          .padding(SPACING.MD)
          .backgroundColor(COLORS.BG_WHITE)
          .borderRadius(BORDER_RADIUS.MD)
        }, (review: Review) => review.id.toString())
      }
    }
    .width('100%')
    .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.MD, bottom: SPACING.LG })
  }

  getQty(goodsId: number): number {
    const item = (this.cartItems || []).find(c => c.goods.id === goodsId && c.storeId === this.storeId)
    return item ? item.quantity : 0
  }
}

// ===================== 订单列表 =====================
@Component
struct OrderListMainPage {
  // 注意：数据源必须在 @StorageLink+@Watch 字段之前声明，
  // 避免 @StorageLink 首次绑定时触发 @Watch 回调访问到未初始化的数据源
  private orderDataSource: OrderDataSource = new OrderDataSource()
  @StorageLink('orderList') @Watch('onOrderListChange') orderList: Order[] = []
  @StorageLink('isLoggedIn') @Watch('onLoginStateChange') loggedIn: boolean = false
  @StorageLink('orderFilterStatus') @Watch('onOrderFilterRequest') requestedStatus: number = -1
  @State @Watch('onFilterChange') currentStatus: number = -1
  @State isRefreshing: boolean = false

  aboutToAppear() {
    // 诊断日志：确认启动渲染时订单数据状态
    this.debugOrderState()
    this.currentStatus = this.requestedStatus
    this.refreshDataSource()
    if (!this.loggedIn) {
      this.orderList = []
      return
    }
    // 从后端拉取最新订单（真实后端模式）
    this.refreshOrders()
  }

  onLoginStateChange(): void {
    if (!this.loggedIn) {
      this.orderList = []
      this.refreshDataSource()
      return
    }
    this.refreshOrders()
  }

  onOrderFilterRequest(): void {
    if (this.requestedStatus >= -1 && this.requestedStatus <= 6) {
      this.currentStatus = this.requestedStatus
    }
  }

  // 拉取后端用户订单并刷新列表
  private async refreshOrders(): Promise<void> {
    if (!this.loggedIn) {
      this.orderList = []
      this.refreshDataSource()
      return
    }
    await syncUserOrdersFromServer()
    this.orderList = AppStorage.get<Order[]>('orderList') || []
    this.refreshDataSource()
  }

  onOrderListChange(): void {
    // 防御：@StorageLink 首次绑定也可能触发本回调，数据源未就绪时直接返回
    if (this.orderDataSource === undefined || this.orderDataSource === null) {
      return
    }
    this.refreshDataSource()
  }

  onFilterChange(): void {
    if (this.orderDataSource === undefined || this.orderDataSource === null) {
      return
    }
    this.refreshDataSource()
  }

  private refreshDataSource(): void {
    // 绝对防御：orderList 非数组时按空数组处理，避免 LazyForEach 崩溃
    let list: Order[] = []
    if (this.loggedIn && Array.isArray(this.orderList)) {
      list = this.orderList
    }
    let filtered: Order[] = list
    if (this.currentStatus !== -1) {
      filtered = filtered.filter(o => o !== null && typeof o === 'object' && o.status === this.currentStatus)
    }
    this.orderDataSource.setData(filtered)
  }

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

      if (!this.loggedIn) {
        EmptyState({ icon: '??', title: '暂无登录', description: '请登录后查看订单' })
      } else if (!Array.isArray(this.orderList) || this.orderList.length === 0) {
        EmptyState({ icon: '📦', title: '暂无订单', description: '快去点一份美味吧' })
      } else {
        Refresh({ refreshing: this.isRefreshing }) {
          List({ space: SPACING.SM }) {
            LazyForEach(this.orderDataSource, (order: Order) => {
              ListItem() {
                this.OrderCard(order)
              }
            }, (item: Order) => item.id.toString())
          }
          .layoutWeight(1)
          .width('100%')
          .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.SM, bottom: SPACING.LG })
          .scrollBar(BarState.Off).divider({ strokeWidth: 0 })
          .cachedCount(5)
        }
        .onRefreshing(() => {
          this.orderList = AppStorage.get<Order[]>('orderList') || []
          this.refreshDataSource()
          this.isRefreshing = false
        })
      }
    }
    .width('100%').height('100%')
    .backgroundColor(COLORS.BG_PRIMARY)
  }

  get filteredOrders(): Order[] {
    // 绝对防御：非数组 / 空数组均返回空列表
    if (!Array.isArray(this.orderList) || this.orderList.length === 0) {
      return []
    }
    if (this.currentStatus === -1) {
      return this.orderList
    }
    return this.orderList.filter(o => o !== null && typeof o === 'object' && o.status === this.currentStatus)
  }

  // 诊断：确认订单列表在渲染时的真实状态（排查崩溃后保留）
  private debugOrderState(): void {
    console.info(`[OrderList] orderList type=${typeof this.orderList} isArray=${Array.isArray(this.orderList)} len=${Array.isArray(this.orderList) ? (this.orderList as Order[]).length : -1} currentStatus=${this.currentStatus}`)
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
      ForEach(order.items || [], (item: CartItem) => {
        Row() {
          Text(item.goods.name).fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_SECONDARY).layoutWeight(1)
          Text(`x${item.quantity}`).fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_HINT)
        }.width('100%')
      }, (item: CartItem) => `${item.goods.id}`)
      Row() {
        Text(`共${(order.items || []).reduce((s, i) => s + i.quantity, 0)}件 实付`)
          .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
        Text(`¥${order.payAmount.toFixed(2)}`)
          .fontSize(FONT_SIZE.LG).fontColor(COLORS.PRICE_RED).fontWeight(FontWeight.Bold)
        Blank()
        if (order.status === 3) {
          Button('确认收货').height(32).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_WHITE)
            .backgroundColor(COLORS.PRIMARY).borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
            .onClick(async () => {
              await confirmOrderRemote(order.id)
              this.orderList = AppStorage.get<Order[]>('orderList') || []
              this.refreshDataSource()
            })
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
    .onClick(() => {
      AppStorage.setOrCreate<Order>('currentOrder', order)
      AppStorage.setOrCreate<number>('currentOrderId', order.id)
      router.pushUrl({ url: 'pages/OrderDetailPage' })
    })
  }
}

// ===================== 个人中心 =====================
@Component
struct ProfileMainPage {
  @StorageLink('isLoggedIn') loggedIn: boolean = false
  @StorageLink('cartItems') cartItems: CartItem[] = []
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
            } else {
              router.pushUrl({ url: 'pages/ProfileEditPage' })
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
          this.AssetItem(this.user.balance.toFixed(2), '余额', () => {})
          this.AssetItem((this.user.coupons || []).filter(c => !c.used).length.toString(), '优惠券', () => { router.pushUrl({ url: 'pages/CouponCenterPage' }) })
          this.AssetItem((this.user.orders || []).length.toString(), '订单', () => {
            AppStorage.setOrCreate<number>('orderFilterStatus', -1)
            this.onNavigate(2)
          })
        }
        .width('100%').padding(SPACING.LG)
        .margin({ top: SPACING.SM })
        .backgroundColor(COLORS.BG_WHITE).borderRadius(BORDER_RADIUS.LG)

        // 订单快捷入口
        Row() {
          this.ProfileOrderEntry('⏳', '待付款', 0)
          this.ProfileOrderEntry('📋', '待接单', 1)
          this.ProfileOrderEntry('🚴', '配送中', 3)
          this.ProfileOrderEntry('✅', '已完成', 4)
        }
        .width('100%').padding(SPACING.LG)
        .margin({ top: SPACING.SM })
        .backgroundColor(COLORS.BG_WHITE).borderRadius(BORDER_RADIUS.LG)
        .justifyContent(FlexAlign.SpaceAround)

        // 功能菜单
        Column() {
          this.ProfileMenuRow('📍', '收货地址', () => {
            if (!this.loggedIn) {
              promptAction.showToast({ message: '请先登录后管理收货地址', duration: 1500 })
              this.onNavigateLogin()
              return
            }
            router.pushUrl({ url: 'pages/AddressListPage' })
          })
          this.ProfileMenuRow('🛒', this.getCartTitle(), () => {
            if (!this.loggedIn) {
              promptAction.showToast({ message: '请先登录后查看购物车', duration: 1500 })
              this.onNavigateLogin()
              return
            }
            router.pushUrl({ url: 'pages/CartPage' })
          })
          this.ProfileMenuRow('❤️', '我的收藏', () => { router.pushUrl({ url: 'pages/FavoriteListPage' }) })
          this.ProfileMenuRow('📞', '联系客服', () => {})
          this.ProfileMenuRow('⚙️', '设置', () => { router.pushUrl({ url: 'pages/SettingsPage' }) })
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
            this.ProfileMenuRow('📋', '店铺管理', () => { router.pushUrl({ url: 'pages/MerchantCenterPage' }) })
            this.ProfileMenuRow('📦', '商品上架', () => { router.pushUrl({ url: 'pages/MerchantCenterPage' }) })
            this.ProfileMenuRow('📊', '订单管理', () => { router.pushUrl({ url: 'pages/MerchantOrdersPage' }) })
            this.ProfileMenuRow('💰', '收入统计', () => { router.pushUrl({ url: 'pages/MerchantStatsPage' }) })
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
  AssetItem(value: string, label: string, action: () => void) {
    Column({ space: 4 }) {
      Text(value).fontSize(FONT_SIZE.XXL).fontWeight(FontWeight.Bold).fontColor(COLORS.PRIMARY)
      Text(label).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
    }
    .layoutWeight(1).alignItems(HorizontalAlign.Center)
    .onClick(() => { action() })
  }

  @Builder
  ProfileOrderEntry(icon: string, title: string, status: number) {
    Column({ space: 4 }) {
      Text(icon).fontSize(28)
      Text(title).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
    }
    .onClick(() => {
      AppStorage.setOrCreate<number>('orderFilterStatus', status)
      this.onNavigate(2)
    })
  }

  private getCartTitle(): string {
    const count: number = this.cartItems.reduce((total: number, item: CartItem) => total + item.quantity, 0)
    return count > 0 ? `购物车 (${count})` : '购物车'
  }

  @Builder
  ProfileMenuRow(icon: string, title: string, action: () => void) {
    Row({ space: SPACING.MD }) {
      Text(icon).fontSize(18)
      Text(title).fontSize(FONT_SIZE.LG).fontColor(COLORS.TEXT_PRIMARY).layoutWeight(1)
      Text('›').fontSize(20).fontColor(COLORS.TEXT_HINT)
    }
    .width('100%').height(52)
    .padding({ left: SPACING.LG, right: SPACING.LG })
    .onClick(() => { action() })
  }
}

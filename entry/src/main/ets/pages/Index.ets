/**
 * 主页面 - 简单外卖App
 * 包含：搜索栏、分类导航、店铺列表、店铺详情、购物车、订单列表、个人中心、底部Tab导航
 */
import { Category, StoreItem, GoodsItem, SpecialGoodsItem, CartItem, Order, User, UserRole, Review, Address, Coupon, Favorite, createEmptyUser } from '../model/Models'
import { addToCart, addCartItemRemote, updateCartItemQuantity, updateCartItemQuantityRemote, refreshCartFromServer, initAppStorage, isLoggedIn, logout, getAllStoresList, getGoodsForStore, isFavorited, syncAddressesRemote, syncCartRemote, syncCategoriesFromServer, syncStoreReviewsRemote, syncStoresFromServer, syncGoodsFromServer, syncUserOrdersFromServer, toggleFavoriteRemote, confirmOrderRemote, getLastRemoteErrorMessage, rechargeBalanceRemote, syncCurrentUserFromServer } from '../service/AppStorageManager'
import { fetchRecommendedStoresApi, fetchSpecialGoodsApi, fetchStoreMerchantCategoriesApi } from '../service/ApiService'
import { LoginPage } from './LoginPage'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS, getOrderStatusText, getOrderStatusColor, formatSales } from '../common/Constants'
import { EmptyState } from '../components/EmptyState'
import { RatingStars } from '../components/RatingStars'
import { ConfirmDialog } from '../components/ConfirmDialog'
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
  @State profileRefreshToken: number = 0
  @StorageLink('isLoggedIn') @Watch('onLoginStateChange') loggedIn: boolean = false
  @State showLogin: boolean = true
  @State showLocationLoginConfirm: boolean = false
  // 管理端跳转占位：管理端不渲染主页（定位/购物车/订单等 C 端功能），直接进入平台管理页
  @State adminRedirecting: boolean = false
  private tabsController: TabsController = new TabsController()

  aboutToAppear() {
    // 初始化全局数据
    initAppStorage()
    // 登录态恢复后同步当前用户与账号库数据（保证不同账号余额等数据独立正确）
    this.loggedIn = isLoggedIn()
    this.showLogin = !this.loggedIn
    // 数据格式保险：校验 AppStorage 关键数据，异常（非数组/非对象）时重置，防止渲染崩溃
    this.sanitizeAppData()
    // 管理端守卫：已登录的管理端不渲染主页，直接跳转平台管理页
    this.guardAdminRole()
    this.consumePendingStoreDetail('aboutToAppear')
  }

  private guardAdminRole(): void {
    if (!this.loggedIn) {
      return
    }
    const currentUser: User | undefined = AppStorage.get<User>('user')
    if (currentUser !== undefined && currentUser.role === UserRole.ADMIN) {
      this.adminRedirecting = true
      router.replaceUrl({ url: 'pages/AdminCenterPage' })
    }
  }

  onLoginStateChange(): void {
    // 401、退出登录或角色变化导致的登录态失效，都必须回到登录页。
    this.showLogin = !this.loggedIn
    if (!this.loggedIn) {
      this.adminRedirecting = false
      const currentUser: User | undefined = AppStorage.get<User>('user')
      if (currentUser !== undefined && currentUser !== null && currentUser.id > 0) {
        // 401 清理内存态后还要清除持久化业务缓存，避免账号之间串数据。
        logout()
      }
      return
    }
    if (this.loggedIn) {
      // 管理端登录/恢复登录态：不进入主页，直接跳转平台管理页
      const currentUser: User | undefined = AppStorage.get<User>('user')
      if (currentUser !== undefined && currentUser.role === UserRole.ADMIN) {
        this.adminRedirecting = true
        router.replaceUrl({ url: 'pages/AdminCenterPage' })
        return
      }
      // 后端业务接口统一要求 JWT，登录成功后再拉取首页真实数据。
      syncCategoriesFromServer()
      syncStoresFromServer()
      syncUserOrdersFromServer()
    }
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
      AppStorage.setOrCreate<number>('userBalance', 0)
    }
    // 未登录时强制重置为“未登录”用户，避免残留旧默认账号昵称（如美食家小张）
    const loggedInFlag: boolean = AppStorage.get<boolean>('isLoggedIn') || false
    if (!loggedInFlag) {
      AppStorage.setOrCreate<User>('user', createEmptyUser())
      AppStorage.setOrCreate<number>('userBalance', 0)
    }
  }

  // 从子路由页面（收藏页/搜索页）返回时，处理店铺详情跳转
  onPageShow() {
    logInfo('Page', '首页 Index onPageShow')
    // 从购物车、结算页等子页面返回时，强制“我的”页重新读取购物车数量，避免 Tabs 子组件保留旧标题。
    this.profileRefreshToken += 1
    this.consumePendingStoreDetail('onPageShow')
    // 管理端防御：任何情况下 Index 对管理端不可见（防止返回键/异常路由回到主页）
    const pageUser: User | undefined = AppStorage.get<User>('user')
    if (this.loggedIn && pageUser !== undefined && pageUser.role === UserRole.ADMIN) {
      this.adminRedirecting = true
      router.replaceUrl({ url: 'pages/AdminCenterPage' })
      return
    }
    if (AppStorage.get<boolean>('pendingLocationAfterLogin') || false) {
      this.showLogin = true
    }
    if (AppStorage.get<boolean>('pendingLocationLoginPrompt') || false) {
      AppStorage.setOrCreate<boolean>('pendingLocationLoginPrompt', false)
      this.showLocationLoginConfirm = true
    }
    if (!(AppStorage.get<boolean>('privacyConsent') || false)) {
      return
    }
    if (isLoggedIn()) {
      // 未登录时不发送受保护请求，避免启动阶段出现无意义的 401。
      syncAddressesRemote()
      syncCartRemote()
      syncCategoriesFromServer()
      syncStoresFromServer()
      syncUserOrdersFromServer()
    }
  }

  /** 消费外部列表页返回的店铺详情请求，必须早于首页隐私/数据刷新分支执行。 */
  private consumePendingStoreDetail(source: string): void {
    const currentStoreId: number = AppStorage.get<number>('currentStoreId') || 0
    const selectedStoreId: number = AppStorage.get<number>('selectedStoreId') || 0
    const pending: boolean = AppStorage.get<boolean>('pendingStoreDetail') || false
    const storeId: number = currentStoreId > 0 ? currentStoreId : (pending ? selectedStoreId : 0)
    logInfo('Navigation', `${source} store detail state current=${currentStoreId} selected=${selectedStoreId} pending=${pending} resolved=${storeId}`)
    if (storeId <= 0) {
      return
    }
    AppStorage.setOrCreate<boolean>('pendingStoreDetail', false)
    AppStorage.setOrCreate<number>('currentStoreId', 0)
    this.showStoreDetail(storeId)
    logInfo('Navigation', `${source} switched to store detail storeId=${storeId} tab=${this.currentTab}`)
  }

  // 打开独立店铺详情页，详情不再复用发现Tab
  private async showStoreDetail(storeId: number, storeName: string = ''): Promise<void> {
    AppStorage.setOrCreate<number>('selectedStoreId', storeId)
    if (storeName !== '') {
      AppStorage.setOrCreate<string>('selectedStoreName', storeName)
    } else {
      const store: StoreItem | undefined = getAllStoresList().find(s => s.id === storeId)
      if (store !== undefined) {
        AppStorage.setOrCreate<string>('selectedStoreName', store.name)
      }
    }
    if (getAllStoresList().find(s => s.id === storeId) === undefined && isLoggedIn()) {
      await syncStoresFromServer()
    }
    if (storeName === '' && getAllStoresList().find(s => s.id === storeId) !== undefined) {
      const syncedStore: StoreItem = getAllStoresList().find(s => s.id === storeId) as StoreItem
      AppStorage.setOrCreate<string>('selectedStoreName', syncedStore.name)
    }
    if ((AppStorage.get<string>('selectedStoreName') || '') === '') {
      AppStorage.setOrCreate<string>('selectedStoreName', '店铺详情')
    }
    router.pushUrl({ url: 'pages/StoreDetailPage' })
  }

  build() {
    Stack() {
      if (this.adminRedirecting) {
        // 管理端跳转占位：不渲染主页/定位/购物车/订单等任何 C 端内容，仅显示过渡提示
        Column({ space: SPACING.MD }) {
          Text('🛠️')
            .fontSize(48)
          Text('正在进入平台管理…')
            .fontSize(FONT_SIZE.LG)
            .fontColor(COLORS.TEXT_SECONDARY)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(COLORS.BG_PRIMARY)
      } else {
      if (!this.showLogin) {
      Tabs({ controller: this.tabsController, barPosition: BarPosition.End }) {
      // 首页Tab
      TabContent() {
        HomePage({
          onStoreClick: (store: StoreItem) => {
            this.showStoreDetail(store.id, store.name)
          },
          onNavigateLogin: () => { this.showLogin = true },
          onNavigateLocationLogin: () => { this.showLocationLoginConfirm = true }
        })
      }.tabBar(this.tabBuilder('首页', 0))

      // 发现Tab - 店铺详情
      TabContent() {
        DiscoverPage({
          onBack: () => {
            this.currentTab = 0
            this.tabsController.changeIndex(0)
          },
          onNavigateLogin: () => { this.showLogin = true },
          onStoreClick: (store: StoreItem) => { this.showStoreDetail(store.id, store.name) }
        })
      }.tabBar(this.tabBuilder('发现', 1))

      // 订单Tab
      TabContent() {
        OrderListMainPage()
      }.tabBar(this.tabBuilder('订单', 2))

      // 我的Tab
      TabContent() {
        ProfileMainPage({
          refreshToken: this.profileRefreshToken,
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
      if (index === 3) {
        this.profileRefreshToken += 1
      }
      logInfo('Page', `首页 Tab 切换 index=${index}`)
    })
    .scrollable(false)
    .animationDuration(0)
    .width('100%')
      .height('100%')
      .backgroundColor(COLORS.BG_PRIMARY)

      }

      // 登录覆盖层（必须放在 Tabs 之后，确保在 Stack 中处于上层，否则会被 Tabs 遮挡无法显示/点击）
      else {
        LoginPage({
          onLoginSuccess: () => {
            this.showLogin = false
            this.loggedIn = true
            const currentUser: User | undefined = AppStorage.get<User>('user')
            if (currentUser !== undefined && currentUser.role === UserRole.ADMIN) {
              router.replaceUrl({ url: 'pages/AdminCenterPage' })
              return
            }
            const shouldLocate: boolean = AppStorage.get<boolean>('pendingLocationAfterLogin') || false
            AppStorage.setOrCreate<boolean>('pendingLocationAfterLogin', false)
            if (shouldLocate) {
              router.pushUrl({ url: 'pages/LocationPage' })
            }
          }
        })
      }
      if (this.showLocationLoginConfirm) {
        ConfirmDialog({
          title: '无法定位',
          content: '当前未登录，无法使用定位功能。是否先登录？',
          confirmText: '去登录',
          cancelText: '取消',
          onConfirm: () => {
            this.showLocationLoginConfirm = false
            AppStorage.setOrCreate<boolean>('pendingLocationAfterLogin', true)
            this.showLogin = true
          },
          onCancel: () => {
            this.showLocationLoginConfirm = false
            AppStorage.setOrCreate<boolean>('pendingLocationAfterLogin', false)
          }
        })
      }
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
  @StorageLink('isLoggedIn') @Watch('onLoginStateChange') loggedIn: boolean = false
  @State specialGoods: SpecialGoodsItem[] = []
  @State searchText: string = ''
  @State currentCategory: number = 0
  @State isRefreshing: boolean = false
  @StorageLink('currentAddress') @Watch('onCurrentAddressChange') currentAddress: Address | null = null
  @State isHeaderVisible: boolean = false
  @State showPrivacyDialog: boolean = false
  onStoreClick: (store: StoreItem) => void = () => {}
  onNavigateLogin: () => void = () => {}
  onNavigateLocationLogin: () => void = () => {}

  onLoginStateChange(): void {
    if (this.loggedIn) {
      this.refreshHomeData()
    } else {
      this.specialGoods = []
    }
  }

  onCurrentAddressChange(): void {
    this.refreshHomeData()
  }

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
    const initialCategories: Category[] = AppStorage.get<Category[]>('categoryList') || []
    this.categories = initialCategories.slice()
    // 隐私同意前不发起网络请求；同意后由确认回调触发同步
    if (AppStorage.get<boolean>('privacyConsent') || false) {
      this.refreshHomeData()
    }
  }

  // 首页特价团购直接读取后端商品接口，避免使用本地模拟商品。
  private async refreshHomeData(): Promise<void> {
    if (!(AppStorage.get<boolean>('privacyConsent') || false)) {
      return
    }
    this.isRefreshing = true
    await syncCategoriesFromServer()
    const latestCategories: Category[] = AppStorage.get<Category[]>('categoryList') || []
    this.categories = latestCategories.slice()
    await syncStoresFromServer()
    if (this.loggedIn) {
      const latitude: number | undefined = this.currentAddress !== null ? this.currentAddress.latitude : undefined
      const longitude: number | undefined = this.currentAddress !== null ? this.currentAddress.longitude : undefined
      this.specialGoods = await fetchSpecialGoodsApi(10, latitude, longitude)
    } else {
      this.specialGoods = []
    }
    this.isRefreshing = false
  }

  private hasCurrentLocation(): boolean {
    if (this.currentAddress === null) {
      return false
    }
    const address: Address = this.currentAddress as Address
    return address.latitude !== undefined && address.longitude !== undefined
      && Number.isFinite(address.latitude) && Number.isFinite(address.longitude)
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

  private getCategoryRowsTemplate(): string {
    const rowCount: number = Math.max(1, Math.ceil(this.categories.length / 5))
    let template: string = ''
    for (let i = 0; i < rowCount; i++) {
      template += i === 0 ? '1fr' : ' 1fr'
    }
    return template
  }

  private getCategoryGridHeight(): number {
    const rowCount: number = Math.max(1, Math.ceil(this.categories.length / 5))
    return rowCount * 80
  }

  private getCategoryIcon(category: Category): string {
    return category.icon.trim() === '' || category.icon === '??' ? '🍔' : category.icon
  }

  private openProductList(mode: string, categoryId: number, title: string): void {
    const requiresLocation: boolean = mode === 'nearby' || mode === 'all'
    if (requiresLocation && !this.loggedIn) {
      this.onNavigateLocationLogin()
      return
    }
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
              if (!this.loggedIn) {
                this.onNavigateLocationLogin()
                return
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
                  Text(this.getCategoryIcon(cat)).fontSize(28)
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
                  this.openProductList('category', cat.id, `${cat.name}店铺`)
                })
              }
            }, (item: Category) => item.id.toString())
          }
          .columnsTemplate('1fr 1fr 1fr 1fr 1fr')
          .rowsTemplate(this.getCategoryRowsTemplate())
          .columnsGap(0)
          .rowsGap(4)
          .width('100%')
          .height(this.getCategoryGridHeight())
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

          // 特价团购标题
          Row() {
            Text('特价团购')
              .fontSize(FONT_SIZE.XL).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
            Blank()
            Text('查看全部 >')
              .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT)
          }
          .width('100%')
          .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.MD, bottom: SPACING.SM })
          .onClick(() => {
            this.openProductList('special', 0, '特价团购')
          })

          // 特价商品列表由后端数据库返回
          if (!this.loggedIn) {
            EmptyState({ icon: '🔒', title: '登录后查看特价团购', description: '商家上新的特价商品会展示在这里' })
          } else if (this.isRefreshing && this.specialGoods.length === 0) {
            EmptyState({ icon: '⏳', title: '正在加载特价商品', description: '请稍候，正在读取最新团购数据' })
          } else if (this.specialGoods.length === 0) {
            EmptyState({ icon: '🛍️', title: '暂无特价商品', description: '商家上新特价商品后会展示在这里' })
          } else {
            Refresh({ refreshing: this.isRefreshing }) {
              Column({ space: SPACING.SM }) {
                ForEach(this.specialGoods, (item: SpecialGoodsItem) => {
                  this.SpecialGoodsCard(item)
                }, (item: SpecialGoodsItem) => `${item.goods.storeId}-${item.goods.id}`)
              }
              .width('100%')
              .padding({ left: SPACING.LG, right: SPACING.LG, bottom: SPACING.LG })
            }
            .onRefreshing(() => { this.refreshHomeData() })
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
                  await this.refreshHomeData()
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

  private openSpecialStore(item: SpecialGoodsItem): void {
    const storeId: number = item.goods.storeId ?? 0
    if (storeId <= 0) {
      promptAction.showToast({ message: '店铺信息暂不可用，请刷新后重试', duration: 1800 })
      return
    }
    AppStorage.setOrCreate<number>('selectedStoreId', storeId)
    AppStorage.setOrCreate<string>('selectedStoreName', item.storeName)
    router.pushUrl({ url: 'pages/StoreDetailPage' })
  }

  @Builder
  SpecialGoodsCard(item: SpecialGoodsItem) {
    Row({ space: SPACING.MD }) {
      Column() {
        Text(item.goods.name.substring(0, 1))
          .fontSize(FONT_SIZE.XL).fontWeight(FontWeight.Bold).fontColor(COLORS.PRIMARY)
      }
      .width(82).height(82).backgroundColor('#FFF1EB').borderRadius(BORDER_RADIUS.MD)
      .justifyContent(FlexAlign.Center)

      Column({ space: 4 }) {
        Row() {
          Text(item.goods.name)
            .fontSize(FONT_SIZE.LG).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
            .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text('特价')
            .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_WHITE)
            .backgroundColor(COLORS.PRICE_RED)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 }).borderRadius(BORDER_RADIUS.ROUND)
        }
        Text(`${item.storeName} · ${item.storeDistance}`)
          .fontSize(FONT_SIZE.SM).fontColor(COLORS.PRIMARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Row({ space: SPACING.SM }) {
          Text(`¥${item.goods.price.toFixed(2)}`)
            .fontSize(FONT_SIZE.XL).fontWeight(FontWeight.Bold).fontColor(COLORS.PRICE_RED)
          if (item.goods.originalPrice !== undefined && item.goods.originalPrice > item.goods.price) {
            Text(`¥${item.goods.originalPrice.toFixed(2)}`)
              .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT)
              .decoration({ type: TextDecorationType.LineThrough })
          }
        }
        Text(item.goods.description)
          .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1).alignItems(HorizontalAlign.Start)
    }
    .width('100%').padding(SPACING.MD).backgroundColor(COLORS.BG_WHITE)
    .borderRadius(BORDER_RADIUS.LG)
    .onClick(() => { this.openSpecialStore(item) })
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

// ===================== 发现/附近推荐页 =====================
@Component
struct DiscoverPage {
  @StorageLink('isLoggedIn') loggedIn: boolean = false
  @StorageLink('currentAddress') @Watch('onCurrentAddressChange') currentAddress: Address | null = null
  @State recommendedStores: StoreItem[] = []
  @State loading: boolean = false
  onBack: () => void = () => {}
  onNavigateLogin: () => void = () => {}
  onStoreClick: (store: StoreItem) => void = () => {}

  aboutToAppear() {
    this.refreshRecommended()
  }

  onCurrentAddressChange(): void {
    this.refreshRecommended()
  }

  private async refreshRecommended(): Promise<void> {
    if (!this.loggedIn) {
      return
    }
    if (this.loading) {
      promptAction.showToast({ message: '推荐店铺正在刷新，请稍候', duration: 1200 })
      return
    }
    this.loading = true
    const latitude: number | undefined = this.currentAddress !== null ? this.currentAddress.latitude : undefined
    const longitude: number | undefined = this.currentAddress !== null ? this.currentAddress.longitude : undefined
    this.recommendedStores = await fetchRecommendedStoresApi(2, 10, latitude, longitude)
    this.loading = false
  }

  private hasLocation(): boolean {
    if (this.currentAddress === null) {
      return false
    }
    const address: Address = this.currentAddress as Address
    return address.latitude !== undefined && address.longitude !== undefined
      && Number.isFinite(address.latitude) && Number.isFinite(address.longitude)
  }

  build() {
    Column() {
      // 导航栏
      Row() {
        Text('‹ 返回')
          .fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_PRIMARY)
          .onClick(() => { this.onBack() })
        Text('发现')
          .fontSize(FONT_SIZE.LG).fontWeight(FontWeight.Bold)
          .layoutWeight(1).textAlign(TextAlign.Center)
        Text('   ').fontSize(FONT_SIZE.MD) // 占位
      }
      .width('100%').height(44)
      .padding({ left: SPACING.LG, right: SPACING.LG })
      .backgroundColor(COLORS.BG_WHITE)

      Column() {
          Row() {
            Text('附近推荐')
              .fontSize(FONT_SIZE.XL).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
              .layoutWeight(1)
            Button('刷新').height(32).fontSize(FONT_SIZE.SM)
              .onClick(() => { this.refreshRecommended() })
          }
          .width('100%').padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.MD })
          if (!this.loggedIn) {
            Column({ space: SPACING.SM }) {
              Text('请登录后查看平台推荐商户').fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_HINT)
              Button('立即登录').height(40).fontSize(FONT_SIZE.MD).onClick(() => { this.onNavigateLogin() })
            }.layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
          } else if (!this.hasLocation()) {
            Column({ space: SPACING.SM }) {
              Text('请先定位，再查看附近推荐商户').fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_HINT)
              Button('去定位').height(40).fontSize(FONT_SIZE.MD)
                .onClick(() => { router.pushUrl({ url: 'pages/LocationPage' }) })
            }.layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
          } else if (this.loading) {
            Column() {
              Text('正在查询附近推荐商户…').fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_HINT)
            }.layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
          } else if (this.recommendedStores.length === 0) {
            Column() {
              Text('暂无附近推荐商户').fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_HINT)
              Text('平台会根据距离和营业状态持续更新推荐').fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT)
                .margin({ top: SPACING.SM })
            }.layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
          } else {
            Scroll() {
              Column({ space: SPACING.SM }) {
                ForEach(this.recommendedStores, (store: StoreItem) => {
                  this.RecommendedStoreCard(store)
                }, (store: StoreItem) => store.id.toString())
              }
              .width('100%').padding(SPACING.LG)
            }.layoutWeight(1).scrollBar(BarState.Off)
          }
      }
      .width('100%').layoutWeight(1)
    }
    .width('100%').height('100%')
    .backgroundColor(COLORS.BG_PRIMARY)
  }

  @Builder
  RecommendedStoreCard(store: StoreItem) {
    Row({ space: SPACING.MD }) {
      Column() {
        Text(store.name.substring(0, 1)).fontSize(28).fontWeight(FontWeight.Bold).fontColor(Color.White)
      }
      .width(76).height(76).backgroundColor(COLORS.PRIMARY).borderRadius(BORDER_RADIUS.MD)
      .justifyContent(FlexAlign.Center)
      Column({ space: 4 }) {
        Row() {
          Text(store.name).fontSize(FONT_SIZE.LG).fontWeight(FontWeight.Bold)
            .fontColor(COLORS.TEXT_PRIMARY).layoutWeight(1).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text('平台推荐').fontSize(FONT_SIZE.XS).fontColor(COLORS.PRIMARY)
            .backgroundColor(COLORS.TAG_BG).padding({ left: 5, right: 5, top: 2, bottom: 2 })
            .borderRadius(BORDER_RADIUS.ROUND)
        }.width('100%')
        Row({ space: 8 }) {
          RatingStars({ rating: store.rating, fontSize: FONT_SIZE.SM, showNumber: true })
          Text(`月售${formatSales(store.monthlySales)}`).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
          Text(store.distance).fontSize(FONT_SIZE.SM).fontColor(COLORS.PRIMARY)
        }
        Text(`${store.deliveryTime} · 配送¥${store.deliveryFee} · ${store.minOrder}元起送`)
          .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
        Text(store.notice).fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
    }
    .width('100%').padding(SPACING.MD).backgroundColor(COLORS.BG_WHITE)
    .borderRadius(BORDER_RADIUS.LG).onClick(() => { this.onStoreClick(store) })
  }
}

// ===================== 店铺详情 =====================
@Component
export struct StoreDetailContent {
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
  private cartOperationQueue: Promise<void> = Promise.resolve()
  @State isFav: boolean = false
  @State goodsLoading: boolean = false
  @StorageLink('reviewList') storeReviews: Review[] = []
  @State currentCat: string = '全部'
  @State goodsCats: string[] = ['全部']
  @State filteredGoodsList: GoodsItem[] = []
  // 店内商户分类（演进项，见大纲 8.3）：优先按商户分类分组，无商户分类时回退平台分类
  @State storeMerchantCats: Category[] = []
  @StorageLink('cartItems') @Watch('onCartItemsChange') cartItems: CartItem[] = []
  @StorageLink('categoryList') categoryList: Category[] = []
  @StorageLink('isLoggedIn') loggedIn: boolean = false
  onNavigateLogin: () => void = () => {}

  aboutToAppear() {
    this.loadStoreData()
  }

  onStoreIdChange(): void {
    this.loadStoreData()
  }

  onCartItemsChange(): void {
    this.updateCartInfo()
  }

  private loadStoreData(): void {
    this.goodsList = getGoodsForStore(this.storeId)
    this.storeMerchantCats = []
    this.goodsLoading = false
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
    this.updateFilteredGoods()
    this.updateCartInfo()
    // 从后端拉取最新商品（真实后端模式）
    this.refreshGoods()
    this.refreshReviews()
  }

  // 拉取后端店铺商品并刷新
  private async refreshGoods(): Promise<void> {
    if (!this.loggedIn) {
      return
    }
    this.goodsLoading = true
    try {
      await syncGoodsFromServer(this.storeId)
      this.storeMerchantCats = await fetchStoreMerchantCategoriesApi(this.storeId)
      const goods: GoodsItem[] = getGoodsForStore(this.storeId)
      this.goodsList = goods
      const cats: string[] = this.getGoodsCategoryNames(goods)
      this.goodsCats = ['全部', ...cats]
      this.currentCat = '全部'
      this.updateFilteredGoods()
    } finally {
      this.goodsLoading = false
    }
  }

  private async refreshReviews(): Promise<void> {
    if (!this.loggedIn) {
      return
    }
    await syncStoreReviewsRemote(this.storeId)
    this.storeReviews = AppStorage.get<Review[]>('reviewList') || []
  }

  // 商品分组名：优先使用店内商户分类；商品均未分组时回退到平台分类名
  private getGoodsCategoryNames(goods: GoodsItem[]): string[] {
    const names: string[] = []
    let hasMerchantCat: boolean = false
    goods.forEach((item: GoodsItem) => {
      const merchantCatId: number = item.merchantCategoryId ?? 0
      if (merchantCatId > 0) {
        const category: Category | undefined = this.storeMerchantCats.find((cat: Category) => cat.id === merchantCatId)
        if (category !== undefined && names.indexOf(category.name) < 0) {
          names.push(category.name)
          hasMerchantCat = true
        }
      }
    })
    if (hasMerchantCat) {
      return names
    }
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

  private enqueueCartOperation(operation: () => Promise<void>): void {
    this.cartOperationQueue = this.cartOperationQueue.then(operation).catch(() => {
      // Keep later cart clicks usable when one request fails.
    })
  }

  private addGoodsToCart(goods: GoodsItem): void {
    this.changeGoodsQuantity(goods, 1)
  }

  private changeGoodsQuantity(goods: GoodsItem, delta: number): void {
    this.enqueueCartOperation(async (): Promise<void> => {
      const synced: boolean = await syncCartRemote()
      if (!synced) {
        this.updateCartInfo()
        const message: string = getLastRemoteErrorMessage()
        promptAction.showToast({ message: message === '' ? 'Cart sync failed, please retry' : message, duration: 2200 })
        return
      }
      const currentCart: CartItem[] = AppStorage.get<CartItem[]>('cartItems') || []
      const currentItem: CartItem | undefined = currentCart.find((item: CartItem) =>
        item.goods.id === goods.id && item.storeId === this.storeId)
      const currentQuantity: number = currentItem === undefined ? 0 : currentItem.quantity
      const nextQuantity: number = currentQuantity + delta
      const ok: boolean = await updateCartItemQuantityRemote(goods.id, nextQuantity)
      await refreshCartFromServer()
      this.updateCartInfo()
      if (!ok) {
        await syncCartRemote()
        this.updateCartInfo()
        const message: string = getLastRemoteErrorMessage()
        promptAction.showToast({ message: message === '' ? 'Cart update failed, please retry' : message, duration: 2200 })
      }
    })
  }

  private async legacyAddGoodsToCart(goods: GoodsItem): Promise<void> {
    const item: CartItem = { goods: goods, quantity: 1, storeId: this.storeId, storeName: this.storeName }
    addToCart(item)
    this.updateCartInfo()
    const ok: boolean = await addCartItemRemote(item)
    if (!ok) {
      await syncCartRemote()
      this.updateCartInfo()
      promptAction.showToast({ message: '加入购物车失败，请稍后重试', duration: 2200 })
    }
  }

  private async legacyChangeGoodsQuantity(goods: GoodsItem, quantity: number): Promise<void> {
    updateCartItemQuantity(goods.id, this.storeId, quantity)
    this.updateCartInfo()
    const ok: boolean = await updateCartItemQuantityRemote(goods.id, quantity)
    if (!ok) {
      await syncCartRemote()
      this.updateCartInfo()
      promptAction.showToast({ message: '修改购物车失败，请稍后重试', duration: 2200 })
    }
  }

  // 按当前分类筛选商品，并显式保存结果，避免 ArkUI 渲染期间计算 getter 时序异常
  private updateFilteredGoods(): void {
    const onShelfGoods: GoodsItem[] = this.goodsList.filter(g => g.isOnShelf !== false)
    if (this.currentCat === '全部') {
      this.filteredGoodsList = onShelfGoods
      return
    }
    // 优先按店内商户分类名匹配
    const merchantCat: Category | undefined = this.storeMerchantCats.find((cat: Category) => cat.name === this.currentCat)
    if (merchantCat !== undefined) {
      this.filteredGoodsList = onShelfGoods.filter(g => (g.merchantCategoryId ?? 0) === merchantCat.id)
      return
    }
    // 回退：按平台分类名匹配
    this.filteredGoodsList = onShelfGoods.filter(g => {
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
              const errorMessage: string = getLastRemoteErrorMessage()
              if (errorMessage !== '') {
                promptAction.showToast({ message: errorMessage, duration: 2200 })
                return
              }
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
              .onClick(() => {
                this.currentCat = catName
                this.updateFilteredGoods()
              })
          }, (catName: string) => catName)
        }
        .padding({ left: SPACING.LG, top: SPACING.SM, bottom: SPACING.SM })
      }
      .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      .width('100%').backgroundColor(COLORS.BG_WHITE)

      // 商品列表
      Column() {
        Scroll() {
          Column() {
            if (this.goodsLoading) {
              Text('正在加载商品…')
                .fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_HINT)
                .width('100%').textAlign(TextAlign.Center)
                .padding({ top: SPACING.XXL, bottom: SPACING.XXL })
            } else if (this.filteredGoodsList.length === 0) {
              Column({ space: SPACING.SM }) {
                Text('暂无商品')
                  .fontSize(FONT_SIZE.LG).fontColor(COLORS.TEXT_HINT)
                Text('当前分类暂时没有可售商品')
                  .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT)
              }
              .width('100%').padding({ top: SPACING.XXL, bottom: SPACING.XXL })
              .alignItems(HorizontalAlign.Center)
            } else {
              ForEach(this.filteredGoodsList, (goods: GoodsItem) => {
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
                  this.GoodsReviewSummary(goods)
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

            // 用户评价列表区域
            this.ReviewsSection()
          }
          .padding({ bottom: SPACING.XL })
        }
        .scrollBar(BarState.Off)
        .layoutWeight(1)

        // 购物车栏
        this.CartBar()
      }
      .layoutWeight(1)
    }
    .width('100%').layoutWeight(1)
  }

  @Builder
  AddMinusButton(goods: GoodsItem) {
    Row({ space: 0 }) {
      if (this.getQty(goods.id) > 0) {
        Text('-').width(24).height(24).fontSize(16).fontColor(COLORS.TEXT_WHITE)
          .backgroundColor(COLORS.PRIMARY).borderRadius(BORDER_RADIUS.CIRCLE)
          .textAlign(TextAlign.Center).onClick(() => {
            this.changeGoodsQuantity(goods, -1)
          })
        Text(this.getQty(goods.id).toString()).width(28).height(24).fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_PRIMARY).textAlign(TextAlign.Center)
      }
      Text('+').width(24).height(24).fontSize(16).fontColor(COLORS.TEXT_WHITE)
        .backgroundColor(COLORS.PRIMARY).borderRadius(BORDER_RADIUS.CIRCLE)
        .textAlign(TextAlign.Center).onClick(() => {
          this.addGoodsToCart(goods)
        })
    }
  }

  private getGoodsReviews(goodsId: number): Review[] {
    return (this.storeReviews || []).filter((review: Review) => review.goodsId === goodsId)
  }

  private canReviewGoods(goodsId: number): boolean {
    const orders: Order[] = AppStorage.get<Order[]>('orderList') || []
    return orders.some((order: Order) => order.storeId === this.storeId && order.status === 4
      && (order.escrowStatus ?? 0) === 1 && order.reviewed === 0
      && (order.items || []).some((item: CartItem) => item.goods.id === goodsId))
  }

  private hasReviewedGoods(goodsId: number): boolean {
    const orders: Order[] = AppStorage.get<Order[]>('orderList') || []
    return orders.some((order: Order) => order.storeId === this.storeId && order.status === 4
      && (order.escrowStatus ?? 0) === 1 && order.reviewed === 1
      && (order.items || []).some((item: CartItem) => item.goods.id === goodsId))
  }

  private openGoodsReview(goodsId: number): void {
    const orders: Order[] = AppStorage.get<Order[]>('orderList') || []
    const order: Order | undefined = orders.find((item: Order) => item.storeId === this.storeId
      && item.status === 4 && (item.escrowStatus ?? 0) === 1 && item.reviewed === 0
      && (item.items || []).some((goodsItem: CartItem) => goodsItem.goods.id === goodsId))
    if (order === undefined) {
      promptAction.showToast({ message: '完成订单后才能评价该商品', duration: 1600 })
      return
    }
    AppStorage.setOrCreate<number>('currentOrderId', order.id)
    AppStorage.setOrCreate<number>('currentReviewGoodsId', goodsId)
    router.pushUrl({ url: 'pages/ReviewPage' })
  }

  @Builder
  GoodsReviewSummary(goods: GoodsItem) {
    Row({ space: SPACING.SM }) {
      Text(`商品评价${this.getGoodsReviews(goods.id).length}条`)
        .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT)
      if (this.getGoodsReviews(goods.id).length > 0) {
        Text(this.getGoodsReviews(goods.id)[0].content || '用户已评价')
          .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_SECONDARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
      } else {
        Text('暂无商品评价').fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT).layoutWeight(1)
      }
      Button(this.hasReviewedGoods(goods.id) ? '已评价' : (this.canReviewGoods(goods.id) ? '去评价' : '评价'))
        .height(26).fontSize(FONT_SIZE.XS)
        .fontColor(this.hasReviewedGoods(goods.id) ? COLORS.TEXT_SECONDARY : (this.canReviewGoods(goods.id) ? Color.White : COLORS.TEXT_SECONDARY))
        .backgroundColor(this.hasReviewedGoods(goods.id) ? COLORS.TEXT_HINT : (this.canReviewGoods(goods.id) ? COLORS.PRIMARY : COLORS.BG_PRIMARY))
        .enabled(!this.hasReviewedGoods(goods.id))
        .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
        .onClick(() => {
          if (!this.hasReviewedGoods(goods.id)) {
            this.openGoodsReview(goods.id)
          }
        })
    }.width('100%')
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
        .width(100)
        .onClick(() => {
          if (this.cartCount > 0) {
            AppStorage.setOrCreate<number>('checkoutStoreId', this.storeId)
            router.pushUrl({ url: 'pages/CheckoutPage' })
          } else {
            promptAction.showToast({ message: '购物车还是空的，请先选择商品', duration: 1600 })
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
            if (review.goodsId > 0) {
              Text(`评价商品：${this.getGoodsName(review.goodsId)}`)
                .fontSize(FONT_SIZE.XS).fontColor(COLORS.PRIMARY).width('100%')
            }
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

  private getGoodsName(goodsId: number): string {
    const goods: GoodsItem | undefined = this.goodsList.find((item: GoodsItem) => item.id === goodsId)
    return goods === undefined ? '店内商品' : goods.name
  }

  getQty(goodsId: number): number {
    const currentCart: CartItem[] = AppStorage.get<CartItem[]>('cartItems') || []
    const item: CartItem | undefined = currentCart.find((cartItem: CartItem) =>
      cartItem.goods.id === goodsId && cartItem.storeId === this.storeId)
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
        Text(getOrderStatusText(order.status, order.escrowStatus ?? 0))
          .fontSize(FONT_SIZE.MD).fontColor(getOrderStatusColor(order.status, order.escrowStatus ?? 0)).fontWeight(FontWeight.Bold)
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
        if (order.status === 4 && (order.escrowStatus ?? 0) === 0) {
          Button('确认收货并结算').height(32).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_WHITE)
            .backgroundColor(COLORS.PRIMARY).borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
            .onClick(async () => {
              const ok: boolean = await confirmOrderRemote(order.id)
              this.orderList = AppStorage.get<Order[]>('orderList') || []
              this.refreshDataSource()
              if (ok) {
                promptAction.showToast({ message: '已确认收货，订单已完成', duration: 1800 })
              } else {
                const errorMessage: string = getLastRemoteErrorMessage()
                promptAction.showToast({ message: errorMessage === '' ? '确认收货失败，请稍后重试' : errorMessage, duration: 2200 })
              }
            })
        } else if (order.status === 3) {
          Text('配送中，送达后可确认收货')
            .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT)
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
  @State showRechargeDialog: boolean = false
  @State rechargeAmount: string = ''
  @State recharging: boolean = false
  @Prop @Watch('onRefreshTokenChange') refreshToken: number = 0
  @StorageLink('isLoggedIn') loggedIn: boolean = false
  @StorageLink('cartItems') @Watch('onCartItemsChange') cartItems: CartItem[] = []
  @State user: User = {
    id: 0, username: '未登录', avatar: '', phone: '', password: '', role: UserRole.CUSTOMER,
    balance: 0, coupons: [], orders: [], storeIds: []
  }
  @State cartTitle: string = '购物车'
  // 资产卡片使用页面自身的可观察文本，避免 Builder 继续复用充值前的余额快照。
  @State balanceDisplay: string = '0.00'
  // 余额绑定独立的 AppStorage 字段，登录、充值和下拉同步都会更新到这里。
  @StorageLink('userBalance') @Watch('onBalanceChange') balance: number = 0
  @State isRefreshing: boolean = false
  @State refreshStatus: string = '余额数据来自数据库'
  onNavigate: (tab: number) => void = () => {}
  onNavigateLogin: () => void = () => {}

  async aboutToAppear(): Promise<void> {
    this.refreshCartTitle()
    this.loadLocalUser()
    await this.refreshFromDatabase()
  }

  async onRefreshTokenChange(): Promise<void> {
    this.refreshCartTitle()
    this.loadLocalUser()
    await this.refreshFromDatabase()
  }

  onCartItemsChange(): void {
    this.refreshCartTitle()
  }

  onBalanceChange(): void {
    this.updateBalanceDisplay()
  }

  private loadLocalUser(): void {
    const currentUser: User | undefined = AppStorage.get<User>('user')
    if (currentUser === undefined || currentUser === null || currentUser.id <= 0) {
      this.user = createEmptyUser()
      this.balance = 0
      this.balanceDisplay = '0.00'
      return
    }
    this.applyUser(currentUser)
  }

  async onPageShow(): Promise<void> {
    this.loadLocalUser()
    await this.refreshFromDatabase()
  }

  private async refreshFromDatabase(): Promise<boolean> {
    if (!isLoggedIn()) {
      return false
    }
    const latestUser: User | undefined = await syncCurrentUserFromServer()
    if (latestUser === undefined) {
      return false
    }
    this.applyUser(latestUser)
    return true
  }

  private applyUser(nextUser: User): void {
    this.user = nextUser
    this.balance = Number.isFinite(nextUser.balance) ? nextUser.balance : 0
    this.updateBalanceDisplay()
  }

  private updateBalanceDisplay(): void {
    const normalizedBalance: number = Number.isFinite(this.balance) ? this.balance : 0
    this.balanceDisplay = normalizedBalance.toFixed(2)
  }

  private async refreshProfileData(): Promise<void> {
    if (this.isRefreshing) {
      return
    }
    if (!isLoggedIn()) {
      this.refreshStatus = '请先登录后同步余额'
      promptAction.showToast({ message: '请先登录后再刷新余额', duration: 1800 })
      return
    }
    this.isRefreshing = true
    this.refreshStatus = '正在从数据库同步余额…'
    try {
      const synced: boolean = await this.refreshFromDatabase()
      if (synced) {
        const now: Date = new Date()
        const hour: string = now.getHours().toString().padStart(2, '0')
        const minute: string = now.getMinutes().toString().padStart(2, '0')
        const second: string = now.getSeconds().toString().padStart(2, '0')
        this.refreshStatus = `已同步数据库 ${hour}:${minute}:${second}`
        promptAction.showToast({ message: '余额已按数据库最新数据同步', duration: 1800 })
      } else {
        const remoteError: string = getLastRemoteErrorMessage()
        this.refreshStatus = remoteError === '' ? '数据库同步失败，请重试' : `同步失败：${remoteError}`
        promptAction.showToast({ message: this.refreshStatus, duration: 2400 })
      }
    } finally {
      this.isRefreshing = false
    }
  }

  private openRechargeDialog(): void {
    if (!this.loggedIn) {
      promptAction.showToast({ message: '\u8bf7\u5148\u767b\u5f55\u540e\u518d\u5145\u503c', duration: 1500 })
      this.onNavigateLogin()
      return
    }
    this.rechargeAmount = ''
    this.showRechargeDialog = true
  }

  private async submitRecharge(): Promise<void> {
    if (this.recharging) {
      promptAction.showToast({ message: '\u5145\u503c\u6b63\u5728\u5904\u7406\uff0c\u8bf7\u7a0d\u5019', duration: 1500 })
      return
    }
    const amount: number = Number.parseFloat(this.rechargeAmount.trim())
    if (!Number.isFinite(amount) || amount < 0.01 || amount > 10000) {
      promptAction.showToast({ message: '\u8bf7\u8f93\u5165 0.01\uff5e10000 \u5143\u7684\u5145\u503c\u91d1\u989d', duration: 1800 })
      return
    }
    this.recharging = true
    const updatedUser: User | undefined = await rechargeBalanceRemote(amount)
    this.recharging = false
    if (updatedUser === undefined) {
      promptAction.showToast({ message: '\u5145\u503c\u5931\u8d25\uff0c\u8bf7\u7a0d\u540e\u91cd\u8bd5', duration: 2200 })
      return
    }
    this.showRechargeDialog = false
    this.rechargeAmount = ''
    const confirmedUser: User = updatedUser as User
    this.applyUser(confirmedUser)
    const latestUser: User | undefined = await syncCurrentUserFromServer()
    if (latestUser !== undefined) {
      this.applyUser(latestUser)
    }
    promptAction.showToast({ message: `\u5145\u503c\u6210\u529f\uff0c\u5f53\u524d\u4f59\u989d ¥${this.balance.toFixed(2)}`, duration: 2000 })
  }

  private refreshCartTitle(): void {
    const currentCart: CartItem[] = AppStorage.get<CartItem[]>('cartItems') || []
    let count: number = 0
    const storeIds: number[] = []
    for (let i = 0; i < currentCart.length; i++) {
      const item: CartItem = currentCart[i]
      if (item !== null && item !== undefined && item.quantity > 0 && storeIds.indexOf(item.storeId) < 0) {
        storeIds.push(item.storeId)
        count += 1
      }
    }
    this.cartTitle = count > 0 ? `购物车 (${count})` : '购物车'
  }

  build() {
    Stack() {
      Refresh({ refreshing: this.isRefreshing }) {
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
                ? (this.user.role === UserRole.ADMIN
                  ? '管理端账户'
                  : this.user.role === UserRole.MERCHANT ? '商户账户' : this.user.phone)
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
          this.AssetItem(this.balanceDisplay, '余额', () => { this.openRechargeDialog() })
          this.AssetItem((this.user.coupons || []).filter(c => !c.used).length.toString(), '优惠券', () => { router.pushUrl({ url: 'pages/CouponCenterPage' }) })
          this.AssetItem((this.user.orders || []).length.toString(), '订单', () => {
            AppStorage.setOrCreate<number>('orderFilterStatus', -1)
            this.onNavigate(2)
          })
        }
        .width('100%').padding(SPACING.LG)
        .margin({ top: SPACING.SM })
        .backgroundColor(COLORS.BG_WHITE).borderRadius(BORDER_RADIUS.LG)

        Row() {
          Text(this.refreshStatus)
            .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT).layoutWeight(1)
          Button(this.isRefreshing ? '\u540c\u6b65\u4e2d\u2026' : '\u7acb\u5373\u5237\u65b0')
            .height(34).fontSize(FONT_SIZE.SM)
            .fontColor(COLORS.PRIMARY).backgroundColor('#FFF3E8')
            .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
            .enabled(!this.isRefreshing)
            .onClick(() => { this.refreshProfileData() })
        }
        .width('100%').padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.SM, bottom: SPACING.SM })
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
          this.ProfileMenuRow('📞', '联系客服', () => { router.pushUrl({ url: 'pages/ContactCustomerServicePage' }) })
          this.ProfileMenuRow('⚙️', '设置', () => { router.pushUrl({ url: 'pages/SettingsPage' }) })
        }
        .width('100%')
        .padding({ top: SPACING.SM })
        .margin({ top: SPACING.SM })
        .backgroundColor(COLORS.BG_WHITE).borderRadius(BORDER_RADIUS.LG)

        // 测试工具入口
        Column() {
          this.ProfileMenuRow('💳', '测试充值余额', () => { this.openRechargeDialog() })
        }
        .width('100%')
        .padding({ top: SPACING.SM })
        .margin({ top: SPACING.SM })
        .backgroundColor(COLORS.BG_WHITE).borderRadius(BORDER_RADIUS.LG)

        if (this.loggedIn && this.user.role === UserRole.MERCHANT) {
          Column() {
            Text('🏪 商户管理入口')
              .fontSize(FONT_SIZE.MD).fontWeight(FontWeight.Bold)
              .fontColor(COLORS.PRIMARY)
              .width('100%')
              .padding({ left: SPACING.LG, top: SPACING.SM, bottom: SPACING.SM })
            this.ProfileMenuRow('📋', '店铺管理', () => { router.pushUrl({ url: 'pages/MerchantCenterPage' }) })
            this.ProfileMenuRow('📊', '订单管理', () => { router.pushUrl({ url: 'pages/MerchantOrdersPage' }) })
            this.ProfileMenuRow('💰', '收入统计', () => { router.pushUrl({ url: 'pages/MerchantStatsPage' }) })
          }
          .width('100%')
          .padding({ top: SPACING.SM })
          .margin({ top: SPACING.SM })
          .backgroundColor('#FFF8F0')
          .borderRadius(BORDER_RADIUS.LG)
        }
        if (this.loggedIn && this.user.role === UserRole.ADMIN) {
          Column() {
            Text('🛠 平台管理入口')
              .fontSize(FONT_SIZE.MD).fontWeight(FontWeight.Bold)
              .fontColor(COLORS.PRIMARY)
              .width('100%')
              .padding({ left: SPACING.LG, top: SPACING.SM, bottom: SPACING.SM })
            this.ProfileMenuRow('🗂', '平台分类、店铺与托管订单', () => {
              router.pushUrl({ url: 'pages/AdminCenterPage' })
            })
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
      .onRefreshing(() => { this.refreshProfileData() })
      .refreshOffset(48)
      .pullToRefresh(true)
      .width('100%').height('100%')

      if (this.showRechargeDialog) {
        this.RechargeDialog()
      }
    }
    .width('100%').height('100%')
  }

  @Builder
  RechargeDialog() {
    Column() {
      Column({ space: SPACING.MD }) {
        Text('\u6d4b\u8bd5\u5145\u503c\u4f59\u989d')
          .fontSize(FONT_SIZE.XL).fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)
        Text('\u5145\u503c\u91d1\u989d\u4f1a\u76f4\u63a5\u5199\u5165\u6570\u636e\u5e93\uff0c\u4ec5\u7528\u4e8e\u5f00\u53d1\u6d4b\u8bd5')
          .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
          .width('100%')
        Text('\u5145\u503c\u91d1\u989d\uff08\u5fc5\u586b\uff09')
          .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
          .width('100%')
        TextInput({ placeholder: '\u8bf7\u8f93\u5165\u91d1\u989d\uff0c\u5982\uff1a100', text: this.rechargeAmount })
          .width('100%').height(44).type(InputType.Number)
          .fontSize(FONT_SIZE.MD).backgroundColor(COLORS.BG_PRIMARY)
          .borderRadius(BORDER_RADIUS.SM)
          .onChange((value: string) => { this.rechargeAmount = value })
        Row({ space: SPACING.SM }) {
          Button('\u53d6\u6d88')
            .layoutWeight(1).height(42)
            .backgroundColor(COLORS.BG_PRIMARY).fontColor(COLORS.TEXT_SECONDARY)
            .onClick(() => { this.showRechargeDialog = false })
          Button(this.recharging ? '\u5145\u503c\u4e2d\u2026' : '\u786e\u8ba4\u5145\u503c')
            .layoutWeight(1).height(42)
            .backgroundColor(COLORS.PRIMARY).fontColor(Color.White)
            .onClick(() => { this.submitRecharge() })
        }.width('100%')
      }
      .width('86%').padding(SPACING.XL)
      .backgroundColor(COLORS.BG_WHITE).borderRadius(BORDER_RADIUS.LG)
    }
    .width('100%').height('100%')
    .backgroundColor('rgba(0,0,0,0.35)')
    .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
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
    return '\u8d2d\u7269\u8f66'
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

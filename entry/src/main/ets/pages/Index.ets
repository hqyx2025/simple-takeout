/**
 * 主页面 - 简单外卖App
 * 包含：搜索栏、分类导航、店铺列表、店铺详情、购物车、订单列表、个人中心、底部Tab导航
 */
import { Category, StoreItem, GoodsItem, GoodsSpec, SpecialGoodsItem, SeckillItem, CartItem, Order, User, UserRole, Review, Address, Coupon, Favorite, Banner, Announcement, MarketingActivity, Setmeal, SetmealItem, SetmealOrder, createEmptyUser } from '../model/Models'
import { addToCart, addCartItemRemote, updateCartItemQuantity, updateCartItemQuantityRemote, createOrderRemote, refreshCartFromServer, initAppStorage, isLoggedIn, logout, getAllStoresList, getGoodsForStore, isFavorited, syncAddressesRemote, syncCartRemote, syncCategoriesFromServer, syncStoreReviewsRemote, syncBannersRemote, syncAnnouncementsRemote, syncStoresFromServer, syncGoodsFromServer, syncUserOrdersFromServer, toggleFavoriteRemote, confirmOrderRemote, cancelOrderRemote, payOrderRemote, fetchSeckillsRemote, getLastRemoteErrorMessage, rechargeBalanceRemote, syncCurrentUserFromServer } from '../service/AppStorageManager'
import { fetchRecommendedStoresApi, fetchSpecialGoodsApi, fetchStoreMerchantCategoriesApi, fetchStoreDetailApi, fetchStoreActivitiesApi, fetchStoreSetmealsApi } from '../service/ApiService'
import { LoginPage } from './LoginPage'
import { AssistantPage } from './AssistantPage'
import { CartPage } from './CartPage'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS, getOrderStatusText, getOrderStatusColor, formatSales, merchantImageSource, DEFAULT_MERCHANT_IMAGE, MODULE_COLOR, MODULE_BG, accentBg, accentFg, accentIndexFromText } from '../common/Constants'
import { EmptyState } from '../components/EmptyState'
import { RatingStars } from '../components/RatingStars'
import { ConfirmDialog } from '../components/ConfirmDialog'
import { ChangePasswordDialog } from '../components/ChangePasswordDialog'
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { initLogger, logInfo, logError, setPrivacyConsent } from '../service/AppLogger'
import { savePrivacyConsent } from '../service/DataPersistence'
import { loadAllData, saveAllData } from '../service/DataPersistence'
import { BreakpointSystem } from '../common/utils/BreakpointSystem'
import { FloatingTabBarTheme } from '../common/theme/FloatingTabBarTheme'
import { common } from '@kit.AbilityKit'

// 定义快捷入口和订单Tab的数据类型，解决 arkts-no-untyped-obj-literals 错误
class QuickEntryItem {
  icon: string = ''
  title: string = ''
  color: ResourceColor = ''

  static create(icon: string, title: string, color: ResourceColor): QuickEntryItem {
    let item = new QuickEntryItem()
    item.icon = icon
    item.title = title
    item.color = color
    return item
  }
}

/** 侧边栏导航条目（避免 arkts-no-obj-literals-as-types）。 */
class SidebarItem {
  title: string = ''
  index: number = 0

  static create(title: string, index: number): SidebarItem {
    let item = new SidebarItem()
    item.title = title
    item.index = index
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
  @State isWide: boolean = false
  private tabsController: TabsController = new TabsController()
  private breakpointSystem: BreakpointSystem = new BreakpointSystem()

  aboutToAppear() {
    // 初始化全局数据
    initAppStorage()
    // 未同意隐私政策：先进入独立同意页，避免首页数据被门禁静默挡住（历史上弹窗覆盖层从不渲染）
    if (!(AppStorage.get<boolean>('privacyConsent') || false)) {
      logInfo('Page', '未同意隐私政策，跳转隐私政策同意页')
      router.replaceUrl({ url: 'pages/ConsentPage' })
      return
    }
    // 登录态恢复后同步当前用户与账号库数据（保证不同账号余额等数据独立正确）
    this.loggedIn = isLoggedIn()
    this.showLogin = !this.loggedIn
    // 数据格式保险：校验 AppStorage 关键数据，异常（非数组/非对象）时重置，防止渲染崩溃
    this.sanitizeAppData()
    // 管理端守卫：已登录的管理端不渲染主页，直接跳转平台管理页
    this.guardAdminRole()
    this.breakpointSystem.register(this.getUIContext().getHostContext() as common.UIAbilityContext, (breakpoint: string): void => {
      this.isWide = this.breakpointSystem.isWideForLayout()
    })
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
    if (currentUser !== undefined && currentUser.role === UserRole.RIDER) {
      this.adminRedirecting = true
      router.replaceUrl({ url: 'pages/RiderCenterPage' })
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
      if (currentUser !== undefined && currentUser.role === UserRole.RIDER) {
        this.adminRedirecting = true
        router.replaceUrl({ url: 'pages/RiderCenterPage' })
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

  onPageShow() {
    logInfo('Page', '首页 Index onPageShow')
    // 从购物车、结算页等子页面返回时，强制“我的”页重新读取购物车数量，避免 Tabs 子组件保留旧标题。
    this.profileRefreshToken += 1
    // 管理端/骑手防御：任何情况下 Index 对管理端、骑手不可见（防止返回键/异常路由回到主页）
    const pageUser: User | undefined = AppStorage.get<User>('user')
    if (this.loggedIn && pageUser !== undefined && pageUser.role === UserRole.ADMIN) {
      this.adminRedirecting = true
      router.replaceUrl({ url: 'pages/AdminCenterPage' })
      return
    }
    if (this.loggedIn && pageUser !== undefined && pageUser.role === UserRole.RIDER) {
      this.adminRedirecting = true
      router.replaceUrl({ url: 'pages/RiderCenterPage' })
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
      if (this.isWide) {
        this.wideLayout()
      } else {
        this.mainTabs()
      }

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
            if (currentUser !== undefined && currentUser.role === UserRole.RIDER) {
              router.replaceUrl({ url: 'pages/RiderCenterPage' })
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

  /** 底部 4 个 Tab 各用一种模块色：一眼看出当前在哪个模块。 */
  private tabColor(targetIndex: number): ResourceColor {
    if (targetIndex === 0) { return MODULE_COLOR.HOME }
    if (targetIndex === 1) { return MODULE_COLOR.REVIEW }
    if (targetIndex === 2) { return MODULE_COLOR.CART }
    return MODULE_COLOR.MINE
  }

  @Builder
  wideLayout() {
    SideBarContainer(SideBarContainerType.Embed) {
      Column() {
        Column({ space: SPACING.MD }) {
          SymbolGlyph($r('sys.symbol.house'))
            .fontSize(24)
            .fontColor([COLORS.PRIMARY])
            .width(40).height(40)
            .backgroundColor(COLORS.BG_CARD)
            .borderRadius(20)
          Text('简单外卖')
            .fontSize(FONT_SIZE.LG)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLORS.TEXT_PRIMARY)
            .maxLines(1)
        }
        .width('100%')
        .padding({ top: SPACING.XL, bottom: SPACING.LG })

        Divider().color(COLORS.DIVIDER).margin({ bottom: SPACING.MD })

        ForEach([
          SidebarItem.create('首页', 0),
          SidebarItem.create('AI助手', 1),
          SidebarItem.create('我的', 3)
        ], (item: SidebarItem) => {
          Button({ type: ButtonType.Normal }) {
            Row({ space: SPACING.MD }) {
              Text(this.currentTab === item.index ? '•' : '  ')
                .fontSize(FONT_SIZE.XL)
                .fontColor(COLORS.PRIMARY)
                .width(20)
              Text(item.title)
                .fontSize(FONT_SIZE.LG)
                .fontColor(this.currentTab === item.index ? COLORS.PRIMARY : COLORS.TEXT_PRIMARY)
                .fontWeight(this.currentTab === item.index ? FontWeight.Bold : FontWeight.Normal)
            }
            .width('100%')
          }
          .width('100%')
          .height(44)
          .buttonStyle(ButtonStyleMode.NORMAL)
          .backgroundColor(this.currentTab === item.index ? COLORS.BG_CARD : Color.Transparent)
          .borderRadius(12)
          .onClick(() => { this.switchTab(item.index) })
        }, (item: SidebarItem) => item.title)
      }
      .width('100%')
      .height('100%')
      .padding(SPACING.SM)
      .backgroundColor(COLORS.BG_PRIMARY)

      Column() {
        this.tabContent()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(COLORS.BG_PRIMARY)
    }
    .showSideBar(true)
    .showControlButton(false)
    .sideBarWidth(200)
    .divider({ strokeWidth: 0, color: Color.Transparent })
    .width('100%')
    .height('100%')
  }

  @Builder
  mainTabs() {
    Tabs({ controller: this.tabsController, barPosition: BarPosition.End }) {
      TabContent() {
        HomePage({
          onStoreClick: (store: StoreItem) => {
            this.showStoreDetail(store.id, store.name)
          },
          onNavigateLogin: () => { this.showLogin = true },
          onNavigateLocationLogin: () => { this.showLocationLoginConfirm = true }
        })
      }.tabBar(this.tabBuilder('首页', 0))

      TabContent() {
        AssistantPage()
      }.tabBar(this.tabBuilder('AI助手', 1))

      TabContent() {
        CartPage()
      }.tabBar(this.tabBuilder('购物车', 2))

      TabContent() {
        ProfileMainPage({
          refreshToken: this.profileRefreshToken,
          onNavigateLogin: () => { this.showLogin = true }
        })
      }.tabBar(this.tabBuilder('我的', 3))
    }
    .barHeight(50)
    .barBackgroundColor(COLORS.BG_WHITE)
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

  /** 切换 Tab 并刷新小部件 */
  private switchTab(index: number): void {
    if (this.currentTab === index) {
      return
    }
    this.currentTab = index
    if (index === 3) {
      this.profileRefreshToken += 1
    }
    this.tabsController.changeIndex(index)
  }

  @Builder
  tabContent() {
    if (this.currentTab === 0) {
      HomePage({
        onStoreClick: (store: StoreItem) => { this.showStoreDetail(store.id, store.name) },
        onNavigateLogin: () => { this.showLogin = true },
        onNavigateLocationLogin: () => { this.showLocationLoginConfirm = true }
      })
    } else if (this.currentTab === 1) {
      AssistantPage()
    } else if (this.currentTab === 2) {
      CartPage()
    } else {
      ProfileMainPage({
        refreshToken: this.profileRefreshToken,
        onNavigateLogin: () => { this.showLogin = true }
      })
    }
  }

  @Builder
  tabBuilder(title: string, targetIndex: number) {
    Column({ space: 2 }) {
      Text(title)
        .fontSize(10)
        .fontColor(this.currentTab === targetIndex ? this.tabColor(targetIndex) : COLORS.TAB_INACTIVE)
        .fontWeight(this.currentTab === targetIndex ? FontWeight.Bold : FontWeight.Normal)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .id(`tab-${targetIndex}`)
    .onClick(() => {
      this.currentTab = targetIndex
      this.tabsController.changeIndex(targetIndex)
    })
  }

  aboutToDisappear() {
    this.breakpointSystem.unregister()
  }
}

// ===================== 首页 =====================
@Component
struct HomePage {
  @StorageLink('categoryList') categories: Category[] = []
  @StorageLink('isLoggedIn') @Watch('onLoginStateChange') loggedIn: boolean = false
  @State specialGoods: SpecialGoodsItem[] = []
  @State banners: Banner[] = []
  @State announcements: Announcement[] = []
  // 限时秒杀（服务端时间窗口内且有剩余名额的秒杀）
  @State seckills: SeckillItem[] = []
  // 秒杀倒计时秒表：每秒 +1，与实际剩余时间相减得到实时剩余（避免每个卡片各自起定时器）
  @State seckillTick: number = 0
  private seckillTimer: number = -1
  @State searchText: string = ''
  @State currentCategory: number = 0
  @State isRefreshing: boolean = false
  @StorageLink('currentAddress') @Watch('onCurrentAddressChange') currentAddress: Address | null = null
  @State isHeaderVisible: boolean = false
  // 附近推荐（原「发现」Tab 的能力，现并入首页）：进入首页与定位变化时刷新
  @State recommendedStores: StoreItem[] = []
  @State recommendedLoading: boolean = false
  // 隐私政策同意改由独立页面 pages/ConsentPage 承载（见该文件注释），首页不再内嵌同意弹窗
  onStoreClick: (store: StoreItem) => void = () => {}
  onNavigateLogin: () => void = () => {}
  onNavigateLocationLogin: () => void = () => {}

  onLoginStateChange(): void {
    if (this.loggedIn) {
      this.refreshHomeData()
      this.refreshRecommended()
    } else {
      this.specialGoods = []
      this.recommendedStores = []
    }
  }

  onCurrentAddressChange(): void {
    this.refreshHomeData()
    this.refreshRecommended()
  }

  /** 拉取附近推荐店铺（2 公里内、平台推荐位）。 */
  private async refreshRecommended(): Promise<void> {
    if (!this.loggedIn) {
      return
    }
    if (this.recommendedLoading) {
      promptAction.showToast({ message: '推荐店铺正在刷新，请稍候', duration: 1200 })
      return
    }
    this.recommendedLoading = true
    const latitude: number | undefined = this.currentAddress !== null ? this.currentAddress.latitude : undefined
    const longitude: number | undefined = this.currentAddress !== null ? this.currentAddress.longitude : undefined
    this.recommendedStores = await fetchRecommendedStoresApi(2, 10, latitude, longitude)
    this.recommendedLoading = false
  }

  /** 推荐区需要定位：没有经纬度时提示去定位，而不是显示空列表。 */
  private hasRecommendLocation(): boolean {
    if (this.currentAddress === null) {
      return false
    }
    const address: Address = this.currentAddress as Address
    return address.latitude !== undefined && address.longitude !== undefined
      && Number.isFinite(address.latitude) && Number.isFinite(address.longitude)
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
    const initialCategories: Category[] = AppStorage.get<Category[]>('categoryList') || []
    this.categories = initialCategories.slice()
    // 秒杀倒计时：单个 1 秒定时器驱动全页秒杀卡片，避免每张卡片各起一个定时器
    this.startSeckillTicker()
    // 隐私同意前不发起网络请求（未同意时 Index 会先跳转 ConsentPage，正常不会走到这里）
    if (AppStorage.get<boolean>('privacyConsent') || false) {
      this.refreshHomeData()
      this.refreshRecommended()
    } else {
      logInfo('Home', '隐私政策未同意，等待用户确认后再加载首页数据')
    }
  }

  aboutToDisappear() {
    this.stopSeckillTicker()
  }

  // 首页特价团购直接读取后端商品接口，避免使用本地模拟商品。
  private async refreshHomeData(): Promise<void> {
    if (!(AppStorage.get<boolean>('privacyConsent') || false)) {
      logInfo('Home', '未同意隐私政策，跳过首页数据加载')
      return
    }
    this.isRefreshing = true
    // 首页数据依赖多个接口，任一失败都不能中断后续步骤（否则秒杀/特价会整块消失），
    // 因此逐步打点并整体捕获异常，异常时保留已有数据并明确记录原因。
    try {
      logInfo('Home', '首页数据加载[1/5] 分类')
      await syncCategoriesFromServer()
      const latestCategories: Category[] = AppStorage.get<Category[]>('categoryList') || []
      this.categories = latestCategories.slice()
      logInfo('Home', '首页数据加载[2/5] 店铺')
      await syncStoresFromServer()
      logInfo('Home', '首页数据加载[3/5] 轮播')
      this.banners = await syncBannersRemote()
      logInfo('Home', '首页数据加载[4/5] 公告')
      this.announcements = await syncAnnouncementsRemote()
      logInfo('Home', '首页数据加载[5/5] 特价与秒杀')
      if (this.loggedIn) {
        const latitude: number | undefined = this.currentAddress !== null ? this.currentAddress.latitude : undefined
        const longitude: number | undefined = this.currentAddress !== null ? this.currentAddress.longitude : undefined
        this.specialGoods = await fetchSpecialGoodsApi(10, latitude, longitude)
        this.seckills = await fetchSeckillsRemote(6)
      } else {
        this.specialGoods = []
        this.seckills = []
      }
      logInfo('Home', `首页数据加载完成：轮播=${this.banners.length} 公告=${this.announcements.length} 特价=${this.specialGoods.length} 秒杀=${this.seckills.length}`)
    } catch (err) {
      logError('Home', '首页数据加载失败（已保留部分数据）', err as Object)
    } finally {
      this.isRefreshing = false
    }
  }

  // ============ 限时秒杀 ============

  private startSeckillTicker(): void {
    if (this.seckillTimer >= 0) {
      return
    }
    this.seckillTick = 0
    this.seckillTimer = setInterval(() => {
      this.seckillTick += 1
    }, 1000)
  }

  private stopSeckillTicker(): void {
    if (this.seckillTimer >= 0) {
      clearInterval(this.seckillTimer)
      this.seckillTimer = -1
    }
  }

  /** 秒杀剩余秒数（服务端下发的 remainSeconds 减去本地秒表）。 */
  private seckillRemainSeconds(item: SeckillItem): number {
    return Math.max(item.remainSeconds - this.seckillTick, 0)
  }

  /** 秒杀倒计时文案：HH:mm:ss。 */
  private seckillCountdown(item: SeckillItem): string {
    const total: number = this.seckillRemainSeconds(item)
    const hour: number = Math.floor(total / 3600)
    const minute: number = Math.floor((total % 3600) / 60)
    const second: number = total % 60
    const hh: string = hour < 10 ? `0${hour}` : `${hour}`
    const mm: string = minute < 10 ? `0${minute}` : `${minute}`
    const ss: string = second < 10 ? `0${second}` : `${second}`
    return `${hh}:${mm}:${ss}`
  }

  /** 秒杀进度百分比（已抢名额 / 总名额）。 */
  private seckillSoldPercent(item: SeckillItem): number {
    if (item.quota <= 0) {
      return 0
    }
    return Math.min(Math.round(item.sold * 100 / item.quota), 100)
  }

  /** 点击秒杀商品：进入所属店铺详情继续选购（秒杀价由后端下单时自动套用）。 */
  private openSeckillStore(item: SeckillItem): void {
    if (item.storeId <= 0) {
      promptAction.showToast({ message: '秒杀商品所属店铺信息缺失', duration: 2500 })
      return
    }
    AppStorage.setOrCreate<number>('selectedStoreId', item.storeId)
    AppStorage.setOrCreate<string>('selectedStoreName', item.storeName)
    router.pushUrl({ url: 'pages/StoreDetailPage' })
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
    // 根节点必须用 Stack 承载隐私弹窗这类覆盖层：
    // 弹窗若作为 Column 中 layoutWeight(1) 滚动区的兄弟节点，会被分配 0 高度而整块不渲染（历史 bug）。
    Stack() {
    Column() {
      // 顶部地址栏 + 搜索
      Column({ space: SPACING.SM }) {
        // 地址(左) + 搜索(右) 并排，避免在 Column 中纵向堆叠
        Row({ space: SPACING.MD }) {
          // 地址
          Row({ space: SPACING.XS }) {
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
          .id('home-location-entry')
          .onClick(() => {
            if (!this.loggedIn) {
              this.onNavigateLocationLogin()
              return
            }
            router.pushUrl({ url: 'pages/LocationPage' })
          })
          .constraintSize({ maxWidth: '46%' })

          // 搜索
          Row({ space: SPACING.XS }) {
            Image($r('app.media.search_icon'))
              .width(20)
              .height(20)
            // 首页搜索栏是「假输入框」：点击整行跳转搜索页。
            // 不能用 TextInput——它会吞掉点击事件（聚焦自身而不冒泡到 Row 的 onClick），
            // 导致首页搜索框点了没有任何反应（设备实测确认的缺陷）。
            Text('搜索美食、店铺')
              .fontSize(FONT_SIZE.MD)
              .fontColor(COLORS.TEXT_HINT)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          .padding({ left: SPACING.MD, right: SPACING.MD })
          .height(32)
          .backgroundColor(COLORS.BG_PRIMARY)
          .borderRadius(BORDER_RADIUS.ROUND)
          .layoutWeight(1)
          .id('home-search-entry')
          .onClick(() => { router.pushUrl({ url: 'pages/SearchPage' }) })
        }
        .width('100%')
      }

      .width('100%')
      .padding({ left: SPACING.LG, right: SPACING.LG, top: 40, bottom: SPACING.MD })
      .backgroundColor(COLORS.BG_WHITE)
      .opacity(this.isHeaderVisible ? 1 : 0)
      .translate({ y: this.isHeaderVisible ? 0 : 8 })
      .animation({ duration: 260, curve: Curve.EaseInOut })

      Refresh({ refreshing: this.isRefreshing }) {
        Scroll() {
          Column() {
            // 分类导航
          Grid() {
            ForEach(this.categories, (cat: Category, index: number) => {
              GridItem() {
                Column({ space: SPACING.XS }) {
                  Text(this.getCategoryIcon(cat))
                    .fontSize(26)
                    .width(46).height(46)
                    .textAlign(TextAlign.Center)
                    .backgroundColor(accentBg(index))
                    .borderRadius(BORDER_RADIUS.LG)
                  Text(cat.name)
                    .fontSize(FONT_SIZE.SM)
                    .fontColor(this.currentCategory === cat.id ? COLORS.PRIMARY : accentFg(index))
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

          // Banner（服务端内容管理数据，为空时回退到默认轮播）
          Swiper() {
            if (this.banners.length === 0) {
              Text('新人专享 满20减15')
                .width('100%').height(120).fontSize(FONT_SIZE.XL)
                .fontColor(COLORS.TEXT_WHITE).backgroundColor(COLORS.PRIMARY)
                .borderRadius(BORDER_RADIUS.MD).textAlign(TextAlign.Center)
              Text('限时秒杀 全场8折')
                .width('100%').height(120).fontSize(FONT_SIZE.XL)
                .fontColor(COLORS.TEXT_WHITE).backgroundColor(COLORS.PRICE_RED)
                .borderRadius(BORDER_RADIUS.MD).textAlign(TextAlign.Center)
            } else {
              ForEach(this.banners, (banner: Banner) => {
                Column({ space: SPACING.XS }) {
                  Text(banner.title)
                    .fontSize(FONT_SIZE.XL).fontColor(COLORS.TEXT_WHITE).fontWeight(FontWeight.Bold)
                  if (banner.subtitle !== '') {
                    Text(banner.subtitle).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_WHITE)
                  }
                }
                .width('100%').height(120)
                .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
                .backgroundColor(banner.color)
                .borderRadius(BORDER_RADIUS.MD)
              }, (banner: Banner) => banner.id.toString())
            }
          }
          .indicator(true).autoPlay(true).interval(3000).loop(true)
          .width('100%')
          .padding({ left: SPACING.LG, right: SPACING.LG })
          .margin({ top: SPACING.SM })

          // 平台公告
          if (this.announcements.length > 0) {
            Row({ space: SPACING.SM }) {
              Text('📢').fontSize(FONT_SIZE.MD)
              Text(this.announcements[0].title)
                .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
                .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .width('100%')
            .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.SM, bottom: SPACING.XS })
          }

          // 快捷入口
          Row({ space: SPACING.XL }) {
            ForEach([
              QuickEntryItem.create('⏰', '限时抢购', COLORS.PRIMARY),
              QuickEntryItem.create('❤️', '收藏夹', COLORS.PRICE_RED),
              QuickEntryItem.create('🎫', '领券中心', COLORS.WARNING),
              QuickEntryItem.create('🏆', '排行榜', COLORS.SUCCESS),
            ], (item: QuickEntryItem) => {
              Column({ space: SPACING.XS }) {
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
                  // 榜单：店铺榜 / 菜品热销榜（服务端按月销量与评分排序）
                  router.pushUrl({ url: 'pages/RankingPage' })
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

          // 限时秒杀：服务端时间窗口内的活动，倒计时结束或名额售罄后自动从列表消失
          if (this.seckills.length > 0) {
            Row({ space: SPACING.SM }) {
              Text('⚡')
                .fontSize(FONT_SIZE.MD)
                .width(28).height(28).textAlign(TextAlign.Center)
                .backgroundColor(MODULE_COLOR.SECKILL)
                .borderRadius(BORDER_RADIUS.SM)
              Text('限时秒杀')
                .fontSize(FONT_SIZE.XL).fontWeight(FontWeight.Bold).fontColor(MODULE_COLOR.SECKILL)
              Blank()
              Text('秒杀价下单自动生效')
                .fontSize(FONT_SIZE.SM).fontColor(MODULE_COLOR.SECKILL)
            }
            .width('100%')
            .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.MD, bottom: SPACING.SM })
            .backgroundColor(MODULE_BG.SECKILL)

            Scroll() {
              Row({ space: SPACING.SM }) {
                ForEach(this.seckills, (item: SeckillItem) => {
                  this.SeckillCard(item)
                }, (item: SeckillItem) => `seckill-${item.id}`)
              }
              .padding({ left: SPACING.LG, right: SPACING.LG })
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
            .width('100%')
          }

          // 附近推荐（原「发现」Tab 并入首页）：2 公里内、平台推荐位的店铺
          Row({ space: SPACING.SM }) {
            Text('📍')
              .fontSize(FONT_SIZE.MD)
              .width(28).height(28).textAlign(TextAlign.Center)
              .backgroundColor(MODULE_COLOR.NEARBY)
              .borderRadius(BORDER_RADIUS.SM)
            Text('附近推荐')
              .fontSize(FONT_SIZE.XL).fontWeight(FontWeight.Bold).fontColor(MODULE_COLOR.NEARBY)
              .layoutWeight(1)
            Text('刷新')
              .fontSize(FONT_SIZE.SM).fontColor(MODULE_COLOR.NEARBY)
              .id('home-recommend-refresh')
              .onClick(() => { this.refreshRecommended() })
          }
          .width('100%')
          .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.MD, bottom: SPACING.SM })
          .backgroundColor(MODULE_BG.NEARBY)

          if (!this.loggedIn) {
            Text('登录后查看平台推荐商户')
              .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT)
              .width('100%').textAlign(TextAlign.Center)
              .padding({ top: SPACING.SM, bottom: SPACING.SM })
          } else if (!this.hasRecommendLocation()) {
            Row({ space: SPACING.SM }) {
              Text('定位后可看到附近推荐商户')
                .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT).layoutWeight(1)
              Button('去定位').height(32).fontSize(FONT_SIZE.SM)
                .id('home-recommend-location')
                .onClick(() => { router.pushUrl({ url: 'pages/LocationPage' }) })
            }
            .width('100%')
            .padding({ left: SPACING.LG, right: SPACING.LG, bottom: SPACING.SM })
          } else if (this.recommendedLoading) {
            Text('正在查询附近推荐商户…')
              .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT)
              .width('100%').textAlign(TextAlign.Center)
              .padding({ top: SPACING.SM, bottom: SPACING.SM })
          } else if (this.recommendedStores.length === 0) {
            Text('暂无附近推荐商户，平台会按距离和营业状态持续更新')
              .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT)
              .width('100%').textAlign(TextAlign.Center)
              .padding({ top: SPACING.SM, bottom: SPACING.SM })
          } else {
            List({ space: SPACING.SM }) {
              ForEach(this.recommendedStores, (store: StoreItem) => {
                ListItem() {
                  RecommendedStoreCardHost({
                    store: store,
                    onStoreClick: (target: StoreItem) => { this.onStoreClick(target) }
                  })
                }
              }, (store: StoreItem) => `recommend-${store.id}`)
            }
            .id('home-recommend-list')
            // 高度按内容自适应（推荐是首页的一段，不是整屏列表），靠外层 Scroll 滚动
            .width('100%')
            .height(this.recommendedStores.length * 108)
            .scrollBar(BarState.Off)
            .padding({ left: SPACING.LG, right: SPACING.LG })
          }

          // 特价团购标题
          Row({ space: SPACING.SM }) {
            Text('🏷️')
              .fontSize(FONT_SIZE.MD)
              .width(28).height(28).textAlign(TextAlign.Center)
              .backgroundColor(MODULE_COLOR.SPECIAL)
              .borderRadius(BORDER_RADIUS.SM)
            Text('特价团购')
              .fontSize(FONT_SIZE.XL).fontWeight(FontWeight.Bold).fontColor(MODULE_COLOR.SPECIAL)
            Blank()
            Text('查看全部 >')
              .fontSize(FONT_SIZE.SM).fontColor(MODULE_COLOR.SPECIAL)
          }
          .width('100%')
          .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.MD, bottom: SPACING.SM })
          .backgroundColor(MODULE_BG.SPECIAL)
          .onClick(() => {
            this.openProductList('special', 0, '特价团购')
          })

          // 特价商品列表由后端数据库返回
          if (!this.loggedIn) {
            EmptyState({ iconGlyph: $r('sys.symbol.lock'), title: '登录后查看特价团购', description: '商家上新的特价商品会展示在这里' })
          } else if (this.isRefreshing && this.specialGoods.length === 0) {
            EmptyState({ icon: '⏳', title: '正在加载特价商品', description: '请稍候，正在读取最新团购数据' })
          } else if (this.specialGoods.length === 0) {
            EmptyState({ icon: '🛍️', title: '暂无特价商品', description: '商家上新特价商品后会展示在这里' })
          } else {
            Column({ space: SPACING.SM }) {
              ForEach(this.specialGoods, (item: SpecialGoodsItem) => {
                this.SpecialGoodsCard(item)
              }, (item: SpecialGoodsItem) => `${item.goods.storeId}-${item.goods.id}`)
            }
            .width('100%')
            .padding({ left: SPACING.LG, right: SPACING.LG, bottom: SPACING.LG })
          }
          }
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
      }
      .layoutWeight(1)
      .pullToRefresh(true)
      .onRefreshing(() => { this.refreshHomeData() })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(COLORS.BG_PRIMARY)
    }
    .width('100%')
    .height('100%')
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
  SeckillCard(item: SeckillItem) {
    Column({ space: SPACING.XS }) {
      Text(item.goodsName)
        .fontSize(FONT_SIZE.MD).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      Row({ space: SPACING.XS }) {
        Text(`¥${item.price.toFixed(2)}`)
          .fontSize(FONT_SIZE.LG).fontWeight(FontWeight.Bold).fontColor(COLORS.PRICE_RED)
        if (item.originalPrice > item.price) {
          Text(`¥${item.originalPrice.toFixed(2)}`)
            .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT)
            .decoration({ type: TextDecorationType.LineThrough })
        }
      }
      .width('100%')

      // 抢购进度：已抢名额 / 总名额
      Row() {
        Text(`已抢 ${item.sold}/${item.quota}`)
          .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT)
        Blank()
        Text(`${this.seckillSoldPercent(item)}%`)
          .fontSize(FONT_SIZE.XS).fontColor(COLORS.PRICE_RED)
      }
      .width('100%')

      // 倒计时：单个页面级定时器驱动，归零后提示用户刷新（后端已结束的活动不再返回）
      Text(this.seckillRemainSeconds(item) > 0
        ? `距结束 ${this.seckillCountdown(item)}`
        : '本场已结束')
        .fontSize(FONT_SIZE.XS)
        .fontColor(COLORS.TEXT_WHITE)
        .backgroundColor(COLORS.PRICE_RED)
        .padding({ left: SPACING.XS, right: SPACING.XS, top: 1, bottom: 1 })
        .borderRadius(BORDER_RADIUS.SM)

      Text(item.storeName)
        .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .width(140)
    .padding(SPACING.MD)
    .backgroundColor(MODULE_BG.SECKILL)
    .borderRadius(BORDER_RADIUS.LG)
    .borderWidth(1)
    .borderColor(MODULE_COLOR.SECKILL)
    .alignItems(HorizontalAlign.Start)
    .onClick(() => { this.openSeckillStore(item) })
  }

  @Builder
  SpecialGoodsCard(item: SpecialGoodsItem) {
    Row({ space: SPACING.MD }) {
      Column() {
        Text(item.goods.name.substring(0, 1))
          .fontSize(FONT_SIZE.XL).fontWeight(FontWeight.Bold)
          .fontColor(accentFg(accentIndexFromText(item.goods.name)))
      }
      .width(82).height(82)
      .backgroundColor(accentBg(accentIndexFromText(item.goods.name)))
      .borderRadius(BORDER_RADIUS.MD)
      .justifyContent(FlexAlign.Center)

      Column({ space: SPACING.XS }) {
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
    .width('100%').padding(SPACING.MD).backgroundColor(MODULE_BG.SPECIAL)
    .borderRadius(BORDER_RADIUS.LG)
    .onClick(() => { this.openSpecialStore(item) })
  }

  @Builder
  StoreCard(store: StoreItem) {
    Row({ space: SPACING.MD }) {
      // 店铺图片占位
      if (store.image !== '') {
        Image(merchantImageSource(store.image))
          .alt(DEFAULT_MERCHANT_IMAGE)
          .width(80).height(80).objectFit(ImageFit.Cover).borderRadius(BORDER_RADIUS.MD)
      } else {
        Column() {
          Text(store.name.substring(0, 1))
            .fontSize(28).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_WHITE)
        }
        .width(80).height(80)
        .backgroundColor(accentFg(accentIndexFromText(store.name)))
        .borderRadius(BORDER_RADIUS.MD)
        .justifyContent(FlexAlign.Center)
      }

      Column({ space: SPACING.XS }) {
        Text(store.name)
          .fontSize(FONT_SIZE.LG).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })

        Row({ space: SPACING.SM }) {
          RatingStars({ rating: store.rating, fontSize: FONT_SIZE.SM, showNumber: true })
          Text(`月售${formatSales(store.monthlySales)}`)
            .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
          Text('|').fontSize(FONT_SIZE.SM).fontColor(COLORS.DIVIDER)
          Text(store.deliveryTime).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
        }

        Row({ space: SPACING.XS }) {
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

// ===================== 附近推荐卡片 =====================
// 原「发现」Tab 已并入首页：推荐数据与卡片渲染都留在首页，这里只保留共享的卡片构建器
@Component
struct RecommendedStoreCardHost {
  store: StoreItem = {
    id: 0, name: '', image: '', rating: 0, monthlySales: 0, deliveryFee: 0, minOrder: 0,
    deliveryTime: '', distance: '', tags: [], notice: '', categoryId: 0, ownerId: 0
  }
  onStoreClick: (store: StoreItem) => void = () => {}

  /**
   * 距离文案：只有服务端用「用户定位 + 门店坐标」真算出来的距离才显示「距你 X」，
   * 门店没坐标或未定位时是「未知距离」——不能沿用历史值假装很近。
   */
  private distanceText(): string {
    const distance: string = this.store.distance ?? ''
    if (distance === '' || distance === '未知距离') {
      return '距离未知'
    }
    return `距你 ${distance}`
  }

  build() {
    Row({ space: SPACING.MD }) {
      if (this.store.image !== '') {
        Image(merchantImageSource(this.store.image))
          .alt(DEFAULT_MERCHANT_IMAGE)
          .width(76).height(76).objectFit(ImageFit.Cover).borderRadius(BORDER_RADIUS.MD)
      } else {
        Column() {
          Text(this.store.name.substring(0, 1)).fontSize(28).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_WHITE)
        }
        .width(76).height(76)
        .backgroundColor(accentFg(accentIndexFromText(this.store.name)))
        .borderRadius(BORDER_RADIUS.MD)
        .justifyContent(FlexAlign.Center)
      }
      Column({ space: SPACING.XS }) {
        Row() {
          Text(this.store.name).fontSize(FONT_SIZE.LG).fontWeight(FontWeight.Bold)
            .fontColor(COLORS.TEXT_PRIMARY).layoutWeight(1).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text('平台推荐').fontSize(FONT_SIZE.XS).fontColor(COLORS.PRIMARY)
            .backgroundColor(COLORS.TAG_BG).padding({ left: 5, right: 5, top: 2, bottom: 2 })
            .borderRadius(BORDER_RADIUS.ROUND)
        }.width('100%')
        Row({ space: SPACING.SM }) {
          RatingStars({ rating: this.store.rating, fontSize: FONT_SIZE.SM, showNumber: true })
          Text(`月售${formatSales(this.store.monthlySales)}`).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
          Text(this.distanceText()).fontSize(FONT_SIZE.SM).fontColor(COLORS.PRIMARY)
        }
        Text(`${this.store.deliveryTime} · 配送¥${this.store.deliveryFee} · ${this.store.minOrder}元起送`)
          .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
        Text(this.store.notice).fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
    }
    .width('100%').padding(SPACING.MD).backgroundColor(COLORS.BG_WHITE)
    .borderRadius(BORDER_RADIUS.LG).onClick(() => { this.onStoreClick(this.store) })
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
  // 店铺照片（商户上传的相对地址），用户端详情页顶部展示
  @State storeImage: string = ''
  @State cartCount: number = 0
  @State cartTotal: number = 0
  // 商品行的「- 数量 +」取值依赖购物车，而 ForEach 的 key 用的是稳定的 goods.id：
  // ArkUI 按 key 复用列表项，键不变就不重建，于是点「+」后数字不更新/不显示。
  // 把本版本号拼进 ForEach key 强制重建（与购物车 cartRenderVersion 同一套路）。
  @State goodsRenderVersion: number = 0
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
  // 多规格菜品：由页面层打开选规格弹窗（弹窗需要 CustomDialogController，只能挂在页面组件上）
  onSelectSpecGoods: (goods: GoodsItem) => void = () => {}
  // 本店进行中的秒杀（商品卡片标出秒杀价）
  @State storeSeckills: SeckillItem[] = []
  // 本店生效中的营销活动与套餐（门店首页横幅/套餐区展示）
  @State storeActivities: MarketingActivity[] = []
  @State storeSetmeals: Setmeal[] = []

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
      this.storeImage = ''
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
      this.storeImage = store.image ?? ''
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
    this.refreshStoreInfo()
    this.refreshStoreSeckills()
    this.refreshStoreActivities()
    this.refreshStoreSetmeals()
  }

  // 本店进行中的限时秒杀：用于在商品卡片上标出秒杀价（下单时后端会自动按秒杀价结算）
  private async refreshStoreSeckills(): Promise<void> {
    if (!this.loggedIn || this.storeId <= 0) {
      this.storeSeckills = []
      return
    }
    const list: SeckillItem[] = await fetchSeckillsRemote(50)
    this.storeSeckills = list.filter((item: SeckillItem) => item.storeId === this.storeId)
  }

  /** 本店生效中的营销活动（折扣/新客立减/满赠），门店首页横幅展示。 */
  private async refreshStoreActivities(): Promise<void> {
    if (!this.loggedIn || this.storeId <= 0) {
      this.storeActivities = []
      return
    }
    this.storeActivities = await fetchStoreActivitiesApi(this.storeId)
  }

  /** 本店套餐（组合购），门店套餐区展示。 */
  private async refreshStoreSetmeals(): Promise<void> {
    if (!this.loggedIn || this.storeId <= 0) {
      this.storeSetmeals = []
      return
    }
    this.storeSetmeals = await fetchStoreSetmealsApi(this.storeId)
  }

  /** 预订套餐：直接下单（items 为空 + setmeals），成功后提示去订单详情支付。 */
  private async buySetmeal(sm: Setmeal): Promise<void> {
    const addr: Address | null | undefined = AppStorage.get<Address | null>('currentAddress')
    if (addr === null || addr === undefined || addr.id <= 0) {
      promptAction.showToast({ message: '请先选择收货地址', duration: 1800 })
      return
    }
    const setmeals: SetmealOrder[] = [ { setmealId: sm.id, quantity: 1 } ]
    const key: string = `sm-${Date.now()}-${Math.floor(Math.random() * 100000)}`
    const order: Order | null = await createOrderRemote(this.storeId, [], addr.id, 0, '', [], '', key, 'DELIVERY', setmeals)
    if (order === null) {
      const err: string = getLastRemoteErrorMessage()
      promptAction.showToast({ message: err === '' ? '套餐下单失败，请稍后重试' : err, duration: 2200 })
      return
    }
    promptAction.showToast({ message: '套餐已下单，请在订单详情完成支付', duration: 2000 })
  }

  /** 菜品当前秒杀价（无秒杀返回 0）。 */
  private getSeckillPrice(goodsId: number): number {
    const matched: SeckillItem[] = this.storeSeckills.filter((item: SeckillItem) => item.goodsId === goodsId)
    return matched.length > 0 ? matched[0].price : 0
  }

  /** 卡片展示价：限时秒杀优先，其次规格最低价/菜品价。 */
  private getDisplayPrice(goods: GoodsItem): number {
    const seckillPrice: number = this.getSeckillPrice(goods.id)
    return seckillPrice > 0 ? seckillPrice : this.getMinSpecPrice(goods)
  }

  /** 卡片划线原价：秒杀时划掉菜品原价，否则划掉商品原价。 */
  private getStruckPrice(goods: GoodsItem): number {
    if (this.getSeckillPrice(goods.id) > 0) {
      return goods.price
    }
    return goods.originalPrice ?? 0
  }

  // 拉取后端权威店铺信息（评分/公告/配送费/起送价/营业时间），避免依赖列表缓存导致数据陈旧
  private async refreshStoreInfo(): Promise<void> {
    if (!this.loggedIn || this.storeId <= 0) {
      return
    }
    const store: StoreItem | null = await fetchStoreDetailApi(this.storeId)
    if (store !== null && store !== undefined) {
      this.storeName = store.name
      this.storeRating = store.rating
      this.storeMonthlySales = store.monthlySales
      this.storeDeliveryFee = store.deliveryFee
      this.storeDeliveryTime = store.deliveryTime
      // 距离不在这里覆盖：详情接口不带用户坐标（算不出真实距离），
      // 覆盖会把列表接口按定位算好的「距你 X km」变成「未知距离」
      this.storeMinOrder = store.minOrder
      this.storeTags = store.tags
      this.storeNotice = store.notice
      this.storeImage = store.image ?? ''
    }
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
    // 多规格购物车行以规格价结算（CartItem.price），无规格商品回退商品价
    this.cartTotal = sc.reduce((s: number, i: CartItem) => {
      const unitPrice: number = i.price ?? i.goods.price
      return s + unitPrice * i.quantity
    }, 0)
    // 购物车已变化：递增渲染版本，让商品行的数量控件重建
    this.goodsRenderVersion += 1
  }

  private enqueueCartOperation(operation: () => Promise<void>): void {
    this.cartOperationQueue = this.cartOperationQueue.then(operation).catch(() => {
      // Keep later cart clicks usable when one request fails.
    })
  }

  private addGoodsToCart(goods: GoodsItem): void {
    const specs: GoodsSpec[] = goods.specs ?? []
    if (specs.length > 0) {
      // 多规格菜品必须选规格后加购，直接加购会被后端拒绝（400「请先选择规格」）
      this.onSelectSpecGoods(goods)
      return
    }
    this.changeGoodsQuantity(goods, 1)
  }

  // 该菜品是否是多规格菜品（specs 非空）
  private hasSpecs(goods: GoodsItem): boolean {
    const specs: GoodsSpec[] = goods.specs ?? []
    return specs.length > 0
  }

  // 规格数量，用于商品卡片上的「N 种规格」标签
  private getSpecCount(goods: GoodsItem): number {
    const specs: GoodsSpec[] = goods.specs ?? []
    return specs.length
  }

  // 规格最低价（后端 price 即为最低规格价，这里按 specs 再取一次最小值做兜底）
  private getMinSpecPrice(goods: GoodsItem): number {
    const specs: GoodsSpec[] = goods.specs ?? []
    if (specs.length === 0) {
      return goods.price
    }
    let minPrice: number = specs[0].price
    specs.forEach((spec: GoodsSpec) => {
      if (spec.price < minPrice) {
        minPrice = spec.price
      }
    })
    return minPrice
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
        // 店铺照片：方便用户确认门店（未上传时用默认占位图）
        Image(merchantImageSource(this.storeImage))
          .alt(DEFAULT_MERCHANT_IMAGE)
          .width('100%').height(160).objectFit(ImageFit.Cover)
          .borderRadius(BORDER_RADIUS.MD)
        Row() {
          Text(this.storeName)
            .fontSize(FONT_SIZE.XL).fontWeight(FontWeight.Bold).fontColor(MODULE_COLOR.MERCHANT)
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
        Row({ space: SPACING.MD }) {
          Text(`${this.storeRating}分`).fontSize(FONT_SIZE.MD).fontColor(COLORS.PRIMARY).fontWeight(FontWeight.Bold)
          Text(`月售${formatSales(this.storeMonthlySales)}`).fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_SECONDARY)
          Text(`配送${this.storeDeliveryTime}`).fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_SECONDARY)
        }
        Row({ space: SPACING.MD }) {
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
        Row({ space: SPACING.XS }) {
          Text('公告：').fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT)
          Text(this.storeNotice).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        }
      }
      .width('100%')
      .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.MD, bottom: SPACING.MD })
      .backgroundColor(MODULE_BG.MERCHANT).margin({ top: SPACING.SM })

      if (this.storeActivities.length > 0) {
        Column({ space: SPACING.XS }) {
          Text('店铺活动').fontSize(FONT_SIZE.MD).fontWeight(FontWeight.Bold).fontColor(MODULE_COLOR.MERCHANT).width('100%')
          Row({ space: SPACING.SM }) {
            ForEach(this.storeActivities, (act: MarketingActivity) => {
              Text(act.title)
                .fontSize(FONT_SIZE.XS).fontColor(COLORS.PRIMARY)
                .backgroundColor(COLORS.TAG_BG)
                .padding({ left: SPACING.SM, right: SPACING.SM, top: 4, bottom: 4 }).borderRadius(BORDER_RADIUS.SM)
            }, (act: MarketingActivity) => act.id.toString())
          }
          .width('100%')
        }
        .width('100%').padding(SPACING.LG).backgroundColor(MODULE_BG.MERCHANT).margin({ top: SPACING.SM })
      }

      if (this.storeSetmeals.length > 0) {
        Column({ space: SPACING.SM }) {
          Text('超值套餐').fontSize(FONT_SIZE.MD).fontWeight(FontWeight.Bold).fontColor(MODULE_COLOR.SPECIAL).width('100%')
          ForEach(this.storeSetmeals, (sm: Setmeal, index: number) => {
            Column({ space: SPACING.XS }) {
              Row() {
                Text(sm.name).fontSize(FONT_SIZE.MD).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY).layoutWeight(1).maxLines(1)
                Text(`¥${sm.price.toFixed(2)}`).fontSize(FONT_SIZE.LG).fontWeight(FontWeight.Bold).fontColor(COLORS.PRICE_RED)
                  .onClick(() => { this.buySetmeal(sm) })
              }.width('100%')
              Text(sm.items.map((it: SetmealItem) => it.goodsName).join(' + ')).fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_SECONDARY).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              if (sm.originalPrice > sm.price) {
                Text(`原价 ¥${sm.originalPrice.toFixed(2)}`).fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT).decoration({ type: TextDecorationType.LineThrough })
              }
            }
            .width('100%').padding(SPACING.MD).backgroundColor(accentBg(index)).borderRadius(BORDER_RADIUS.MD)
          }, (sm: Setmeal) => sm.id.toString())
        }
        .width('100%').padding(SPACING.LG).backgroundColor(MODULE_BG.SPECIAL).margin({ top: SPACING.SM })
      }

      // 分类Tab
      Scroll() {
        Row({ space: SPACING.SM }) {
          ForEach(this.goodsCats, (catName: string, index: number) => {
            Text(catName)
              .fontSize(FONT_SIZE.MD)
              .fontColor(this.currentCat === catName ? COLORS.TEXT_WHITE : accentFg(index))
              .backgroundColor(this.currentCat === catName ? accentFg(index) : accentBg(index))
              .padding({ left: 12, right: 12, top: 4, bottom: 4 })
              .borderRadius(BORDER_RADIUS.ROUND)
              .height(28)
              .id(`goods-cat-${catName}`)
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
        // 用 List 承载：Scroll 在内容不足一屏时会把内容垂直居中，导致第一条数据不在顶部
        List() {
          if (this.goodsLoading) {
            ListItem() {
              Text('正在加载商品…')
                .fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_HINT)
                .width('100%').textAlign(TextAlign.Center)
                .padding({ top: SPACING.XXL, bottom: SPACING.XXL })
            }
          } else if (this.filteredGoodsList.length === 0) {
            ListItem() {
              Column({ space: SPACING.SM }) {
                Text('暂无商品')
                  .fontSize(FONT_SIZE.LG).fontColor(COLORS.TEXT_HINT)
                Text('当前分类暂时没有可售商品')
                  .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT)
              }
              .width('100%').padding({ top: SPACING.XXL, bottom: SPACING.XXL })
              .alignItems(HorizontalAlign.Center)
            }
          } else {
            // 当前分类命中的商品数：id 里带数量，供设备端用例断言「切分类确实换了列表」
            ListItem() {
              Text(`共 ${this.filteredGoodsList.length} 件商品`)
                .id(`goods-count-${this.filteredGoodsList.length}`)
                .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT)
                .width('100%')
                .padding({ top: SPACING.SM, bottom: SPACING.SM })
            }
            ForEach(this.filteredGoodsList, (goods: GoodsItem) => {
            ListItem() {
            Row({ space: SPACING.MD }) {
                // 商品图片：商户上传图拼 API 基址，无图/加载失败回退默认占位图
                Image(merchantImageSource(goods.image))
                  .alt(DEFAULT_MERCHANT_IMAGE)
                  .width(90).height(90).objectFit(ImageFit.Cover).borderRadius(BORDER_RADIUS.MD)
                  .backgroundColor(COLORS.BG_PRIMARY)

                // 商品信息
                Column({ space: SPACING.XS }) {
                  Row({ space: SPACING.XS }) {
                    Text(goods.name)
                      .fontSize(FONT_SIZE.LG).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
                      .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    if (goods.tag) {
                      Text(goods.tag)
                        .fontSize(FONT_SIZE.XS).fontColor(COLORS.PRICE_RED)
                        .borderWidth(1).borderColor(COLORS.PRICE_RED)
                        .padding({ left: 2, right: 2, top: 1, bottom: 1 }).borderRadius(BORDER_RADIUS.SM)
                    }
                    if (this.getSpecCount(goods) > 1) {
                      Text(`${this.getSpecCount(goods)} 种规格`)
                        .fontSize(FONT_SIZE.XS).fontColor(COLORS.TAG_TEXT)
                        .backgroundColor(COLORS.TAG_BG)
                        .padding({ left: SPACING.XS, right: SPACING.XS, top: 1, bottom: 1 })
                        .borderRadius(BORDER_RADIUS.SM)
                    }
                    // 限时秒杀：下单时后端自动按秒杀价结算
                    if (this.getSeckillPrice(goods.id) > 0) {
                      Text('⚡限时秒杀')
                        .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_WHITE)
                        .backgroundColor(COLORS.PRICE_RED)
                        .padding({ left: SPACING.XS, right: SPACING.XS, top: 1, bottom: 1 })
                        .borderRadius(BORDER_RADIUS.SM)
                    }
                  }
                  Text(goods.description)
                    .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT)
                    .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                  this.GoodsReviewSummary(goods)
                  Row({ space: SPACING.XS }) {
                    Text(`月售${formatSales(goods.sales)}`).fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT)
                    Text(`好评${goods.rating}%`).fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT)
                  }
                  Row() {
                    this.GoodsPriceArea(goods)
                    if (this.getStruckPrice(goods) > 0 && this.getStruckPrice(goods) > this.getDisplayPrice(goods)) {
                      Text(`¥${this.getStruckPrice(goods)}`).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT)
                        .decoration({ type: TextDecorationType.LineThrough }).margin({ left: 4 })
                    }
                    Blank()
                    this.AddMinusButton(goods)
                  }.width('100%')
                }
                .layoutWeight(1).alignItems(HorizontalAlign.Start)
              }
              .width('100%').padding(SPACING.MD)
              .backgroundColor(accentBg(accentIndexFromText(goods.name)))
              .borderRadius(BORDER_RADIUS.MD)
              }
            }, (item: GoodsItem) => `${this.goodsRenderVersion}-${item.id}`)
          }

          // 用户评价列表区域
          ListItem() {
            this.ReviewsSection()
          }
        }
        .width('100%')
        .scrollBar(BarState.Off)
        .layoutWeight(1)
        .padding({ bottom: SPACING.XL })

        // 购物车栏
        this.CartBar()
      }
      .layoutWeight(1)
    }
    .width('100%').layoutWeight(1)
  }

  // 商品卡片价格：限时秒杀价优先，多规格菜品显示「¥最低规格价 起」
  @Builder
  GoodsPriceArea(goods: GoodsItem) {
    Row({ space: 2 }) {
      Text('¥').fontSize(FONT_SIZE.SM).fontColor(COLORS.PRICE_RED).fontWeight(FontWeight.Bold)
      Text(this.getDisplayPrice(goods).toString())
        .fontSize(FONT_SIZE.XL).fontColor(COLORS.PRICE_RED).fontWeight(FontWeight.Bold)
      if (this.hasSpecs(goods) && this.getSeckillPrice(goods.id) <= 0) {
        Text('起').fontSize(FONT_SIZE.SM).fontColor(COLORS.PRICE_RED)
      }
    }
  }

  @Builder
  AddMinusButton(goods: GoodsItem) {
    Row({ space: 0 }) {
      if (this.hasSpecs(goods)) {
        // 多规格菜品：规格价与规格库存各不相同，统一走选规格弹窗（后端要求 specId）
        Text('选规格')
          .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_WHITE)
          .backgroundColor(COLORS.PRIMARY)
          .borderRadius(BORDER_RADIUS.ROUND)
          .padding({ left: SPACING.SM, right: SPACING.SM, top: SPACING.XS, bottom: SPACING.XS })
          .onClick(() => {
            this.addGoodsToCart(goods)
          })
      } else {
        if (this.getQty(goods.id) > 0) {
          Text('-').id(`goods-minus-${goods.id}`).width(24).height(24).fontSize(16).fontColor(COLORS.TEXT_WHITE)
            .backgroundColor(COLORS.PRIMARY).borderRadius(BORDER_RADIUS.CIRCLE)
            .textAlign(TextAlign.Center).onClick(() => {
              this.changeGoodsQuantity(goods, -1)
            })
          Text(this.getQty(goods.id).toString()).id(`goods-qty-${goods.id}`)
            .width(28).height(24).fontSize(FONT_SIZE.MD)
            .fontColor(COLORS.TEXT_PRIMARY).textAlign(TextAlign.Center)
        }
        Text('+').id(`goods-plus-${goods.id}`).width(24).height(24).fontSize(16).fontColor(COLORS.TEXT_WHITE)
          .backgroundColor(COLORS.PRIMARY).borderRadius(BORDER_RADIUS.CIRCLE)
          .textAlign(TextAlign.Center).onClick(() => {
            this.addGoodsToCart(goods)
          })
      }
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
        .fontColor(this.hasReviewedGoods(goods.id) ? COLORS.TEXT_SECONDARY : (this.canReviewGoods(goods.id) ? COLORS.TEXT_WHITE : COLORS.TEXT_SECONDARY))
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
          .backgroundColor(MODULE_COLOR.CART).borderRadius(BORDER_RADIUS.ROUND)
          .textAlign(TextAlign.Center)
        if (this.cartCount > 0) {
          Text(this.cartCount.toString())
            .fontSize(10).fontColor(COLORS.TEXT_WHITE).backgroundColor(COLORS.PRICE_RED)
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
        .backgroundColor(this.cartCount > 0 ? MODULE_COLOR.CART : COLORS.TEXT_SECONDARY)
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
        .fontSize(FONT_SIZE.LG).fontWeight(FontWeight.Bold).fontColor(MODULE_COLOR.REVIEW)
        .width('100%').padding(SPACING.SM)
        .backgroundColor(MODULE_BG.REVIEW)
        .borderRadius(BORDER_RADIUS.MD)

      if (this.storeReviews.length === 0) {
        Text('暂无评价')
          .fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_HINT)
          .width('100%').textAlign(TextAlign.Center)
          .padding({ top: SPACING.LG, bottom: SPACING.LG })
      } else {
        ForEach(this.storeReviews.slice(0, 3), (review: Review) => {
          Column({ space: SPACING.XS }) {
            Row({ space: SPACING.SM }) {
              Text(review.anonymous === 1 ? '匿名用户' : review.username)
                .fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_PRIMARY).fontWeight(FontWeight.Bold)
              Text(this.getStars(review.rating))
                .fontSize(FONT_SIZE.SM).fontColor(COLORS.WARNING)
            }
            .width('100%')
            Text(review.content)
              .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
              .width('100%')
            // 图文评价：用户上传的图片（点击可全屏查看）
            if (this.hasReviewImages(review)) {
              Row({ space: SPACING.XS }) {
                ForEach(review.images.slice(0, 3), (imageUrl: string, index: number) => {
                  Image(imageUrl)
                    .width(72)
                    .height(72)
                    .borderRadius(BORDER_RADIUS.SM)
                    .objectFit(ImageFit.Cover)
                    .id(`store-review-image-${index}`)
                    .onClick(() => { this.previewReviewImage(imageUrl) })
                }, (imageUrl: string, index: number) => `${index}_${imageUrl}`)
              }
              .width('100%')
            }
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
            if (review.reply !== '') {
              Column({ space: SPACING.XS }) {
                Text('商家回复')
                  .fontSize(FONT_SIZE.XS).fontColor(COLORS.PRIMARY).fontWeight(FontWeight.Bold)
                  .width('100%')
                Text(review.reply)
                  .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
                  .width('100%')
              }
              .width('100%')
              .padding(SPACING.MD)
              .backgroundColor(COLORS.BG_PRIMARY)
              .borderRadius(BORDER_RADIUS.SM)
            }
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

  /** 该评价是否带图（历史评价可能没有 images 字段）。 */
  private hasReviewImages(review: Review): boolean {
    const images: string[] = review.images
    return Array.isArray(images) && images.length > 0
  }

  /** 点击评价图片：进入全屏预览页。 */
  private previewReviewImage(imageUrl: string): void {
    // 注意：日志里不要写「地址=」，AppLogger 的脱敏规则会把「地址=xxx」整段替换成 [REDACTED_ADDRESS]
    logInfo('Review', `点击评价图片，进入预览页（有图片=${imageUrl !== ''}）`)
    if (imageUrl === '') {
      promptAction.showToast({ message: '图片地址为空，无法预览', duration: 2000 })
      return
    }
    AppStorage.setOrCreate<string>('reviewPreviewUrl', imageUrl)
    router.pushUrl({ url: 'pages/ReviewImagePage' })
  }

  private getGoodsName(goodsId: number): string {
    const goods: GoodsItem | undefined = this.goodsList.find((item: GoodsItem) => item.id === goodsId)
    return goods === undefined ? '店内商品' : goods.name
  }

  getQty(goodsId: number): number {
    // 必须读被观察的 this.cartItems，而不是 AppStorage.get：
    // 后者绕过状态观察，行内不会建立依赖，数量变化时该行不会刷新。
    const currentCart: CartItem[] = this.cartItems || []
    const item: CartItem | undefined = currentCart.find((cartItem: CartItem) =>
      cartItem.goods.id === goodsId && cartItem.storeId === this.storeId)
    return item ? item.quantity : 0
  }
}

// ===================== 个人中心 =====================
@Component
struct ProfileMainPage {
  @State showRechargeDialog: boolean = false
  @State showChangePwd: boolean = false
  @State rechargeAmount: string = ''
  @State recharging: boolean = false
  @Prop @Watch('onRefreshTokenChange') refreshToken: number = 0
  @StorageLink('isLoggedIn') loggedIn: boolean = false
  @State user: User = {
    id: 0, username: '未登录', avatar: '', phone: '', password: '', role: UserRole.CUSTOMER,
    balance: 0, coupons: [], orders: [], storeIds: []
  }
  // 资产卡片使用页面自身的可观察文本，避免 Builder 继续复用充值前的余额快照。
  @State balanceDisplay: string = '0.00'
  // 余额显示只由当前页面的接口结果驱动，避免 StorageLink 旧快照回调覆盖新余额。
  @State balance: number = 0
  @State isRefreshing: boolean = false
  @State refreshStatus: string = '余额数据来自数据库'
  onNavigateLogin: () => void = () => {}

  async aboutToAppear(): Promise<void> {
    this.loadLocalUser()
    await this.refreshFromDatabase()
  }

  async onRefreshTokenChange(): Promise<void> {
    this.loadLocalUser()
    await this.refreshFromDatabase()
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
    const normalizedBalance: number = Number.isFinite(nextUser.balance) ? nextUser.balance : 0
    this.user = nextUser
    // 直接使用接口返回值更新显示文本，避免 StorageLink 写入后的即时回读仍是旧快照。
    this.balanceDisplay = normalizedBalance.toFixed(2)
    this.balance = normalizedBalance
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
    promptAction.showToast({ message: `\u5145\u503c\u6210\u529f\uff0c\u5f53\u524d\u4f59\u989d ¥${confirmedUser.balance.toFixed(2)}`, duration: 2000 })
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
                .fontSize(24).fontColor(COLORS.TEXT_WHITE).fontWeight(FontWeight.Bold)
            }
            .width(60).height(60).backgroundColor('rgba(255,255,255,0.3)')
            .borderRadius(BORDER_RADIUS.CIRCLE).justifyContent(FlexAlign.Center)
            Column({ space: SPACING.XS }) {
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
                .fontColor(COLORS.TEXT_WHITE).backgroundColor('rgba(255,255,255,0.3)')
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
          // 余额直接在 Builder 内读取页面状态，避免普通 Builder 参数保留充值前的快照。
          this.BalanceAssetItem()
          this.AssetItem((this.user.coupons || []).filter(c => !c.used).length.toString(), '优惠券', () => { router.pushUrl({ url: 'pages/CouponCenterPage' }) })
          this.AssetItem((this.user.orders || []).length.toString(), '订单', () => {
            AppStorage.setOrCreate<number>('orderFilterStatus', -1)
            if (!this.loggedIn) {
              promptAction.showToast({ message: '请先登录后查看订单', duration: 1500 })
              this.onNavigateLogin()
              return
            }
            router.pushUrl({ url: 'pages/OrderListPage' })
          })
        }
        .width('100%').padding(SPACING.LG)
        .margin({ top: SPACING.SM })
        .backgroundColor(COLORS.BG_WHITE).borderRadius(BORDER_RADIUS.LG)

        // Row() {
        //   Button(this.isRefreshing ? '\u540c\u6b65\u4e2d\u2026' : '\u7acb\u5373\u5237\u65b0')
        //     .height(34).fontSize(FONT_SIZE.SM)
        //     .fontColor(COLORS.PRIMARY).backgroundColor(COLORS.WARM_BG)
        //     .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
        //     .enabled(!this.isRefreshing)
        //     .onClick(() => { this.refreshProfileData() })
        // }
        // .width('100%').justifyContent(FlexAlign.End)
        // .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.SM, bottom: SPACING.SM })
        // .margin({ top: SPACING.SM })
        // .backgroundColor(COLORS.BG_WHITE).borderRadius(BORDER_RADIUS.LG)

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
          this.ProfileMenuRow('❤️', '我的收藏', () => { router.pushUrl({ url: 'pages/FavoriteListPage' }) })
          this.ProfileMenuRow('📞', '联系客服', () => { router.pushUrl({ url: 'pages/ContactCustomerServicePage' }) })
          this.ProfileMenuRow('⚙️', '设置', () => { router.pushUrl({ url: 'pages/SettingsPage' }) })
          this.ProfileMenuRow('🔑', '修改密码', () => { this.showChangePwd = true })
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
            SymbolGlyph($r('sys.symbol.store')).fontSize(FONT_SIZE.MD)
              Text(' 商户管理入口')
              .fontSize(FONT_SIZE.MD).fontWeight(FontWeight.Bold)
              .fontColor(COLORS.PRIMARY)
              .width('100%')
              .padding({ left: SPACING.LG, top: SPACING.SM, bottom: SPACING.SM })
            this.ProfileMenuRow('📋', '店铺管理', () => { router.pushUrl({ url: 'pages/MerchantCenterPage' }) }, 'profile-merchant-center')
            this.ProfileMenuRow('📊', '订单管理', () => { router.pushUrl({ url: 'pages/MerchantOrdersPage' }) }, 'profile-merchant-orders')
            this.ProfileMenuRow('💰', '收入统计', () => { router.pushUrl({ url: 'pages/MerchantStatsPage' }) }, 'profile-merchant-stats')
          }
          .width('100%')
          .padding({ top: SPACING.SM })
          .margin({ top: SPACING.SM })
          .backgroundColor(COLORS.WARM_BG)
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
          .backgroundColor(COLORS.WARM_BG)
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
      if (this.showChangePwd) {
        ChangePasswordDialog({
          onSuccess: () => { this.showChangePwd = false; logout(); router.replaceUrl({ url: 'pages/Index' }) },
          onClose: () => { this.showChangePwd = false }
        })
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
            .backgroundColor(COLORS.PRIMARY).fontColor(COLORS.TEXT_WHITE)
            .onClick(() => { this.submitRecharge() })
        }.width('100%')
      }
      .width('86%').padding(SPACING.XL)
      .backgroundColor(COLORS.BG_WHITE).borderRadius(BORDER_RADIUS.LG)
    }
    .width('100%').height('100%')
    .backgroundColor(COLORS.OVERLAY)
    .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
  }

  @Builder
  BalanceAssetItem() {
    Column({ space: SPACING.XS }) {
      Text(this.balanceDisplay)
        .fontSize(FONT_SIZE.XXL).fontWeight(FontWeight.Bold).fontColor(COLORS.PRIMARY)
      Text('余额').fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
    }
    .layoutWeight(1).alignItems(HorizontalAlign.Center)
    .onClick(() => { this.openBalancePage() })
  }

  /** 余额点击进钱包页（余额 + 已绑定银行卡）；未登录先引导登录。 */
  private openBalancePage(): void {
    if (!this.loggedIn) {
      promptAction.showToast({ message: '请先登录后查看钱包', duration: 1500 })
      this.onNavigateLogin()
      return
    }
    router.pushUrl({ url: 'pages/BalancePage' })
  }

  @Builder
  AssetItem(value: string, label: string, action: () => void) {
    Column({ space: SPACING.XS }) {
      Text(value).fontSize(FONT_SIZE.XXL).fontWeight(FontWeight.Bold)
        .fontColor(accentFg(accentIndexFromText(label)))
      Text(label).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
    }
    .layoutWeight(1).alignItems(HorizontalAlign.Center)
    .onClick(() => { action() })
  }

  @Builder
  ProfileOrderEntry(icon: string, title: string, status: number) {
    Column({ space: SPACING.XS }) {
      Text(icon).fontSize(24)
        .width(44).height(44).textAlign(TextAlign.Center)
        .backgroundColor(accentBg(accentIndexFromText(title)))
        .borderRadius(BORDER_RADIUS.CIRCLE)
      Text(title).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
    }
    .onClick(() => {
      AppStorage.setOrCreate<number>('orderFilterStatus', status)
      if (!this.loggedIn) {
        promptAction.showToast({ message: '请先登录后查看订单', duration: 1500 })
        this.onNavigateLogin()
        return
      }
      router.pushUrl({ url: 'pages/OrderListPage' })
    })
  }

  @Builder
  ProfileMenuRow(icon: string, title: string, action: () => void, rowId: string = '') {
    Row({ space: SPACING.MD }) {
      Text(icon).fontSize(18)
        .width(36).height(36).textAlign(TextAlign.Center)
        .backgroundColor(accentBg(accentIndexFromText(title)))
        .borderRadius(BORDER_RADIUS.MD)
      Text(title).fontSize(FONT_SIZE.LG).fontColor(COLORS.TEXT_PRIMARY).layoutWeight(1)
      Text('›').fontSize(20).fontColor(COLORS.TEXT_HINT)
    }
    .width('100%').height(52)
    .padding({ left: SPACING.LG, right: SPACING.LG })
    .id(rowId)
    .onClick(() => { action() })
  }
}


/**
 * 主页面 - 简单外卖App
 * 包含：搜索栏、分类导航、店铺列表、店铺详情、购物车、订单列表、个人中心、底部Tab导航
 */
import { StoreItem, CartItem, Order, User, UserRole, Address, Coupon, Favorite, createEmptyUser } from '../model/Models'
import { initAppStorage, isLoggedIn, logout, getAllStoresList, syncAddressesRemote, syncCartRemote, syncCategoriesFromServer, syncStoresFromServer } from '../service/AppStorageManager'

import { LoginPage } from './LoginPage'

import { AssistantPage } from './AssistantPage'
import { CartPage } from './CartPage'
import { AdaptiveTabBar } from '../components/AdaptiveTabBar'

import { COLORS, SPACING, FONT_SIZE } from '../common/Constants'

import { ConfirmDialog } from '../components/ConfirmDialog'

import { routerCompat as router } from '../common/UiNavigation'
import { logInfo } from '../service/AppLogger'

import { HomeTheme } from '../common/theme/HomeTheme'

import { AppMotion } from '../common/theme/AppMotion'

import { HomePage } from '../components/home/HomePage'
import { ProfileMainPage } from '../components/profile/ProfileMainPage'

@Entry
@Component
struct Index {
  @StorageLink('appReduceMotion') reduceMotion: boolean = false
  @State currentTab: number = 0
  @State selectedTab: number = 0
  @State profileRefreshToken: number = 0
  private lastHomeRefreshAt: number = 0
  @StorageLink('isLoggedIn') @Watch('onLoginStateChange') loggedIn: boolean = false
  @State showLogin: boolean = true
  @State showLocationLoginConfirm: boolean = false
  // 管理端跳转占位：管理端不渲染主页（定位/购物车/订单等 C 端功能），直接进入平台管理页
  @State adminRedirecting: boolean = false
  @State pageVisible: boolean = true
  @State systemBottomInset: number = 0
  private safeViewportHeight: number = 0
  private contentViewportHeight: number = 0
  private tabsController: TabsController = new TabsController()

  private updateSystemBottomInset(): void {
    if (this.safeViewportHeight <= 0 || this.contentViewportHeight <= 0) { return }
    this.systemBottomInset = Math.max(0, this.contentViewportHeight - this.safeViewportHeight)
  }

  pageTransition() {
    PageTransitionEnter(AppMotion.pageEnter(RouteType.Push))
      .translate({ x: AppMotion.distance(AppMotion.PAGE_OFFSET) }).opacity(0)
    PageTransitionExit(AppMotion.pageExit(RouteType.Push))
      .translate({ x: -AppMotion.distance(AppMotion.RETURN_OFFSET) }).opacity(0)
    PageTransitionEnter(AppMotion.pageEnter(RouteType.Pop))
      .translate({ x: -AppMotion.distance(AppMotion.RETURN_OFFSET) }).opacity(0)
    PageTransitionExit(AppMotion.pageExit(RouteType.Pop))
      .translate({ x: AppMotion.distance(AppMotion.PAGE_OFFSET) }).opacity(0)
  }

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
    this.pageVisible = true
    logInfo('Page', '首页 Index onPageShow')
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
      const now: number = Date.now()
      if (now - this.lastHomeRefreshAt < 5000) {
        return
      }
      this.lastHomeRefreshAt = now
      // 返回首页时只刷新一次服务端权威数据，避免短时间内重复请求。
      this.profileRefreshToken += 1
      // 未登录时不发送受保护请求，避免启动阶段出现无意义的 401。
      syncAddressesRemote()
      syncCartRemote()
      syncCategoriesFromServer()
      syncStoresFromServer()
    }
  }

  // 打开独立店铺详情页，详情不再复用发现Tab
  onPageHide(): void { this.pageVisible = false }

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
          Image($r('app.media.ui_tools')).width(48).height(48).objectFit(ImageFit.Contain)
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
      this.mainTabs()

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
    .width('100%')
    .height('100%')
    .backgroundColor(HomeTheme.SURFACE)
    // 背景覆盖手势区，登录覆盖层仍按系统安全区布局。
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  @Builder
  mainTabs() {
    Stack({ alignContent: Alignment.Bottom }) {
    Tabs({ controller: this.tabsController, barPosition: BarPosition.End, index: $$this.currentTab }) {
      TabContent() {
        if (this.selectedTab === 0) {
        HomePage({
          bottomInset: this.systemBottomInset,
          onStoreClick: (store: StoreItem) => {
            this.showStoreDetail(store.id, store.name)
          },
          onNavigateLogin: () => { this.showLogin = true },
          onNavigateLocationLogin: () => { this.showLocationLoginConfirm = true }
        })
      }
      }

      TabContent() {
        if (this.selectedTab === 1) {
        AssistantPage({ bottomInset: this.systemBottomInset,
          onNavigateTab: (index: number) => { this.tabsController.changeIndex(index) } })
      }
      }

      TabContent() {
        if (this.selectedTab === 2) {
        CartPage({ bottomInset: this.systemBottomInset, onBrowse: () => { this.tabsController.changeIndex(0) } })
      }
      }

      TabContent() {
        if (this.selectedTab === 3) {
        ProfileMainPage({
          bottomInset: this.systemBottomInset,
          refreshToken: this.profileRefreshToken,
          onNavigateLogin: () => { this.showLogin = true }
        })
      }
      }
    }
    .barHeight(0)
    .barBackgroundColor(HomeTheme.SURFACE)
    .onAnimationStart((index: number, targetIndex: number) => {
      // 只更新选中外观；提前修改 Tabs 的 index 会跳过原生切换动画。
      this.selectedTab = targetIndex
    })
    .onChange((index: number) => {
      this.currentTab = index
      this.selectedTab = index
      if (index === 3) {
        this.profileRefreshToken += 1
      }
      logInfo('Page', `首页 Tab 切换 index=${index}`)
    })
    .scrollable(false)
    .animationDuration(this.reduceMotion ? 0 : AppMotion.TAB)
    .animationCurve(Curve.EaseOut)
    .width('100%')
    // 所有 Tab 内容铺到手势区，悬浮导航仍按系统安全区布局。
    .height(LayoutPolicy.matchParent)
    .align(Alignment.Top)
    .backgroundColor(HomeTheme.SURFACE)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    .onSizeChange((_: SizeOptions, size: SizeOptions) => {
      this.contentViewportHeight = Number(size.height)
      this.updateSystemBottomInset()
    })
    AdaptiveTabBar({ selected: this.selectedTab, active: this.pageVisible,
      onSelect: (index: number) => { this.tabsController.changeIndex(index) } })
    }
    .width('100%').height('100%')
    .onSizeChange((_: SizeOptions, size: SizeOptions) => {
      this.safeViewportHeight = Number(size.height)
      this.updateSystemBottomInset()
    })
  }

}

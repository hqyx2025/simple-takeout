import { AppButtonStyle, AppRefreshStyle } from '../../common/theme/AppTheme'
/**
 * 主页面 - 简单外卖App
 * 包含：搜索栏、分类导航、店铺列表、店铺详情、购物车、订单列表、个人中心、底部Tab导航
 */
import { User, UserRole, createEmptyUser } from '../../model/Models'
import { isLoggedIn, logout, getLastRemoteErrorMessage, syncCurrentUserFromServer } from '../../service/AppStorageManager'

import { FloatingTabBarTheme } from '../../common/theme/FloatingTabBarTheme'

import { promptCompat as promptAction, routerCompat as router } from '../../common/UiNavigation'

import { HomeTheme } from '../../common/theme/HomeTheme'

import { AppMotion } from '../../common/theme/AppMotion'

@Component
export struct ProfileMainPage {
  @Prop bottomInset: number = 0
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
  private lastRefreshAt: number = 0
  private refreshInFlight: boolean = false

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
    if (this.refreshInFlight || Date.now() - this.lastRefreshAt < 5000) { return true }
    this.refreshInFlight = true
    const latestUser: User | undefined = await syncCurrentUserFromServer()
    this.refreshInFlight = false
    if (latestUser === undefined) {
      return false
    }
    this.applyUser(latestUser)
    this.lastRefreshAt = Date.now()
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
    this.lastRefreshAt = 0
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

  build() {
    Stack() {
      Refresh({ refreshing: this.isRefreshing }) {
        Scroll() {
          Column() {
            Column({ space: 16 }) {
              this.ProfileHeader()
              this.ProfileAssets()
              this.ProfileOrders()

              Column() {
                this.ProfileSectionTitle('常用服务')
                this.ProfileMenuRow($r('app.media.home_location'), '收货地址', () => {
                  if (!this.loggedIn) {
                    promptAction.showToast({ message: '请先登录后管理收货地址', duration: 1500 })
                    this.onNavigateLogin()
                    return
                  }
                  router.pushUrl({ url: 'pages/AddressListPage' })
                })
                this.ProfileMenuRow($r('app.media.home_heart'), '我的收藏', () => {
                  router.pushUrl({ url: 'pages/FavoriteListPage' })
                })
                this.ProfileMenuRow($r('app.media.profile_headset'), '售后帮助', () => {
                  router.pushUrl({ url: 'pages/ContactCustomerServicePage' })
                })
                this.ProfileMenuRow($r('app.media.profile_settings'), '设置', () => {
                  router.pushUrl({ url: 'pages/SettingsPage' })
                }, 'profile-app-settings')
              }
              .width('100%').padding({ top: 16, bottom: 4 })
              .backgroundColor(HomeTheme.CARD).borderRadius(20)

              Column() {
                this.ProfileSectionTitle('钱包服务')
                this.ProfileMenuRow($r('app.media.profile_wallet'), '钱包与银行卡', () => {
                  this.openBalancePage()
                })
              }
              .width('100%').padding({ top: 16, bottom: 4 })
              .backgroundColor(HomeTheme.CARD).borderRadius(20)

              if (this.loggedIn && this.user.role === UserRole.MERCHANT) {
                Column() {
                  this.ProfileSectionTitle('商户管理入口')
                  this.ProfileMenuRow($r('app.media.profile_store'), '店铺管理', () => {
                    router.pushUrl({ url: 'pages/MerchantCenterPage' })
                  }, 'profile-merchant-center')
                  this.ProfileMenuRow($r('app.media.profile_order'), '订单管理', () => {
                    router.pushUrl({ url: 'pages/MerchantOrdersPage' })
                  }, 'profile-merchant-orders')
                  this.ProfileMenuRow($r('app.media.profile_chart'), '收入统计', () => {
                    router.pushUrl({ url: 'pages/MerchantStatsPage' })
                  }, 'profile-merchant-stats')
                }
                .width('100%').padding({ top: 16, bottom: 4 })
                .backgroundColor(HomeTheme.CARD).borderRadius(20)
              }
              if (this.loggedIn && this.user.role === UserRole.ADMIN) {
                Column() {
                  this.ProfileSectionTitle('平台管理入口')
                  this.ProfileMenuRow($r('app.media.profile_shield'), '平台分类、店铺与托管订单', () => {
                    router.pushUrl({ url: 'pages/AdminCenterPage' })
                  })
                }
                .width('100%').padding({ top: 16, bottom: 4 })
                .backgroundColor(HomeTheme.CARD).borderRadius(20)
              }
              if (this.loggedIn) {
                Button('退出', { type: ButtonType.Normal })
                  .attributeModifier(new AppButtonStyle())
                  .width('100%').height(48)
                  .fontSize(14).fontColor(HomeTheme.MUTED)
                  .backgroundColor(HomeTheme.CARD).borderRadius(16)
                  .id('profile-logout')
                  .animation(AppMotion.pressAnimation())
                  .onClick(() => {
                    logout()
                    this.loggedIn = false
                  })
              }
            }
            .width('100%').constraintSize({ maxWidth: 680 })
          }
          .width('100%').padding({ left: 16, right: 16, top: 20,
            bottom: FloatingTabBarTheme.CONTENT_INSET + this.bottomInset + 16 })
        }
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
        .width('100%').height('100%')
        .backgroundColor(HomeTheme.SURFACE)
      }
      .onRefreshing(() => { this.refreshProfileData() })
      .attributeModifier(new AppRefreshStyle())
      .width('100%').height('100%')

    }
    .width('100%').height('100%')
    .backgroundColor(HomeTheme.SURFACE)
  }

  @Builder
  ProfileHeader() {
    Column({ space: 12 }) {
      Text('我的')
        .fontSize(28).fontWeight(FontWeight.Bold).fontColor(HomeTheme.TEXT)
        .width('100%')
      Button({ type: ButtonType.Normal }) {
        Row({ space: 14 }) {
          Column() {
            if (this.loggedIn && this.user.username.length > 0) {
              Text(this.user.username.charAt(0))
                .fontSize(26).fontWeight(FontWeight.Bold).fontColor(HomeTheme.ACCENT)
            } else {
              Image($r('app.media.home_nav_profile')).width(30).height(30)
                .accessibilityLevel('no')
            }
          }
          .width(64).height(64).justifyContent(FlexAlign.Center)
          .backgroundColor(HomeTheme.SOFT).borderRadius(22)
          Column({ space: 7 }) {
            Text(this.user.username)
              .fontSize(22).fontWeight(FontWeight.Bold).fontColor(HomeTheme.TEXT)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.loggedIn
              ? (this.user.role === UserRole.ADMIN
                ? '管理端账户'
                : this.user.role === UserRole.MERCHANT ? '商户账户' : this.user.phone)
              : '点击登录')
              .fontSize(13).fontColor(HomeTheme.MUTED)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(HorizontalAlign.Start).layoutWeight(1)
          Image($r('app.media.home_chevron')).width(18).height(18)
            .rotate({ angle: -90 })
            .accessibilityLevel('no')
        }
        .width('100%').padding({ top: 8, bottom: 8 })
      }
        .attributeModifier(new AppButtonStyle())
      .width('100%').padding(0)
      .backgroundColor(Color.Transparent).borderRadius(18)
      .id('profile-account')
      .animation(AppMotion.pressAnimation())
      .onClick(() => {
        if (!this.loggedIn) {
          this.onNavigateLogin()
        } else {
          router.pushUrl({ url: 'pages/ProfileEditPage' })
        }
      })
    }
    .width('100%')
  }

  @Builder
  ProfileAssets() {
    Row() {
      // 直接读取当前页面状态，充值后余额保持可观察更新。
      this.BalanceAssetItem()
      Divider().vertical(true).height(32).strokeWidth(1).color(HomeTheme.INPUT)
      this.AssetItem((this.user.coupons || []).filter(c => !c.used).length.toString(), '优惠券', () => {
        router.pushUrl({ url: 'pages/CouponCenterPage' })
      })
      Divider().vertical(true).height(32).strokeWidth(1).color(HomeTheme.INPUT)
      this.AssetItem((this.user.orders || []).length.toString(), '订单', () => {
        this.openOrders(-1)
      })
    }
    .width('100%').padding({ left: 4, right: 4, top: 10, bottom: 10 })
    .backgroundColor(HomeTheme.CARD).borderRadius(20)
  }

  @Builder
  ProfileOrders() {
    Column({ space: 8 }) {
      Row() {
        Text('我的订单').fontSize(17).fontWeight(FontWeight.Bold).fontColor(HomeTheme.TEXT)
        Blank()
        Button({ type: ButtonType.Normal }) {
          Row({ space: 3 }) {
            Text('全部订单').fontSize(12).fontColor(HomeTheme.MUTED)
            Image($r('app.media.home_chevron')).width(14).height(14)
              .rotate({ angle: -90 })
              .accessibilityLevel('no')
          }
        }
          .attributeModifier(new AppButtonStyle())
        .height(44).padding({ left: 8, right: 0 })
        .backgroundColor(Color.Transparent)
        .animation(AppMotion.pressAnimation())
        .onClick(() => { this.openOrders(-1) })
      }
      .width('100%').padding({ left: 16, right: 16 })
      Row() {
        this.ProfileOrderEntry($r('app.media.home_clock'), '待付款', 0)
        this.ProfileOrderEntry($r('app.media.profile_order'), '待接单', 1)
        this.ProfileOrderEntry($r('app.media.profile_rider'), '配送中', 3)
        this.ProfileOrderEntry($r('app.media.profile_complete'), '已完成', 4)
      }
      .width('100%').padding({ left: 6, right: 6 })
    }
    .width('100%').padding({ top: 4, bottom: 12 })
    .backgroundColor(HomeTheme.CARD).borderRadius(20)
  }

  @Builder
  ProfileSectionTitle(title: string) {
    Text(title)
      .fontSize(17).fontWeight(FontWeight.Bold).fontColor(HomeTheme.TEXT)
      .width('100%').padding({ left: 16, right: 16, bottom: 6 })
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
  BalanceAssetItem() {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 7 }) {
        Text(this.balanceDisplay)
          .fontSize(22).fontWeight(FontWeight.Bold).fontColor(HomeTheme.ACCENT)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text('余额').fontSize(12).fontColor(HomeTheme.MUTED)
      }
      .width('100%').alignItems(HorizontalAlign.Center)
    }
      .attributeModifier(new AppButtonStyle())
    .layoutWeight(1).height(72).padding({ left: 4, right: 4 })
    .backgroundColor(Color.Transparent).borderRadius(14)
    .animation(AppMotion.pressAnimation())
    .onClick(() => { this.openBalancePage() })
  }

  @Builder
  AssetItem(value: string, label: string, action: () => void) {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 7 }) {
        Text(value).fontSize(22).fontWeight(FontWeight.Bold).fontColor(HomeTheme.TEXT)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(label).fontSize(12).fontColor(HomeTheme.MUTED)
      }
      .width('100%').alignItems(HorizontalAlign.Center)
    }
      .attributeModifier(new AppButtonStyle())
    .layoutWeight(1).height(72).padding({ left: 4, right: 4 })
    .backgroundColor(Color.Transparent).borderRadius(14)
    .animation(AppMotion.pressAnimation())
    .onClick(() => { action() })
  }

  @Builder
  ProfileOrderEntry(icon: Resource, title: string, status: number) {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 7 }) {
        Image(icon).width(24).height(24).accessibilityLevel('no')
        Text(title).fontSize(12).fontColor(HomeTheme.MUTED)
      }
      .width('100%').padding({ top: 8, bottom: 8 })
    }
      .attributeModifier(new AppButtonStyle())
    .layoutWeight(1).constraintSize({ minHeight: 64 }).padding(0)
    .backgroundColor(Color.Transparent).borderRadius(14)
    .animation(AppMotion.pressAnimation())
    .onClick(() => { this.openOrders(status) })
  }

  private openOrders(status: number): void {
    AppStorage.setOrCreate<number>('orderFilterStatus', status)
    if (!this.loggedIn) {
      promptAction.showToast({ message: '请先登录后查看订单', duration: 1500 })
      this.onNavigateLogin()
      return
    }
    router.pushUrl({ url: 'pages/OrderListPage' })
  }

  @Builder
  ProfileMenuRow(icon: Resource, title: string, action: () => void, rowId: string = '') {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 12 }) {
        Image(icon).width(22).height(22).accessibilityLevel('no')
        Text(title).fontSize(16).fontColor(HomeTheme.TEXT).layoutWeight(1)
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        Image($r('app.media.home_chevron')).width(16).height(16)
          .rotate({ angle: -90 })
          .accessibilityLevel('no')
      }
      .width('100%').padding({ left: 16, right: 16, top: 16, bottom: 16 })
    }
      .attributeModifier(new AppButtonStyle())
    .width('100%').constraintSize({ minHeight: 56 }).padding(0)
    .backgroundColor(Color.Transparent).borderRadius(14)
    .id(rowId)
    .animation(AppMotion.pressAnimation())
    .onClick(() => { action() })
  }
}

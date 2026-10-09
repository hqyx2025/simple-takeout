import { abilityAccessCtrl, bundleManager, common } from '@kit.AbilityKit'
import { notificationManager } from '@kit.NotificationKit'
import { AppButtonStyle, AppCardStyle, AppInputStyle, AppTheme } from '../common/theme/AppTheme'
import { AppMotion } from '../common/theme/AppMotion'
import { COLORS, SPACING, FONT_SIZE, APP_CONFIG } from '../common/Constants'
import { User, UserRole, createEmptyUser } from '../model/Models'
import { logout } from '../service/AppStorageManager'
import { getCacheSize, clearAppCache } from '../service/CacheService'
import { ConfirmDialog } from '../components/ConfirmDialog'
import { PageHeader } from '../components/PageHeader'
import { routerCompat as router, promptCompat as promptAction } from '../common/UiNavigation'

/** 设置项作为独立组件接收 @Prop，保证异步状态（缓存、通知等）更新后文案同步刷新。 */
@Component
struct SettingsItemRow {
  @Prop icon: Resource = $r('app.media.ui_info')
  @Prop title: string = ''
  @Prop value: string = ''
  @Prop itemId: string = ''
  action: () => void = () => {}

  build() {
    Button({ type: ButtonType.Normal }) {
      Row({ space: SPACING.MD }) {
        Image(this.icon).width(20).height(20).objectFit(ImageFit.Contain).accessibilityLevel('no')
        Text(this.title).fontSize(FONT_SIZE.LG).fontColor(COLORS.TEXT_PRIMARY)
          .layoutWeight(1).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.value !== '') {
          Text(this.value).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
            .constraintSize({ maxWidth: '45%' }).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        Image($r('app.media.home_chevron')).width(16).height(16).rotate({ angle: -90 }).accessibilityLevel('no')
      }.width('100%')
    }.attributeModifier(new AppButtonStyle()).width('100%').constraintSize({ minHeight: 60 })
      .padding(SPACING.LG).backgroundColor(Color.Transparent).id(this.itemId)
      .accessibilityText(this.value === '' ? this.title : `${this.title}，${this.value}`)
      .onClick(() => { this.action() })
  }
}

/** 设置总入口：按用途归类，通用偏好仍由应用设置页管理。 */
@Entry
@Component
export struct SettingsPage {
  @StorageLink('isLoggedIn') loggedIn: boolean = false
  @StorageLink('user') user: User = createEmptyUser()
  @State showAbout: boolean = false
  @State showLogoutConfirm: boolean = false
  @State switchingAccount: boolean = false
  @State showCacheConfirm: boolean = false
  @State showPrivacySheet: boolean = false
  @State cacheSize: string = '计算中…'
  @State clearingCache: boolean = false
  @State notificationStatus: string = '读取中…'
  @State locationStatus: string = '读取中…'
  @State openingNotifications: boolean = false
  @State openingPermissions: boolean = false
  @State version: string = APP_CONFIG.VERSION
  onBack: () => void = () => { router.back() }
  onLogout: () => void = () => {}

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

  private abilityContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  aboutToAppear(): void {
    this.calculateCacheSize()
    this.refreshSystemStatus()
    try { this.version = bundleManager.getBundleInfoForSelfSync(0).versionName } catch (_) {}
  }

  onPageShow(): void { this.refreshSystemStatus() }

  aboutToDisappear(): void {
  }

  private async refreshSystemStatus(): Promise<void> {
    try {
      this.notificationStatus = notificationManager.isNotificationEnabledSync() ? '已开启' : '未开启'
    } catch (_) { this.notificationStatus = '系统管理' }
    try {
      const manager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager()
      const tokenId: number = this.abilityContext().applicationInfo.accessTokenId
      const precise: abilityAccessCtrl.GrantStatus = await manager.checkAccessToken(tokenId, 'ohos.permission.LOCATION')
      const approximate: abilityAccessCtrl.GrantStatus = await manager.checkAccessToken(tokenId, 'ohos.permission.APPROXIMATELY_LOCATION')
      this.locationStatus = precise === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED ? '精确位置已允许'
        : approximate === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED ? '模糊位置已允许' : '未允许'
    } catch (_) { this.locationStatus = '系统管理' }
  }

  private openAccountPage(url: string): void {
    if (!this.loggedIn) {
      promptAction.showToast({ message: '请先登录', duration: 1500 })
      router.replaceUrl({ url: 'pages/Index' })
      return
    }
    router.pushUrl({ url: url })
  }

  private async calculateCacheSize(): Promise<void> {
    try {
      const bytes: number = await getCacheSize(this.abilityContext())
      this.cacheSize = bytes < 1024 * 1024 ? `${(bytes / 1024).toFixed(1)} KB`
        : `${(bytes / (1024 * 1024)).toFixed(1)} MB`
    } catch (_) { this.cacheSize = '读取失败' }
  }

  private async clearCache(): Promise<void> {
    if (this.clearingCache) { return }
    this.showCacheConfirm = false
    this.clearingCache = true
    try {
      await clearAppCache(this.abilityContext())
      promptAction.showToast({ message: '缓存已清理', duration: 1500 })
    } catch (_) {
      promptAction.showToast({ message: '部分缓存未能清理，请稍后重试', duration: 2000 })
    } finally {
      await this.calculateCacheSize()
      this.clearingCache = false
    }
  }

  private doLogout(): void {
    this.showLogoutConfirm = false
    logout()
    this.onLogout()
    router.replaceUrl({ url: 'pages/Index' })
  }


  private async openNotifications(): Promise<void> {
    if (this.openingNotifications) { return }
    this.openingNotifications = true
    try {
      await notificationManager.openNotificationSettingsWithResult(this.abilityContext())
      await this.refreshSystemStatus()
    } catch (_) {
      promptAction.showToast({ message: '请在系统设置的通知管理中调整简单外卖通知', duration: 2500 })
    } finally { this.openingNotifications = false }
  }

  private async openPermissions(): Promise<void> {
    if (this.openingPermissions) { return }
    this.openingPermissions = true
    try {
      const context: common.UIAbilityContext = this.abilityContext()
      await context.startAbility({
        action: 'ohos.want.action.viewData', uri: 'application_info_entry',
        parameters: { settingsParamBundleName: context.applicationInfo.name }
      })
    } catch (_) {
      promptAction.showToast({ message: '请在系统设置 → 应用 → 简单外卖 → 权限中调整', duration: 2500 })
    } finally { this.openingPermissions = false }
  }

  build() {
    Stack() {
      Column() {
        PageHeader({ title: '设置', backId: 'settings-back', onBack: () => { this.onBack() } })
        Scroll() {
          Column({ space: SPACING.LG }) {
            this.GroupTitle('个人与地址')
            Column() {
              SettingsItemRow({ icon: $r('app.media.login_user'), title: '个人信息',
                value: this.loggedIn ? this.user.username : '未登录', action: () => { this.openAccountPage('pages/ProfileEditPage') },
                itemId: 'settings-profile' })
              if (this.user.role === UserRole.CUSTOMER) {
                this.SettingDivider()
                SettingsItemRow({ icon: $r('app.media.home_location'), title: '收货地址',
                  action: () => { this.openAccountPage('pages/AddressListPage') }, itemId: 'settings-address' })
              }
            }.attributeModifier(new AppCardStyle()).width('100%').padding(SPACING.XS)

            this.GroupTitle('账号与隐私')
            Column() {
              if (this.loggedIn) {
                SettingsItemRow({ icon: $r('app.media.profile_shield'), title: '账号安全', value: '修改密码',
                  action: () => { router.pushUrl({ url: 'pages/AccountSecurityPage' }) }, itemId: 'settings-security' })
                this.SettingDivider()
                SettingsItemRow({ icon: $r('app.media.profile_shield'), title: '支付密码', value: '设置/修改',
                  action: () => { router.pushUrl({ url: 'pages/AccountSecurityPage' }) }, itemId: 'settings-payment-password-entry' })
                this.SettingDivider()
              }
              SettingsItemRow({ icon: $r('app.media.login_lock'), title: '隐私设置', value: '权限与政策',
                action: () => { this.showPrivacySheet = true }, itemId: 'settings-privacy' })
            }.attributeModifier(new AppCardStyle()).width('100%').padding(SPACING.XS)

            this.GroupTitle('常用设置')
            Column() {
              if (this.user.role === UserRole.CUSTOMER) {
                SettingsItemRow({ icon: $r('app.media.profile_wallet'), title: '钱包与银行卡',
                  action: () => { this.openAccountPage('pages/BalancePage') }, itemId: 'settings-wallet' })
                this.SettingDivider()
              }
              SettingsItemRow({ icon: $r('app.media.home_announcement'), title: '消息通知', value: this.notificationStatus,
                action: () => { this.openNotifications() }, itemId: 'settings-notifications' })
              this.SettingDivider()
              SettingsItemRow({ icon: $r('app.media.profile_settings'), title: '应用设置', value: '外观、字体、导航',
                action: () => { router.pushUrl({ url: 'pages/AppSettingsPage' }) }, itemId: 'settings-general' })
              this.SettingDivider()
              SettingsItemRow({ icon: $r('app.media.ui_trash'), title: '清除缓存',
                value: this.clearingCache ? '清理中…' : this.cacheSize,
                action: () => { if (!this.clearingCache) { this.showCacheConfirm = true } }, itemId: 'settings-cache' })
            }.attributeModifier(new AppCardStyle()).width('100%').padding(SPACING.XS)

            this.GroupTitle('帮助与关于')
            Column() {
              SettingsItemRow({ icon: $r('app.media.ui_info'), title: '关于简单外卖', value: `v${this.version}`,
                action: () => { this.showAbout = true }, itemId: 'settings-about' })
              this.SettingDivider()
              SettingsItemRow({ icon: $r('app.media.profile_headset'), title: '帮助与客服',
                action: () => { router.pushUrl({ url: 'pages/ContactCustomerServicePage' }) }, itemId: 'settings-help' })
            }.attributeModifier(new AppCardStyle()).width('100%').padding(SPACING.XS)
          }.width('100%').constraintSize({ maxWidth: 680 }).padding(SPACING.LG)
        }.width('100%').layoutWeight(1).align(Alignment.Top).scrollBar(BarState.Off)

        Row({ space: SPACING.MD }) {
          if (this.loggedIn) {
            Button('切换账号')
              .attributeModifier(new AppButtonStyle()).layoutWeight(1).height(AppTheme.CONTROL_HEIGHT)
              .fontColor(COLORS.TEXT_PRIMARY).backgroundColor(COLORS.INPUT)
              .border({ width: 1, color: COLORS.DIVIDER }).id('settings-switch-account')
              .onClick(() => { this.switchingAccount = true; this.showLogoutConfirm = true })
            Button('退出登录')
              .attributeModifier(new AppButtonStyle()).layoutWeight(1).height(AppTheme.CONTROL_HEIGHT)
              .id('settings-logout')
              .onClick(() => { this.switchingAccount = false; this.showLogoutConfirm = true })
          } else {
            Button('登录')
              .attributeModifier(new AppButtonStyle()).width('100%').height(AppTheme.CONTROL_HEIGHT)
              .id('settings-login').onClick(() => { router.replaceUrl({ url: 'pages/Index' }) })
          }
        }.width('100%').constraintSize({ maxWidth: 680 }).padding(SPACING.LG)
      }.width('100%').height('100%').backgroundColor(COLORS.BG_PRIMARY)

      if (this.showAbout) { this.AboutDialog() }
      if (this.showCacheConfirm) {
        ConfirmDialog({ title: '清除缓存', content: '清理临时文件，购物车、订单、收货地址和应用设置都会保留。',
          confirmText: '清理', cancelText: '取消', onConfirm: () => { this.clearCache() },
          onCancel: () => { this.showCacheConfirm = false } })
      }
      if (this.showLogoutConfirm) {
        ConfirmDialog({ title: this.switchingAccount ? '切换账号' : '确认退出',
          content: this.switchingAccount ? '退出当前账号后，使用另一个账号登录。' : '确定要退出登录吗？',
          confirmText: this.switchingAccount ? '切换账号' : '退出', cancelText: '取消',
          onConfirm: () => { this.doLogout() }, onCancel: () => { this.showLogoutConfirm = false } })
      }
    }.width('100%').height('100%')
    .bindSheet($$this.showPrivacySheet, this.PrivacySheet(), {
      height: SheetSize.MEDIUM, detents: [SheetSize.MEDIUM, SheetSize.LARGE], preferType: SheetType.BOTTOM,
      showClose: true, dragBar: true, backgroundColor: AppTheme.CARD,
      radius: { topLeft: AppTheme.SHEET_RADIUS, topRight: AppTheme.SHEET_RADIUS }
    })
  }

  @Builder
  GroupTitle(title: string) {
    Text(title).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
      .width('100%').padding({ left: SPACING.MD }).margin({ bottom: -SPACING.SM })
  }

  @Builder
  SettingDivider() {
    Divider().color(COLORS.DIVIDER).margin({ left: 48, right: SPACING.LG })
  }

  @Builder
  PrivacySheet() {
    Column() {
      PageHeader({ title: '隐私设置', showBack: false, topPadding: 0, headerBgColor: AppTheme.CARD })
      Scroll() {
        Column({ space: SPACING.LG }) {
          Text('定位权限用于选择配送地址和查看附近店铺，可在系统中随时调整。')
            .fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_SECONDARY).width('100%')
          SettingsItemRow({ icon: $r('app.media.home_location'), title: '定位权限', value: this.locationStatus,
            action: () => { this.openPermissions() }, itemId: 'settings-location-permission' })
          SettingsItemRow({ icon: $r('app.media.login_shield'), title: '系统权限管理',
            action: () => { this.openPermissions() }, itemId: 'settings-system-permissions' })
          SettingsItemRow({ icon: $r('app.media.login_lock'), title: '隐私政策', action: () => {
            this.showPrivacySheet = false
            router.pushUrl({ url: 'pages/PrivacyPolicyPage' })
          }, itemId: 'settings-privacy-policy' })
        }.width('100%').padding(SPACING.LG)
      }.width('100%').layoutWeight(1).align(Alignment.Top)
    }.width('100%').height('100%').backgroundColor(AppTheme.CARD)
  }

  @Builder
  AboutDialog() {
    Stack() {
      Column().width('100%').height('100%').backgroundColor(COLORS.OVERLAY)
        .onClick(() => { this.showAbout = false })
      Column({ space: SPACING.MD }) {
        Image($r('app.media.home_bowl')).width(60).height(60).objectFit(ImageFit.Contain)
        Text('简单外卖').fontSize(FONT_SIZE.XXL).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
        Text(`v${this.version}`).fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_SECONDARY)
        Text('一款便捷学生点外卖的鸿蒙App').fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_SECONDARY)
          .textAlign(TextAlign.Center)
        Text('HarmonyOS NEXT 毕业设计项目').fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
        Button('关闭').attributeModifier(new AppButtonStyle()).width('100%').height(44)
          .id('settings-about-close').onClick(() => { this.showAbout = false })
      }.attributeModifier(new AppCardStyle()).width('80%').constraintSize({ maxWidth: 460 })
      .padding(SPACING.XXL).alignItems(HorizontalAlign.Center)
    }.width('100%').height('100%').alignContent(Alignment.Center)
  }
}

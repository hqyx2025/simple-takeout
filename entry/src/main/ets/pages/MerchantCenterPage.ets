import { COLORS, SPACING, FONT_SIZE } from '../common/Constants'
import { AppButtonStyle, AppCardStyle } from '../common/theme/AppTheme'
import { PageHeader } from '../components/PageHeader'
import { RemoteState } from '../components/RemoteState'
import { routerCompat as router, promptCompat as promptAction } from '../common/UiNavigation'
import { StoreItem, GoodsItem, Category, User, UserRole, createEmptyUser } from '../model/Models'
import { PageSession } from '../service/PageSession'
import { fetchMerchantStoresResultApi, fetchMerchantGoodsResultApi, fetchMerchantCategoriesResultApi,
  updateMerchantGoodsApi, deleteMerchantGoodsApi, createMerchantCategoryApi, updateMerchantCategoryApi,
  deleteMerchantCategoryApi } from '../service/api/MerchantApi'
import { MerchantOrdersPage } from './MerchantOrdersPage'
import { logout } from '../service/AppStorageManager'

@Entry
@Component
export struct MerchantCenterPage {
  private session: PageSession = new PageSession()
  @State tab: number = 0
  @State visible: boolean = true
  @State stores: StoreItem[] = []
  @State loading: boolean = true
  @State failed: boolean = false
  @StorageLink('user') @Watch('onIdentityChange') user: User = createEmptyUser()
  @StorageLink('isLoggedIn') @Watch('onIdentityChange') loggedIn: boolean = false

  aboutToAppear(): void {
    if (!this.session.start(UserRole.MERCHANT)) { router.replaceUrl({ url: 'pages/Index' }); return }
    this.load()
  }
  onPageShow(): void { this.visible = true; this.load() }
  onPageHide(): void { this.visible = false; this.session.pause() }
  onIdentityChange(): void {
    if (this.session.matchesIdentity()) { return }
    this.stores = []
    this.session.pause()
    router.replaceUrl({ url: 'pages/Index' })
  }
  private async load(): Promise<void> {
    const version: number = this.session.request()
    if (!this.session.current(version)) { return }
    this.loading = true
    this.failed = false
    const result: StoreItem[] | null = await fetchMerchantStoresResultApi()
    if (!this.session.current(version)) { return }
    this.loading = false
    if (result === null) { this.failed = true; return }
    this.stores = result
  }

  @Builder
  Entry(label: string, url: string, id: string) {
    Button(label).attributeModifier(new AppButtonStyle()).width('100%').height(48).id(id)
      .onClick(() => { router.pushUrl({ url }) })
  }

  @Builder
  Workbench() {
    Column() {
      PageHeader({ title: '经营工作台', showBack: false, actionLabel: '新建门店',
        onAction: () => { router.pushUrl({ url: 'pages/MerchantStoreEditPage' }) } })
      Scroll() {
        Column({ space: SPACING.MD }) {
          this.Entry('收入统计', 'pages/MerchantStatsPage', 'profile-merchant-stats')
          this.Entry('营销管理', 'pages/MerchantMarketingPage', 'merchant-marketing-entry')
          this.Entry('评价管理', 'pages/MerchantReviewsPage', 'merchant-reviews-entry')
          this.Entry('分类管理', 'pages/MerchantCategoryPage', 'merchant-category-entry')
          Text('我的门店').fontColor(COLORS.TEXT_PRIMARY).fontSize(FONT_SIZE.LG).width('100%')
          RemoteState({ loading: this.loading, failed: this.failed, hasData: this.stores.length > 0,
            emptyTitle: '暂无门店，点击右上角新建门店', onRetry: () => { this.load() } })
          ForEach(this.stores, (store: StoreItem) => { this.StoreCard(store) }, (store: StoreItem) => store.id.toString())
        }.width('100%').padding(SPACING.LG)
      }.layoutWeight(1).width('100%').align(Alignment.Top)
    }.width('100%').height('100%')
  }

  @Builder
  StoreCard(store: StoreItem) {
    Column({ space: SPACING.SM }) {
      Text(store.name).fontSize(FONT_SIZE.LG).fontColor(COLORS.TEXT_PRIMARY).width('100%')
      Text(store.reviewStatus === 0 ? '待审核' : store.reviewStatus === 2 ? '审核驳回'
        : store.platformStatus === 0 ? '平台已停用' : store.status === 1 ? '营业中' : '休息中')
        .fontColor(COLORS.TEXT_SECONDARY).width('100%')
      if ((store.reviewReason ?? '') !== '') { Text(store.reviewReason ?? '').fontColor(COLORS.ERROR).width('100%') }
      Button('管理门店 ›').attributeModifier(new AppButtonStyle()).width('100%').height(44)
        .id(`merchant-store-goods-${store.id}`)
        .onClick(() => { router.pushUrl({ url: 'pages/MerchantStoreDetailPage', params: { storeId: store.id } }) })
    }.attributeModifier(new AppCardStyle()).width('100%').padding(SPACING.LG)
  }

  @Builder
  MyAccount() {
    Column() {
      PageHeader({ title: '我的', showBack: false })
      Scroll() {
        Column({ space: SPACING.MD }) {
          Text(this.user.username).fontColor(COLORS.TEXT_PRIMARY).fontSize(FONT_SIZE.XL).width('100%')
          this.Entry('个人资料', 'pages/ProfileEditPage', 'merchant-profile')
          this.Entry('账号安全', 'pages/AccountSecurityPage', 'merchant-security')
          this.Entry('地址管理', 'pages/AddressListPage', 'merchant-addresses')
          this.Entry('设置', 'pages/SettingsPage', 'merchant-settings')
        }.width('100%').padding(SPACING.LG)
      }.layoutWeight(1).width('100%').align(Alignment.Top)
      Button('退出登录').attributeModifier(new AppButtonStyle()).width('90%').height(48).id('merchant-logout')
        .onClick(() => { logout(); router.replaceUrl({ url: 'pages/Index' }) }).margin(SPACING.MD)
    }.width('100%').height('100%')
  }

  @Builder
  Tab(label: string, index: number) {
    Button(label).attributeModifier(new AppButtonStyle()).layoutWeight(1).height(48)
      .fontColor(this.tab === index ? COLORS.ON_PRIMARY : COLORS.TEXT_PRIMARY)
      .backgroundColor(this.tab === index ? COLORS.PRIMARY : COLORS.INPUT)
      .id('merchant-tab-' + index).onClick(() => { this.tab = index })
  }

  build() {
    Column() {
      Column() {
        if (this.tab === 0) { this.Workbench() }
        else if (this.tab === 1) {
          if (this.visible) { MerchantOrdersPage({ embedded: true }) }
        }
        else { this.MyAccount() }
      }.layoutWeight(1).width('100%')
      Row({ space: SPACING.SM }) { this.Tab('工作台', 0); this.Tab('订单', 1); this.Tab('我的', 2) }
        .width('100%').padding(SPACING.SM).backgroundColor(COLORS.BG_PRIMARY)
    }.width('100%').height('100%').backgroundColor(COLORS.BG_PRIMARY)
  }
}

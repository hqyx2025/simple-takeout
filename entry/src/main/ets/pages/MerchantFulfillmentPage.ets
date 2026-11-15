import { User, createEmptyUser } from '../model/Models'
import { COLORS, SPACING, FONT_SIZE } from '../common/Constants'
import { AppButtonStyle } from '../common/theme/AppTheme'
import { PageHeader } from '../components/PageHeader'
import { RemoteState } from '../components/RemoteState'
import { routerCompat as router, promptCompat as promptAction } from '../common/UiNavigation'
import { StoreItem, UserRole } from '../model/Models'
import { PageSession } from '../service/PageSession'
import { fetchMerchantStoresResultApi } from '../service/api/MerchantApi'
import { FulfillmentSettings, fetchFulfillmentApi, saveFulfillmentApi } from '../service/api/AfterSalesApi'

@Entry
@Component
struct MerchantFulfillmentPage {
  private session: PageSession = new PageSession()
  @StorageLink('user') @Watch('onSessionIdentityChange') currentUser: User = createEmptyUser()
  @StorageLink('isLoggedIn') @Watch('onSessionIdentityChange') authenticated: boolean = false

  @State mode: string = ''
  @State selected: string = ''
  @State storeName: string = ''
  @State loading: boolean = true
  @State failed: boolean = false
  @State saving: boolean = false
  private storeId: number = 0

  onSessionIdentityChange(): void {
    if (this.session.matchesIdentity()) { return }
    this.session.pause()
    this.mode = ''; this.selected = ''
    router.replaceUrl({ url: 'pages/Index' })
  }

  aboutToAppear(): void {
    this.storeId = router.getParams()?.storeId ?? 0
    if (this.storeId <= 0 || !this.session.start(UserRole.MERCHANT)) { router.back(); return }
    this.load()
  }
  onPageShow(): void { if (this.storeId > 0) { this.saving = false; this.load() } }
  onPageHide(): void { this.session.pause() }
  private async load(): Promise<void> {
    const version: number = this.session.request()
    this.loading = true; this.failed = false
    const stores: StoreItem[] | null = await fetchMerchantStoresResultApi()
    if (!this.session.current(version)) { return }
    const store: StoreItem | undefined = stores?.find((item: StoreItem) => item.id === this.storeId)
    if (store === undefined) { this.loading = false; this.failed = true; return }
    this.storeName = store.name
    const settings: FulfillmentSettings | null = await fetchFulfillmentApi(this.storeId)
    if (!this.session.current(version)) { return }
    this.loading = false
    this.failed = settings === null
    if (settings !== null) { this.mode = settings.mode; this.selected = settings.mode }
  }
  private async save(): Promise<void> {
    if (this.saving || this.loading || this.failed || !['RIDER', 'MERCHANT'].includes(this.selected)) { return }
    const version: number = this.session.request()
    if (!this.session.current(version)) { return }
    this.saving = true
    const ok: boolean = await saveFulfillmentApi(this.storeId, this.selected)
    if (!this.session.current(version)) { return }
    this.saving = false
    if (ok) { this.mode = this.selected; promptAction.showToast({ message: '已保存，仅影响后续新订单' }) }
    else { promptAction.showToast({ message: '配送方式保存未确认，请刷新核对后重试' }) }
  }
  build() {
    Column() {
      PageHeader({ title: this.storeName === '' ? '门店配送设置' : this.storeName + ' · 配送设置', onBack: () => { router.back() } })
      Scroll() {
        Column({ space: SPACING.MD }) {
          Text('仅影响后续新订单，已有订单按下单时方式履约。').fontColor(COLORS.TEXT_SECONDARY).fontSize(FONT_SIZE.SM)
          if (this.loading || this.failed) {
            RemoteState({ loading: this.loading, failed: this.failed, hasData: this.mode !== '', onRetry: () => { this.load() } })
          }
          Button((this.selected === 'RIDER' ? '✓ ' : '') + '骑手配送').attributeModifier(new AppButtonStyle()).width('100%').height(48)
            .enabled(!this.loading && !this.failed && !this.saving).onClick(() => { this.selected = 'RIDER' })
          Button((this.selected === 'MERCHANT' ? '✓ ' : '') + '商家配送').attributeModifier(new AppButtonStyle()).width('100%').height(48)
            .enabled(!this.loading && !this.failed && !this.saving).onClick(() => { this.selected = 'MERCHANT' })
        }.width('100%').padding(SPACING.LG)
      }.layoutWeight(1).width('100%').align(Alignment.Top)
      Button(this.saving ? '保存中…' : '保存配送方式').attributeModifier(new AppButtonStyle()).width('90%').height(48).margin(SPACING.MD)
        .enabled(!this.loading && !this.failed && !this.saving && this.selected !== '' && this.selected !== this.mode)
        .onClick(() => { this.save() })
    }.width('100%').height('100%').backgroundColor(COLORS.BG_PRIMARY)
  }
}

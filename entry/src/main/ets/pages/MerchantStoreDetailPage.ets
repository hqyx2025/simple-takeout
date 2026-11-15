import { COLORS, SPACING } from '../common/Constants'
import { AppButtonStyle } from '../common/theme/AppTheme'
import { PageHeader } from '../components/PageHeader'
import { RemoteState } from '../components/RemoteState'
import { routerCompat as router, promptCompat as promptAction } from '../common/UiNavigation'
import { StoreItem, User, UserRole, createEmptyUser } from '../model/Models'
import { PageSession } from '../service/PageSession'
import { fetchMerchantStoresResultApi } from '../service/api/MerchantApi'
import { post, put, ApiResponse } from '../service/HttpClient'

interface BusinessStatusPatch { status: number; deliveryFee: number; minOrder: number; deliveryRadius: number }

@Entry
@Component
struct MerchantStoreDetailPage {
  private session: PageSession = new PageSession()
  @StorageLink('user') @Watch('onSessionIdentityChange') currentUser: User = createEmptyUser()
  @StorageLink('isLoggedIn') @Watch('onSessionIdentityChange') authenticated: boolean = false

  @State store: StoreItem | null = null
  @State loading: boolean = true
  @State failed: boolean = false
  @State busy: boolean = false
  private storeId: number = 0

  onSessionIdentityChange(): void {
    if (this.session.matchesIdentity()) { return }
    this.session.pause()
    this.store = null
    router.replaceUrl({ url: 'pages/Index' })
  }

  aboutToAppear(): void {
    this.storeId = router.getParams()?.storeId ?? 0
    if (this.storeId <= 0 || !this.session.start(UserRole.MERCHANT)) { router.back(); return }
    this.load()
  }
  onPageShow(): void { if (this.storeId > 0) { this.busy = false; this.load() } }
  onPageHide(): void { this.session.pause() }
  private async load(): Promise<void> {
    const version: number = this.session.request()
    this.loading = true
    const stores: StoreItem[] | null = await fetchMerchantStoresResultApi()
    if (!this.session.current(version)) { return }
    this.loading = false
    this.failed = stores === null
    if (stores !== null) { this.store = stores.find((store: StoreItem) => store.id === this.storeId) ?? null }
  }
  private async changeBusiness(resubmit: boolean): Promise<void> {
    if (this.busy || this.store === null) { return }
    const version: number = this.session.request()
    if (!this.session.current(version)) { return }
    this.busy = true
    const patch: BusinessStatusPatch = { status: this.store.status === 1 ? 0 : 1, deliveryFee: -1, minOrder: -1, deliveryRadius: -1 }
    const result: ApiResponse<Object> = resubmit
      ? await post<Object>(`/api/merchant/stores/${this.storeId}/review`)
      : await put<Object>(`/api/merchant/stores/${this.storeId}`, patch)
    if (!this.session.current(version)) { return }
    this.busy = false
    if (result.code === 200) { promptAction.showToast({ message: resubmit ? '已重新提交审核' : '营业状态已更新' }); this.load() }
  }
  @Builder
  Entry(label: string, url: string, id: string) {
    Button(label).attributeModifier(new AppButtonStyle()).width('100%').height(48).id(id)
      .onClick(() => { router.pushUrl({ url, params: { storeId: this.storeId } }) })
  }
  build() {
    Column() {
      PageHeader({ title: this.store?.name ?? '门店详情', onBack: () => { router.back() } })
      Scroll() {
        Column({ space: SPACING.MD }) {
          RemoteState({ loading: this.loading, failed: this.failed, hasData: this.store !== null,
            emptyTitle: '门店不存在或无权管理', onRetry: () => { this.load() } })
          if (this.store !== null) {
            Text(this.store.address ?? '').fontColor(COLORS.TEXT_SECONDARY).width('100%')
            this.Entry('商品管理', 'pages/MerchantGoodsPage', 'merchant-store-products')
            this.Entry('编辑门店', 'pages/MerchantStoreEditPage', 'merchant-store-edit')
            this.Entry('门店配送设置', 'pages/MerchantFulfillmentPage', 'merchant-fulfillment')
            this.Entry('分类管理（商户共享）', 'pages/MerchantCategoryPage', 'merchant-category-entry')
            if (this.store.reviewStatus === 2) {
              Button('重新提交审核').attributeModifier(new AppButtonStyle()).width('100%').height(48)
                .id(`merchant-store-resubmit-${this.storeId}`).enabled(!this.busy).onClick(() => { this.changeBusiness(true) })
            }
            if (this.store.reviewStatus === 1 && this.store.platformStatus === 1) {
              Button(this.store.status === 1 ? '设为休息' : '开始营业').attributeModifier(new AppButtonStyle()).width('100%').height(48)
                .enabled(!this.busy).onClick(() => { this.changeBusiness(false) })
            }
          }
        }.width('100%').padding(SPACING.LG)
      }.layoutWeight(1).width('100%').align(Alignment.Top)
    }.width('100%').height('100%').backgroundColor(COLORS.BG_PRIMARY)
  }
}

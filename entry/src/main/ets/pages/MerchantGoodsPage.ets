import { COLORS, SPACING, FONT_SIZE } from '../common/Constants'
import { AppButtonStyle, AppCardStyle } from '../common/theme/AppTheme'
import { PageHeader } from '../components/PageHeader'
import { RemoteState } from '../components/RemoteState'
import { routerCompat as router, promptCompat as promptAction } from '../common/UiNavigation'
import { StoreItem, GoodsItem, User, UserRole, createEmptyUser } from '../model/Models'
import { PageSession } from '../service/PageSession'
import { fetchMerchantStoresResultApi, fetchMerchantGoodsResultApi, updateMerchantGoodsApi, deleteMerchantGoodsApi } from '../service/api/MerchantApi'

@Entry
@Component
struct MerchantGoodsPage {
  private session: PageSession = new PageSession()
  @StorageLink('user') @Watch('onSessionIdentityChange') currentUser: User = createEmptyUser()
  @StorageLink('isLoggedIn') @Watch('onSessionIdentityChange') authenticated: boolean = false

  @State goods: GoodsItem[] = []
  @State storeName: string = ''
  @State loading: boolean = true
  @State failed: boolean = false
  @State busy: boolean = false
  private storeId: number = 0

  onSessionIdentityChange(): void {
    if (this.session.matchesIdentity()) { return }
    this.session.pause()
    this.goods = []
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
    this.failed = false
    const stores: StoreItem[] | null = await fetchMerchantStoresResultApi()
    if (!this.session.current(version)) { return }
    const store: StoreItem | undefined = stores?.find((item: StoreItem) => item.id === this.storeId)
    if (store === undefined) { this.loading = false; this.failed = true; return }
    this.storeName = store.name
    const result: GoodsItem[] | null = await fetchMerchantGoodsResultApi(this.storeId)
    if (!this.session.current(version)) { return }
    this.loading = false
    if (result === null) { this.failed = true; return }
    this.goods = result
  }
  private openGoods(goods: GoodsItem, inventory: boolean): void {
    router.pushUrl({ url: inventory ? 'pages/MerchantInventoryPage' : 'pages/MerchantEditGoodsPage',
      params: { storeId: this.storeId, goodsId: goods.id } })
  }
  private async remove(goods: GoodsItem): Promise<void> {
    if (this.busy) { return }
    const version: number = this.session.request()
    try {
      const choice = await this.getUIContext().getPromptAction().showDialog({ title: '删除商品',
        message: `确认删除「${goods.name}」？`, buttons: [{ text: '取消', color: COLORS.TEXT_SECONDARY }, { text: '删除', color: COLORS.ERROR }] })
      if (choice.index !== 1 || !this.session.current(version)) { return }
      this.busy = true
      const ok: boolean = await deleteMerchantGoodsApi(goods.id)
      if (!this.session.current(version)) { return }
      this.busy = false
      if (ok) { promptAction.showToast({ message: '商品已删除' }); this.load() }
    } catch (_) { if (this.session.current(version)) { this.busy = false } }
  }
  private async shelf(goods: GoodsItem): Promise<void> {
    if (this.busy) { return }
    const version: number = this.session.request()
    if (!this.session.current(version)) { return }
    this.busy = true
    const result: GoodsItem | null = await updateMerchantGoodsApi(goods, goods.isOnShelf === false)
    if (!this.session.current(version)) { return }
    this.busy = false
    if (result !== null) { promptAction.showToast({ message: result.isOnShelf === false ? '已下架' : '已上架' }); this.load() }
  }
  @Builder
  GoodsCard(goods: GoodsItem) {
    Column({ space: SPACING.SM }) {
      Row() {
        Text(goods.name).fontColor(COLORS.TEXT_PRIMARY).fontSize(FONT_SIZE.LG).layoutWeight(1)
        Text('¥' + goods.price.toFixed(2)).fontColor(COLORS.PRICE_RED)
      }.width('100%')
      Text((goods.isOnShelf === false ? '已下架 · ' : '') + '库存 ' + (goods.stock ?? 0))
        .fontColor(COLORS.TEXT_SECONDARY).width('100%')
      Flex({ wrap: FlexWrap.Wrap }) {
        Button('编辑').attributeModifier(new AppButtonStyle()).height(44).margin(SPACING.XS).enabled(!this.busy)
          .id(`merchant-goods-edit-${goods.id}`).onClick(() => { this.openGoods(goods, false) })
        Button('库存').attributeModifier(new AppButtonStyle()).height(44).margin(SPACING.XS).enabled(!this.busy)
          .id(`merchant-goods-stock-${goods.id}`).onClick(() => { this.openGoods(goods, true) })
        Button(goods.isOnShelf === false ? '上架' : '下架').attributeModifier(new AppButtonStyle()).height(44).margin(SPACING.XS)
          .enabled(!this.busy).onClick(() => { this.shelf(goods) })
        Button('删除').attributeModifier(new AppButtonStyle()).height(44).margin(SPACING.XS).fontColor(COLORS.ERROR)
          .enabled(!this.busy).onClick(() => { this.remove(goods) })
      }.width('100%')
    }.attributeModifier(new AppCardStyle()).width('100%').padding(SPACING.LG)
  }
  build() {
    Column() {
      PageHeader({ title: this.storeName === '' ? '商品管理' : this.storeName + ' · 商品管理', backId: 'merchant-goods-back',
        onBack: () => { router.back() }, actionLabel: '添加商品', actionEnabled: this.storeName !== '',
        onAction: () => { router.pushUrl({ url: 'pages/MerchantAddGoodsPage', params: { storeId: this.storeId } }) } })
      Scroll() {
        Column({ space: SPACING.MD }) {
          RemoteState({ loading: this.loading, failed: this.failed, hasData: this.goods.length > 0,
            emptyTitle: '暂无商品，点击右上角添加商品', onRetry: () => { this.load() } })
          ForEach(this.goods, (goods: GoodsItem) => { this.GoodsCard(goods) }, (goods: GoodsItem) => `${goods.id}:${goods.version ?? 0}:${goods.isOnShelf}`)
        }.width('100%').padding(SPACING.LG)
      }.layoutWeight(1).width('100%').align(Alignment.Top)
    }.width('100%').height('100%').backgroundColor(COLORS.BG_PRIMARY)
  }
}

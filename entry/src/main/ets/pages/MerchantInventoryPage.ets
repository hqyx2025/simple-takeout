import { User, createEmptyUser } from '../model/Models'
import { COLORS, SPACING, FONT_SIZE } from '../common/Constants'
import { AppButtonStyle } from '../common/theme/AppTheme'
import { PageHeader } from '../components/PageHeader'
import { FormInput } from '../components/FormInput'
import { FormSelect } from '../components/FormSelect'
import { RemoteState } from '../components/RemoteState'
import { routerCompat as router, promptCompat as promptAction } from '../common/UiNavigation'
import { GoodsItem, GoodsSpec, UserRole } from '../model/Models'
import { PageSession } from '../service/PageSession'
import { fetchMerchantGoodsResultApi, changeMerchantStockApi } from '../service/api/MerchantApi'

@Entry
@Component
struct MerchantInventoryPage {
  private session: PageSession = new PageSession()
  @StorageLink('user') @Watch('onSessionIdentityChange') currentUser: User = createEmptyUser()
  @StorageLink('isLoggedIn') @Watch('onSessionIdentityChange') authenticated: boolean = false

  @State goods: GoodsItem | null = null
  @State loading: boolean = true
  @State failed: boolean = false
  @State busy: boolean = false
  @State replenish: boolean = true
  @State amount: string = ''
  @State selection: number = 0
  @State options: SelectOption[] = []
  @State currentStock: number = 0
  @State outcome: string = ''
  private storeId: number = 0
  private goodsId: number = 0

  onSessionIdentityChange(): void {
    if (this.session.matchesIdentity()) { return }
    this.session.pause()
    this.goods = null; this.amount = ''
    router.replaceUrl({ url: 'pages/Index' })
  }

  aboutToAppear(): void {
    this.storeId = router.getParams()?.storeId ?? 0
    this.goodsId = router.getParams()?.goodsId ?? 0
    if (this.storeId <= 0 || this.goodsId <= 0 || !this.session.start(UserRole.MERCHANT)) { router.back(); return }
    this.load()
  }
  onPageShow(): void { if (this.goodsId > 0) { this.busy = false; this.load() } }
  onPageHide(): void { this.amount = ''; this.session.pause() }
  private applyGoods(goods: GoodsItem): void {
    const selectedId: number = (this.goods?.specs ?? [])[this.selection]?.id ?? 0
    this.goods = goods
    const specs: GoodsSpec[] = goods.specs ?? []
    this.selection = Math.max(0, specs.findIndex((spec: GoodsSpec) => spec.id === selectedId))
    this.options = specs.length > 0 ? specs.map((spec: GoodsSpec): SelectOption => ({ value: spec.name })) : [{ value: '商品库存' }]
    this.updateStock()
  }
  private updateStock(): void { this.currentStock = (this.goods?.specs ?? [])[this.selection]?.stock ?? this.goods?.stock ?? 0 }
  private async load(): Promise<void> {
    if (this.busy) { return }
    const version: number = this.session.request()
    this.loading = true; this.failed = false
    const list: GoodsItem[] | null = await fetchMerchantGoodsResultApi(this.storeId)
    if (!this.session.current(version)) { return }
    this.loading = false
    this.outcome = ''
    const goods: GoodsItem | undefined = list?.find((item: GoodsItem) => item.id === this.goodsId)
    if (goods === undefined) { this.failed = true; return }
    this.applyGoods(goods)
  }
  private async save(): Promise<void> {
    if (this.busy || this.loading || this.failed || this.goods === null) { return }
    const amount: number = Number(this.amount.trim())
    if (this.amount.trim() === '' || !Number.isInteger(amount) || amount < (this.replenish ? 1 : 0) || amount > 9999) {
      promptAction.showToast({ message: this.replenish ? '补货数量须为 1 到 9999 的整数' : '盘点数量须为 0 到 9999 的整数' }); return
    }
    const version: number = this.session.request()
    if (!this.session.current(version)) { return }
    const spec: GoodsSpec | undefined = (this.goods.specs ?? [])[this.selection]
    const previous: number = this.currentStock
    this.busy = true
    const updated: GoodsItem | null = await changeMerchantStockApi(this.goodsId, spec?.id ?? 0, amount,
      spec === undefined ? (this.goods.version ?? -1) : (spec.version ?? -1), this.replenish)
    if (!this.session.current(version)) { return }
    this.busy = false
    if (updated === null) {
      this.failed = true
      this.outcome = '操作结果未确认，请先刷新核对库存后再操作'
      return
    }
    this.applyGoods(updated)
    this.amount = ''
    this.outcome = `库存已更新：${previous} → ${this.currentStock}`
    promptAction.showToast({ message: this.replenish ? '补货成功' : '盘点已保存' })
  }
  build() {
    Column() {
      PageHeader({ title: (this.goods?.name ?? '商品') + ' · 库存', onBack: () => { router.back() }, actionLabel: '刷新库存',
        actionEnabled: !this.busy && !this.loading, onAction: () => { this.load() } })
      Scroll() {
        Column({ space: SPACING.MD }) {
          if (this.loading || this.failed) {
            RemoteState({ loading: this.loading, failed: this.failed, hasData: this.goods !== null,
              errorText: this.outcome, retryId: 'merchant-inventory-refresh', onRetry: () => { this.load() } })
          }
          Row({ space: SPACING.SM }) {
            Button(this.replenish ? '✓ 补货' : '补货').attributeModifier(new AppButtonStyle()).layoutWeight(1).height(44).id('merchant-inventory-replenish')
              .enabled(!this.busy).onClick(() => { this.replenish = true; this.amount = '' })
            Button(!this.replenish ? '✓ 盘点' : '盘点').attributeModifier(new AppButtonStyle()).layoutWeight(1).height(44).id('merchant-inventory-count')
              .enabled(!this.busy).onClick(() => { this.replenish = false; this.amount = '' })
          }.width('100%')
          FormSelect({ isEnabled: !this.busy && !this.loading && !this.failed, label: '库存对象', options: this.options, selected: this.selection, fieldId: 'merchant-inventory-spec',
            onSelect: (index: number) => { if (!this.busy) { this.selection = index; this.amount = ''; this.updateStock() } } })
          Text('当前库存：' + this.currentStock).fontSize(FONT_SIZE.LG).fontColor(COLORS.TEXT_PRIMARY)
          FormInput({ label: this.replenish ? '补货数量' : '盘点后的库存', value: this.amount, inputType: InputType.Number,
            placeholder: this.replenish ? '如：20，增加 20 份' : '如：20，将库存设为 20 份',
            fieldId: 'merchant-inventory-amount', isEnabled: !this.busy && !this.loading && !this.failed,
            onChange: (value: string) => { this.amount = value } })
          if (this.outcome !== '') { Text(this.outcome).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY) }
        }.width('100%').padding(SPACING.LG)
      }.layoutWeight(1).width('100%').align(Alignment.Top)
      Button(this.busy ? '提交中…' : this.replenish ? '确认补货' : '保存盘点').attributeModifier(new AppButtonStyle())
        .width('90%').height(48).margin(SPACING.MD).enabled(!this.busy && !this.loading && !this.failed && this.goods !== null)
        .id('merchant-inventory-submit').onClick(() => { this.save() })
    }.width('100%').height('100%').backgroundColor(COLORS.BG_PRIMARY)
  }
}

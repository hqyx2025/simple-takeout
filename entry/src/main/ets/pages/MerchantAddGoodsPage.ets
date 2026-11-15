import { getAuthSessionEpoch } from '../service/HttpClient'
import { RemoteState } from '../components/RemoteState'
import { FormDraftStore, StoredFormDraft, askToRestoreDraft, discardUnreadableDraft } from '../service/FormDraftStore'
import { fetchMerchantStoresResultApi, fetchMerchantCategoriesResultApi, fetchMerchantGoodsResultApi } from '../service/api/MerchantApi'
import { FormSelect } from '../components/FormSelect'
import { TagInput } from '../components/TagInput'
import { ImageUpload } from '../components/ImageUpload'
import { FormInput } from '../components/FormInput'
import { AppButtonStyle, AppCardStyle, AppInputStyle } from '../common/theme/AppTheme'
/** 商户新增商品页：表单确认后才写入数据库，并在返回前重新读取商品数据。 */
import { AppMotion } from '../common/theme/AppMotion'
import { Category, GoodsItem, GoodsSpec, StoreItem, User, UserRole } from '../model/Models'
import { createMerchantGoodsApi, fetchMerchantCategoriesApi, fetchMerchantGoodsApi, uploadImageApi } from '../service/ApiService'
import { getLastRemoteErrorMessage, updateGoodsSpecsRemote } from '../service/AppStorageManager'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS, merchantImageSource, DEFAULT_MERCHANT_IMAGE, MODULE_COLOR, MODULE_BG, accentBg, accentFg, accentIndexFromText } from '../common/Constants'
import { photoAccessHelper } from '@kit.MediaLibraryKit'
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { PageHeader } from '../components/PageHeader'

/** 多规格最多行数（超出时提示，不静默丢弃） */
const MAX_SPEC_ROWS: number = 5

/** 规格编辑行：输入用字符串保存，提交时再转换为数字（id=0 表示新增规格） */
class SpecRow {
  key: string = ''
  id: number = 0
  name: string = ''
  price: string = ''
  stock: string = ''

  constructor(key: string, id: number, name: string, price: string, stock: string) {
    this.key = key
    this.id = id
    this.name = name
    this.price = price
    this.stock = stock
  }
}

interface GoodsDraftSpec { id: number; name: string; price: string }

@Entry
@Component
export struct MerchantAddGoodsPage {
  pageTransition() {
    PageTransitionEnter(AppMotion.pageEnter(RouteType.Push))
      .translate({ x: AppMotion.distance(AppMotion.PAGE_OFFSET) })
      .opacity(0)
    PageTransitionExit(AppMotion.pageExit(RouteType.Push))
      .translate({ x: -AppMotion.distance(AppMotion.RETURN_OFFSET) })
      .opacity(0)
    PageTransitionEnter(AppMotion.pageEnter(RouteType.Pop))
      .translate({ x: -AppMotion.distance(AppMotion.RETURN_OFFSET) })
      .opacity(0)
    PageTransitionExit(AppMotion.pageExit(RouteType.Pop))
      .translate({ x: AppMotion.distance(AppMotion.PAGE_OFFSET) })
      .opacity(0)
  }

  @StorageLink('isLoggedIn') @Watch('onFormIdentityChange') loggedIn: boolean = false
  @StorageLink('user') @Watch('onFormIdentityChange') user: User = {
    id: 0, username: '未登录', avatar: '', phone: '', password: '', role: UserRole.CUSTOMER,
    balance: 0, coupons: [], orders: [], storeIds: []
  }
  @State storeId: number = 0
  @State categories: Category[] = []
  @State @Watch('onDraftChange') goodsName: string = ''
  @State @Watch('onDraftChange') goodsDescription: string = ''
  @State @Watch('onDraftChange') price: string = ''
  @State @Watch('onDraftChange') originalPrice: string = ''
  @State @Watch('onDraftChange') image: string = ''
  @State stock: string = '99'
  @State @Watch('onDraftChange') categoryId: number = 0
  @State @Watch('onDraftChange') isSpecial: boolean = false
  @State @Watch('onDraftChange') multiSpecEnabled: boolean = false
  @State specRows: SpecRow[] = []
  @State specStockTotal: number = 0
  @State submitting: boolean = false
  @State imageUploading: boolean = false
  @State @Watch('onDraftChange') originalTag: string = '新品'
  private pageActive: boolean = true
  private nextSpecKey: number = 1

  @State loadFailed: boolean = false
  @State storeName: string = ''
  @State draftError: string = ''
  private draft: FormDraftStore = new FormDraftStore()
  private draftInitialized: boolean = false
  private draftTimer: number = -1
  private formEpoch: number = -1
  private formOwner: number = 0

  onFormIdentityChange(): void {
    if (this.formOwner <= 0 || this.formOwner === undefined) { return }
    const user: User | undefined = AppStorage.get<User>('user')
    if (this.loggedIn && this.formOwner === user?.id && user?.role === UserRole.MERCHANT && this.formEpoch === getAuthSessionEpoch()) { return }
    this.pageActive = false
    clearTimeout(this.draftTimer)
    this.goodsName = ''; this.goodsDescription = ''; this.image = ''; this.specRows = []
    router.replaceUrl({ url: 'pages/Index' })
  }

  onBackPress(): boolean { return this.submitting || this.imageUploading }

  private formCurrent(): boolean {
    const user: User | undefined = AppStorage.get<User>('user')
    return this.pageActive && this.loggedIn && this.formEpoch === getAuthSessionEpoch()
      && user?.id === this.formOwner && user?.role === UserRole.MERCHANT
  }
  private draftFields(): Record<string, string> {
    const fields: Record<string, string> = {}
    fields['name'] = this.goodsName
    fields['description'] = this.goodsDescription
    fields['price'] = this.price
    fields['originalPrice'] = this.originalPrice
    fields['category'] = this.categoryId.toString()
    fields['special'] = this.isSpecial.toString()
    fields['image'] = this.image
    fields['tag'] = this.originalTag
    fields['multiSpec'] = this.multiSpecEnabled.toString()
    const specs: GoodsDraftSpec[] = this.specRows.map((row: SpecRow): GoodsDraftSpec => ({ id: row.id, name: row.name, price: row.price }))
    fields['specs'] = JSON.stringify(specs)
    return fields
  }
  private async initializeDraft(): Promise<void> {
    if (this.draftInitialized || !this.formCurrent()) { return }
    try {
      const saved: StoredFormDraft | null = await this.draft.open(`goods:${this.storeId}:create`, this.draftFields())
      if (!this.formCurrent()) { return }
      if (saved !== null) {
        const restore: boolean = await askToRestoreDraft(this.getUIContext(), saved)
        if (!this.formCurrent()) { return }
        if (restore) { this.applyDraft(saved.fields) }
        else if (!(await this.draft.clear())) { this.draftError = '草稿清理失败'; return }
      }
      this.draft.resume(this.draftFields())
      this.draftInitialized = true
    } catch (_) {
      if (!this.formCurrent()) { return }
      const discarded: boolean = await discardUnreadableDraft(this.getUIContext(), this.draft)
      if (!this.formCurrent()) { return }
      if (!discarded) { router.back(); return }
      this.draft.resume(this.draftFields())
      this.draftInitialized = true
    }
  }
  private applyDraft(fields: Record<string, string>): void {
    this.goodsName = fields['name'] ?? this.goodsName
    this.goodsDescription = fields['description'] ?? this.goodsDescription
    this.price = fields['price'] ?? this.price
    this.originalPrice = fields['originalPrice'] ?? this.originalPrice
    const category: number = Number(fields['category'] ?? '0')
    this.categoryId = this.categories.some((item: Category) => item.id === category) ? category : 0
    this.isSpecial = fields['special'] === 'true'
    const image: string = fields['image'] ?? ''
    if (image.startsWith('/uploads/')) { this.image = image }
    this.originalTag = fields['tag'] ?? this.originalTag
    this.multiSpecEnabled = fields['multiSpec'] === 'true'
    try {
      const saved: GoodsDraftSpec[] = JSON.parse(fields['specs'] ?? '[]') as GoodsDraftSpec[]
      if (Array.isArray(saved)) {
        const rows: SpecRow[] = []
        saved.slice(0, MAX_SPEC_ROWS).forEach((row: GoodsDraftSpec) => {
          if (typeof row.name !== 'string' || typeof row.price !== 'string' || !Number.isInteger(row.id) || row.id < 0) { return }
          const existing: SpecRow | undefined = this.specRows.find((item: SpecRow) => item.id === row.id && row.id > 0)
          if (row.id > 0 && existing === undefined) { return }
          rows.push(new SpecRow(`spec-${this.nextSpecKey++}`, row.id, row.name, row.price, existing?.stock ?? '0'))
        })
        this.specRows = rows
        this.refreshSpecStockTotal()
      }
    } catch (_) { this.draftError = '规格草稿无效，已保留服务端规格' }
  }
  onDraftChange(): void {
    if (!this.draftInitialized || !this.formCurrent()) { return }
    clearTimeout(this.draftTimer)
    this.draftTimer = setTimeout(() => { this.saveDraft() }, 400)
  }
  private async saveDraft(): Promise<void> {
    if (!(await this.draft.save(this.draftFields()))) { this.draftError = '草稿保存失败，请勿关闭页面'; promptAction.showToast({ message: this.draftError }) }
  }
  private async clearDraft(): Promise<void> {
    clearTimeout(this.draftTimer)
    if (!(await this.draft.clear())) { promptAction.showToast({ message: '商品已保存，旧草稿清理失败' }) }
  }

  async aboutToAppear(): Promise<void> {
    this.pageActive = true
    this.formEpoch = getAuthSessionEpoch()
    this.formOwner = this.user.id
    if (!this.loggedIn || this.user.role !== UserRole.MERCHANT) {
      promptAction.showToast({ message: '请使用商户账号登录后添加商品', duration: 1800 })
      router.back()
      return
    }
    this.storeId = router.getParams()?.storeId ?? 0
    if (this.storeId <= 0) {
      promptAction.showToast({ message: '未找到要添加商品的店铺', duration: 1800 })
      router.back()
      return
    }
    const stores: StoreItem[] | null = await fetchMerchantStoresResultApi()
    if (!this.formCurrent()) { return }
    const store: StoreItem | undefined = stores?.find((item: StoreItem) => item.id === this.storeId)
    if (store === undefined) { this.loadFailed = true; return }
    this.storeName = store.name
    const categories: Category[] | null = await fetchMerchantCategoriesResultApi()
    if (!this.formCurrent()) { return }
    if (categories === null) { this.loadFailed = true; return }
    this.categories = categories
    this.loadFailed = false
    await this.initializeDraft()
  }

  onPageHide(): void { clearTimeout(this.draftTimer); this.saveDraft(); this.pageActive = false }
  onPageShow(): void { this.pageActive = true }
  aboutToDisappear(): void { this.onPageHide() }

  private selectCategory(id: number): void {
    this.categoryId = id
  }

  private parsePrice(value: string): number {
    const parsed: number = Number(value.trim())
    return Number.isFinite(parsed) ? parsed : 0
  }

  private parseStock(value: string): number {
    const parsed: number = Number(value.trim())
    return Number.isFinite(parsed) && Number.isInteger(parsed) ? parsed : -1
  }

  /** 接口失败时优先展示后端/网络层给出的具体原因 */
  private failureReason(fallback: string): string {
    const reason: string = getLastRemoteErrorMessage().trim()
    return reason !== '' ? reason : fallback
  }

  // ============ 多规格 ============

  private toggleSpecs(enabled: boolean): void {
    this.multiSpecEnabled = enabled
    if (enabled) {
      if (this.specRows.length === 0) {
        this.addSpecRow()
      }
      return
    }
    if (this.specRows.length > 0) {
      this.specRows = []
      this.refreshSpecStockTotal()
      promptAction.showToast({ message: '已关闭多规格，商品将按统一的单价与库存售卖', duration: 2400 })
    }
  }

  private addSpecRow(): void {
    if (this.specRows.length >= MAX_SPEC_ROWS) {
      promptAction.showToast({ message: `最多只能配置 ${MAX_SPEC_ROWS} 条规格`, duration: 2000 })
      return
    }
    const rows: SpecRow[] = this.specRows.slice()
    rows.push(new SpecRow(`spec-${this.nextSpecKey}`, 0, '', '', ''))
    this.nextSpecKey += 1
    this.specRows = rows
    this.refreshSpecStockTotal()
    this.onDraftChange()
  }

  private removeSpecRow(index: number): void {
    const target: SpecRow | undefined = this.specRows[index]
    if (target === undefined) {
      return
    }
    const rows: SpecRow[] = this.specRows.filter((row: SpecRow) => row.key !== target.key)
    this.specRows = rows
    this.refreshSpecStockTotal()
    this.onDraftChange()
    if (rows.length === 0) {
      promptAction.showToast({ message: '规格已清空，提交后该商品没有规格', duration: 2000 })
    }
  }

  private computeSpecStockTotal(): number {
    let total: number = 0
    this.specRows.forEach((row: SpecRow) => {
      const stock: number = this.parseStock(row.stock)
      if (stock > 0) {
        total += stock
      }
    })
    return total
  }

  private refreshSpecStockTotal(): void {
    this.specStockTotal = this.computeSpecStockTotal()
  }

  // 规格行输入统一按行号写回，避免在 @Builder 内部修改参数对象
  private setSpecName(index: number, value: string): void {
    const row: SpecRow | undefined = this.specRows[index]
    if (row !== undefined) {
      row.name = value
      this.onDraftChange()
    }
  }

  private setSpecPrice(index: number, value: string): void {
    const row: SpecRow | undefined = this.specRows[index]
    if (row !== undefined) {
      row.price = value
      this.onDraftChange()
    }
  }

  private setSpecStock(index: number, value: string): void {
    const row: SpecRow | undefined = this.specRows[index]
    if (row !== undefined) {
      row.stock = value
      this.refreshSpecStockTotal()
    }
  }

  /** 多规格时库存字段的说明文案（无规格时返回空串，不显示提示） */
  private specStockHint(): string {
    if (!this.multiSpecEnabled || this.specRows.length === 0) {
      return ''
    }
    return `库存由各规格合计（${this.specStockTotal} 份）`
  }

  /** 校验规格行，返回第一条错误提示；空串表示全部合法 */
  private validateSpecRows(): string {
    const rows: SpecRow[] = this.specRows
    for (let i = 0; i < rows.length; i++) {
      const row: SpecRow = rows[i]
      const name: string = row.name.trim()
      if (name === '') {
        return `第 ${i + 1} 行的规格名称为空，请填写，如：大份`
      }
      const price: number = this.parsePrice(row.price)
      if (row.price.trim() === '' || price <= 0 || price > 9999.99) {
        return `第 ${i + 1} 行「${name}」的价格必须为 0.01-9999.99 元`
      }
      const stock: number = this.parseStock(row.stock)
      if (row.stock.trim() === '' || stock < 0 || stock > 9999) {
        return `第 ${i + 1} 行「${name}」的库存必须是 0-9999 的整数（0 表示售罄）`
      }
      for (let j = 0; j < i; j++) {
        if (rows[j].name.trim() === name) {
          return `第 ${i + 1} 行与第 ${j + 1} 行的规格名称重复：${name}`
        }
      }
    }
    return ''
  }

  /** 把规格行转换为接口参数（goodsId 在商品创建成功后才可知） */
  private buildSpecs(goodsId: number): GoodsSpec[] {
    const specs: GoodsSpec[] = []
    this.specRows.forEach((row: SpecRow) => {
      const spec: GoodsSpec = {
        id: row.id,
        goodsId: goodsId,
        name: row.name.trim(),
        price: this.parsePrice(row.price),
        stock: this.parseStock(row.stock)
      }
      specs.push(spec)
    })
    return specs
  }

  private async confirmAdd(): Promise<void> {
    if (!this.formCurrent() || this.loadFailed || this.submitting || this.imageUploading) {
      promptAction.showToast({ message: '提交中，请稍候', duration: 1400 })
      return
    }
    const name: string = this.goodsName.trim()
    const price: number = this.parsePrice(this.price)
    const originalPrice: number = this.originalPrice.trim() === '' ? price : this.parsePrice(this.originalPrice)
    const stock: number = this.parseStock(this.stock)
    if (name === '') {
      promptAction.showToast({ message: '请输入商品名称' })
      return
    }
    if (price <= 0 || price > 9999.99) {
      promptAction.showToast({ message: '价格必须在 0.01 到 9999.99 元之间' })
      return
    }
    if (stock < 0 || stock > 9999) {
      promptAction.showToast({ message: '库存必须是 0 到 9999 的整数' })
      return
    }
    if (this.isSpecial && originalPrice <= price) {
      promptAction.showToast({ message: '特价商品原价必须高于特价价' })
      return
    }
    // 规格行校验放在提交前，明确指出第几行有问题，避免后端报错后用户无从下手
    if (this.multiSpecEnabled && this.specRows.length > 0) {
      const specError: string = this.validateSpecRows()
      if (specError !== '') {
        promptAction.showToast({ message: specError, duration: 2800 })
        return
      }
    }
    const goods: GoodsItem = {
      id: 0,
      name: name,
      description: this.goodsDescription.trim() || '美味可口',
      price: price,
      originalPrice: originalPrice,
      image: this.image,
      categoryId: 1,
      merchantCategoryId: this.categoryId,
      stock: stock,
      sales: 0,
      rating: 5.0,
      tag: this.originalTag,
      isOnShelf: true,
      isSpecial: this.isSpecial
    }
    this.submitting = true
    promptAction.showToast({ message: '提交中...', duration: 1200 })
    const created: GoodsItem | null = await createMerchantGoodsApi(this.storeId, goods)
    if (!this.formCurrent()) { return }
    if (created === null) {
      this.submitting = false
      promptAction.showToast({ message: `商品添加失败：${this.failureReason('请检查网络后重试')}`, duration: 2800 })
      return
    }
    await this.clearDraft()
    if (!this.formCurrent()) { return }
    // 规格需在拿到商品 id 后整体覆盖提交；创建成功但规格失败时商品不会丢失，提示到编辑页重试
    if (this.multiSpecEnabled && this.specRows.length > 0) {
      const specs: GoodsSpec[] = this.buildSpecs(created.id)
      const specSaved: GoodsItem | null = await updateGoodsSpecsRemote(created.id, specs)
      if (!this.formCurrent()) { return }
      if (specSaved === null) {
        this.submitting = false
        promptAction.showToast({
          message: `商品已创建，但规格保存失败，请到编辑页重试：${this.failureReason('请检查网络')}`,
          duration: 3200
        })
        router.replaceUrl({ url: 'pages/MerchantEditGoodsPage', params: { storeId: this.storeId, goodsId: created.id } })
        return
      }
    }
    // 确认接口成功后再读一次数据库，避免返回列表使用旧数据。
    const latestGoods: GoodsItem[] = await fetchMerchantGoodsApi(this.storeId)
    if (!this.formCurrent()) { return }
    this.submitting = false
    if (latestGoods.find((item: GoodsItem) => item.id === created.id) === undefined) {
      promptAction.showToast({ message: '商品已创建，进入编辑页核对最新信息', duration: 2600 })
      router.replaceUrl({ url: 'pages/MerchantEditGoodsPage', params: { storeId: this.storeId, goodsId: created.id } })
      return
    }
    await this.clearDraft()
    promptAction.showToast({ message: '商品添加成功，列表已刷新' })
    router.back()
  }

  @Builder
  CategoryOptions() {
    FormSelect({ label: '店内分类', options: this.categoryOptions(),
      selected: this.categories.findIndex((item: Category) => item.id === this.categoryId) + 1,
      fieldId: 'merchant-goods-category', onSelect: (index: number) => { this.selectCategory(index === 0 ? 0 : this.categories[index - 1].id) } })
  }

  private categoryOptions(): SelectOption[] {
    const options: SelectOption[] = [{ value: '未分组' }]
    return options.concat(this.categories.map((item: Category): SelectOption => { return { value: item.name } }))
  }

  @Builder
  FieldLabel(text: string, required: boolean) {
    Row() {
      Text(text)
        .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
      if (required) {
        Text(' *').fontSize(FONT_SIZE.SM).fontColor(COLORS.ERROR)
      }
    }
    .width('100%')
  }

  @Builder
  NumberField(label: string, placeholder: string, value: string, hint: string, onChange: (value: string) => void) {
    Column({ space: SPACING.XS }) {

      FormInput({ label: label,
        value: value,
        placeholder: placeholder,
        inputType: label === '库存' ? InputType.Number : InputType.NUMBER_DECIMAL,
        onChange: (next: string) => { onChange(next) },
        fieldId: 'MerchantAddGoodsPage-value-' + label,
        required: true }).width('100%')
      if (hint !== '') {
        Text(hint)
          .fontSize(FONT_SIZE.XS).fontColor(MODULE_COLOR.MERCHANT)
      }
    }
    .layoutWeight(1)
  }

  /** 规格编辑行：规格名 + 价格 + 库存 + 行尾删除按钮 */
  @Builder
  SpecRowEditor(row: SpecRow, index: number) {
    Row({ space: SPACING.XS }) {
      Column() {
        Text((index + 1).toString())
          .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_SECONDARY)
      }
      .width(18).height(40)
      .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)

      FormInput({ label: '规格名称',
        value: row.name,
        placeholder: '如：大份/加辣',
        onChange: (value: string) => { this.setSpecName(index, value) },
        fieldId: 'MerchantAddGoodsPage-row-name' + '-' + index,
        required: true }).layoutWeight(1)

      FormInput({ label: '价格',
        value: row.price,
        placeholder: '价格',
        inputType: InputType.NUMBER_DECIMAL,
        onChange: (value: string) => { this.setSpecPrice(index, value) },
        fieldId: 'MerchantAddGoodsPage-row-price' + '-' + index,
        required: true }).width(62)

      FormInput({ label: '库存',
        value: row.stock,
        placeholder: '库存',
        inputType: InputType.Number,
        onChange: (value: string) => { this.setSpecStock(index, value) },
        fieldId: 'MerchantAddGoodsPage-row-stock' + '-' + index,
        required: true }).width(62)

      Column() {
        Image($r('app.media.ui_close')).width(FONT_SIZE.SM).height(FONT_SIZE.SM).objectFit(ImageFit.Contain)
      }
      .width(30).height(40)
      .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      .backgroundColor(COLORS.ERROR_LIGHT).borderRadius(BORDER_RADIUS.SM)
      .onClick(() => { this.removeSpecRow(index) })
    }
    .width('100%')
    .padding(SPACING.SM)
    .backgroundColor(COLORS.BG_PRIMARY)
    .borderRadius(BORDER_RADIUS.MD)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  SpecSection() {
    Column({ space: SPACING.SM }) {
      Row() {
        Image($r('app.media.ui_document')).objectFit(ImageFit.Contain)
          .width(28).height(28)
          .backgroundColor(accentBg(2))
          .borderRadius(BORDER_RADIUS.SM)
        Column({ space: SPACING.XS }) {
          Text('多规格')
            .fontSize(FONT_SIZE.MD).fontColor(accentFg(2))
          Text('如：大份/小份、加辣')
            .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT)
        }
        .layoutWeight(1).alignItems(HorizontalAlign.Start)
        Toggle({ type: ToggleType.Switch, isOn: this.multiSpecEnabled })
          .onChange((value: boolean) => { this.toggleSpecs(value) })
      }
      .width('100%').alignItems(VerticalAlign.Center)

      Text('每种规格分别设置售价和库存。')
        .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT).width('100%')

      if (this.multiSpecEnabled) {
        if (this.specRows.length === 0) {
          Text('暂无规格行，点击下方「＋ 添加规格」新增')
            .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT).width('100%')
        }
        ForEach(this.specRows, (row: SpecRow, index: number) => {
          this.SpecRowEditor(row, index)
        }, (row: SpecRow, index: number) => `${row.key}-${index}`)
        Button(`＋ 添加规格（${this.specRows.length}/${MAX_SPEC_ROWS}）`)
          .attributeModifier(new AppButtonStyle())
          .width('100%').height(40).fontSize(FONT_SIZE.SM)
          .fontColor(MODULE_COLOR.MERCHANT).backgroundColor(MODULE_BG.MERCHANT)
          .borderRadius(BORDER_RADIUS.MD)
          .onClick(() => { this.addSpecRow() })
        Text('规格名称不可重复；价格为 0.01-9999.99 元，库存为 0-9999 的整数（0 表示售罄）。')
          .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT).width('100%')
      }
    }
    .width('100%')
  }

  build() {
    Column() {
      PageHeader({ title: this.storeName === '' ? '添加商品' : this.storeName + ' · 添加商品', backText: '‹ 返回', backId: 'merchant-add-goods-back', titleColor: COLORS.TEXT_PRIMARY, headerBgColor: COLORS.BG_PRIMARY, onBack: () => { if (!this.submitting && !this.imageUploading) { router.back() } } })

      if (this.draftError !== '') { Text(this.draftError).fontColor(COLORS.ERROR).fontSize(FONT_SIZE.SM) }
      if (this.loadFailed) { RemoteState({ failed: true, onRetry: () => { this.aboutToAppear() } }) }
      else {
      Scroll() {
        Column({ space: SPACING.MD }) {

          Column({ space: SPACING.MD }) {
            Row() {
              Image($r('app.media.ui_document')).objectFit(ImageFit.Contain)
                .width(28).height(28)
                .backgroundColor(accentBg(1))
                .borderRadius(BORDER_RADIUS.SM)
              Text('基本信息')
                .fontSize(FONT_SIZE.LG).fontWeight(FontWeight.Bold)
                .fontColor(accentFg(1)).margin({ left: SPACING.SM })
            }
            .width('100%')
            Column({ space: SPACING.XS }) {

              FormInput({ label: '商品名称',
                value: this.goodsName,
                placeholder: '如：宫保鸡丁',
                fieldId: 'merchant-goods-name',
                onChange: (value: string) => { this.goodsName = value },
                required: true }).width('100%')
            }
            Column({ space: SPACING.XS }) {

              FormInput({ label: '商品描述',
                value: this.goodsDescription,
                placeholder: '如：招牌菜，微辣',
                fieldId: 'merchant-goods-description',
                onChange: (value: string) => { this.goodsDescription = value } }).width('100%')
            }
            Row({ space: SPACING.MD }) {
              this.NumberField('售价', '如：25.00', this.price, '', (value: string) => { this.price = value })
              this.NumberField('库存', '0-9999', this.stock, this.specStockHint(), (value: string) => { this.stock = value })
            }
            Column({ space: SPACING.XS }) {

              FormInput({ label: '原价（元）',
                value: this.originalPrice,
                placeholder: '特价时填写，如：30.00',
                inputType: InputType.NUMBER_DECIMAL,
                fieldId: 'merchant-goods-original-price',
                onChange: (value: string) => { this.originalPrice = value } }).width('100%')
            }
            Column({ space: SPACING.XS }) {
              this.FieldLabel('商品图片', false)
              ImageUpload({ images: this.image ? [this.image] : [], maxFiles: 1, disabled: this.submitting,
                onChange: (images: string[]) => { this.image = images[0] ?? '' },
                onBusy: (busy: boolean) => { this.imageUploading = busy } })
              TagInput({ value: this.originalTag, isEnabled: !this.submitting, onChange: (value: string) => { this.originalTag = value } })
            }
            Row() {
              Text('加入特价团购')
                .fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_PRIMARY)
              Blank()
              Toggle({ type: ToggleType.Switch, isOn: this.isSpecial })
                .onChange((value: boolean) => { this.isSpecial = value })
            }
            .width('100%')
            Column({ space: SPACING.XS }) {
              this.FieldLabel('店内分类', false)
              this.CategoryOptions()
            }
          }
            .attributeModifier(new AppCardStyle())
          .width('100%').padding(SPACING.LG)

          Column() {
            this.SpecSection()
          }
            .attributeModifier(new AppCardStyle())
          .width('100%').padding(SPACING.LG)
        }
        .width('100%')
        .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.MD, bottom: SPACING.XL })
      }.align(Alignment.Top)
      .layoutWeight(1).scrollBar(BarState.Off)

      }

      Row({ space: SPACING.MD }) {
        Button('取消').id('merchant-goods-cancel')
          .attributeModifier(new AppButtonStyle())
          .layoutWeight(1).height(46).fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_SECONDARY).backgroundColor(COLORS.BG_PRIMARY)
          .borderRadius(BORDER_RADIUS.ROUND)
          .enabled(!this.submitting && !this.imageUploading).onClick(() => { router.back() })
        Button(this.submitting ? '提交中...' : '确认添加').id('merchant-goods-submit').enabled(!this.loadFailed && !this.submitting)
          .attributeModifier(new AppButtonStyle())
          .layoutWeight(1).height(46).fontSize(FONT_SIZE.MD).fontColor(COLORS.ON_PRIMARY).backgroundColor(MODULE_COLOR.MERCHANT)
          .borderRadius(BORDER_RADIUS.ROUND)
          .onClick(() => { this.confirmAdd() })
      }
      .width('100%').padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.SM, bottom: SPACING.LG })
      .backgroundColor(COLORS.BG_WHITE)
    }
    .width('100%').height('100%').backgroundColor(COLORS.BG_PRIMARY)
  }
}

/** 商户编辑商品页：打开和保存均以数据库返回数据为准。 */
import { Category, GoodsItem, GoodsSpec, User, UserRole } from '../model/Models'
import { fetchMerchantCategoriesApi, fetchMerchantGoodsApi, updateMerchantGoodsApi, uploadImageApi } from '../service/ApiService'
import { getLastRemoteErrorMessage, updateGoodsSpecsRemote } from '../service/AppStorageManager'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS, merchantImageSource, DEFAULT_MERCHANT_IMAGE } from '../common/Constants'
import { photoAccessHelper } from '@kit.MediaLibraryKit'
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'

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

@Entry
@Component
export struct MerchantEditGoodsPage {
  @StorageLink('isLoggedIn') loggedIn: boolean = false
  @StorageLink('user') user: User = {
    id: 0, username: '未登录', avatar: '', phone: '', password: '', role: UserRole.CUSTOMER,
    balance: 0, coupons: [], orders: [], storeIds: []
  }
  @State storeId: number = 0
  @State goodsId: number = 0
  @State categories: Category[] = []
  @State goodsName: string = ''
  @State goodsDescription: string = ''
  @State price: string = ''
  @State originalPrice: string = ''
  @State stock: string = '99'
  @State categoryId: number = 0
  @State isSpecial: boolean = false
  @State isOnShelf: boolean = true
  @State image: string = ''
  @State platformCategoryId: number = 1
  @State sales: number = 0
  @State rating: number = 4.5
  @State originalTag: string = ''
  @State originalSpecCount: number = 0
  @State multiSpecEnabled: boolean = false
  @State specRows: SpecRow[] = []
  @State specStockTotal: number = 0
  @State loading: boolean = true
  @State submitting: boolean = false
  private nextSpecKey: number = 1

  async aboutToAppear(): Promise<void> {
    if (!this.loggedIn || this.user.role !== UserRole.MERCHANT) {
      promptAction.showToast({ message: '请使用商户账号登录后编辑商品', duration: 1800 })
      router.back()
      return
    }
    this.storeId = AppStorage.get<number>('merchantGoodsStoreId') || 0
    this.goodsId = AppStorage.get<number>('merchantEditGoodsId') || 0
    if (this.storeId <= 0 || this.goodsId <= 0) {
      promptAction.showToast({ message: '商品信息暂不可用，请返回后重试', duration: 1800 })
      router.back()
      return
    }
    await this.loadGoods()
  }

  private async loadGoods(): Promise<void> {
    this.loading = true
    const categories: Category[] = await fetchMerchantCategoriesApi()
    const goodsList: GoodsItem[] = await fetchMerchantGoodsApi(this.storeId)
    const goods: GoodsItem | undefined = goodsList.find((item: GoodsItem) => item.id === this.goodsId)
    if (goods === undefined) {
      this.loading = false
      promptAction.showToast({ message: '商品不存在或已被删除，请刷新列表', duration: 2200 })
      router.back()
      return
    }
    this.categories = categories
    this.goodsName = goods.name
    this.goodsDescription = goods.description
    this.price = goods.price.toString()
    this.originalPrice = (goods.originalPrice ?? goods.price).toString()
    this.stock = (goods.stock ?? 0).toString()
    this.categoryId = goods.merchantCategoryId ?? 0
    this.isSpecial = goods.isSpecial === true
    this.isOnShelf = goods.isOnShelf !== false
    this.image = goods.image
    this.platformCategoryId = goods.categoryId
    this.sales = goods.sales
    this.rating = goods.rating
    this.originalTag = goods.tag ?? ''
    this.initSpecRows(goods)
    this.loading = false
  }

  /** 用商品已有规格初始化规格行（specs 可能为 undefined） */
  private initSpecRows(goods: GoodsItem): void {
    const specs: GoodsSpec[] = goods.specs !== undefined && Array.isArray(goods.specs) ? goods.specs : []
    this.originalSpecCount = specs.length
    const rows: SpecRow[] = []
    specs.forEach((spec: GoodsSpec) => {
      rows.push(new SpecRow(
        `spec-${this.nextSpecKey}`,
        spec.id,
        spec.name,
        spec.price.toString(),
        spec.stock.toString()
      ))
      this.nextSpecKey += 1
    })
    this.multiSpecEnabled = rows.length > 0
    this.specRows = rows
    this.refreshSpecStockTotal()
  }

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
      promptAction.showToast({
        message: this.originalSpecCount > 0
          ? '已关闭多规格，保存后将清空该菜品的全部规格'
          : '已关闭多规格，商品将按统一的单价与库存售卖',
        duration: 2600
      })
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
  }

  private removeSpecRow(index: number): void {
    const target: SpecRow | undefined = this.specRows[index]
    if (target === undefined) {
      return
    }
    const rows: SpecRow[] = this.specRows.filter((row: SpecRow) => row.key !== target.key)
    this.specRows = rows
    this.refreshSpecStockTotal()
    if (rows.length === 0) {
      promptAction.showToast({
        message: this.originalSpecCount > 0
          ? '规格已全部删除，保存后将清空该菜品的规格'
          : '规格已清空，保存后该商品没有规格',
        duration: 2600
      })
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
    }
  }

  private setSpecPrice(index: number, value: string): void {
    const row: SpecRow | undefined = this.specRows[index]
    if (row !== undefined) {
      row.price = value
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

  /** 把规格行转换为接口参数（整体覆盖，空数组表示清空规格） */
  private buildSpecs(): GoodsSpec[] {
    const specs: GoodsSpec[] = []
    this.specRows.forEach((row: SpecRow) => {
      const spec: GoodsSpec = {
        id: row.id,
        goodsId: this.goodsId,
        name: row.name.trim(),
        price: this.parsePrice(row.price),
        stock: this.parseStock(row.stock)
      }
      specs.push(spec)
    })
    return specs
  }

  private async confirmEdit(): Promise<void> {
    if (this.submitting) {
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
    const updatedGoods: GoodsItem = {
      id: this.goodsId,
      storeId: this.storeId,
      name: name,
      description: this.goodsDescription.trim() || '美味可口',
      price: price,
      originalPrice: originalPrice,
      image: this.image,
      categoryId: this.platformCategoryId,
      merchantCategoryId: this.categoryId,
      stock: stock,
      sales: this.sales,
      rating: this.rating,
      tag: this.isSpecial ? '特价团购' : (this.originalTag === '特价团购' ? '' : this.originalTag),
      isOnShelf: this.isOnShelf,
      isSpecial: this.isSpecial
    }
    this.submitting = true
    promptAction.showToast({ message: '提交中...', duration: 1200 })
    // 规格整体覆盖：行被清空时传空数组即清空规格；原本没有规格且未新增时跳过该请求
    const specs: GoodsSpec[] = this.multiSpecEnabled ? this.buildSpecs() : []
    const needSpecSave: boolean = specs.length > 0 || this.originalSpecCount > 0
    if (needSpecSave) {
      const specSaved: GoodsItem | null = await updateGoodsSpecsRemote(this.goodsId, specs)
      if (specSaved === null) {
        this.submitting = false
        promptAction.showToast({ message: `规格保存失败：${this.failureReason('请检查网络后重试')}`, duration: 2800 })
        return
      }
    }
    const updated: GoodsItem | null = await updateMerchantGoodsApi(updatedGoods, this.isOnShelf)
    if (updated === null) {
      this.submitting = false
      promptAction.showToast({
        message: needSpecSave
          ? `规格已保存，但商品信息保存失败：${this.failureReason('请检查网络后重试')}`
          : `商品信息保存失败：${this.failureReason('请检查网络后重试')}`,
        duration: 3000
      })
      return
    }
    const latestGoods: GoodsItem[] = await fetchMerchantGoodsApi(this.storeId)
    this.submitting = false
    if (latestGoods.find((item: GoodsItem) => item.id === this.goodsId) === undefined) {
      promptAction.showToast({ message: '商品已保存，但刷新数据失败，请返回后重试', duration: 2600 })
      return
    }
    promptAction.showToast({ message: '商品保存成功，列表已刷新', duration: 1800 })
    router.back()
  }

  @Builder
  CategoryOptions() {
    Scroll() {
      Row({ space: SPACING.SM }) {
        Text('未分组')
          .fontSize(FONT_SIZE.SM)
          .fontColor(this.categoryId === 0 ? COLORS.TEXT_WHITE : COLORS.TEXT_SECONDARY)
          .backgroundColor(this.categoryId === 0 ? COLORS.PRIMARY : COLORS.BG_PRIMARY)
          .padding({ left: SPACING.MD, right: SPACING.MD, top: SPACING.SM, bottom: SPACING.SM })
          .borderRadius(BORDER_RADIUS.ROUND)
          .onClick(() => { this.selectCategory(0) })
        ForEach(this.categories, (category: Category) => {
          Text(category.name)
            .fontSize(FONT_SIZE.SM)
            .fontColor(this.categoryId === category.id ? COLORS.TEXT_WHITE : COLORS.TEXT_SECONDARY)
            .backgroundColor(this.categoryId === category.id ? COLORS.PRIMARY : COLORS.BG_PRIMARY)
            .padding({ left: SPACING.MD, right: SPACING.MD, top: SPACING.SM, bottom: SPACING.SM })
            .borderRadius(BORDER_RADIUS.ROUND)
            .onClick(() => { this.selectCategory(category.id) })
        }, (category: Category) => category.id.toString())
      }
      .padding({ left: SPACING.XS, right: SPACING.LG })
    }
    .width('100%').height(44)
    .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
  }

  @Builder
  FieldLabel(text: string, required: boolean) {
    Row() {
      Text(text).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
      if (required) {
        Text(' *').fontSize(FONT_SIZE.SM).fontColor(COLORS.ERROR)
      }
    }
    .width('100%')
  }

  @Builder
  NumberField(label: string, placeholder: string, value: string, hint: string, onChange: (value: string) => void) {
    Column({ space: SPACING.XS }) {
      this.FieldLabel(label, true)
      TextInput({ placeholder: placeholder, text: value })
        .width('100%').height(44).type(InputType.Number)
        .onChange((next: string) => { onChange(next) })
      if (hint !== '') {
        Text(hint)
          .fontSize(FONT_SIZE.XS).fontColor(COLORS.PRIMARY)
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

      TextInput({ placeholder: '如：大份/加辣', text: row.name })
        .layoutWeight(1).height(40).fontSize(FONT_SIZE.SM)
        .onChange((value: string) => { this.setSpecName(index, value) })

      TextInput({ placeholder: '价格', text: row.price })
        .width(62).height(40).fontSize(FONT_SIZE.SM).type(InputType.Number)
        .onChange((value: string) => { this.setSpecPrice(index, value) })

      TextInput({ placeholder: '库存', text: row.stock })
        .width(62).height(40).fontSize(FONT_SIZE.SM).type(InputType.Number)
        .onChange((value: string) => { this.setSpecStock(index, value) })

      Column() {
        Text('✕')
          .fontSize(FONT_SIZE.SM).fontColor(COLORS.ERROR)
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
        Column({ space: SPACING.XS }) {
          Text('多规格')
            .fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_PRIMARY)
          Text('如：大份/小份、加辣')
            .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT)
        }
        .layoutWeight(1).alignItems(HorizontalAlign.Start)
        Toggle({ type: ToggleType.Switch, isOn: this.multiSpecEnabled })
          .onChange((value: boolean) => { this.toggleSpecs(value) })
      }
      .width('100%').alignItems(VerticalAlign.Center)

      Text('配置规格后，菜品价格与库存分别按规格单独计算（菜品价取规格最低价、库存为规格合计）；多规格菜品下单时必须选择规格。')
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
          .width('100%').height(40).fontSize(FONT_SIZE.SM)
          .fontColor(COLORS.PRIMARY).backgroundColor(COLORS.TAG_BG)
          .borderRadius(BORDER_RADIUS.MD)
          .onClick(() => { this.addSpecRow() })
        Text(this.originalSpecCount > 0
          ? '规格名称不可重复；删除全部规格行并保存会清空该菜品的规格。'
          : '规格名称不可重复；价格为 0.01-9999.99 元，库存为 0-9999 的整数（0 表示售罄）。')
          .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT).width('100%')
      }
    }
    .width('100%')
  }

  /** 选择并上传商品图片：成功后写入 this.image（相对 /uploads/ 地址）。 */
  private async pickImage(): Promise<void> {
    try {
      const picker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker()
      const options: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions()
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE
      options.maxSelectNumber = 1
      const result: photoAccessHelper.PhotoSelectResult = await picker.select(options)
      if (!result.photoUris || result.photoUris.length === 0) {
        return
      }
      const uploaded = await uploadImageApi(result.photoUris[0], false)
      if (uploaded !== null && uploaded.url !== '') {
        this.image = uploaded.url
        promptAction.showToast({ message: '图片已上传', duration: 1500 })
      } else {
        promptAction.showToast({ message: '图片上传失败，请重试', duration: 2200 })
      }
    } catch (err) {
      promptAction.showToast({ message: '选择图片失败，请重试', duration: 2200 })
    }
  }

  @Builder
  FormContent() {
    Scroll() {
      Column({ space: SPACING.MD }) {
        Column({ space: SPACING.SM }) {
          Text('确认保存后将写入数据库，并刷新商品管理列表')
            .fontSize(FONT_SIZE.SM).fontColor(COLORS.PRIMARY)
          Text('商品名称、价格和库存会进行范围校验；店内分类只能选择数据库中已有分类。')
            .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT)
        }
        .width('100%').padding(SPACING.MD)
        .backgroundColor(COLORS.TAG_BG).borderRadius(BORDER_RADIUS.MD)

        Column({ space: SPACING.MD }) {
          Column({ space: SPACING.XS }) {
            this.FieldLabel('商品名称', true)
            TextInput({ placeholder: '如：宫保鸡丁', text: this.goodsName })
              .width('100%').height(44)
              .onChange((value: string) => { this.goodsName = value })
          }
          Column({ space: SPACING.XS }) {
            this.FieldLabel('商品描述', false)
            TextInput({ placeholder: '如：招牌菜，微辣', text: this.goodsDescription })
              .width('100%').height(44)
              .onChange((value: string) => { this.goodsDescription = value })
          }
          Row({ space: SPACING.MD }) {
            this.NumberField('特价价', '如：25.00', this.price, '', (value: string) => { this.price = value })
            this.NumberField('库存', '0-9999', this.stock, this.specStockHint(), (value: string) => { this.stock = value })
          }
          Column({ space: SPACING.XS }) {
            this.FieldLabel('原价', false)
            TextInput({ placeholder: '特价时填写，如：30.00', text: this.originalPrice })
              .width('100%').height(44).type(InputType.Number)
              .onChange((value: string) => { this.originalPrice = value })
          }
          Column({ space: SPACING.XS }) {
            this.FieldLabel('商品图片', false)
            Row({ space: SPACING.MD }) {
              Image(merchantImageSource(this.image))
                .alt(DEFAULT_MERCHANT_IMAGE)
                .width(72).height(72).objectFit(ImageFit.Cover).borderRadius(BORDER_RADIUS.MD)
              Button(this.image === '' ? '＋ 上传图片' : '更换图片')
                .fontSize(FONT_SIZE.SM).height(36).borderRadius(BORDER_RADIUS.MD)
                .onClick(() => { this.pickImage() })
            }
            .width('100%').alignItems(VerticalAlign.Center)
          }
          Row() {
            Text('加入特价团购').fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_PRIMARY)
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
        .width('100%').padding(SPACING.LG)
        .backgroundColor(COLORS.BG_WHITE).borderRadius(BORDER_RADIUS.LG)

        Column() {
          this.SpecSection()
        }
        .width('100%').padding(SPACING.LG)
        .backgroundColor(COLORS.BG_WHITE).borderRadius(BORDER_RADIUS.LG)
      }
      .width('100%')
      .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.MD, bottom: SPACING.XL })
    }
    .layoutWeight(1).scrollBar(BarState.Off)
  }

  build() {
    Column() {
      Row() {
        Text('‹ 返回')
          .fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_PRIMARY)
          .onClick(() => { router.back() })
        Text('编辑商品')
          .fontSize(FONT_SIZE.XL).fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY).layoutWeight(1).textAlign(TextAlign.Center)
        Text(' ').width(28)
      }
      .width('100%').height(56).padding({ left: SPACING.LG, right: SPACING.LG })
      .backgroundColor(COLORS.BG_WHITE).alignItems(VerticalAlign.Center)

      if (this.loading) {
        Column() {
          Text('正在读取商品数据...')
            .fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_HINT)
        }
        .layoutWeight(1).width('100%')
        .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      } else {
        this.FormContent()
        Row({ space: SPACING.MD }) {
          Button('取消')
            .layoutWeight(1).height(46).fontSize(FONT_SIZE.MD)
            .fontColor(COLORS.TEXT_SECONDARY).backgroundColor(COLORS.BG_PRIMARY)
            .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
            .onClick(() => { router.back() })
          Button(this.submitting ? '提交中...' : '确认保存')
            .layoutWeight(1).height(46).fontSize(FONT_SIZE.MD)
            .fontColor(COLORS.TEXT_WHITE).backgroundColor(COLORS.PRIMARY)
            .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
            .onClick(() => { this.confirmEdit() })
        }
        .width('100%').padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.SM, bottom: SPACING.LG })
        .backgroundColor(COLORS.BG_WHITE)
      }
    }
    .width('100%').height('100%').backgroundColor(COLORS.BG_PRIMARY)
  }
}

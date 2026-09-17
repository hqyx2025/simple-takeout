/** 商户新增商品页：表单确认后才写入数据库，并在返回前重新读取商品数据。 */
import { Category, GoodsItem, GoodsSpec, User, UserRole } from '../model/Models'
import { createMerchantGoodsApi, fetchMerchantCategoriesApi, fetchMerchantGoodsApi, uploadImageApi } from '../service/ApiService'
import { getLastRemoteErrorMessage, updateGoodsSpecsRemote } from '../service/AppStorageManager'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS, merchantImageSource, DEFAULT_MERCHANT_IMAGE, MODULE_COLOR, MODULE_BG, accentBg, accentFg, accentIndexFromText } from '../common/Constants'
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
export struct MerchantAddGoodsPage {
  @StorageLink('isLoggedIn') loggedIn: boolean = false
  @StorageLink('user') user: User = {
    id: 0, username: '未登录', avatar: '', phone: '', password: '', role: UserRole.CUSTOMER,
    balance: 0, coupons: [], orders: [], storeIds: []
  }
  @State storeId: number = 0
  @State categories: Category[] = []
  @State goodsName: string = ''
  @State goodsDescription: string = ''
  @State price: string = ''
  @State originalPrice: string = ''
  @State image: string = ''
  @State stock: string = '99'
  @State categoryId: number = 0
  @State isSpecial: boolean = false
  @State multiSpecEnabled: boolean = false
  @State specRows: SpecRow[] = []
  @State specStockTotal: number = 0
  @State submitting: boolean = false
  private nextSpecKey: number = 1

  async aboutToAppear(): Promise<void> {
    if (!this.loggedIn || this.user.role !== UserRole.MERCHANT) {
      promptAction.showToast({ message: '请使用商户账号登录后添加商品', duration: 1800 })
      router.back()
      return
    }
    this.storeId = AppStorage.get<number>('merchantGoodsStoreId') || 0
    if (this.storeId <= 0) {
      promptAction.showToast({ message: '未找到要添加商品的店铺', duration: 1800 })
      router.back()
      return
    }
    this.categories = await fetchMerchantCategoriesApi()
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
      tag: this.isSpecial ? '特价团购' : '新品',
      isOnShelf: true,
      isSpecial: this.isSpecial
    }
    this.submitting = true
    promptAction.showToast({ message: '提交中...', duration: 1200 })
    const created: GoodsItem | null = await createMerchantGoodsApi(this.storeId, goods)
    if (created === null) {
      this.submitting = false
      promptAction.showToast({ message: `商品添加失败：${this.failureReason('请检查网络后重试')}`, duration: 2800 })
      return
    }
    // 规格需在拿到商品 id 后整体覆盖提交；创建成功但规格失败时商品不会丢失，提示到编辑页重试
    if (this.multiSpecEnabled && this.specRows.length > 0) {
      const specs: GoodsSpec[] = this.buildSpecs(created.id)
      const specSaved: GoodsItem | null = await updateGoodsSpecsRemote(created.id, specs)
      if (specSaved === null) {
        this.submitting = false
        promptAction.showToast({
          message: `商品已创建，但规格保存失败，请到编辑页重试：${this.failureReason('请检查网络')}`,
          duration: 3200
        })
        return
      }
    }
    // 确认接口成功后再读一次数据库，避免返回列表使用旧数据。
    const latestGoods: GoodsItem[] = await fetchMerchantGoodsApi(this.storeId)
    this.submitting = false
    if (latestGoods.find((item: GoodsItem) => item.id === created.id) === undefined) {
      promptAction.showToast({ message: '商品已保存，但刷新数据失败，请返回后重试', duration: 2600 })
      return
    }
    AppStorage.setOrCreate<string>('merchantGoodsFeedback', '商品添加成功，列表已刷新')
    router.back()
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
  CategoryOptions() {
    Scroll() {
      Row({ space: SPACING.SM }) {
        Text('未分组')
          .fontSize(FONT_SIZE.SM)
          .fontColor(this.categoryId === 0 ? accentFg(accentIndexFromText('未分组')) : COLORS.TEXT_SECONDARY)
          .backgroundColor(this.categoryId === 0 ? accentBg(accentIndexFromText('未分组')) : COLORS.BG_PRIMARY)
          .padding({ left: SPACING.MD, right: SPACING.MD, top: SPACING.SM, bottom: SPACING.SM })
          .borderRadius(BORDER_RADIUS.ROUND)
          .onClick(() => { this.selectCategory(0) })
        ForEach(this.categories, (category: Category) => {
          Text(category.name)
            .fontSize(FONT_SIZE.SM)
            .fontColor(this.categoryId === category.id ? accentFg(accentIndexFromText(category.name)) : COLORS.TEXT_SECONDARY)
            .backgroundColor(this.categoryId === category.id ? accentBg(accentIndexFromText(category.name)) : COLORS.BG_PRIMARY)
            .padding({ left: SPACING.MD, right: SPACING.MD, top: SPACING.SM, bottom: SPACING.SM })
            .borderRadius(BORDER_RADIUS.ROUND)
            .onClick(() => { this.selectCategory(category.id) })
        }, (category: Category) => category.id.toString())
      }
      .padding({ left: SPACING.XS, right: SPACING.LG })
    }
    .width('100%')
    .height(44)
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
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
      this.FieldLabel(label, true)
      TextInput({ placeholder: placeholder, text: value })
        .width('100%').height(44).type(InputType.Number)
        .onChange((next: string) => { onChange(next) })
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
        Text('🧾')
          .fontSize(FONT_SIZE.MD)
          .width(28).height(28).textAlign(TextAlign.Center)
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
      Row() {
        Text('‹ 返回')
          .fontSize(FONT_SIZE.MD).fontColor(MODULE_COLOR.MERCHANT)
          .onClick(() => { router.back() })
        Text('添加商品')
          .fontSize(FONT_SIZE.XL).fontWeight(FontWeight.Bold)
          .fontColor(MODULE_COLOR.MERCHANT).layoutWeight(1).textAlign(TextAlign.Center)
        Text(' ').width(28)
      }
      .width('100%').height(56).padding({ left: SPACING.LG, right: SPACING.LG })
      .backgroundColor(MODULE_BG.MERCHANT).alignItems(VerticalAlign.Center)

      Scroll() {
        Column({ space: SPACING.MD }) {
          Column({ space: SPACING.SM }) {
            Text('确认后将保存到数据库，并立即刷新商品列表')
              .fontSize(FONT_SIZE.SM).fontColor(accentFg(0))
            Text('请填写商品信息；库存和分类使用固定范围与数据库分类，避免录入无效数据。')
              .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT)
          }
          .width('100%').padding(SPACING.MD)
          .backgroundColor(accentBg(0)).borderRadius(BORDER_RADIUS.MD)

          Column({ space: SPACING.MD }) {
            Row() {
              Text('📝')
                .fontSize(FONT_SIZE.MD)
                .width(28).height(28).textAlign(TextAlign.Center)
                .backgroundColor(accentBg(1))
                .borderRadius(BORDER_RADIUS.SM)
              Text('基本信息')
                .fontSize(FONT_SIZE.LG).fontWeight(FontWeight.Bold)
                .fontColor(accentFg(1)).margin({ left: SPACING.SM })
            }
            .width('100%')
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
                  .fontColor(COLORS.TEXT_WHITE).backgroundColor(MODULE_COLOR.MERCHANT)
                  .onClick(() => { this.pickImage() })
              }
              .width('100%').alignItems(VerticalAlign.Center)
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

      Row({ space: SPACING.MD }) {
        Button('取消')
          .layoutWeight(1).height(46).fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_SECONDARY).backgroundColor(COLORS.BG_PRIMARY)
          .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
          .onClick(() => { router.back() })
        Button(this.submitting ? '提交中...' : '确认添加')
          .layoutWeight(1).height(46).fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_WHITE).backgroundColor(MODULE_COLOR.MERCHANT)
          .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
          .onClick(() => { this.confirmAdd() })
      }
      .width('100%').padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.SM, bottom: SPACING.LG })
      .backgroundColor(COLORS.BG_WHITE)
    }
    .width('100%').height('100%').backgroundColor(COLORS.BG_PRIMARY)
  }
}

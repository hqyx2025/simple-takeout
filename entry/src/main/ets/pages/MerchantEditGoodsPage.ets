/** 商户编辑商品页：打开和保存均以数据库返回数据为准。 */
import { Category, GoodsItem, User, UserRole } from '../model/Models'
import { fetchMerchantCategoriesApi, fetchMerchantGoodsApi, updateMerchantGoodsApi } from '../service/ApiService'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS } from '../common/Constants'
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'

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
  @State loading: boolean = true
  @State saving: boolean = false

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
    this.loading = false
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

  private async confirmEdit(): Promise<void> {
    if (this.saving) {
      promptAction.showToast({ message: '商品正在保存，请稍候', duration: 1400 })
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
    this.saving = true
    const updated: GoodsItem | null = await updateMerchantGoodsApi(updatedGoods, this.isOnShelf)
    if (updated === null) {
      this.saving = false
      promptAction.showToast({ message: '商品保存失败，请检查网络后重试', duration: 2200 })
      return
    }
    const latestGoods: GoodsItem[] = await fetchMerchantGoodsApi(this.storeId)
    this.saving = false
    if (latestGoods.find((item: GoodsItem) => item.id === this.goodsId) === undefined) {
      promptAction.showToast({ message: '商品已保存，但刷新数据失败，请返回后重试', duration: 2600 })
      return
    }
    AppStorage.setOrCreate<boolean>('merchantGoodsNeedsRefresh', true)
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
      .padding({ left: 2, right: SPACING.LG })
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
  NumberField(label: string, placeholder: string, value: string, onChange: (value: string) => void) {
    Column({ space: SPACING.XS }) {
      this.FieldLabel(label, true)
      TextInput({ placeholder: placeholder, text: value })
        .width('100%').height(46).type(InputType.Number)
        .onChange((next: string) => { onChange(next) })
    }
    .layoutWeight(1)
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
        .backgroundColor('#FFF7ED').borderRadius(BORDER_RADIUS.MD)

        Column({ space: SPACING.MD }) {
          Column({ space: SPACING.XS }) {
            this.FieldLabel('商品名称', true)
            TextInput({ placeholder: '如：宫保鸡丁', text: this.goodsName })
              .width('100%').height(46)
              .onChange((value: string) => { this.goodsName = value })
          }
          Column({ space: SPACING.XS }) {
            this.FieldLabel('商品描述', false)
            TextInput({ placeholder: '如：招牌菜，微辣', text: this.goodsDescription })
              .width('100%').height(46)
              .onChange((value: string) => { this.goodsDescription = value })
          }
          Row({ space: SPACING.MD }) {
            this.NumberField('特价价', '如：25.00', this.price, (value: string) => { this.price = value })
            this.NumberField('库存', '0-9999', this.stock, (value: string) => { this.stock = value })
          }
          Column({ space: SPACING.XS }) {
            this.FieldLabel('原价', false)
            TextInput({ placeholder: '特价时填写，如：30.00', text: this.originalPrice })
              .width('100%').height(46).type(InputType.Number)
              .onChange((value: string) => { this.originalPrice = value })
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
        Text(' ').width(42)
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
          Button(this.saving ? '保存中...' : '确认保存')
            .layoutWeight(1).height(46).fontSize(FONT_SIZE.MD)
            .fontColor(Color.White).backgroundColor(COLORS.PRIMARY)
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

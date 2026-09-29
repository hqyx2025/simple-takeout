import { AppButtonStyle, AppTheme } from '../common/theme/AppTheme'
/**
 * 独立店铺详情页。
 * 首页附近店、发现推荐、分类商品、搜索和收藏入口统一进入此页面。
 * 多规格 SKU：商品 specs 非空时必须先选规格再加购（后端要求 specId，否则返回 400）。
 */
import { AppMotion } from '../common/theme/AppMotion'
import { StoreDetailContent } from './Index'
import { LoginPage } from './LoginPage'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS } from '../common/Constants'
import { PageHeader } from '../components/PageHeader'
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { GoodsItem, GoodsSpec, CartItem } from '../model/Models'
import { addCartItemRemote, getLastRemoteErrorMessage, refreshCartFromServer } from '../service/AppStorageManager'

// 数量步进器上下限
const SPEC_MIN_QUANTITY: number = 1

/** 空商品占位：ArkTS 严格模式要求组件成员变量必须有初值，同时避免无类型对象字面量 */
function createEmptyGoodsItem(): GoodsItem {
  const item: GoodsItem = {
    id: 0,
    storeId: 0,
    name: '',
    description: '',
    price: 0,
    image: '',
    categoryId: 0,
    stock: 0,
    sales: 0,
    rating: 0,
    specs: []
  }
  return item
}

/**
 * 多规格菜品半屏面板，规格区域滚动，数量与加购按钮固定在底部。
 * 规格名 / 规格价 / 规格库存全部来自后端 goods.specs；库存为 0 的规格不可选。
 * 加入购物车成功后由调用方刷新购物车角标，失败时展示后端错误文案，不做静默失败。
 */
@Component
export struct SpecSelectSheet {
  // 通过闭包在弹窗创建时读取菜品，避免弹窗参数被过早求值导致拿到旧数据
  resolveGoods: () => GoodsItem = (): GoodsItem => createEmptyGoodsItem()
  storeId: number = 0
  storeName: string = ''
  onClose: () => void = () => {}
  @State currentGoods: GoodsItem = createEmptyGoodsItem()
  @State goodsName: string = ''
  @State specList: GoodsSpec[] = []
  @State selectedSpecId: number = 0
  @State quantity: number = SPEC_MIN_QUANTITY
  @Link submitting: boolean
  @State selectedPrice: number = 0

  aboutToAppear(): void {
    const goods: GoodsItem = this.resolveGoods()
    this.currentGoods = goods
    this.goodsName = goods.name
    const rawSpecs: GoodsSpec[] = goods.specs ?? []
    this.specList = Array.isArray(rawSpecs) ? rawSpecs : []
    this.selectedSpecId = 0
    this.quantity = SPEC_MIN_QUANTITY
    this.submitting = false
  }

  private getSelectedSpec(): GoodsSpec | undefined {
    return this.specList.find((spec: GoodsSpec) => spec.id === this.selectedSpecId)
  }

  private selectSpec(spec: GoodsSpec): void {
    if (spec.stock <= 0) {
      promptAction.showToast({ message: `「${spec.name}」已售罄，请选择其他规格`, duration: 2000 })
      return
    }
    this.selectedSpecId = spec.id
    this.selectedPrice = spec.price
    if (this.quantity > spec.stock) {
      this.quantity = spec.stock
    }
    if (this.quantity < SPEC_MIN_QUANTITY) {
      this.quantity = SPEC_MIN_QUANTITY
    }
  }

  private changeQuantity(delta: number): void {
    const spec: GoodsSpec | undefined = this.getSelectedSpec()
    if (spec === undefined) {
      promptAction.showToast({ message: '请先选择规格', duration: 2000 })
      return
    }
    if (spec.stock <= 0) {
      promptAction.showToast({ message: `「${spec.name}」已售罄，请选择其他规格`, duration: 2000 })
      return
    }
    let next: number = this.quantity + delta
    if (next < SPEC_MIN_QUANTITY) {
      next = SPEC_MIN_QUANTITY
    }
    if (next > spec.stock) {
      next = spec.stock
      promptAction.showToast({ message: `「${spec.name}」仅剩 ${spec.stock} 份`, duration: 2000 })
    }
    this.quantity = next
  }

  private closeDialog(): void {
    if (!this.submitting) {
      this.onClose()
    }
  }

  private async submit(): Promise<void> {
    if (this.submitting) {
      promptAction.showToast({ message: '正在加入购物车，请稍候', duration: 2000 })
      return
    }
    const spec: GoodsSpec | undefined = this.getSelectedSpec()
    if (spec === undefined) {
      promptAction.showToast({ message: '请先选择规格', duration: 2000 })
      return
    }
    if (spec.stock <= 0) {
      promptAction.showToast({ message: `「${spec.name}」已售罄，请选择其他规格`, duration: 2000 })
      return
    }
    let count: number = this.quantity
    if (count < SPEC_MIN_QUANTITY) {
      count = SPEC_MIN_QUANTITY
    }
    if (count > spec.stock) {
      count = spec.stock
    }
    this.submitting = true
    try {
      const item: CartItem = {
        goods: this.currentGoods,
        quantity: count,
        storeId: this.currentGoods.storeId ?? this.storeId,
        storeName: this.storeName,
        specId: spec.id,
        specName: spec.name,
        price: spec.price,
        stock: spec.stock
      }
      const ok: boolean = await addCartItemRemote(item)
      if (!ok) {
        const message: string = getLastRemoteErrorMessage()
        promptAction.showToast({
          message: message === '' ? '加入购物车失败，请稍后重试' : message,
          duration: 3000
        })
        return
      }
      await refreshCartFromServer()
      promptAction.showToast({ message: '已加入购物车', duration: 2000 })
      this.onClose()
    } finally {
      this.submitting = false
    }
  }

  @Builder
  SpecRow(spec: GoodsSpec) {
    Row() {
      Radio({ value: spec.id.toString(), group: 'goods-spec' })
        .checked(this.selectedSpecId === spec.id)
        .enabled(spec.stock > 0 && !this.submitting)
        .radioStyle({ checkedBackgroundColor: AppTheme.PRIMARY,
          uncheckedBorderColor: AppTheme.MUTED, indicatorColor: AppTheme.PRIMARY_TEXT })
        .accessibilityText(spec.name)
        .onChange((checked: boolean) => { if (checked) { this.selectSpec(spec) } })
      Column({ space: SPACING.XS }) {
        Text(spec.name)
          .fontSize(FONT_SIZE.MD)
          .fontWeight(this.selectedSpecId === spec.id ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(spec.stock <= 0 ? COLORS.TEXT_HINT : COLORS.TEXT_PRIMARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(spec.stock <= 0 ? '售罄' : `剩余 ${spec.stock} 份`)
          .fontSize(FONT_SIZE.XS)
          .fontColor(spec.stock <= 0 ? COLORS.ERROR : COLORS.TEXT_HINT)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text(`¥${spec.price.toFixed(2)}`)
        .fontSize(FONT_SIZE.LG)
        .fontWeight(FontWeight.Bold)
        .fontColor(spec.stock <= 0 ? COLORS.TEXT_HINT : COLORS.PRICE_RED)
    }
    .width('100%')
    .padding(SPACING.MD)
    .backgroundColor(this.selectedSpecId === spec.id ? COLORS.TAG_BG : COLORS.BG_WHITE)
    .borderWidth(1)
    .borderColor(this.selectedSpecId === spec.id ? COLORS.PRIMARY : COLORS.DIVIDER)
    .borderRadius(BORDER_RADIUS.MD)
    .enabled(!this.submitting)
    .accessibilitySelected(this.selectedSpecId === spec.id)
    .id(`spec-option-${spec.id}`)
    .onClick(() => { this.selectSpec(spec) })
  }

  build() {
    Column() {
      // 顶部：菜品名 + 选择规格
      Row() {
        Column({ space: SPACING.XS }) {
          Text(this.goodsName)
            .fontSize(FONT_SIZE.XL).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.specList.length > 1 ? `选择规格（${this.specList.length} 种）` : '选择规格')
            .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Button({ type: ButtonType.Circle }) {
          Image($r('app.media.ui_close')).width(20).height(20).objectFit(ImageFit.Contain)
        }
          .width(44).height(44).backgroundColor(AppTheme.INPUT)
          .accessibilityText('关闭规格选择').id('spec-close')
          .enabled(!this.submitting)
          .onClick(() => { this.closeDialog() })
      }
      .width('100%')

      // 规格列表：库存为 0 显示售罄且不可选（用 List 承载，避免 Scroll 内容不足一屏时垂直居中）
      List({ space: SPACING.SM }) {
        ForEach(this.specList, (spec: GoodsSpec) => {
          ListItem() {
            this.SpecRow(spec)
          }
        }, (spec: GoodsSpec) => spec.id.toString())
      }
      .scrollBar(BarState.Off)
      .width('100%')
      .layoutWeight(1)
      .edgeEffect(EdgeEffect.Spring)
      .margin({ top: SPACING.MD })

      // 数量步进器：选中规格后出现，最少 1 份、最多不超过该规格库存
      if (this.selectedSpecId > 0) {
        Row() {
          Text('数量').fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_PRIMARY).layoutWeight(1)
          Row({ space: SPACING.MD }) {
            Button('-')
              .width(44).height(44).fontSize(FONT_SIZE.LG).fontColor(COLORS.PRIMARY)
              .backgroundColor(COLORS.BG_PRIMARY).borderRadius(BORDER_RADIUS.CIRCLE)
              .enabled(!this.submitting && this.quantity > SPEC_MIN_QUANTITY)
              .accessibilityText('减少数量')
              .onClick(() => { this.changeQuantity(-1) })
            Text(this.quantity.toString())
              .fontSize(FONT_SIZE.LG).fontColor(COLORS.TEXT_PRIMARY)
              .width(32).textAlign(TextAlign.Center)
            Button('+')
              .width(44).height(44).fontSize(FONT_SIZE.LG).fontColor(COLORS.ON_PRIMARY)
              .backgroundColor(COLORS.PRIMARY).borderRadius(BORDER_RADIUS.CIRCLE)
              .enabled(!this.submitting)
              .accessibilityText('增加数量')
              .onClick(() => { this.changeQuantity(1) })
          }
        }
        .width('100%')
        .margin({ top: SPACING.MD })
      }

      if (this.selectedSpecId > 0) {
        Text(`合计 ¥${(this.selectedPrice * this.quantity).toFixed(2)}`)
          .fontSize(FONT_SIZE.XL).fontWeight(FontWeight.Bold).fontColor(COLORS.PRICE_RED)
          .width('100%').margin({ top: SPACING.SM })
      }
      Button('加入购物车')
        .attributeModifier(new AppButtonStyle())
        .width('100%').height(AppTheme.CONTROL_HEIGHT)
        .enabled(!this.submitting)
        .id('spec-add-cart')
        .fontSize(FONT_SIZE.LG).fontColor(COLORS.ON_PRIMARY)
        .backgroundColor(COLORS.PRIMARY)
        .borderRadius(BORDER_RADIUS.ROUND)
        .margin({ top: SPACING.LG })
        .onClick(() => { this.submit() })
    }
    .width('100%')
    .height('100%')
    .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.LG, bottom: SPACING.XXL })
    .backgroundColor(COLORS.BG_WHITE)
    .borderRadius({ topLeft: BORDER_RADIUS.XL, topRight: BORDER_RADIUS.XL })
  }
}

@Entry
@Component
export struct StoreDetailPage {
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

  @StorageLink('selectedStoreId') storeId: number = 0
  @StorageLink('selectedStoreName') storeName: string = ''
  @StorageLink('isLoggedIn') loggedIn: boolean = false
  @State showLogin: boolean = false
  @State detailVisible: boolean = true
  // 待选规格的菜品；弹窗通过闭包在打开时读取，保证切换菜品后弹窗展示的是最新菜品
  @State specGoods: GoodsItem = createEmptyGoodsItem()
  @State showSpecSheet: boolean = false
  @State specSubmitting: boolean = false

  @Builder
  SpecSheet() {
    SpecSelectSheet({
      resolveGoods: (): GoodsItem => this.specGoods,
      storeId: this.storeId,
      storeName: this.storeName,
      submitting: $specSubmitting,
      onClose: () => { this.showSpecSheet = false }
    })
  }

  aboutToAppear(): void {
    if (this.storeId <= 0) {
      promptAction.showToast({ message: '店铺信息不存在' })
      router.back()
    }
  }

  onPageShow(): void {
    this.detailVisible = true
  }

  onPageHide(): void {
    this.detailVisible = false
  }

  private openSpecDialog(goods: GoodsItem): void {
    this.specGoods = goods
    this.showSpecSheet = true
  }

  private goBack(): void {
    AppStorage.setOrCreate<number>('selectedStoreId', 0)
    AppStorage.setOrCreate<string>('selectedStoreName', '')
    router.back()
  }

  build() {
    Stack() {
      Column() {
        PageHeader({ title: this.storeName || '店铺详情', topPadding: SPACING.SM, onBack: () => { this.goBack() } })

        if (this.storeId > 0) {
          StoreDetailContent({
            storeId: this.storeId,
            pageVisible: this.detailVisible,
            onNavigateLogin: () => { this.showLogin = true },
            onSelectSpecGoods: (goods: GoodsItem) => { this.openSpecDialog(goods) }
          })
          .layoutWeight(1)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(COLORS.BG_PRIMARY)

      if (this.showLogin && !this.loggedIn) {
        Column() {
          LoginPage({
            onLoginSuccess: () => {
              this.showLogin = false
            }
          })
        }
        .width('100%')
        .height('100%')
        .backgroundColor(COLORS.BG_PRIMARY)
      }
    }
    .width('100%')
    .height('100%')
    .bindSheet($$this.showSpecSheet, this.SpecSheet(), {
      height: '70%',
      detents: ['70%', SheetSize.LARGE],
      preferType: SheetType.BOTTOM,
      showClose: false,
      dragBar: true,
      backgroundColor: AppTheme.CARD,
      radius: { topLeft: AppTheme.SHEET_RADIUS, topRight: AppTheme.SHEET_RADIUS },
      onWillDismiss: (action: DismissSheetAction) => {
        if (!this.specSubmitting) {
          action.dismiss()
        }
      },
      onDisappear: () => { this.specGoods = createEmptyGoodsItem() }
    })
  }
}

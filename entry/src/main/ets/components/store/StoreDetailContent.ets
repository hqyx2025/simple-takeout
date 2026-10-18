import { AppButtonStyle, AppCardStyle, AppFilterStyle, AppTheme } from '../../common/theme/AppTheme'
/**
 * 主页面 - 简单外卖App
 * 包含：搜索栏、分类导航、店铺列表、店铺详情、购物车、订单列表、个人中心、底部Tab导航
 */
import { Category, StoreItem, GoodsItem, GoodsSpec, SeckillItem, CartItem, Order, Review, Address, MarketingActivity, Setmeal, SetmealItem, SetmealOrder } from '../../model/Models'
import { addCartItemRemote, updateCartItemQuantityRemote, createOrderRemote, refreshCartFromServer, isLoggedIn, getAllStoresList, getGoodsForStore, isFavorited, syncCartRemote, syncStoreReviewsRemote, syncGoodsFromServer, toggleFavoriteRemote, fetchSeckillsRemote, getLastRemoteErrorMessage } from '../../service/AppStorageManager'
import { fetchStoreMerchantCategoriesApi, fetchStoreDetailApi, fetchStoreActivitiesApi, fetchStoreSetmealsApi } from '../../service/ApiService'

import { CartAddAnimator, CartAddFlight } from '../../components/CartAddFlight'

import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS, formatSales, merchantImageSource, DEFAULT_MERCHANT_IMAGE, MODULE_COLOR, MODULE_BG, accentBg } from '../../common/Constants'

import { promptCompat as promptAction, routerCompat as router } from '../../common/UiNavigation'
import { logInfo } from '../../service/AppLogger'

import { AppMotion } from '../../common/theme/AppMotion'

class GoodsDataSource implements IDataSource {
  private items: GoodsItem[] = []
  private listeners: DataChangeListener[] = []
  totalCount(): number { return this.items.length }
  getData(index: number): GoodsItem { return this.items[index] }
  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) { this.listeners.push(listener) }
  }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index: number = this.listeners.indexOf(listener)
    if (index >= 0) { this.listeners.splice(index, 1) }
  }
  setData(items: GoodsItem[]): void {
    this.items = items.slice()
    this.listeners.forEach((listener: DataChangeListener) => listener.onDataReloaded())
  }
}

@Component
export struct StoreDetailContent {
  @Prop @Watch('onPageVisibilityChange') pageVisible: boolean = true
  // 收藏页/搜索页返回后，父组件会复用详情组件实例；使用 @Prop + @Watch
  // 确保切换店铺时重新加载商品、评分和店铺信息，避免标题与内容错位。
  @Prop @Watch('onStoreIdChange') storeId: number = 0
  @State goodsList: GoodsItem[] = []
  @State storeName: string = ''
  @State storeRating: number = 0
  @State storeMonthlySales: number = 0
  @State storeDeliveryFee: number = 0
  @State storeDeliveryTime: string = ''
  @State storeDistance: string = ''
  @State storeMinOrder: number = 0
  @State storeTags: string[] = []
  @State storeNotice: string = ''
  // 店铺照片（商户上传的相对地址），用户端详情页顶部展示
  @State storeImage: string = ''
  @State cartCount: number = 0
  @State cartTotal: number = 0
  // 商品行的「- 数量 +」取值依赖购物车，而 ForEach 的 key 用的是稳定的 goods.id：
  // ArkUI 按 key 复用列表项，键不变就不重建，于是点「+」后数字不更新/不显示。
  // 行 key 只使用业务主键，展开态由卡片状态承载。
  private goodsDataSource: GoodsDataSource = new GoodsDataSource()
  private cartAnimator: CartAddAnimator = new CartAddAnimator()
  private active: boolean = false
  @State cartPulse: number = 1
  private cartOperationQueue: Promise<void> = Promise.resolve()
  @State isFav: boolean = false
  @State goodsLoading: boolean = false
  @StorageLink('reviewList') storeReviews: Review[] = []
  @State currentCat: string = '全部'
  @State goodsCats: string[] = ['全部']
  @State filteredGoodsList: GoodsItem[] = []
  // 店内商户分类（演进项，见大纲 8.3）：优先按商户分类分组，无商户分类时回退平台分类
  @State storeMerchantCats: Category[] = []
  @StorageLink('cartItems') @Watch('onCartItemsChange') cartItems: CartItem[] = []
  @StorageLink('categoryList') categoryList: Category[] = []
  @StorageLink('isLoggedIn') loggedIn: boolean = false
  onNavigateLogin: () => void = () => {}
  // 多规格菜品：由页面层打开原生半屏规格面板。
  onSelectSpecGoods: (goods: GoodsItem) => void = () => {}
  // 本店进行中的秒杀（商品卡片标出秒杀价）
  @State storeSeckills: SeckillItem[] = []
  // 本店生效中的营销活动与套餐（门店首页横幅/套餐区展示）
  @State storeActivities: MarketingActivity[] = []
  @State storeSetmeals: Setmeal[] = []

  aboutToAppear() {
    this.active = true
    this.loadStoreData()
  }

  aboutToDisappear(): void {
    this.active = false
  }

  onPageVisibilityChange(): void {
    this.active = this.pageVisible
    if (!this.pageVisible) {
      this.cartAnimator.cancel()
    }
  }

  onStoreIdChange(): void {
    this.loadStoreData()
  }

  onCartItemsChange(): void {
    this.updateCartInfo()
  }

  private loadStoreData(): void {
    this.goodsList = getGoodsForStore(this.storeId)
    this.storeMerchantCats = []
    this.goodsLoading = false
    const store = getAllStoresList().find(s => s.id === this.storeId)
    if (store === undefined) {
      this.storeName = ''
      this.storeRating = 0
      this.storeMonthlySales = 0
      this.storeDeliveryFee = 0
      this.storeDeliveryTime = ''
      this.storeDistance = ''
      this.storeMinOrder = 0
      this.storeTags = []
      this.storeNotice = ''
      this.storeImage = ''
    }
    if (store) {
      this.storeName = store.name
      this.storeRating = store.rating
      this.storeMonthlySales = store.monthlySales
      this.storeDeliveryFee = store.deliveryFee
      this.storeDeliveryTime = store.deliveryTime
      this.storeDistance = store.distance
      this.storeMinOrder = store.minOrder
      this.storeTags = store.tags
      this.storeNotice = store.notice
      this.storeImage = store.image ?? ''
    }
    this.isFav = isFavorited(this.storeId)
    this.storeReviews = []
    const cats: string[] = this.getGoodsCategoryNames(this.goodsList)
    this.goodsCats = ['全部', ...cats]
    this.currentCat = '全部'
    this.updateFilteredGoods()
    this.updateCartInfo()
    // 从后端拉取最新商品（真实后端模式）
    this.refreshGoods()
    this.refreshReviews()
    this.refreshStoreInfo()
    this.refreshStoreSeckills()
    this.refreshStoreActivities()
    this.refreshStoreSetmeals()
  }

  // 本店进行中的限时秒杀：用于在商品卡片上标出秒杀价（下单时后端会自动按秒杀价结算）
  private async refreshStoreSeckills(): Promise<void> {
    if (!this.loggedIn || this.storeId <= 0) {
      this.storeSeckills = []
      return
    }
    const list: SeckillItem[] = await fetchSeckillsRemote(50)
    this.storeSeckills = list.filter((item: SeckillItem) => item.storeId === this.storeId)
  }

  /** 本店生效中的营销活动（折扣/新客立减/满赠），门店首页横幅展示。 */
  private async refreshStoreActivities(): Promise<void> {
    if (!this.loggedIn || this.storeId <= 0) {
      this.storeActivities = []
      return
    }
    this.storeActivities = await fetchStoreActivitiesApi(this.storeId)
  }

  /** 本店套餐（组合购），门店套餐区展示。 */
  private async refreshStoreSetmeals(): Promise<void> {
    if (!this.loggedIn || this.storeId <= 0) {
      this.storeSetmeals = []
      return
    }
    this.storeSetmeals = await fetchStoreSetmealsApi(this.storeId)
  }

  /** 预订套餐：直接下单（items 为空 + setmeals），成功后提示去订单详情支付。 */
  private async buySetmeal(sm: Setmeal): Promise<void> {
    const addr: Address | null | undefined = AppStorage.get<Address | null>('currentAddress')
    if (addr === null || addr === undefined || addr.id <= 0) {
      promptAction.showToast({ message: '请先选择收货地址', duration: 1800 })
      return
    }
    const setmeals: SetmealOrder[] = [ { setmealId: sm.id, quantity: 1 } ]
    const key: string = `sm-${Date.now()}-${Math.floor(Math.random() * 100000)}`
    const order: Order | null = await createOrderRemote(this.storeId, [], addr.id, 0, '', [], '', key, 'DELIVERY', setmeals)
    if (order === null) {
      const err: string = getLastRemoteErrorMessage()
      promptAction.showToast({ message: err === '' ? '套餐下单失败，请稍后重试' : err, duration: 2200 })
      return
    }
    promptAction.showToast({ message: '套餐已下单，请在订单详情完成支付', duration: 2000 })
  }

  /** 菜品当前秒杀价（无秒杀返回 0）。 */
  private getSeckillPrice(goodsId: number): number {
    const matched: SeckillItem[] = this.storeSeckills.filter((item: SeckillItem) => item.goodsId === goodsId)
    return matched.length > 0 ? matched[0].price : 0
  }

  /** 卡片展示价：限时秒杀优先，其次规格最低价/菜品价。 */
  private getDisplayPrice(goods: GoodsItem): number {
    const seckillPrice: number = this.getSeckillPrice(goods.id)
    return seckillPrice > 0 ? seckillPrice : this.getMinSpecPrice(goods)
  }

  /** 卡片划线原价：秒杀时划掉菜品原价，否则划掉商品原价。 */
  private getStruckPrice(goods: GoodsItem): number {
    if (this.getSeckillPrice(goods.id) > 0) {
      return goods.price
    }
    return goods.originalPrice ?? 0
  }

  // 拉取后端权威店铺信息（评分/公告/配送费/起送价/营业时间），避免依赖列表缓存导致数据陈旧
  private async refreshStoreInfo(): Promise<void> {
    if (!this.loggedIn || this.storeId <= 0) {
      return
    }
    const store: StoreItem | null = await fetchStoreDetailApi(this.storeId)
    if (store !== null && store !== undefined) {
      this.storeName = store.name
      this.storeRating = store.rating
      this.storeMonthlySales = store.monthlySales
      this.storeDeliveryFee = store.deliveryFee
      this.storeDeliveryTime = store.deliveryTime
      // 距离不在这里覆盖：详情接口不带用户坐标（算不出真实距离），
      // 覆盖会把列表接口按定位算好的「距你 X km」变成「未知距离」
      this.storeMinOrder = store.minOrder
      this.storeTags = store.tags
      this.storeNotice = store.notice
      this.storeImage = store.image ?? ''
    }
  }

  // 拉取后端店铺商品并刷新
  private async refreshGoods(): Promise<void> {
    if (!this.loggedIn) {
      return
    }
    this.goodsLoading = true
    try {
      await syncGoodsFromServer(this.storeId)
      this.storeMerchantCats = await fetchStoreMerchantCategoriesApi(this.storeId)
      const goods: GoodsItem[] = getGoodsForStore(this.storeId)
      this.goodsList = goods
      const cats: string[] = this.getGoodsCategoryNames(goods)
      this.goodsCats = ['全部', ...cats]
      this.currentCat = '全部'
      this.updateFilteredGoods()
    } finally {
      this.goodsLoading = false
    }
  }

  private async refreshReviews(): Promise<void> {
    if (!this.loggedIn) {
      return
    }
    await syncStoreReviewsRemote(this.storeId)
    this.storeReviews = AppStorage.get<Review[]>('reviewList') || []
  }

  // 商品分组名：优先使用店内商户分类；商品均未分组时回退到平台分类名
  private getGoodsCategoryNames(goods: GoodsItem[]): string[] {
    const names: string[] = []
    let hasMerchantCat: boolean = false
    goods.forEach((item: GoodsItem) => {
      const merchantCatId: number = item.merchantCategoryId ?? 0
      if (merchantCatId > 0) {
        const category: Category | undefined = this.storeMerchantCats.find((cat: Category) => cat.id === merchantCatId)
        if (category !== undefined && names.indexOf(category.name) < 0) {
          names.push(category.name)
          hasMerchantCat = true
        }
      }
    })
    if (hasMerchantCat) {
      return names
    }
    goods.forEach((item: GoodsItem) => {
      const category: Category | undefined = this.categoryList.find((cat: Category) => cat.id === item.categoryId)
      if (category !== undefined && names.indexOf(category.name) < 0) {
        names.push(category.name)
      }
    })
    return names
  }

  updateCartInfo() {
    this.cartItems = AppStorage.get<CartItem[]>('cartItems') || []
    const sc = (this.cartItems || []).filter(c => c.storeId === this.storeId)
    this.cartCount = sc.reduce((s, i) => s + i.quantity, 0)
    // 多规格购物车行以规格价结算（CartItem.price），无规格商品回退商品价
    this.cartTotal = sc.reduce((s: number, i: CartItem) => {
      const unitPrice: number = i.price ?? i.goods.price
      return s + unitPrice * i.quantity
    }, 0)
    // 购物车已变化：递增渲染版本，让商品行的数量控件重建
  }

  private enqueueCartOperation(operation: () => Promise<void>): void {
    this.cartOperationQueue = this.cartOperationQueue.then(operation).catch(() => {
      // Keep later cart clicks usable when one request fails.
    })
  }

  private addGoodsToCart(goods: GoodsItem): void {
    const specs: GoodsSpec[] = goods.specs ?? []
    if (specs.length > 0) {
      // 多规格菜品必须选规格后加购，直接加购会被后端拒绝（400「请先选择规格」）
      this.onSelectSpecGoods(goods)
      return
    }
    if (!isLoggedIn()) {
      this.onNavigateLogin()
      return
    }
    if ((goods.stock ?? 1) <= 0) {
      promptAction.showToast({ message: '该商品已售罄', duration: 1600 })
      return
    }
    const storeId: number = this.storeId
    const session: string = AppStorage.get<string>('authToken') ?? ''
    // 点击立即入队；飞行动画只提供反馈，不能阻塞或取消已接受的加购。
    this.cartAnimator.play(`goods-plus-${goods.id}`).catch(() => {})
    this.enqueueCartOperation(async (): Promise<void> => {
      if (!this.active || storeId !== this.storeId || session !== (AppStorage.get<string>('authToken') ?? '')) {
        return
      }
      const item: CartItem = { goods: goods, quantity: 1, storeId: storeId, storeName: this.storeName }
      const ok: boolean = await addCartItemRemote(item)
      if (ok && this.active) {
        this.getUIContext().animateTo({ duration: AppMotion.duration(120), curve: Curve.EaseOut }, () => {
          this.cartPulse = 1.12
        })
        this.getUIContext().animateTo({ delay: AppMotion.duration(120), duration: AppMotion.duration(180), curve: Curve.EaseOut }, () => {
          this.cartPulse = 1
        })
      }
    })
  }

  // 该菜品是否是多规格菜品（specs 非空）
  private hasSpecs(goods: GoodsItem): boolean {
    const specs: GoodsSpec[] = goods.specs ?? []
    return specs.length > 0
  }

  // 规格数量，用于商品卡片上的「N 种规格」标签
  private getSpecCount(goods: GoodsItem): number {
    const specs: GoodsSpec[] = goods.specs ?? []
    return specs.length
  }

  // 规格最低价（后端 price 即为最低规格价，这里按 specs 再取一次最小值做兜底）
  private getMinSpecPrice(goods: GoodsItem): number {
    const specs: GoodsSpec[] = goods.specs ?? []
    if (specs.length === 0) {
      return goods.price
    }
    let minPrice: number = specs[0].price
    specs.forEach((spec: GoodsSpec) => {
      if (spec.price < minPrice) {
        minPrice = spec.price
      }
    })
    return minPrice
  }

  private changeGoodsQuantity(goods: GoodsItem, delta: number): void {
    this.enqueueCartOperation(async (): Promise<void> => {
      const synced: boolean = await syncCartRemote()
      if (!synced) {
        this.updateCartInfo()
        const message: string = getLastRemoteErrorMessage()
        promptAction.showToast({ message: message === '' ? 'Cart sync failed, please retry' : message, duration: 2200 })
        return
      }
      const currentCart: CartItem[] = AppStorage.get<CartItem[]>('cartItems') || []
      const currentItem: CartItem | undefined = currentCart.find((item: CartItem) =>
        item.goods.id === goods.id && item.storeId === this.storeId)
      const currentQuantity: number = currentItem === undefined ? 0 : currentItem.quantity
      const nextQuantity: number = currentQuantity + delta
      const ok: boolean = await updateCartItemQuantityRemote(goods.id, nextQuantity)
      await refreshCartFromServer()
      this.updateCartInfo()
      if (!ok) {
        await syncCartRemote()
        this.updateCartInfo()
        const message: string = getLastRemoteErrorMessage()
        promptAction.showToast({ message: message === '' ? 'Cart update failed, please retry' : message, duration: 2200 })
      }
    })
  }

  // 按当前分类筛选商品，并显式保存结果，避免 ArkUI 渲染期间计算 getter 时序异常
  private updateFilteredGoods(): void {
    const onShelfGoods: GoodsItem[] = this.goodsList.filter(g => g.isOnShelf !== false)
    if (this.currentCat === '全部') {
      this.filteredGoodsList = onShelfGoods
      this.goodsDataSource.setData(this.filteredGoodsList)
      return
    }
    // 优先按店内商户分类名匹配
    const merchantCat: Category | undefined = this.storeMerchantCats.find((cat: Category) => cat.name === this.currentCat)
    if (merchantCat !== undefined) {
      this.filteredGoodsList = onShelfGoods.filter(g => (g.merchantCategoryId ?? 0) === merchantCat.id)
      this.goodsDataSource.setData(this.filteredGoodsList)
      return
    }
    // 回退：按平台分类名匹配
    this.filteredGoodsList = onShelfGoods.filter(g => {
      const category: Category | undefined = this.categoryList.find((cat: Category) => cat.id === g.categoryId)
      return category !== undefined && category.name === this.currentCat
    })
    this.goodsDataSource.setData(this.filteredGoodsList)
  }

  @Builder
  CategoryFilter(catName: string) {
    Button(catName)
      .attributeModifier(new AppFilterStyle(this.currentCat === catName))
      .animation(AppMotion.pressAnimation())
      .accessibilitySelected(this.currentCat === catName)
      .id(`goods-cat-${catName}`)
      .onClick(() => {
        this.currentCat = catName
        this.updateFilteredGoods()
      })
  }

  // 生成评分星星字符串
  getStars(rating: number): string {
    let stars: string = ''
    for (let i = 0; i < rating; i++) {
      stars += '★'
    }
    return stars
  }

  @Builder
  StoreIntro() {
    Column() {
      // 店铺信息
      Column({ space: 6 }) {
        Row({ space: SPACING.MD }) {
          Image(merchantImageSource(this.storeImage))
            .alt(DEFAULT_MERCHANT_IMAGE)
            .width(84).height(84).objectFit(ImageFit.Contain)
            .backgroundColor(AppTheme.INPUT).borderRadius(AppTheme.CONTROL_RADIUS)
            .id('store-header-image')
          Column({ space: 6 }) {
        Row() {
          Text(this.storeName)
            .fontSize(FONT_SIZE.XL).fontWeight(FontWeight.Bold).fontColor(MODULE_COLOR.MERCHANT)
            .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Image(this.isFav ? $r('app.media.ui_heart_active') : $r('app.media.home_heart')).width(24).height(24).objectFit(ImageFit.Contain)
            .onClick(async () => {
              if (!isLoggedIn()) {
                promptAction.showToast({
                  message: '请先登录后再收藏',
                  duration: 1500
                })
                this.onNavigateLogin()
                return
              }
              const fav: boolean = await toggleFavoriteRemote(this.storeId)
              const errorMessage: string = getLastRemoteErrorMessage()
              if (errorMessage !== '') {
                promptAction.showToast({ message: errorMessage, duration: 2200 })
                return
              }
              this.isFav = fav
              promptAction.showToast({
                message: fav ? '已收藏' : '已取消收藏',
                duration: 2000
              })
            })
        }
        .width('100%')
        Row({ space: SPACING.SM }) {
          Text(`${this.storeRating}分`).fontSize(FONT_SIZE.MD).fontColor(COLORS.PRIMARY).fontWeight(FontWeight.Bold)
          Text(`月售${formatSales(this.storeMonthlySales)}`).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
          Text(`配送${this.storeDeliveryTime}`).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
        }
        Row({ space: SPACING.SM }) {
          Text(`配送费¥${this.storeDeliveryFee}`).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
          Text(`${this.storeMinOrder}元起送`).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
          Text(this.storeDistance).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
        }
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        }.width('100%').alignItems(VerticalAlign.Center)
        Row({ space: 6 }) {
          ForEach(this.storeTags, (tag: string) => {
            Text(tag).fontSize(FONT_SIZE.XS).fontColor(COLORS.TAG_TEXT)
              .backgroundColor(COLORS.TAG_BG)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 }).borderRadius(BORDER_RADIUS.SM)
          }, (tag: string) => tag)
        }
        Row({ space: SPACING.XS }) {
          Text('公告：').fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT)
          Text(this.storeNotice).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        }
      }
      .width('100%')
      .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.MD, bottom: SPACING.MD })
      .alignItems(HorizontalAlign.Start)
      .backgroundColor(AppTheme.CARD)
      .border({ width: { bottom: 1 }, color: AppTheme.BORDER })

      if (this.storeActivities.length > 0) {
        Column({ space: SPACING.XS }) {
          Text('店铺活动').fontSize(FONT_SIZE.MD).fontWeight(FontWeight.Bold).fontColor(MODULE_COLOR.MERCHANT).width('100%')
          Row({ space: SPACING.SM }) {
            ForEach(this.storeActivities, (act: MarketingActivity) => {
              Text(act.title)
                .fontSize(FONT_SIZE.XS).fontColor(COLORS.PRIMARY)
                .backgroundColor(COLORS.TAG_BG)
                .padding({ left: SPACING.SM, right: SPACING.SM, top: 4, bottom: 4 }).borderRadius(BORDER_RADIUS.SM)
            }, (act: MarketingActivity) => act.id.toString())
          }
          .width('100%')
        }
        .width('100%').padding(SPACING.LG).backgroundColor(MODULE_BG.MERCHANT).margin({ top: SPACING.SM })
      }

      if (this.storeSetmeals.length > 0) {
        Column({ space: SPACING.SM }) {
          Text('超值套餐').fontSize(FONT_SIZE.MD).fontWeight(FontWeight.Bold).fontColor(MODULE_COLOR.SPECIAL).width('100%')
          ForEach(this.storeSetmeals, (sm: Setmeal, index: number) => {
            Column({ space: SPACING.XS }) {
              Row() {
                Text(sm.name).fontSize(FONT_SIZE.MD).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY).layoutWeight(1).maxLines(1)
                Text(`¥${sm.price.toFixed(2)}`).fontSize(FONT_SIZE.LG).fontWeight(FontWeight.Bold).fontColor(COLORS.PRICE_RED)
                  .onClick(() => { this.buySetmeal(sm) })
              }.width('100%')
              Text(sm.items.map((it: SetmealItem) => it.goodsName).join(' + ')).fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_SECONDARY).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              if (sm.originalPrice > sm.price) {
                Text(`原价 ¥${sm.originalPrice.toFixed(2)}`).fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT).decoration({ type: TextDecorationType.LineThrough })
              }
            }
            .width('100%').padding(SPACING.MD).backgroundColor(accentBg(index)).borderRadius(BORDER_RADIUS.MD)
          }, (sm: Setmeal) => sm.id.toString())
        }
        .width('100%').padding(SPACING.LG).backgroundColor(MODULE_BG.SPECIAL).margin({ top: SPACING.SM })
      }

    }.width('100%')
  }

  @Builder
  CategoryBar() {
      // 分类Tab
      Scroll() {
        Row({ space: SPACING.SM }) {
          ForEach(this.goodsCats, (catName: string, index: number) => {
            this.CategoryFilter(catName)
          }, (catName: string) => catName)
        }
        .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.SM, bottom: SPACING.SM })
      }
      .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      .align(Alignment.Start)
      .width('100%').backgroundColor(COLORS.BG_WHITE)

  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
    Column() {
      // 店铺介绍与活动跟随列表滚动；原生分组表头吸顶，底部操作区独立。
      List() {
        ListItem() {
          this.StoreIntro()
        }
        ListItemGroup({ header: this.CategoryBar() }) {
          if (this.goodsLoading) {
            ListItem() {
              Text('正在加载商品…')
                .fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_HINT)
                .width('100%').textAlign(TextAlign.Center)
                .padding({ top: SPACING.XXL, bottom: SPACING.XXL })
            }
          } else if (this.filteredGoodsList.length === 0) {
            ListItem() {
              Column({ space: SPACING.SM }) {
                Text('暂无商品')
                  .fontSize(FONT_SIZE.LG).fontColor(COLORS.TEXT_HINT)
                Text('当前分类暂时没有可售商品')
                  .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT)
              }
              .width('100%').padding({ top: SPACING.XXL, bottom: SPACING.XXL })
              .alignItems(HorizontalAlign.Center)
            }
          } else {
            // 当前分类命中的商品数：id 里带数量，供设备端用例断言「切分类确实换了列表」
            ListItem() {
              Text(`共 ${this.filteredGoodsList.length} 件商品`)
                .id(`goods-count-${this.filteredGoodsList.length}`)
                .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT)
                .width('100%')
                .padding({ left: SPACING.LG, top: SPACING.SM, bottom: SPACING.SM })
            }
            LazyForEach(this.goodsDataSource, (goods: GoodsItem) => {
            ListItem() {
            Row({ space: SPACING.MD }) {
                // 商品图片：商户上传图拼 API 基址，无图/加载失败回退默认占位图
                Image(merchantImageSource(goods.image))
                  .alt(DEFAULT_MERCHANT_IMAGE)
                  .width(80).height(80).objectFit(ImageFit.Contain).borderRadius(BORDER_RADIUS.MD)
                  .backgroundColor(COLORS.BG_PRIMARY)

                // 商品信息
                Column({ space: SPACING.XS }) {
                  Row({ space: SPACING.XS }) {
                    Text(goods.name)
                      .fontSize(FONT_SIZE.LG).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
                      .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    if (goods.tag) {
                      Text(goods.tag)
                        .fontSize(FONT_SIZE.XS).fontColor(COLORS.PRICE_RED)
                        .borderWidth(1).borderColor(COLORS.PRICE_RED)
                        .padding({ left: 2, right: 2, top: 1, bottom: 1 }).borderRadius(BORDER_RADIUS.SM)
                    }
                    if (this.getSpecCount(goods) > 1) {
                      Text(`${this.getSpecCount(goods)} 种规格`)
                        .fontSize(FONT_SIZE.XS).fontColor(COLORS.TAG_TEXT)
                        .backgroundColor(COLORS.TAG_BG)
                        .padding({ left: SPACING.XS, right: SPACING.XS, top: 1, bottom: 1 })
                        .borderRadius(BORDER_RADIUS.SM)
                    }
                    // 限时秒杀：下单时后端自动按秒杀价结算
                    if (this.getSeckillPrice(goods.id) > 0) {
                      Text('⚡限时秒杀')
                        .fontSize(FONT_SIZE.XS).fontColor(COLORS.ON_PRIMARY)
                        .backgroundColor(COLORS.PRICE_RED)
                        .padding({ left: SPACING.XS, right: SPACING.XS, top: 1, bottom: 1 })
                        .borderRadius(BORDER_RADIUS.SM)
                    }
                  }
                  Text(goods.description)
                    .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT)
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  this.GoodsReviewSummary(goods)
                  Row({ space: SPACING.XS }) {
                    Text(`月售${formatSales(goods.sales)}`).fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT)
                    Text(`好评${goods.rating}%`).fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT)
                  }
                  Row() {
                    this.GoodsPriceArea(goods)
                    if (this.getStruckPrice(goods) > 0 && this.getStruckPrice(goods) > this.getDisplayPrice(goods)) {
                      Text(`¥${this.getStruckPrice(goods)}`).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT)
                        .decoration({ type: TextDecorationType.LineThrough }).margin({ left: 4 })
                    }
                    Blank()
                    this.AddMinusButton(goods)
                  }.width('100%')
                }
                .layoutWeight(1).alignItems(HorizontalAlign.Start)
              }
              .width('100%').padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.SM, bottom: SPACING.SM })
              .alignItems(VerticalAlign.Top)
              .backgroundColor(AppTheme.CARD)
              .border({ width: { bottom: 1 }, color: AppTheme.BORDER })
              }
            }, (item: GoodsItem) => `${item.id}`)
          }

          // 用户评价列表区域
          ListItem() {
            this.ReviewsSection()
          }
        }
      }
      .width('100%').layoutWeight(1)
      .id('store-detail-list')
      .sticky(StickyStyle.Header)
      .edgeEffect(EdgeEffect.Spring)
      .scrollBar(BarState.Off)
      .padding({ bottom: SPACING.XL })

      this.CartBar()
    }
    .width('100%').height('100%')
    CartAddFlight({ animator: this.cartAnimator })
    }.width('100%').height('100%').id('store-detail-content')
  }

  // 商品卡片价格：限时秒杀价优先，多规格菜品显示「¥最低规格价 起」
  @Builder
  GoodsPriceArea(goods: GoodsItem) {
    Row({ space: 2 }) {
      Text('¥').fontSize(FONT_SIZE.SM).fontColor(COLORS.PRICE_RED).fontWeight(FontWeight.Bold)
      Text(this.getDisplayPrice(goods).toString())
        .fontSize(FONT_SIZE.XL).fontColor(COLORS.PRICE_RED).fontWeight(FontWeight.Bold)
      if (this.hasSpecs(goods) && this.getSeckillPrice(goods.id) <= 0) {
        Text('起').fontSize(FONT_SIZE.SM).fontColor(COLORS.PRICE_RED)
      }
    }
  }

  @Builder
  AddMinusButton(goods: GoodsItem) {
    Row({ space: 0 }) {
      if (this.hasSpecs(goods)) {
        // 多规格菜品：规格价与规格库存各不相同，统一走选规格弹窗（后端要求 specId）
        Text('选规格')
          .fontSize(FONT_SIZE.SM).fontColor(COLORS.ON_PRIMARY)
          .backgroundColor(COLORS.PRIMARY)
          .borderRadius(BORDER_RADIUS.ROUND)
          .padding({ left: SPACING.SM, right: SPACING.SM, top: SPACING.XS, bottom: SPACING.XS })
          .onClick(() => {
            this.addGoodsToCart(goods)
          })
      } else {
        if (this.getQty(goods.id) > 0) {
          Text('-').id(`goods-minus-${goods.id}`).width(32).height(32).fontSize(16).fontColor(COLORS.ON_PRIMARY)
            .backgroundColor(COLORS.PRIMARY).borderRadius(BORDER_RADIUS.CIRCLE)
            .textAlign(TextAlign.Center).onClick(() => {
              this.changeGoodsQuantity(goods, -1)
            })
          Text(this.getQty(goods.id).toString()).id(`goods-qty-${goods.id}`)
            .width(28).height(32).fontSize(FONT_SIZE.MD)
            .fontColor(COLORS.TEXT_PRIMARY).textAlign(TextAlign.Center)
        }
        Text('+').id(`goods-plus-${goods.id}`).width(32).height(32).fontSize(16).fontColor(COLORS.ON_PRIMARY)
          .backgroundColor(COLORS.PRIMARY).borderRadius(BORDER_RADIUS.CIRCLE)
          .textAlign(TextAlign.Center).onClick(() => {
            this.addGoodsToCart(goods)
          })
      }
    }
  }

  private getGoodsReviews(goodsId: number): Review[] {
    return (this.storeReviews || []).filter((review: Review) => review.goodsId === goodsId)
  }

  private canReviewGoods(goodsId: number): boolean {
    const orders: Order[] = AppStorage.get<Order[]>('orderList') || []
    return orders.some((order: Order) => order.storeId === this.storeId && order.status === 4
      && (order.escrowStatus ?? 0) === 1 && order.reviewed === 0
      && (order.items || []).some((item: CartItem) => item.goods.id === goodsId))
  }

  private hasReviewedGoods(goodsId: number): boolean {
    const orders: Order[] = AppStorage.get<Order[]>('orderList') || []
    return orders.some((order: Order) => order.storeId === this.storeId && order.status === 4
      && (order.escrowStatus ?? 0) === 1 && order.reviewed === 1
      && (order.items || []).some((item: CartItem) => item.goods.id === goodsId))
  }

  private openGoodsReview(goodsId: number): void {
    const orders: Order[] = AppStorage.get<Order[]>('orderList') || []
    const order: Order | undefined = orders.find((item: Order) => item.storeId === this.storeId
      && item.status === 4 && (item.escrowStatus ?? 0) === 1 && item.reviewed === 0
      && (item.items || []).some((goodsItem: CartItem) => goodsItem.goods.id === goodsId))
    if (order === undefined) {
      promptAction.showToast({ message: '完成订单后才能评价该商品', duration: 1600 })
      return
    }
    AppStorage.setOrCreate<number>('currentOrderId', order.id)
    AppStorage.setOrCreate<number>('currentReviewGoodsId', goodsId)
    router.pushUrl({ url: 'pages/ReviewPage' })
  }

  @Builder
  GoodsReviewSummary(goods: GoodsItem) {
    Row({ space: SPACING.SM }) {
      Text(`评价${this.getGoodsReviews(goods.id).length}条`)
        .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT)
      if (this.getGoodsReviews(goods.id).length > 0) {
        Text(this.getGoodsReviews(goods.id)[0].content || '用户已评价')
          .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_SECONDARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
      } else {
        Text('暂无商品评价').fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT).layoutWeight(1)
      }
      Button(this.hasReviewedGoods(goods.id) ? '已评价' : (this.canReviewGoods(goods.id) ? '去评价' : '评价'))
        .height(24).padding({ left: 6, right: 6 }).fontSize(FONT_SIZE.XS)
        .fontColor(this.hasReviewedGoods(goods.id) ? COLORS.TEXT_SECONDARY : (this.canReviewGoods(goods.id) ? COLORS.ON_PRIMARY : COLORS.TEXT_SECONDARY))
        .backgroundColor(this.hasReviewedGoods(goods.id) ? COLORS.TEXT_HINT : (this.canReviewGoods(goods.id) ? COLORS.PRIMARY : COLORS.BG_PRIMARY))
        .enabled(!this.hasReviewedGoods(goods.id))
        .borderRadius(BORDER_RADIUS.ROUND)
        .onClick(() => {
          if (!this.hasReviewedGoods(goods.id)) {
            this.openGoodsReview(goods.id)
          }
        })
    }.width('100%')
  }

  @Builder
  CartBar() {
    Row() {
      Stack() {
        Image($r('app.media.home_nav_cart')).objectFit(ImageFit.Contain).width(50).height(50)
          .backgroundColor(COLORS.TAG_BG).padding(12).borderRadius(BORDER_RADIUS.ROUND)
        if (this.cartCount > 0) {
          Text(this.cartCount.toString())
            .fontSize(10).fontColor(COLORS.ON_PRIMARY).backgroundColor(COLORS.PRICE_RED)
            .borderRadius(BORDER_RADIUS.CIRCLE).textAlign(TextAlign.Center)
            .width(18).height(18)
        }
      }
      .alignContent(Alignment.TopEnd)
      .id('store-cart-target')
      .scale({ x: this.cartPulse, y: this.cartPulse })
      Column({ space: 2 }) {
        Row({ space: 2 }) {
          Text('¥').fontSize(FONT_SIZE.SM).fontColor(COLORS.PRICE_RED)
          Text(this.cartTotal.toFixed(2)).id('store-cart-total').fontSize(FONT_SIZE.XL).fontColor(COLORS.PRICE_RED).fontWeight(FontWeight.Bold)
        }
        Text(`另需配送费¥${this.storeDeliveryFee}`).fontSize(FONT_SIZE.XS)
          .fontColor(COLORS.TEXT_SECONDARY)
      }
      .margin({ left: SPACING.SM }).alignItems(HorizontalAlign.Start)
      Blank()
      Button(this.cartCount > 0 ? `去结算(${this.cartCount})` : '去购物')
        .attributeModifier(new AppButtonStyle())
        .height(40).fontSize(FONT_SIZE.MD).fontColor(COLORS.ON_PRIMARY)
        .backgroundColor(COLORS.PRIMARY)
        .borderRadius(BORDER_RADIUS.ROUND)
        .id('store-checkout')
        .width(100)
        .onClick(() => {
          if (this.cartCount > 0) {
            AppStorage.setOrCreate<number>('checkoutStoreId', this.storeId)
            router.pushUrl({ url: 'pages/CheckoutPage' })
          } else {
            promptAction.showToast({ message: '购物车还是空的，请先选择商品', duration: 1600 })
          }
        })
    }
    .width('100%').height(72)
    .padding({ left: SPACING.LG, right: SPACING.SM })
    .backgroundColor(COLORS.BG_CARD)
    .border({ width: { top: 1 }, color: COLORS.DIVIDER })
  }

  @Builder
  ReviewsSection() {
    Column({ space: SPACING.SM }) {
      Text(`用户评价（${this.storeReviews.length}条）`)
        .fontSize(FONT_SIZE.LG).fontWeight(FontWeight.Bold).fontColor(MODULE_COLOR.REVIEW)
        .width('100%').padding(SPACING.SM)
        .backgroundColor(MODULE_BG.REVIEW)
        .borderRadius(BORDER_RADIUS.MD)

      if (this.storeReviews.length === 0) {
        Text('暂无评价')
          .fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_HINT)
          .width('100%').textAlign(TextAlign.Center)
          .padding({ top: SPACING.LG, bottom: SPACING.LG })
      } else {
        ForEach(this.storeReviews.slice(0, 3), (review: Review) => {
          Column({ space: SPACING.XS }) {
            Row({ space: SPACING.SM }) {
              Text(review.anonymous === 1 ? '匿名用户' : review.username)
                .fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_PRIMARY).fontWeight(FontWeight.Bold)
              Text(this.getStars(review.rating))
                .fontSize(FONT_SIZE.SM).fontColor(COLORS.WARNING)
            }
            .width('100%')
            Text(review.content)
              .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
              .width('100%')
            // 图文评价：用户上传的图片（点击可全屏查看）
            if (this.hasReviewImages(review)) {
              Row({ space: SPACING.XS }) {
                ForEach(review.images.slice(0, 3), (imageUrl: string, index: number) => {
                  Image(imageUrl)
                    .width(72)
                    .height(72)
                    .borderRadius(BORDER_RADIUS.SM)
                    .objectFit(ImageFit.Cover)
                    .id(`store-review-image-${index}`)
                    .onClick(() => { this.previewReviewImage(imageUrl) })
                }, (imageUrl: string, index: number) => `${index}_${imageUrl}`)
              }
              .width('100%')
            }
            if (review.goodsId > 0) {
              Text(`评价商品：${this.getGoodsName(review.goodsId)}`)
                .fontSize(FONT_SIZE.XS).fontColor(COLORS.PRIMARY).width('100%')
            }
            if (review.tags.length > 0) {
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(review.tags, (tag: string) => {
                  Text(tag)
                    .fontSize(FONT_SIZE.XS).fontColor(COLORS.TAG_TEXT).backgroundColor(COLORS.TAG_BG)
                    .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                    .borderRadius(BORDER_RADIUS.SM)
                    .margin({ right: 4, bottom: 4 })
                }, (tag: string) => tag)
              }
              .width('100%')
            }
            Text(review.createTime)
              .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT)
              .width('100%')
            if (review.reply !== '') {
              Column({ space: SPACING.XS }) {
                Text('商家回复')
                  .fontSize(FONT_SIZE.XS).fontColor(COLORS.PRIMARY).fontWeight(FontWeight.Bold)
                  .width('100%')
                Text(review.reply)
                  .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
                  .width('100%')
              }
              .width('100%')
              .padding(SPACING.MD)
              .backgroundColor(COLORS.BG_PRIMARY)
              .borderRadius(BORDER_RADIUS.SM)
            }
          }
            .attributeModifier(new AppCardStyle())
          .width('100%')
          .padding(SPACING.MD)
        }, (review: Review) => review.id.toString())
      }
    }
    .width('100%')
    .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.MD, bottom: SPACING.LG })
  }

  /** 该评价是否带图（历史评价可能没有 images 字段）。 */
  private hasReviewImages(review: Review): boolean {
    const images: string[] = review.images
    return Array.isArray(images) && images.length > 0
  }

  /** 点击评价图片：进入全屏预览页。 */
  private previewReviewImage(imageUrl: string): void {
    // 注意：日志里不要写「地址=」，AppLogger 的脱敏规则会把「地址=xxx」整段替换成 [REDACTED_ADDRESS]
    logInfo('Review', `点击评价图片，进入预览页（有图片=${imageUrl !== ''}）`)
    if (imageUrl === '') {
      promptAction.showToast({ message: '图片地址为空，无法预览', duration: 2000 })
      return
    }
    AppStorage.setOrCreate<string>('reviewPreviewUrl', imageUrl)
    router.pushUrl({ url: 'pages/ReviewImagePage' })
  }

  private getGoodsName(goodsId: number): string {
    const goods: GoodsItem | undefined = this.goodsList.find((item: GoodsItem) => item.id === goodsId)
    return goods === undefined ? '店内商品' : goods.name
  }

  getQty(goodsId: number): number {
    // 必须读被观察的 this.cartItems，而不是 AppStorage.get：
    // 后者绕过状态观察，行内不会建立依赖，数量变化时该行不会刷新。
    const currentCart: CartItem[] = this.cartItems || []
    const item: CartItem | undefined = currentCart.find((cartItem: CartItem) =>
      cartItem.goods.id === goodsId && cartItem.storeId === this.storeId)
    return item ? item.quantity : 0
  }
}

// ===================== 个人中心 =====================

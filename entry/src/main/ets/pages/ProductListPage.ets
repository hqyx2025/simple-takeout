/**
 * 商品列表页：承接主页分类、附近商品和附近全部商品入口。
 */
import { Address, GoodsItem, StoreItem } from '../model/Models'
import { getAllStoresList, getGoodsForStore, syncStoresFromServer, syncGoodsFromServer } from '../service/AppStorageManager'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS } from '../common/Constants'
import { EmptyState } from '../components/EmptyState'
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { logInfo } from '../service/AppLogger'

class ProductListMode {
  static readonly CATEGORY: string = 'category'
  static readonly NEARBY: string = 'nearby'
  static readonly ALL: string = 'all'
  static readonly SPECIAL: string = 'special'
  static readonly RANKING: string = 'ranking'
}

class ProductListItem {
  store: StoreItem
  goods: GoodsItem

  constructor(store: StoreItem, goods: GoodsItem) {
    this.store = store
    this.goods = goods
  }
}

@Entry
@Component
export struct ProductListPage {
  @StorageLink('isLoggedIn') loggedIn: boolean = false
  @StorageLink('currentAddress') currentAddress: Address | null = null
  @State mode: string = ProductListMode.ALL
  @State title: string = '附近全部商品'
  @State categoryId: number = 0
  @State products: ProductListItem[] = []
  @State categoryStores: StoreItem[] = []

  aboutToAppear(): void {
    this.readRequest()
    if (!this.loggedIn) {
      return
    }
    this.loadProducts()
  }

  onPageShow(): void {
    // 从定位页返回后重新按最新定位筛选商品。
    if (this.loggedIn) {
      this.loadProducts()
    }
  }

  private readRequest(): void {
    this.mode = AppStorage.get<string>('productListMode') || ProductListMode.ALL
    this.title = AppStorage.get<string>('productListTitle') || '附近全部商品'
    this.categoryId = AppStorage.get<number>('productListCategoryId') || 0
  }

  private hasLocation(): boolean {
    if (this.currentAddress === null) {
      return false
    }
    const address: Address = this.currentAddress as Address
    return address.address.trim() !== '' || address.detail.trim() !== '' ||
      (address.latitude !== undefined && address.longitude !== undefined)
  }

  private parseDistance(distance: string): number {
    const match: RegExpMatchArray | null = distance.match(/([0-9]+(?:\.[0-9]+)?)/)
    if (match === null) {
      return Number.MAX_VALUE
    }
    return Number.parseFloat(match[1])
  }

  private getCandidateStores(): StoreItem[] {
    const stores: StoreItem[] = getAllStoresList()
    if ((this.mode === ProductListMode.NEARBY || this.mode === ProductListMode.ALL ||
      this.mode === ProductListMode.SPECIAL || this.mode === ProductListMode.RANKING) && !this.hasLocation()) {
      return []
    }

    // 服务端 StoreItem.distance 表示当前定位到店铺的距离；附近取 2km 内，
    // 查看全部取当前定位周边 5km 内的全部店铺。
    const radius: number = this.mode === ProductListMode.NEARBY ? 2.0 : 5.0
    if (this.mode === ProductListMode.CATEGORY && !this.hasLocation()) {
      return stores
    }
    return stores.filter((store: StoreItem) => this.parseDistance(store.distance) <= radius)
  }

  private async loadProducts(): Promise<void> {
    await syncStoresFromServer()
    const candidates: StoreItem[] = this.getCandidateStores()
    if (this.mode === ProductListMode.CATEGORY) {
      this.categoryStores = candidates.filter((store: StoreItem) => this.matchesCategory(store))
      this.products = []
      return
    }
    this.categoryStores = []
    const result: ProductListItem[] = []
    const currentMode: string = this.mode
    const currentCategoryId: number = this.categoryId
    for (let i = 0; i < candidates.length; i++) {
      const store: StoreItem = candidates[i]
      await syncGoodsFromServer(store.id)
      const goods: GoodsItem[] = getGoodsForStore(store.id)
      goods.forEach((item: GoodsItem) => {
        const productCategoryId: number = this.getProductCategoryId(store, item)
        if (currentMode === ProductListMode.CATEGORY && currentCategoryId > 0) {
          if (productCategoryId !== currentCategoryId) {
            return
          }
        }
        if (currentMode === ProductListMode.SPECIAL && item.tag === undefined && item.sales < 1000) {
          return
        }
        result.push(new ProductListItem(store, item))
      })
    }

    if (this.mode === ProductListMode.RANKING || this.mode === ProductListMode.SPECIAL) {
      result.sort((left: ProductListItem, right: ProductListItem) => right.goods.sales - left.goods.sales)
    }
    this.products = result
  }

  private matchesCategory(store: StoreItem): boolean {
    if (this.categoryId <= 0) {
      return true
    }
    if (store.categoryId === this.categoryId) {
      return true
    }
    const categoryIds: number[] = store.categoryIds || []
    return categoryIds.indexOf(this.categoryId) >= 0
  }

  private getProductCategoryId(store: StoreItem, item: GoodsItem): number {
    // 扩展商品使用统一描述生成；这类商品没有独立食品分类，按所属店铺主分类归类，
    // 避免所有店铺的扩展菜品被错误分散到同一个分类。
    if (item.description.indexOf('美味可口') >= 0) {
      return store.categoryId
    }
    return item.categoryId
  }

  private getLocationText(): string {
    if (!this.hasLocation()) {
      return '未定位，请先选择配送位置'
    }
    const address: Address = this.currentAddress as Address
    const text: string = `${address.address} ${address.detail}`.trim()
    return text === '' ? '当前位置商品' : text
  }

  private goToLocation(): void {
    if (!(AppStorage.get<boolean>('isLoggedIn') || false)) {
      AppStorage.setOrCreate<boolean>('pendingLocationLoginPrompt', true)
      router.back()
      return
    }
    router.pushUrl({ url: 'pages/LocationPage' })
  }

  private openStore(item: ProductListItem): void {
    this.prepareStoreDetail(item.store)
    router.back()
  }

  private openStoreByStore(store: StoreItem): void {
    this.prepareStoreDetail(store)
    router.back()
  }

  /**
   * 返回首页时同时写入两个导航状态：currentStoreId 供 Index.onPageShow 消费，
   * selectedStoreId 供 DiscoverTab 立即渲染，避免只设置单一状态导致点击后停留在列表页。
   */
  private prepareStoreDetail(store: StoreItem): void {
    AppStorage.setOrCreate<number>('currentStoreId', store.id)
    AppStorage.setOrCreate<number>('selectedStoreId', store.id)
    AppStorage.setOrCreate<string>('selectedStoreName', store.name)
    // 标记本次返回必须打开店铺详情，避免返回首页过程中 currentStoreId 被旧页面生命周期覆盖。
    AppStorage.setOrCreate<boolean>('pendingStoreDetail', true)
    logInfo('Navigation', `ProductListPage prepare store detail storeId=${store.id} name=${store.name}`)
  }

  @Builder
  StoreResultCard(store: StoreItem) {
    Row({ space: SPACING.MD }) {
      Text(store.name.substring(0, 1))
        .width(56)
        .height(56)
        .fontSize(FONT_SIZE.XL)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLORS.PRIMARY)
        .backgroundColor('#FFF1EB')
        .borderRadius(BORDER_RADIUS.MD)
        .textAlign(TextAlign.Center)
      Column({ space: 4 }) {
        Text(store.name)
          .fontSize(FONT_SIZE.LG)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Row({ space: SPACING.SM }) {
          Text(`${store.rating} 分`).fontSize(FONT_SIZE.SM).fontColor(COLORS.PRIMARY)
          Text(`月售${store.monthlySales}`).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
          Text(store.deliveryTime).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
        }
        Row({ space: SPACING.SM }) {
          Text(`配送费¥${store.deliveryFee}`).fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT)
          Text(`${store.minOrder}元起送`).fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT)
          Text(store.distance).fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT)
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(SPACING.LG)
    .backgroundColor(COLORS.BG_WHITE)
    .borderRadius(BORDER_RADIUS.LG)
  }

  build() {
    Column() {
      Row() {
        Text('‹')
          .fontSize(FONT_SIZE.XXL)
          .fontColor(COLORS.TEXT_PRIMARY)
          .onClick(() => { router.back() })
        Column({ space: 2 }) {
          Text(this.title)
            .fontSize(FONT_SIZE.XL)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLORS.TEXT_PRIMARY)
          Text(this.getLocationText())
            .fontSize(FONT_SIZE.XS)
            .fontColor(COLORS.TEXT_HINT)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)
        Text('')
          .fontSize(FONT_SIZE.XXL)
      }
      .width('100%')
      .height(64)
      .padding({ left: SPACING.LG, right: SPACING.LG })
      .backgroundColor(COLORS.BG_WHITE)

      if (!this.loggedIn) {
        EmptyState({ icon: '🔒', title: '暂无登录', description: '请登录后查看商品' })
      } else if (this.mode === ProductListMode.CATEGORY) {
        if (this.categoryStores.length === 0) {
          EmptyState({ icon: '🏪', title: '暂无该分类店铺', description: '当前分类暂时没有可展示的店铺' })
        } else {
          List({ space: SPACING.SM }) {
            ForEach(this.categoryStores, (store: StoreItem) => {
              ListItem() {
                this.StoreResultCard(store)
              }
              .onClick(() => { this.openStoreByStore(store) })
            }, (store: StoreItem) => store.id.toString())
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.SM, bottom: SPACING.LG })
          .divider({ strokeWidth: 0 })
        }
      } else if (!this.hasLocation()) {
        Column({ space: SPACING.MD }) {
          EmptyState({ icon: '📍', title: '请先选择配送位置', description: '定位后才能展示附近商品' })
          Button('去选择位置')
            .height(44)
            .padding({ left: SPACING.XL, right: SPACING.XL })
            .fontSize(FONT_SIZE.MD)
            .fontColor(Color.White)
            .backgroundColor(COLORS.PRIMARY)
            .borderRadius(BORDER_RADIUS.ROUND)
            .type(ButtonType.Capsule)
            .onClick(() => { this.goToLocation() })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else if (this.products.length === 0) {
        EmptyState({ icon: '🍽️', title: '暂无符合条件的商品', description: '可以换个分类或查看附近全部商品' })
      } else {
        List({ space: SPACING.SM }) {
          ForEach(this.products, (item: ProductListItem) => {
            ListItem() {
              Column({ space: SPACING.SM }) {
                Row() {
                  Text(item.goods.name)
                    .fontSize(FONT_SIZE.LG)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(COLORS.TEXT_PRIMARY)
                    .layoutWeight(1)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(`¥${item.goods.price.toFixed(2)}`)
                    .fontSize(FONT_SIZE.LG)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(COLORS.PRICE_RED)
                }
                Text(item.goods.description)
                  .fontSize(FONT_SIZE.SM)
                  .fontColor(COLORS.TEXT_SECONDARY)
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
                Row({ space: SPACING.SM }) {
                  Text(item.store.name)
                    .fontSize(FONT_SIZE.SM)
                    .fontColor(COLORS.PRIMARY)
                  Text(`月售${item.goods.sales}`)
                    .fontSize(FONT_SIZE.XS)
                    .fontColor(COLORS.TEXT_HINT)
                  Text(`${item.store.distance}`)
                    .fontSize(FONT_SIZE.XS)
                    .fontColor(COLORS.TEXT_HINT)
                  if (item.goods.tag !== undefined && item.goods.tag !== '') {
                    Text(item.goods.tag)
                      .fontSize(FONT_SIZE.XS)
                      .fontColor(COLORS.TAG_TEXT)
                      .backgroundColor(COLORS.TAG_BG)
                      .padding({ left: SPACING.XS, right: SPACING.XS, top: 2, bottom: 2 })
                      .borderRadius(BORDER_RADIUS.SM)
                  }
                }
                .width('100%')
              }
              .width('100%')
              .padding(SPACING.LG)
              .backgroundColor(COLORS.BG_WHITE)
              .borderRadius(BORDER_RADIUS.LG)
              .onClick(() => { this.openStore(item) })
            }
          }, (item: ProductListItem) => `${item.store.id}-${item.goods.id}`)
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.SM, bottom: SPACING.LG })
        .divider({ strokeWidth: 0 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(COLORS.BG_PRIMARY)
  }
}

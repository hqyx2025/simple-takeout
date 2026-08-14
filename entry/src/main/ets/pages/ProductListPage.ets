/**
 * 商品列表页：承接主页分类、附近商品和附近全部商品入口。
 */
import { Address, GoodsItem, StoreItem } from '../model/Models'
import { getAllStoresList, getGoodsForStore } from '../service/AppStorageManager'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS } from '../common/Constants'
import { EmptyState } from '../components/EmptyState'
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'

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
  @StorageLink('currentAddress') currentAddress: Address | null = null
  @State mode: string = ProductListMode.ALL
  @State title: string = '附近全部商品'
  @State categoryId: number = 0
  @State products: ProductListItem[] = []

  aboutToAppear(): void {
    this.readRequest()
    this.loadProducts()
  }

  onPageShow(): void {
    // 从定位页返回后重新按最新定位筛选商品。
    this.loadProducts()
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

    // Mock/服务端 StoreItem.distance 表示当前定位到店铺的距离；附近取 2km 内，
    // 查看全部取当前定位周边 5km 内的全部店铺。
    const radius: number = this.mode === ProductListMode.NEARBY ? 2.0 : 5.0
    if (this.mode === ProductListMode.CATEGORY && !this.hasLocation()) {
      return stores
    }
    return stores.filter((store: StoreItem) => this.parseDistance(store.distance) <= radius)
  }

  private loadProducts(): void {
    const candidates: StoreItem[] = this.getCandidateStores()
    const result: ProductListItem[] = []
    candidates.forEach((store: StoreItem) => {
      const goods: GoodsItem[] = getGoodsForStore(store.id)
      goods.forEach((item: GoodsItem) => {
        const productCategoryId: number = this.getProductCategoryId(store, item)
        if (this.mode === ProductListMode.CATEGORY && this.categoryId > 0) {
          if (productCategoryId !== this.categoryId) {
            return
          }
        }
        if (this.mode === ProductListMode.SPECIAL && item.tag === undefined && item.sales < 1000) {
          return
        }
        result.push(new ProductListItem(store, item))
      })
    })

    if (this.mode === ProductListMode.RANKING || this.mode === ProductListMode.SPECIAL) {
      result.sort((left: ProductListItem, right: ProductListItem) => right.goods.sales - left.goods.sales)
    }
    this.products = result
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
    router.pushUrl({ url: 'pages/LocationPage' })
  }

  private openStore(item: ProductListItem): void {
    AppStorage.setOrCreate<number>('currentStoreId', item.store.id)
    router.back()
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

      if (!this.hasLocation() && this.mode !== ProductListMode.CATEGORY) {
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

/**
 * 榜单页：店铺榜（按月销量+评分排序）与菜品热销榜（跨店铺按累计销量排序）。
 * 数据全部来自后端榜单接口；名次徽章前三名使用强调色，点击条目进入店铺详情页。
 */
import { SpecialGoodsItem, StoreItem } from '../model/Models'
import { fetchRankGoodsRemote, fetchRankStoresRemote, getLastRemoteErrorMessage } from '../service/AppStorageManager'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS, formatSales, merchantImageSource, DEFAULT_MERCHANT_IMAGE, MODULE_COLOR, MODULE_BG } from '../common/Constants'
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { RatingStars } from '../components/RatingStars'
import { EmptyState } from '../components/EmptyState'
import { LoadingIndicator } from '../components/LoadingIndicator'
import { PageHeader } from '../components/PageHeader'
import { logInfo } from '../service/AppLogger'

/** 单次拉取条数（后端限制 1-50） */
const RANK_LIMIT: number = 20

@Entry
@Component
export struct RankingPage {
  @StorageLink('isLoggedIn') loggedIn: boolean = false
  @State currentTab: number = 0
  @State storeList: StoreItem[] = []
  @State goodsList: SpecialGoodsItem[] = []
  @State loading: boolean = true
  @State refreshing: boolean = false
  @State storeError: string = ''
  @State goodsError: string = ''

  aboutToAppear(): void {
    logInfo('Page', '进入榜单页 RankingPage')
    this.loadRankData(true)
  }

  /** 拉取两个榜单；showLoading=false 用于下拉刷新与点击重试，避免整页闪烁 */
  private async loadRankData(showLoading: boolean): Promise<void> {
    if (showLoading) {
      this.loading = true
    }
    if (!this.loggedIn) {
      this.storeList = []
      this.goodsList = []
      this.storeError = ''
      this.goodsError = ''
      this.loading = false
      this.refreshing = false
      return
    }
    const stores: StoreItem[] = await fetchRankStoresRemote(RANK_LIMIT)
    this.storeError = getLastRemoteErrorMessage()
    this.storeList = Array.isArray(stores) ? stores : []
    const goods: SpecialGoodsItem[] = await fetchRankGoodsRemote(RANK_LIMIT)
    this.goodsError = getLastRemoteErrorMessage()
    this.goodsList = Array.isArray(goods) ? goods : []
    this.loading = false
    this.refreshing = false
    if (this.storeError !== '' || this.goodsError !== '') {
      // 后端业务失败 / 网络异常都要给出具体原因，不能静默留空列表
      const reason: string = this.storeError !== '' ? this.storeError : this.goodsError
      promptAction.showToast({ message: `榜单加载失败：${reason}`, duration: 3000 })
      return
    }
    logInfo('Rank', `榜单加载完成 店铺=${this.storeList.length} 菜品=${this.goodsList.length}`)
  }

  private switchTab(index: number): void {
    if (this.currentTab === index) {
      return
    }
    this.currentTab = index
    logInfo('Rank', `榜单切换 Tab=${index}`)
  }

  /** 名次徽章底色：前三名用金/银/铜强调色，其余用中性底色 */
  private rankBadgeColor(rank: number): ResourceColor {
    if (rank === 1) {
      return COLORS.SECONDARY
    }
    if (rank === 2) {
      return COLORS.WARNING
    }
    if (rank === 3) {
      return COLORS.PRIMARY
    }
    return COLORS.BG_PRIMARY
  }

  private rankTextColor(rank: number): ResourceColor {
    if (rank === 1) {
      return COLORS.TEXT_PRIMARY
    }
    if (rank === 2 || rank === 3) {
      return COLORS.TEXT_WHITE
    }
    return COLORS.TEXT_SECONDARY
  }

  /**
   * 打开店铺详情页。
   * StoreDetailPage 通过 @StorageLink('selectedStoreId'/'selectedStoreName') 取参（不读路由 params），
   * 因此必须先写入 AppStorage 再 pushUrl，与首页 showStoreDetail 的做法保持一致。
   */
  private openStoreDetail(storeId: number, storeName: string): void {
    if (storeId <= 0) {
      promptAction.showToast({ message: '店铺信息不完整，无法打开详情', duration: 2200 })
      return
    }
    AppStorage.setOrCreate<number>('selectedStoreId', storeId)
    AppStorage.setOrCreate<string>('selectedStoreName', storeName !== '' ? storeName : '店铺详情')
    logInfo('Navigation', `榜单跳转店铺详情 storeId=${storeId} storeName=${storeName}`)
    router.pushUrl({ url: 'pages/StoreDetailPage' })
  }

  @Builder
  RankBadge(rank: number) {
    Column() {
      Text(rank.toString())
        .fontSize(FONT_SIZE.SM)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.rankTextColor(rank))
    }
    .width(26)
    .height(26)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.rankBadgeColor(rank))
    .borderRadius(BORDER_RADIUS.SM)
  }

  /** 每个榜单一种模块色，避免两个 Tab 完全同色。 */
  private tabColor(index: number): ResourceColor {
    return index === 0 ? MODULE_COLOR.NEARBY : MODULE_COLOR.SPECIAL
  }

  @Builder
  TabButton(title: string, index: number) {
    Column({ space: SPACING.XS }) {
      Text(title)
        .fontSize(FONT_SIZE.MD)
        .fontWeight(this.currentTab === index ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.currentTab === index ? this.tabColor(index) : COLORS.TEXT_SECONDARY)
      Divider()
        .strokeWidth(2)
        .color(this.currentTab === index ? this.tabColor(index) : COLORS.DIVIDER)
    }
    .layoutWeight(1)
    .height(48)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => { this.switchTab(index) })
  }

  @Builder
  StoreRankItem(item: StoreItem, rank: number) {
    Row({ space: SPACING.MD }) {
      this.RankBadge(rank)
      Column({ space: SPACING.XS }) {
        Text(item.name)
          .fontSize(FONT_SIZE.LG)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Row({ space: SPACING.SM }) {
          RatingStars({ rating: item.rating, fontSize: FONT_SIZE.SM, showNumber: true })
          Text(`月售 ${formatSales(item.monthlySales)}`)
            .fontSize(FONT_SIZE.SM)
            .fontColor(COLORS.TEXT_SECONDARY)
          if (item.distance !== '') {
            Text(item.distance)
              .fontSize(FONT_SIZE.SM)
              .fontColor(COLORS.TEXT_SECONDARY)
          }
        }
        .alignItems(VerticalAlign.Center)
        Text(`¥${item.minOrder.toFixed(2)} 起送`)
          .fontSize(FONT_SIZE.SM)
          .fontColor(COLORS.PRIMARY)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text('›')
        .fontSize(FONT_SIZE.XL)
        .fontColor(COLORS.TEXT_HINT)
    }
    .width('100%')
    .padding(SPACING.LG)
    .backgroundColor(COLORS.BG_WHITE)
    .borderRadius(BORDER_RADIUS.LG)
    .alignItems(VerticalAlign.Center)
    .onClick(() => { this.openStoreDetail(item.id, item.name) })
  }

  @Builder
  GoodsRankItem(item: SpecialGoodsItem, rank: number) {
    Row({ space: SPACING.MD }) {
      this.RankBadge(rank)
      Image(merchantImageSource(item.goods.image))
        .alt(DEFAULT_MERCHANT_IMAGE)
        .width(64)
        .height(64)
        .objectFit(ImageFit.Cover)
        .borderRadius(BORDER_RADIUS.MD)
      Column({ space: SPACING.XS }) {
        Text(item.goods.name)
          .fontSize(FONT_SIZE.LG)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Row({ space: SPACING.SM }) {
          Text(`店铺：${item.storeName}`)
            .fontSize(FONT_SIZE.SM)
            .fontColor(COLORS.TEXT_SECONDARY)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          if (item.storeDistance !== '') {
            Text(item.storeDistance)
              .fontSize(FONT_SIZE.SM)
              .fontColor(COLORS.TEXT_SECONDARY)
          }
        }
        .alignItems(VerticalAlign.Center)
        .width('100%')
        Row() {
          Text(`销量 ${formatSales(item.goods.sales)}`)
            .fontSize(FONT_SIZE.SM)
            .fontColor(COLORS.TEXT_SECONDARY)
          Blank()
          Text(`¥${item.goods.price.toFixed(2)}`)
            .fontSize(FONT_SIZE.LG)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLORS.PRICE_RED)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text('›')
        .fontSize(FONT_SIZE.XL)
        .fontColor(COLORS.TEXT_HINT)
    }
    .width('100%')
    .padding(SPACING.LG)
    .backgroundColor(COLORS.BG_WHITE)
    .borderRadius(BORDER_RADIUS.LG)
    .alignItems(VerticalAlign.Center)
    .onClick(() => { this.openStoreDetail(item.goods.storeId ?? 0, item.storeName) })
  }

  @Builder
  ErrorView(reason: string) {
    Column({ space: SPACING.MD }) {
      SymbolGlyph($r('sys.symbol.dot_radiowaves'))
        .fontSize(52)
      Text(`榜单加载失败：${reason}`)
        .fontSize(FONT_SIZE.MD)
        .fontColor(COLORS.TEXT_SECONDARY)
        .textAlign(TextAlign.Center)
        .padding({ left: SPACING.XL, right: SPACING.XL })
      Button('点击重试')
        .height(40)
        .fontSize(FONT_SIZE.MD)
        .fontColor(COLORS.TEXT_WHITE)
        .backgroundColor(COLORS.PRIMARY)
        .borderRadius(BORDER_RADIUS.ROUND)
        .type(ButtonType.Capsule)
        .padding({ left: SPACING.XL, right: SPACING.XL })
        .onClick(() => { this.loadRankData(false) })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  RankHint(text: string) {
    Text(text)
      .fontSize(FONT_SIZE.XS)
      .fontColor(COLORS.TEXT_HINT)
      .width('100%')
      .padding({
        left: SPACING.LG,
        right: SPACING.LG,
        top: SPACING.SM,
        bottom: SPACING.SM
      })
      .backgroundColor(COLORS.BG_PRIMARY)
  }

  build() {
    Column() {
      // 顶部导航栏
      PageHeader({ title: '榜单', onBack: () => { router.back() } })

      // Tab 切换（自绘 Tab，与优惠券中心页风格一致）
      Row() {
        this.TabButton('店铺榜', 0)
        this.TabButton('菜品榜', 1)
      }
      .width('100%')
      .backgroundColor(MODULE_BG.RANKING)

      // 内容区
      if (this.loading) {
        LoadingIndicator({ text: '榜单加载中...' })
      } else if (!this.loggedIn) {
        EmptyState({ icon: '🔒', title: '暂无登录', description: '请登录后查看榜单' })
      } else if (this.currentTab === 0) {
        this.RankHint('店铺榜按月销量排序，同销量时按评分排序（仅营业店铺）')
        if (this.storeError !== '') {
          this.ErrorView(this.storeError)
        } else if (!Array.isArray(this.storeList) || this.storeList.length === 0) {
          EmptyState({ icon: '🏆', title: '暂无店铺榜单', description: '暂时没有营业中的店铺数据' })
        } else {
          Refresh({ refreshing: this.refreshing }) {
            List({ space: SPACING.MD }) {
              ForEach(this.storeList, (item: StoreItem, index: number) => {
                ListItem() {
                  this.StoreRankItem(item, index + 1)
                }
              }, (item: StoreItem) => item.id.toString())
            }
            .width('100%')
            .height('100%')
            .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.SM, bottom: SPACING.XL })
            .scrollBar(BarState.Off)
            .divider({ strokeWidth: 0 })
            .cachedCount(5)
          }
          .layoutWeight(1)
          .pullToRefresh(true)
          .onRefreshing(() => {
            this.refreshing = true
            this.loadRankData(false)
          })
        }
      } else {
        this.RankHint('菜品榜为跨店铺累计销量排行，点击可进入所属店铺')
        if (this.goodsError !== '') {
          this.ErrorView(this.goodsError)
        } else if (!Array.isArray(this.goodsList) || this.goodsList.length === 0) {
          EmptyState({ icon: '🍜', title: '暂无菜品榜单', description: '暂时没有热销菜品数据' })
        } else {
          Refresh({ refreshing: this.refreshing }) {
            List({ space: SPACING.MD }) {
              ForEach(this.goodsList, (item: SpecialGoodsItem, index: number) => {
                ListItem() {
                  this.GoodsRankItem(item, index + 1)
                }
              }, (item: SpecialGoodsItem) => item.goods.id.toString())
            }
            .width('100%')
            .height('100%')
            .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.SM, bottom: SPACING.XL })
            .scrollBar(BarState.Off)
            .divider({ strokeWidth: 0 })
            .cachedCount(5)
          }
          .layoutWeight(1)
          .pullToRefresh(true)
          .onRefreshing(() => {
            this.refreshing = true
            this.loadRankData(false)
          })
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(COLORS.BG_PRIMARY)
  }
}

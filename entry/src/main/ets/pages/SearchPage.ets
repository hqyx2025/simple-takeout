import { MatchText } from '../components/MatchText'
import { AppButtonStyle, AppCardStyle, AppSearchStyle } from '../common/theme/AppTheme'
import { PageHeader } from '../components/PageHeader'
import { LoadingIndicator } from '../components/LoadingIndicator'
/**
 * 搜索页 - 热门搜索、历史搜索、店铺搜索结果
 */
import { AppMotion } from '../common/theme/AppMotion'
import { Address, StoreItem, User, createEmptyUser } from '../model/Models'
import { SearchStoreDataSource } from '../model/SearchStoreDataSource'
import { formatSales } from '../common/Constants'
import { searchStoresResultApi, StoreSearchResult } from '../service/api/CatalogApi'
import { getAuthSessionEpoch } from '../service/HttpClient'
import { getSearchHistory, addSearchHistory, clearSearchHistory } from '../service/PreferencesHelper'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS, MODULE_COLOR, accentFg, accentIndexFromText, merchantImageSource, DEFAULT_MERCHANT_IMAGE } from '../common/Constants'
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { logInfo } from '../service/AppLogger'

@Entry
@Component
export struct SearchPage {
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

  @StorageLink('isLoggedIn') @Watch('resetSearch') loggedIn: boolean = false
  @StorageProp('user') @Watch('onSearchOwnerChange') searchOwner: User = createEmptyUser()
  @State searchText: string = ''
  @State hotWords: string[] = []
  @State historyWords: string[] = []
  @State resultCount: number = 0
  @State hasSearched: boolean = false
  @State searching: boolean = false
  @State searchFailed: boolean = false
  private lastSearchKeyword: string = ''
  private ownerId: number = 0
  private readonly results: SearchStoreDataSource = new SearchStoreDataSource()
  private readonly resultScroller: Scroller = new Scroller()
  private searchRequest: number = 0
  private suggestTimer: number = -1
  // 直接压栈独立 StoreDetailPage，返回时回到搜索页（不再 back 给首页代跳）
  onStoreClick: (store: StoreItem) => void = (store: StoreItem) => {
    if (store.id <= 0) {
      promptAction.showToast({ message: '店铺信息不完整，无法打开详情', duration: 2200 })
      return
    }
    router.pushUrl({ url: 'pages/StoreDetailPage', params: { storeId: store.id } })
  }
  onBack: () => void = () => { router.back() }

  aboutToAppear() {
    logInfo('Page', '进入搜索页 SearchPage')
    this.ownerId = this.searchOwner.id
    this.hotWords = []
    this.loadHistory()
  }

  async loadHistory() {
    const history: string[] = await getSearchHistory()
    this.historyWords = history
  }

  async doSearch() {
    clearTimeout(this.suggestTimer)
    if (!this.loggedIn) {
      promptAction.showToast({ message: '请先登录后搜索店铺', duration: 1800 })
      return
    }
    const keyword: string = this.searchText.trim()
    if (keyword === '') {
      return
    }
    const request: number = ++this.searchRequest
    const epoch: number = getAuthSessionEpoch()
    const ownerId: number = this.searchOwner.id
    this.resultScroller.scrollEdge(Edge.Top)
    this.searching = true
    this.hasSearched = true
    this.searchFailed = false
    this.lastSearchKeyword = keyword
    try {
      // 清除输入、切换关键词或退出登录后，旧请求不能覆盖新界面。
      const currentAddress: Address | null = AppStorage.get<Address>('currentAddress') ?? null
      const latitude: number | undefined = currentAddress !== null ? currentAddress.latitude : undefined
      const longitude: number | undefined = currentAddress !== null ? currentAddress.longitude : undefined
      const remote: StoreSearchResult = await searchStoresResultApi(keyword, latitude, longitude)
      if (request !== this.searchRequest || !this.loggedIn || ownerId !== this.searchOwner.id ||
        epoch !== getAuthSessionEpoch()) {
        return
      }
      this.searchFailed = !remote.success
      this.results.setData(remote.stores)
      this.resultCount = this.results.totalCount()
      if (!remote.success) {
        logInfo('Search', `搜索请求失败 keyword=${keyword}`)
        return
      }
      logInfo('Search', `执行搜索 keyword=${keyword} 命中${remote.stores.length}家店铺`)
      await addSearchHistory(keyword)
      await this.loadHistory()
    } finally {
      if (request === this.searchRequest) {
        this.searching = false
      }
    }
  }

  resetSearch(): void {
    clearTimeout(this.suggestTimer)
    this.searchRequest += 1
    this.searching = false
    this.hasSearched = false
    this.searchFailed = false
    this.lastSearchKeyword = ''
    this.results.setData([])
    this.resultCount = 0
  }

  onSearchOwnerChange(): void {
    if (this.ownerId === this.searchOwner.id) { return }
    this.ownerId = this.searchOwner.id
    this.resetSearch()
  }

  onPageHide(): void {
    clearTimeout(this.suggestTimer)
    // 页面压栈隐藏时只作废在途请求；组件销毁会自然释放结果，退出账号仍由 Watch 清理。
    this.searchRequest += 1
    this.searching = false
  }

  aboutToDisappear(): void { this.onPageHide() }

  searchByKeyword(keyword: string) {
    this.searchText = keyword
    this.doSearch()
  }

  retrySearch(): void {
    if (this.lastSearchKeyword === '') {
      return
    }
    this.searchText = this.lastSearchKeyword
    this.doSearch()
  }

  async clearHistory() {
    await clearSearchHistory()
    await this.loadHistory()
  }

  build() {
    Column() {
      PageHeader({ title: '搜索', backText: '‹', backId: 'search-back', onBack: () => { this.onBack() } })
      Row({ space: SPACING.XS }) {
        Search({ placeholder: '搜索美食、店铺', value: this.searchText })
          .attributeModifier(new AppSearchStyle())
          .layoutWeight(1)
          .id('search-input')
          .accessibilityText('搜索美食、店铺')
          .onChange((value: string) => {
            this.searchText = value
            this.resetSearch()
            if (value.trim()) { this.suggestTimer = setTimeout(() => { this.doSearch() }, 300) }
          })
          .onSubmit(() => { this.doSearch() })
        Button('搜索', { type: ButtonType.Normal })
          .attributeModifier(new AppButtonStyle())
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.ON_PRIMARY)
          .height(44)
          .padding({ left: 12, right: 12 })
          .id('search-submit')
          .onClick(() => { this.doSearch() })
      }
      .width('100%')
      .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.SM, bottom: SPACING.SM })
      .backgroundColor(COLORS.BG_PRIMARY)

      // 内容区（用 List 承载：Scroll 在内容不足一屏时会把内容垂直居中）
      List({ space: SPACING.SM, scroller: this.resultScroller }) {
        if (!this.loggedIn) {
          ListItem() {
            this.EmptyLoginResult()
          }
        } else if (this.searching) {
          ListItem() {
            LoadingIndicator({ text: '正在搜索店铺…' }).height(240)
          }
        } else if (!this.hasSearched) {
          // 未搜索时显示：热门搜索 + 历史搜索
          if (this.hotWords.length > 0) {
            ListItem() {
              this.HotSearchSection()
            }
          }
          ListItem() {
            this.HistorySection()
          }
        } else {
          // 搜索结果
          if (this.searchFailed) {
            ListItem() {
              this.FailedResult()
            }
          } else if (this.resultCount === 0) {
            ListItem() {
              this.EmptyResult()
            }
          } else {
            LazyForEach(this.results, (store: StoreItem) => {
              ListItem() {
                this.StoreCard(store)
              }
            }, (item: StoreItem) => this.results.keyFor(item))
          }
        }
      }
      .id('search-page-list')
      .cachedCount(3)
      .width('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .divider({ strokeWidth: 0 })
      .layoutWeight(1)
      .padding(this.hasSearched ? { left: SPACING.LG, right: SPACING.LG, top: SPACING.SM, bottom: SPACING.LG } : { bottom: SPACING.LG })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(COLORS.BG_PRIMARY)
  }

  @Builder
  HotSearchSection() {
    Column({ space: SPACING.SM }) {
      Text('热门搜索')
        .fontSize(FONT_SIZE.LG)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLORS.TEXT_PRIMARY)
        .width('100%')
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.hotWords, (word: string) => {
          Text(word)
            .fontSize(FONT_SIZE.MD)
            .fontColor(COLORS.TEXT_SECONDARY)
            .backgroundColor(COLORS.BG_PRIMARY)
            .padding({ left: SPACING.MD, right: SPACING.MD, top: SPACING.SM, bottom: SPACING.SM })
            .borderRadius(BORDER_RADIUS.ROUND)
            .margin({ right: SPACING.SM, bottom: SPACING.SM })
            .onClick(() => { this.searchByKeyword(word) })
        }, (word: string) => word)
      }
      .width('100%')
    }
    .width('100%')
    .padding(SPACING.LG)
    .backgroundColor(COLORS.BG_WHITE)
    .margin({ top: SPACING.SM })
  }

  @Builder
  HistorySection() {
    Column({ space: SPACING.SM }) {
      Row() {
        Text('历史搜索')
          .fontSize(FONT_SIZE.LG)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)
          .layoutWeight(1)
        Text('清空')
          .constraintSize({ minWidth: 44, minHeight: 44 }).textAlign(TextAlign.Center)
          .fontSize(FONT_SIZE.SM)
          .fontColor(COLORS.TEXT_HINT)
          .onClick(() => { this.clearHistory() })
      }
      .width('100%')
      if (this.historyWords.length === 0) {
        Text('暂无搜索历史')
          .fontSize(FONT_SIZE.SM)
          .fontColor(COLORS.TEXT_HINT)
          .width('100%')
      } else {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.historyWords, (word: string) => {
            Text(word)
              .fontSize(FONT_SIZE.MD)
              .fontColor(COLORS.TEXT_SECONDARY)
              .backgroundColor(COLORS.BG_PRIMARY)
              .padding({ left: SPACING.MD, right: SPACING.MD, top: SPACING.SM, bottom: SPACING.SM })
              .borderRadius(BORDER_RADIUS.ROUND)
              .margin({ right: SPACING.SM, bottom: SPACING.SM })
              .onClick(() => { this.searchByKeyword(word) })
          }, (word: string) => word)
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(SPACING.LG)
    .backgroundColor(COLORS.BG_WHITE)
    .margin({ top: SPACING.SM })
  }

  @Builder
  EmptyResult() {
    Column() {
      Image($r('app.media.home_search')).width(60).height(60).objectFit(ImageFit.Contain)
      Text('没有找到相关店铺')
        .fontSize(FONT_SIZE.LG)
        .fontColor(COLORS.TEXT_HINT)
        .margin({ top: SPACING.MD })
      Text('换个关键词试试吧')
        .fontSize(FONT_SIZE.MD)
        .fontColor(COLORS.TEXT_HINT)
        .margin({ top: SPACING.SM })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .margin({ top: 80 })
    .id('search-empty')
  }

  @Builder
  FailedResult() {
    Column({ space: SPACING.SM }) {
      Image($r('app.media.home_search')).width(60).height(60).objectFit(ImageFit.Contain)
      Text('搜索未完成')
        .fontSize(FONT_SIZE.LG)
        .fontColor(COLORS.TEXT_PRIMARY)
        .margin({ top: SPACING.MD })
      Text('暂时无法加载搜索结果，请检查网络后重试。你的搜索词已保留。')
        .fontSize(FONT_SIZE.MD)
        .fontColor(COLORS.TEXT_HINT)
        .textAlign(TextAlign.Center)
      Button('重新搜索')
        .attributeModifier(new AppButtonStyle())
        .height(44)
        .margin({ top: SPACING.SM })
        .id('search-retry')
        .onClick(() => { this.retrySearch() })
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .margin({ top: 80 })
    .id('search-failed')
  }

  @Builder
  EmptyLoginResult() {
    Column() {
      Image($r('app.media.login_lock')).width(60).height(60).objectFit(ImageFit.Contain)
      Text('暂无登录').fontSize(FONT_SIZE.LG).fontColor(COLORS.TEXT_HINT).margin({ top: SPACING.MD })
      Text('请登录后搜索店铺').fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_HINT).margin({ top: SPACING.SM })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  StoreCard(store: StoreItem) {
    Row({ space: SPACING.MD }) {
      // 店铺图片占位
      if (store.image !== '') {
        Image(merchantImageSource(store.image))
          .alt(DEFAULT_MERCHANT_IMAGE)
          .width(80).height(80).objectFit(ImageFit.Cover).borderRadius(BORDER_RADIUS.MD)
      } else {
        Column() {
          Text(store.name.substring(0, 1))
            .fontSize(FONT_SIZE.TITLE)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLORS.ON_PRIMARY)
        }
        .width(80)
        .height(80)
        .backgroundColor(accentFg(accentIndexFromText(store.name)))
        .borderRadius(BORDER_RADIUS.MD)
        .justifyContent(FlexAlign.Center)
      }

      Column({ space: SPACING.XS }) {
        MatchText({ text: store.name, query: this.searchText })

        Row({ space: SPACING.SM }) {
          Text(`${store.rating}分`)
            .fontSize(FONT_SIZE.SM)
            .fontColor(COLORS.PRIMARY)
            .fontWeight(FontWeight.Bold)
          Text(`月售${formatSales(store.monthlySales)}`)
            .fontSize(FONT_SIZE.SM)
            .fontColor(COLORS.TEXT_SECONDARY)
          Text('|')
            .fontSize(FONT_SIZE.SM)
            .fontColor(COLORS.DIVIDER)
          Text(store.deliveryTime)
            .fontSize(FONT_SIZE.SM)
            .fontColor(COLORS.TEXT_SECONDARY)
        }

        Row({ space: SPACING.XS }) {
          Text(`配送¥${store.deliveryFee}`)
            .fontSize(FONT_SIZE.SM)
            .fontColor(COLORS.TEXT_SECONDARY)
          Text('|')
            .fontSize(FONT_SIZE.SM)
            .fontColor(COLORS.DIVIDER)
          Text(`${store.minOrder}元起送`)
            .fontSize(FONT_SIZE.SM)
            .fontColor(COLORS.TEXT_SECONDARY)
          Text('|')
            .fontSize(FONT_SIZE.SM)
            .fontColor(COLORS.DIVIDER)
          Text(store.distance)
            .fontSize(FONT_SIZE.SM)
            .fontColor(COLORS.TEXT_SECONDARY)
        }

        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(store.tags, (tag: string) => {
            Text(tag)
              .fontSize(FONT_SIZE.XS)
              .fontColor(COLORS.TAG_TEXT)
              .backgroundColor(COLORS.TAG_BG)
              .padding({ left: 4, right: 4, top: 2, bottom: 2 })
              .borderRadius(BORDER_RADIUS.SM)
          }, (tag: string) => tag)
        }
        .width('100%')
        .margin({ bottom: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
      .attributeModifier(new AppCardStyle())
    .width('100%')
    .padding(SPACING.MD)
    .id(`search-store-${store.id}`)
    .onClick(() => { this.onStoreClick(store) })
  }
}

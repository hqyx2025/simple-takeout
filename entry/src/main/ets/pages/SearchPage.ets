import { AppButtonStyle, AppCardStyle, AppSearchStyle } from '../common/theme/AppTheme'
import { PageHeader } from '../components/PageHeader'
import { LoadingIndicator } from '../components/LoadingIndicator'
/**
 * 搜索页 - 热门搜索、历史搜索、店铺搜索结果
 */
import { AppMotion } from '../common/theme/AppMotion'
import { StoreItem } from '../model/Models'
import { formatSales } from '../common/Constants'
import { searchStoresRemote } from '../service/AppStorageManager'
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
  @State searchText: string = ''
  @State hotWords: string[] = []
  @State historyWords: string[] = []
  @State searchResults: StoreItem[] = []
  @State hasSearched: boolean = false
  @State searching: boolean = false
  private searchRequest: number = 0
  // 直接压栈独立 StoreDetailPage，返回时回到搜索页（不再 back 给首页代跳）
  onStoreClick: (store: StoreItem) => void = (store: StoreItem) => {
    if (store.id <= 0) {
      promptAction.showToast({ message: '店铺信息不完整，无法打开详情', duration: 2200 })
      return
    }
    AppStorage.setOrCreate<number>('selectedStoreId', store.id)
    AppStorage.setOrCreate<string>('selectedStoreName', store.name !== '' ? store.name : '店铺详情')
    router.pushUrl({ url: 'pages/StoreDetailPage' })
  }
  onBack: () => void = () => { router.back() }

  aboutToAppear() {
    logInfo('Page', '进入搜索页 SearchPage')
    this.hotWords = []
    this.loadHistory()
  }

  async loadHistory() {
    const history: string[] = await getSearchHistory()
    this.historyWords = history
  }

  async doSearch() {
    if (!this.loggedIn) {
      promptAction.showToast({ message: '请先登录后搜索店铺', duration: 1800 })
      return
    }
    const keyword: string = this.searchText.trim()
    if (keyword === '') {
      return
    }
    const request: number = ++this.searchRequest
    this.searching = true
    this.hasSearched = true
    try {
      // 清除输入、切换关键词或退出登录后，旧请求不能覆盖新界面。
      const remote: StoreItem[] = await searchStoresRemote(keyword)
      if (request !== this.searchRequest || !this.loggedIn) {
        return
      }
      this.searchResults = remote
      logInfo('Search', `执行搜索 keyword=${keyword} 命中${remote.length}家店铺`)
      await addSearchHistory(keyword)
      await this.loadHistory()
    } finally {
      if (request === this.searchRequest) {
        this.searching = false
      }
    }
  }

  resetSearch(): void {
    this.searchRequest += 1
    this.searching = false
    this.hasSearched = false
    this.searchResults = []
  }

  aboutToDisappear(): void {
    this.resetSearch()
  }

  searchByKeyword(keyword: string) {
    this.searchText = keyword
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
      List({ space: SPACING.SM }) {
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
          if (this.searchResults.length === 0) {
            ListItem() {
              this.EmptyResult()
            }
          } else {
            ForEach(this.searchResults, (store: StoreItem) => {
              ListItem() {
                this.StoreCard(store)
              }
            }, (item: StoreItem) => item.id.toString())
          }
        }
      }
      .id('search-page-list')
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
        Text(store.name)
          .fontSize(FONT_SIZE.LG)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

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

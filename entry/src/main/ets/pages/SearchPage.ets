/**
 * 搜索页 - 热门搜索、历史搜索、店铺搜索结果
 */
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
  @StorageLink('isLoggedIn') loggedIn: boolean = false
  @State searchText: string = ''
  @State hotWords: string[] = []
  @State historyWords: string[] = []
  @State searchResults: StoreItem[] = []
  @State hasSearched: boolean = false
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
    this.hasSearched = true
    // 搜索店铺只使用后端结果，避免本地缓存混入搜索结果。
    const remote: StoreItem[] = await searchStoresRemote(keyword)
    this.searchResults = remote
    logInfo('Search', `执行搜索 keyword=${keyword} 命中${this.searchResults.length}家店铺`)
    // 保存搜索历史
    await addSearchHistory(keyword)
    await this.loadHistory()
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
      // 顶部导航栏：返回 + 搜索框 + 搜索按钮
      Row({ space: SPACING.XS }) {
        Text('‹')
          .fontSize(24)
          .fontColor(COLORS.TEXT_PRIMARY)
          // 补足触控区域：原实现无宽高，可点面积仅约 20×30px（低于 40×40 的可用性基线），
          // 真机/模拟器上很难点中，表现为"返回按钮点了没反应"。
          .width(40)
          .height(40)
          .textAlign(TextAlign.Center)
          .id('search-back')
          .onClick(() => { this.onBack() })
        TextInput({ placeholder: '搜索美食、店铺', text: this.searchText })
          .layoutWeight(1)
          .height(36)
          .backgroundColor(COLORS.BG_PRIMARY)
          .borderRadius(BORDER_RADIUS.ROUND)
          .id('search-input')
          .onChange((value: string) => { this.searchText = value })
        Text('搜索')
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.PRIMARY)
          .id('search-submit')
          .onClick(() => { this.doSearch() })
      }
      .width('100%')
      .height(44)
      .padding({ left: SPACING.LG, right: SPACING.LG })
      .backgroundColor(COLORS.BG_WHITE)

      // 内容区（用 List 承载：Scroll 在内容不足一屏时会把内容垂直居中）
      List() {
        if (!this.loggedIn) {
          ListItem() {
            this.EmptyLoginResult()
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
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(60)
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
      SymbolGlyph($r('sys.symbol.lock')).fontSize(60)
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
            .fontColor(COLORS.TEXT_WHITE)
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
    .width('100%')
    .padding(SPACING.MD)
    .backgroundColor(COLORS.BG_WHITE)
    .borderRadius(BORDER_RADIUS.LG)
    .id(`search-store-${store.id}`)
    .onClick(() => { this.onStoreClick(store) })
  }
}

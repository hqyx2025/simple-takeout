/**
 * 搜索页 - 热门搜索、历史搜索、店铺搜索结果
 */
import { StoreItem } from '../model/Models'
import { getHotSearchWords, formatSales } from '../service/MockDataService'
import { getAllStoresList } from '../service/AppStorageManager'
import { getSearchHistory, addSearchHistory, clearSearchHistory } from '../service/PreferencesHelper'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS } from '../common/Constants'

@Entry
@Component
export struct SearchPage {
  @State searchText: string = ''
  @State hotWords: string[] = []
  @State historyWords: string[] = []
  @State searchResults: StoreItem[] = []
  @State hasSearched: boolean = false
  onStoreClick: (store: StoreItem) => void = () => {}
  onBack: () => void = () => {}

  aboutToAppear() {
    this.hotWords = getHotSearchWords()
    this.loadHistory()
  }

  async loadHistory() {
    const history: string[] = await getSearchHistory()
    this.historyWords = history
  }

  async doSearch() {
    const keyword: string = this.searchText.trim()
    if (keyword === '') {
      return
    }
    this.hasSearched = true
    // 搜索店铺：从所有店铺中过滤名称包含关键词的
    const allStores: StoreItem[] = getAllStoresList()
    this.searchResults = allStores.filter((s: StoreItem) => s.name.includes(keyword))
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
      Row({ space: 4 }) {
        Text('‹')
          .fontSize(24)
          .fontColor(COLORS.TEXT_PRIMARY)
          .onClick(() => { this.onBack() })
        TextInput({ placeholder: '搜索美食、店铺', text: this.searchText })
          .layoutWeight(1)
          .height(36)
          .backgroundColor('#F0F0F0')
          .borderRadius(BORDER_RADIUS.ROUND)
          .onChange((value: string) => { this.searchText = value })
        Text('搜索')
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.PRIMARY)
          .onClick(() => { this.doSearch() })
      }
      .width('100%')
      .height(44)
      .padding({ left: SPACING.LG, right: SPACING.LG })
      .backgroundColor(COLORS.BG_WHITE)

      // 内容区
      Scroll() {
        Column() {
          if (!this.hasSearched) {
            // 未搜索时显示：热门搜索 + 历史搜索
            this.HotSearchSection()
            this.HistorySection()
          } else {
            // 搜索结果
            if (this.searchResults.length === 0) {
              this.EmptyResult()
            } else {
              List({ space: SPACING.SM }) {
                ForEach(this.searchResults, (store: StoreItem) => {
                  ListItem() {
                    this.StoreCard(store)
                  }
                }, (item: StoreItem) => item.id.toString())
              }
              .width('100%')
              .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.SM, bottom: SPACING.LG })
              .scrollBar(BarState.Off)
              .divider({ strokeWidth: 0 })
            }
          }
        }
        .width('100%')
      }
      .scrollBar(BarState.Off)
      .layoutWeight(1)
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
      Text('🔍')
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
  }

  @Builder
  StoreCard(store: StoreItem) {
    Row({ space: SPACING.MD }) {
      // 店铺图片占位
      Column() {
        Text(store.name.substring(0, 1))
          .fontSize(FONT_SIZE.TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
      }
      .width(80)
      .height(80)
      .backgroundColor(COLORS.PRIMARY)
      .borderRadius(BORDER_RADIUS.MD)
      .justifyContent(FlexAlign.Center)

      Column({ space: 4 }) {
        Text(store.name)
          .fontSize(FONT_SIZE.LG)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Row({ space: 8 }) {
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

        Row({ space: 4 }) {
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
    .onClick(() => { this.onStoreClick(store) })
  }
}

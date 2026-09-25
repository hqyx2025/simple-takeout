/**
 * 收藏列表页
 * 展示当前用户的收藏店铺列表
 * 支持取消收藏与点击跳转店铺（直接压栈独立 StoreDetailPage）
 */
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS, MODULE_COLOR, accentFg, accentIndexFromText, merchantImageSource, DEFAULT_MERCHANT_IMAGE } from '../common/Constants'
import { Favorite } from '../model/Models'
import { getFavorites, toggleFavoriteRemote, syncFavoritesRemote, getLastRemoteErrorMessage } from '../service/AppStorageManager'
import { EmptyState } from '../components/EmptyState'
import { PageHeader } from '../components/PageHeader'
import { logInfo } from '../service/AppLogger'

// 收藏列表懒加载数据源（实现 IDataSource）
class FavoriteDataSource implements IDataSource {
  private list: Favorite[] = []
  private listeners: DataChangeListener[] = []

  totalCount(): number {
    return this.list.length
  }

  getData(index: number): Favorite {
    return this.list[index]
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    this.listeners.push(listener)
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((l: DataChangeListener) => l !== listener)
  }

  setData(data: Favorite[]): void {
    this.list = data
    this.listeners.forEach((l: DataChangeListener) => l.onDataReloaded())
  }

  notifyDataReload(): void {
    this.listeners.forEach((l: DataChangeListener) => l.onDataReloaded())
  }
}

@Entry
@Component
export struct FavoriteListPage {
  @StorageLink('isLoggedIn') loggedIn: boolean = false
  @State favoriteList: Favorite[] = []
  private dataSource: FavoriteDataSource = new FavoriteDataSource()

  aboutToAppear() {
    logInfo('Page', '进入收藏列表页 FavoriteListPage')
    if (!this.loggedIn) {
      return
    }
    this.loadFavorites()
  }

  private async loadFavorites(): Promise<void> {
    // 从后端拉取最新收藏（真实后端模式）
    await syncFavoritesRemote()
    this.favoriteList = getFavorites()
    this.dataSource.setData(this.favoriteList)
  }

  build() {
    Column() {
      // 顶部导航栏
      PageHeader({ title: '我的收藏', onBack: () => { router.back() } })

      // 内容区
      if (!this.loggedIn) {
        EmptyState({ iconGlyph: $r('sys.symbol.lock'), title: '暂无登录', description: '请登录后查看收藏' })
      } else if (this.favoriteList.length === 0) {
        EmptyState({ icon: '💝', title: '暂无收藏店铺', description: '去首页收藏喜欢的店铺吧' })
      } else {
        List({ space: SPACING.MD }) {
          LazyForEach(this.dataSource, (item: Favorite) => {
            ListItem() {
              this.FavoriteItemBuilder(item)
            }
          }, (item: Favorite) => item.id.toString())
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.SM, bottom: SPACING.XXL })
        .cachedCount(5)
        .divider({ strokeWidth: 0 })
        .backgroundColor(COLORS.BG_PRIMARY)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(COLORS.BG_PRIMARY)
  }

  @Builder
  FavoriteItemBuilder(item: Favorite) {
    Row() {
      // 有店铺照片就显示照片，没有才用首字母色块占位
      if (item.storeImage !== '') {
        Image(merchantImageSource(item.storeImage))
          .alt(DEFAULT_MERCHANT_IMAGE)
          .width(56).height(56).objectFit(ImageFit.Cover).borderRadius(BORDER_RADIUS.LG)
      } else {
        Text(this.getFirstChar(item.storeName))
          .fontSize(FONT_SIZE.XXL)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_WHITE)
          .backgroundColor(accentFg(accentIndexFromText(item.storeName)))
          .width(56)
          .height(56)
          .borderRadius(BORDER_RADIUS.LG)
          .textAlign(TextAlign.Center)
      }

      // 店铺信息
      Column({ space: SPACING.XS }) {
        Text(item.storeName)
          .fontSize(FONT_SIZE.LG)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(`收藏于 ${item.createTime}`)
          .fontSize(FONT_SIZE.SM)
          .fontColor(COLORS.TEXT_SECONDARY)
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: SPACING.MD })

      // 取消收藏按钮
      Button('取消收藏')
        .fontSize(FONT_SIZE.SM)
        .fontColor(COLORS.TEXT_SECONDARY)
        .backgroundColor(COLORS.BG_PRIMARY)
        .borderRadius(BORDER_RADIUS.ROUND)
        .type(ButtonType.Capsule)
        .height(32)
        .padding({ left: SPACING.MD, right: SPACING.MD })
        .onClick(() => { this.onCancelFavorite(item.storeId) })
    }
    .width('100%')
    .padding(SPACING.LG)
    .backgroundColor(COLORS.BG_WHITE)
    .borderRadius(BORDER_RADIUS.LG)
    .alignItems(VerticalAlign.Center)
    .onClick(() => { this.onItemClick(item.storeId, item.storeName) })
  }

  // 获取店铺名称首字符作为色块占位
  private getFirstChar(name: string): string {
    if (name.length > 0) {
      return name.charAt(0)
    }
    return '店'
  }

  // 取消收藏：切换状态、刷新列表、提示
  private async onCancelFavorite(storeId: number): Promise<void> {
    await toggleFavoriteRemote(storeId)
    const errorMessage: string = getLastRemoteErrorMessage()
    if (errorMessage !== '') {
      promptAction.showToast({ message: errorMessage, duration: 2200 })
      return
    }
    this.loadFavorites()
    logInfo('Favorite', `收藏页取消收藏 storeId=${storeId}`)
    promptAction.showToast({ message: '已取消收藏' })
  }

  // 点击收藏项：直接压栈独立 StoreDetailPage，返回时回到收藏页
  private onItemClick(storeId: number, storeName: string): void {
    if (storeId <= 0) {
      promptAction.showToast({ message: '店铺信息不完整，无法打开详情', duration: 2200 })
      return
    }
    AppStorage.setOrCreate<number>('selectedStoreId', storeId)
    AppStorage.setOrCreate<string>('selectedStoreName', storeName !== '' ? storeName : '店铺详情')
    logInfo('Navigation', `收藏页打开店铺详情 storeId=${storeId}`)
    router.pushUrl({ url: 'pages/StoreDetailPage' })
  }
}

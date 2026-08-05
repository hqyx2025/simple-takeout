/**
 * 收藏列表页
 * 展示当前用户的收藏店铺列表
 * 支持取消收藏与点击跳转店铺（存储 currentStoreId 后 router.back 由首页接收）
 */
import router from '@ohos.router'
import { promptAction } from '@kit.ArkUI'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS } from '../common/Constants'
import { Favorite } from '../model/Models'
import { getFavorites, toggleFavorite } from '../service/AppStorageManager'
import { EmptyState } from '../components/EmptyState'

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
  @State favoriteList: Favorite[] = []
  private dataSource: FavoriteDataSource = new FavoriteDataSource()

  aboutToAppear() {
    this.loadFavorites()
  }

  private loadFavorites(): void {
    this.favoriteList = getFavorites()
    this.dataSource.setData(this.favoriteList)
  }

  build() {
    Column() {
      // 顶部导航栏
      Row() {
        Text('‹')
          .fontSize(FONT_SIZE.XXL)
          .fontColor(COLORS.TEXT_PRIMARY)
          .onClick(() => { router.back() })
        Text('我的收藏')
          .fontSize(FONT_SIZE.XL)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        // 占位以保持标题居中
        Text('‹')
          .fontSize(FONT_SIZE.XXL)
          .fontColor(Color.Transparent)
      }
      .width('100%')
      .height(56)
      .padding({ left: SPACING.LG, right: SPACING.LG })
      .backgroundColor(COLORS.BG_WHITE)
      .alignItems(VerticalAlign.Center)

      // 内容区
      if (this.favoriteList.length === 0) {
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
        .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.SM })
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
      // 店铺首字母色块占位（不编造图片URL）
      Text(this.getFirstChar(item.storeName))
        .fontSize(FONT_SIZE.XXL)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLORS.TEXT_WHITE)
        .backgroundColor(COLORS.PRIMARY)
        .width(56)
        .height(56)
        .borderRadius(BORDER_RADIUS.LG)
        .textAlign(TextAlign.Center)

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
    .onClick(() => { this.onItemClick(item.storeId) })
  }

  // 获取店铺名称首字符作为色块占位
  private getFirstChar(name: string): string {
    if (name.length > 0) {
      return name.charAt(0)
    }
    return '店'
  }

  // 取消收藏：切换状态、刷新列表、提示
  private onCancelFavorite(storeId: number): void {
    toggleFavorite(storeId)
    this.loadFavorites()
    promptAction.showToast({ message: '已取消收藏' })
  }

  // 点击收藏项：存储店铺ID后返回（由首页接收跳转店铺详情）
  private onItemClick(storeId: number): void {
    AppStorage.setOrCreate<number>('currentStoreId', storeId)
    router.back()
  }
}

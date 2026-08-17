/**
 * 独立店铺详情页。
 * 首页附近店、发现推荐、分类商品、搜索和收藏入口统一进入此页面。
 */
import { StoreDetailContent } from './Index'
import { LoginPage } from './LoginPage'
import { COLORS, SPACING, FONT_SIZE } from '../common/Constants'
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'

@Entry
@Component
export struct StoreDetailPage {
  @StorageLink('selectedStoreId') storeId: number = 0
  @StorageLink('selectedStoreName') storeName: string = ''
  @StorageLink('isLoggedIn') loggedIn: boolean = false
  @State showLogin: boolean = false

  aboutToAppear(): void {
    if (this.storeId <= 0) {
      promptAction.showToast({ message: '店铺信息不存在' })
      router.back()
    }
  }

  private goBack(): void {
    AppStorage.setOrCreate<number>('selectedStoreId', 0)
    AppStorage.setOrCreate<string>('selectedStoreName', '')
    router.back()
  }

  build() {
    Stack() {
      Column() {
        Row() {
          Text('‹ 返回')
            .fontSize(FONT_SIZE.MD)
            .fontColor(COLORS.PRIMARY)
            .onClick(() => { this.goBack() })
          Text(this.storeName || '店铺详情')
            .fontSize(FONT_SIZE.LG)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLORS.TEXT_PRIMARY)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
          Text('  ').fontSize(FONT_SIZE.MD)
        }
        .width('100%')
        .height(48)
        .padding({ left: SPACING.LG, right: SPACING.LG })
        .backgroundColor(COLORS.BG_WHITE)

        if (this.storeId > 0) {
          StoreDetailContent({
            storeId: this.storeId,
            onNavigateLogin: () => { this.showLogin = true }
          })
          .layoutWeight(1)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(COLORS.BG_PRIMARY)

      if (this.showLogin && !this.loggedIn) {
        Column() {
          LoginPage({
            onLoginSuccess: () => {
              this.showLogin = false
            }
          })
        }
        .width('100%')
        .height('100%')
        .backgroundColor(COLORS.BG_PRIMARY)
      }
    }
    .width('100%')
    .height('100%')
  }
}

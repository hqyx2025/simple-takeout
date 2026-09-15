/**
 * 骑手中心（四端改造）：上线/下线、配送统计、入口
 */
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS } from '../common/Constants'
import { Rider } from '../model/Models'
import { fetchRiderProfileRemote, logout, setRiderStatusRemote } from '../service/AppStorageManager'
import { logInfo } from '../service/AppLogger'

@Entry
@Component
export struct RiderCenterPage {
  @StorageLink('isLoggedIn') loggedIn: boolean = false
  @State rider: Rider | null = null
  @State loading: boolean = false
  @State toggling: boolean = false

  async aboutToAppear(): Promise<void> {
    logInfo('Page', '进入骑手中心 RiderCenterPage')
    if (this.loggedIn) {
      await this.loadProfile()
    }
  }

  private async loadProfile(): Promise<void> {
    this.loading = true
    this.rider = await fetchRiderProfileRemote()
    this.loading = false
  }

  private async toggleOnline(): Promise<void> {
    if (this.rider === null || this.toggling) {
      return
    }
    this.toggling = true
    const target: number = this.rider.online === 1 ? 0 : 1
    const updated: Rider | null = await setRiderStatusRemote(target)
    this.toggling = false
    if (updated !== null) {
      this.rider = updated
      promptAction.showToast({ message: target === 1 ? '已上线，可开始抢单' : '已下线', duration: 1500 })
    } else {
      promptAction.showToast({ message: '状态更新失败，请重试', duration: 2000 })
    }
  }

  build() {
    Column() {
      Row() {
        Text('退出登录')
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.PRIMARY)
          .layoutWeight(1)
          .onClick(() => {
            logout()
            router.replaceUrl({ url: 'pages/Index' })
          })
        Text('🛵 骑手中心')
          .fontSize(FONT_SIZE.XXL)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)
          .layoutWeight(1)
      }
      .width('100%')
      .height(56)
      .padding({ left: SPACING.LG, right: SPACING.LG })
      .backgroundColor(COLORS.BG_WHITE)

      if (!this.loggedIn) {
        Column() {
          Text('🔒').fontSize(60).margin({ top: 80 })
          Text('请使用骑手账号登录').fontSize(FONT_SIZE.LG).fontColor(COLORS.TEXT_HINT).margin({ top: SPACING.MD })
        }
        .layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      } else if (this.loading) {
        Column() {
          Text('正在加载…').fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_HINT)
        }
        .layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      } else if (this.rider === null) {
        Column() {
          Text('⚠️').fontSize(60).margin({ top: 80 })
          Text('骑手档案加载失败').fontSize(FONT_SIZE.LG).fontColor(COLORS.TEXT_HINT).margin({ top: SPACING.MD })
        }
        .layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      } else {
        // 用 List 承载：Scroll 在内容不足一屏时会把内容垂直居中，导致内容不在顶部
        List({ space: SPACING.SM }) {
          // 上线开关
          ListItem() {
            Column({ space: SPACING.SM }) {
              Row() {
                Text(this.rider!.name)
                  .fontSize(FONT_SIZE.XL).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
                  .layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.rider!.online === 1 })
                  .id('rider-online-toggle')
                  .onChange(() => { this.toggleOnline() })
              }
              .width('100%')
              Text(this.rider!.phone).fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_SECONDARY).width('100%')
              Text(this.rider!.online === 1 ? '● 在线，可抢单' : '● 离线')
                .fontSize(FONT_SIZE.SM)
                .fontColor(this.rider!.online === 1 ? COLORS.SUCCESS : COLORS.TEXT_HINT)
                .id('rider-online-status')
            }
            .width('100%').padding(SPACING.LG).backgroundColor(COLORS.BG_WHITE).borderRadius(BORDER_RADIUS.LG)
          }

          // 统计
          ListItem() {
            Row() {
              Column({ space: SPACING.XS }) {
                Text(this.rider!.totalOrders.toString())
                  .fontSize(FONT_SIZE.XXL).fontWeight(FontWeight.Bold).fontColor(COLORS.PRIMARY)
                Text('累计配送').fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
              }.layoutWeight(1).alignItems(HorizontalAlign.Center)
              Column({ space: SPACING.XS }) {
                Text(`¥${this.rider!.totalIncome.toFixed(2)}`)
                  .fontSize(FONT_SIZE.XXL).fontWeight(FontWeight.Bold).fontColor(COLORS.PRIMARY)
                Text('累计收入').fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
              }.layoutWeight(1).alignItems(HorizontalAlign.Center)
            }
            .width('100%').padding(SPACING.LG).backgroundColor(COLORS.BG_WHITE).borderRadius(BORDER_RADIUS.LG)
          }

          ListItem() {
            Column() {
              Button('抢单大厅')
                .width('100%').height(48).fontSize(FONT_SIZE.LG)
                .fontColor(COLORS.TEXT_WHITE).backgroundColor(COLORS.PRIMARY)
                .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
                .margin({ top: SPACING.MD })
                .id('rider-pool-entry')
                .onClick(() => {
                  if (this.rider!.online === 1) {
                    router.pushUrl({ url: 'pages/RiderOrderPoolPage' })
                  }
                  else {
                    promptAction.showToast({ message: '请先上线', duration: 1500 })
                  }
                })

              Button('我的配送单')
                .width('100%').height(48).fontSize(FONT_SIZE.LG)
                .fontColor(COLORS.PRIMARY).backgroundColor(COLORS.TAG_BG)
                .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
                .id('rider-orders-entry')
                .onClick(() => { router.pushUrl({ url: 'pages/RiderOrdersPage' }) })
            }
            .width('100%')
          }
        }
        .width('100%')
        .layoutWeight(1).scrollBar(BarState.Off)
        .padding(SPACING.LG)
      }
    }
    .width('100%').height('100%').backgroundColor(COLORS.BG_PRIMARY)
  }
}

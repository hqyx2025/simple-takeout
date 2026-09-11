/**
 * 管理端骑手管理（四端改造）：骑手列表与启用/停用
 */
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS } from '../common/Constants'
import { Rider } from '../model/Models'
import { syncAdminRidersRemote, updateRiderStatusRemote } from '../service/AppStorageManager'
import { StatusBadge } from '../components/StatusBadge'
import { logInfo } from '../service/AppLogger'

@Entry
@Component
export struct AdminRiderPage {
  @State riders: Rider[] = []
  @State loading: boolean = false

  async aboutToAppear(): Promise<void> {
    logInfo('Page', '进入管理端骑手管理 AdminRiderPage')
    await this.loadRiders()
  }

  private async loadRiders(): Promise<void> {
    this.loading = true
    this.riders = await syncAdminRidersRemote()
    this.loading = false
  }

  private async toggleStatus(rider: Rider): Promise<void> {
    const target: number = rider.status === 1 ? 0 : 1
    const ok: boolean = await updateRiderStatusRemote(rider.id, target)
    if (ok) {
      promptAction.showToast({ message: target === 1 ? '已启用该骑手' : '已停用该骑手', duration: 1500 })
      await this.loadRiders()
    } else {
      promptAction.showToast({ message: '操作失败，请重试', duration: 2000 })
    }
  }

  build() {
    Column() {
      Row() {
        Text('‹ 返回')
          .fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_PRIMARY)
          .onClick(() => { router.back() })
        Text('骑手管理')
          .fontSize(FONT_SIZE.XL).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
          .layoutWeight(1).textAlign(TextAlign.Center)
        Text('刷新')
          .fontSize(FONT_SIZE.MD).fontColor(COLORS.PRIMARY)
          .onClick(() => { this.loadRiders() })
      }
      .width('100%').height(56).padding({ left: SPACING.LG, right: SPACING.LG })
      .backgroundColor(COLORS.BG_WHITE)

      if (this.loading) {
        Column() {
          Text('正在加载…').fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_HINT)
        }.layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      } else if (this.riders.length === 0) {
        Column() {
          Text('🛵').fontSize(60).margin({ top: 40 })
          Text('暂无骑手').fontSize(FONT_SIZE.LG).fontColor(COLORS.TEXT_HINT).margin({ top: SPACING.MD })
          Text('骑手通过「注册→选择骑手」开通').fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT).margin({ top: SPACING.SM })
        }.layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      } else {
        Scroll() {
          Column({ space: SPACING.SM }) {
            ForEach(this.riders, (rider: Rider) => {
              this.RiderCard(rider)
            }, (rider: Rider) => rider.id.toString())
          }
          .width('100%').padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.SM, bottom: SPACING.XXL })
        }
        .layoutWeight(1).scrollBar(BarState.Off)
      }
    }
    .width('100%').height('100%').backgroundColor(COLORS.BG_PRIMARY)
  }

  @Builder
  RiderCard(rider: Rider) {
    Column({ space: SPACING.XS }) {
      Row() {
        Text(rider.name).fontSize(FONT_SIZE.LG).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY).layoutWeight(1)
        StatusBadge({ text: rider.status === 1 ? '启用中' : '已停用', mode: rider.status === 1 ? 'success' : 'gray' })
      }.width('100%')
      Text(rider.phone).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY).width('100%')
      Text(`${rider.online === 1 ? '在线' : '离线'} · 累计配送 ${rider.totalOrders} 单 · 收入 ¥${rider.totalIncome.toFixed(2)}`)
        .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY).width('100%')
      Row() {
        Blank()
        Button(rider.status === 1 ? '停用' : '启用')
          .height(32).fontSize(FONT_SIZE.SM)
          .fontColor(rider.status === 1 ? COLORS.ERROR : COLORS.PRIMARY)
          .backgroundColor(rider.status === 1 ? COLORS.ERROR_LIGHT : COLORS.TAG_BG)
          .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
          .onClick(() => { this.toggleStatus(rider) })
      }.width('100%')
    }
    .width('100%').padding(SPACING.LG).backgroundColor(COLORS.BG_WHITE).borderRadius(BORDER_RADIUS.LG)
  }
}

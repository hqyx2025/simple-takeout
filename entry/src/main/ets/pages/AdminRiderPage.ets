/**
 * 管理端骑手管理（四端改造）：骑手列表与启用/停用
 */
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS, MODULE_COLOR, MODULE_BG, accentBg, accentFg, accentIndexFromText } from '../common/Constants'
import { Rider } from '../model/Models'
import { syncAdminRidersRemote, updateRiderStatusRemote } from '../service/AppStorageManager'
import { StatusBadge } from '../components/StatusBadge'
import { PageHeader } from '../components/PageHeader'
import { logInfo } from '../service/AppLogger'

@Entry
@Component
export struct AdminRiderPage {
  @State riders: Rider[] = []
  // -1 全部 / 1 已启用 / 0 已停用（列表已在内存中，本地筛选即可）
  @State statusFilter: number = -1
  @State displayRiders: Rider[] = []
  @State renderVersion: number = 0
  @State loading: boolean = false

  async aboutToAppear(): Promise<void> {
    logInfo('Page', '进入管理端骑手管理 AdminRiderPage')
    await this.loadRiders()
  }

  private async loadRiders(): Promise<void> {
    this.loading = true
    this.riders = await syncAdminRidersRemote()
    this.applyFilter()
    this.loading = false
  }

  /** 按启用状态筛选（显式计算，避免渲染期 getter 求值）。 */
  private applyFilter(): void {
    if (!Array.isArray(this.riders)) {
      this.displayRiders = []
      return
    }
    this.displayRiders = this.statusFilter === -1
      ? this.riders
      : this.riders.filter((rider: Rider) => rider.status === this.statusFilter)
    this.renderVersion += 1
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
      PageHeader({
        title: '骑手管理',
        backId: 'admin-rider-back',
        headerBgColor: MODULE_BG.ADMIN,
        actionColor: MODULE_COLOR.ADMIN,
        actionLabel: '刷新',
        onBack: () => { router.back() },
        onAction: () => { this.loadRiders() }
      })

      Row({ space: SPACING.MD }) {
        Text('状态').fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT)
        Button('全部').id('admin-rider-status-all').fontSize(FONT_SIZE.SM)
          .backgroundColor(this.statusFilter === -1 ? MODULE_COLOR.ADMIN : COLORS.BG_PRIMARY)
          .fontColor(this.statusFilter === -1 ? COLORS.TEXT_WHITE : COLORS.TEXT_SECONDARY)
          .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule).onClick(() => { this.statusFilter = -1; this.applyFilter() })
        Button('已启用').id('admin-rider-status-enabled').fontSize(FONT_SIZE.SM)
          .backgroundColor(this.statusFilter === 1 ? MODULE_COLOR.ADMIN : COLORS.BG_PRIMARY)
          .fontColor(this.statusFilter === 1 ? COLORS.TEXT_WHITE : COLORS.TEXT_SECONDARY)
          .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule).onClick(() => { this.statusFilter = 1; this.applyFilter() })
        Button('已停用').id('admin-rider-status-disabled').fontSize(FONT_SIZE.SM)
          .backgroundColor(this.statusFilter === 0 ? MODULE_COLOR.ADMIN : COLORS.BG_PRIMARY)
          .fontColor(this.statusFilter === 0 ? COLORS.TEXT_WHITE : COLORS.TEXT_SECONDARY)
          .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule).onClick(() => { this.statusFilter = 0; this.applyFilter() })
      }
      .width('100%').padding({ left: SPACING.LG, right: SPACING.LG, bottom: SPACING.SM })
      .backgroundColor(MODULE_BG.ADMIN)

      if (this.loading) {
        Column() {
          Text('正在加载…').fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_HINT)
        }.layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      } else if (this.displayRiders.length === 0) {
        Column() {
          SymbolGlyph($r('sys.symbol.express_delivery')).fontSize(60).margin({ top: 40 })
          Text(this.statusFilter === -1 ? '暂无骑手' : '当前筛选条件下暂无骑手')
            .fontSize(FONT_SIZE.LG).fontColor(COLORS.TEXT_HINT).margin({ top: SPACING.MD })
          Text('骑手通过「注册→选择骑手」开通').fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT).margin({ top: SPACING.SM })
        }.layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      } else {
        // 用 List 承载：Scroll 在内容不足一屏时会把内容垂直居中，导致第一条数据不在筛选行下方
        List({ space: SPACING.SM }) {
          ForEach(this.displayRiders, (rider: Rider) => {
            ListItem() {
              this.RiderCard(rider)
            }
          }, (rider: Rider) => `${this.renderVersion}-${rider.id}`)
        }
        .width('100%').layoutWeight(1).scrollBar(BarState.Off)
        .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.SM, bottom: SPACING.XXL })
      }
    }
    .width('100%').height('100%').backgroundColor(COLORS.BG_PRIMARY)
  }

  @Builder
  RiderCard(rider: Rider) {
    Column({ space: SPACING.XS }) {
      Row({ space: SPACING.SM }) {
        Text(rider.name.substring(0, 1))
          .width(40).height(40).textAlign(TextAlign.Center)
          .fontSize(FONT_SIZE.LG).fontWeight(FontWeight.Bold)
          .fontColor(accentFg(accentIndexFromText(rider.name)))
          .backgroundColor(accentBg(accentIndexFromText(rider.name)))
          .borderRadius(BORDER_RADIUS.ROUND)
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
          .fontColor(rider.status === 1 ? COLORS.ERROR : MODULE_COLOR.ADMIN)
          .backgroundColor(rider.status === 1 ? COLORS.ERROR_LIGHT : COLORS.TAG_BG)
          .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
          .onClick(() => { this.toggleStatus(rider) })
      }.width('100%')
    }
    .width('100%').padding(SPACING.LG).backgroundColor(COLORS.BG_WHITE).borderRadius(BORDER_RADIUS.LG)
  }
}

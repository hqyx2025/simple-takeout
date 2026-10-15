import { AppButtonStyle, AppCardStyle } from '../common/theme/AppTheme'
import { AppMotion } from '../common/theme/AppMotion'
import { AdminOperationLog, User, UserRole } from '../model/Models'
import { fetchAdminOperationLogsApi } from '../service/ApiService'
import { COLORS, SPACING, FONT_SIZE, MODULE_COLOR } from '../common/Constants'
import { PageHeader } from '../components/PageHeader'
import { StatusBadge } from '../components/StatusBadge'
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { logInfo } from '../service/AppLogger'

@Entry
@Component
export struct AdminAuditPage {
  pageTransition() {
    PageTransitionEnter(AppMotion.pageEnter(RouteType.Push))
      .translate({ x: AppMotion.distance(AppMotion.PAGE_OFFSET) }).opacity(0)
    PageTransitionExit(AppMotion.pageExit(RouteType.Push))
      .translate({ x: -AppMotion.distance(AppMotion.RETURN_OFFSET) }).opacity(0)
    PageTransitionEnter(AppMotion.pageEnter(RouteType.Pop))
      .translate({ x: -AppMotion.distance(AppMotion.RETURN_OFFSET) }).opacity(0)
    PageTransitionExit(AppMotion.pageExit(RouteType.Pop))
      .translate({ x: AppMotion.distance(AppMotion.PAGE_OFFSET) }).opacity(0)
  }

  @StorageLink('isLoggedIn') loggedIn: boolean = false
  @StorageLink('user') user: User = {
    id: 0, username: '未登录', avatar: '', phone: '', password: '', role: UserRole.CUSTOMER,
    balance: 0, coupons: [], orders: [], storeIds: []
  }
  @State logs: AdminOperationLog[] = []
  @State page: number = 1
  @State total: number = 0
  @State hasMore: boolean = false
  @State loading: boolean = false
  @State renderVersion: number = 0

  aboutToAppear(): void {
    logInfo('Page', '进入管理操作审计页 AdminAuditPage')
    if (!this.loggedIn || this.user.role !== UserRole.ADMIN) {
      promptAction.showToast({ message: '仅管理端账号可以查看操作审计', duration: 1600 })
      router.replaceUrl({ url: 'pages/Index' })
      return
    }
    this.refresh()
  }

  private async refresh(): Promise<void> {
    if (this.loading) {
      return
    }
    this.loading = true
    this.page = 1
    const result = await fetchAdminOperationLogsApi(1)
    this.logs = result.list
    this.total = result.total
    this.hasMore = result.hasMore
    this.renderVersion += 1
    this.loading = false
  }

  private async loadMore(): Promise<void> {
    if (this.loading || !this.hasMore) {
      return
    }
    this.loading = true
    const result = await fetchAdminOperationLogsApi(this.page + 1)
    this.logs = this.logs.concat(result.list)
    this.page = result.page
    this.total = result.total
    this.hasMore = result.hasMore
    this.renderVersion += 1
    this.loading = false
  }

  private formatTime(timestamp: number): string {
    const date: Date = new Date(timestamp)
    const pad = (value: number): string => value < 10 ? `0${value}` : `${value}`
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())} ` +
      `${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}`
  }

  private roleName(role: number): string {
    switch (role) {
      case UserRole.CUSTOMER: return '用户'
      case UserRole.MERCHANT: return '商户'
      case UserRole.ADMIN: return '管理员'
      case UserRole.RIDER: return '骑手'
      default: return '系统'
    }
  }

  build() {
    Column() {
      PageHeader({
        title: '操作审计',
        backId: 'admin-audit-back',
        headerBgColor: COLORS.BG_PRIMARY,
        actionColor: MODULE_COLOR.ADMIN,
        actionLabel: this.loading ? '加载中' : '刷新',
        onBack: () => { router.back() },
        onAction: () => { this.refresh() }
      })

      List({ space: SPACING.SM }) {
        if (this.logs.length === 0 && !this.loading) {
          ListItem() {
            Text('暂无操作记录').fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT)
              .width('100%').padding(SPACING.LG)
          }
        }
        ForEach(this.logs, (item: AdminOperationLog) => {
          ListItem() {
            Column({ space: SPACING.XS }) {
              Row({ space: SPACING.SM }) {
                Text(item.action).fontSize(FONT_SIZE.MD).fontWeight(FontWeight.Bold)
                  .fontColor(COLORS.TEXT_PRIMARY).layoutWeight(1)
                StatusBadge({ text: item.outcome === 'SUCCESS' ? '成功' : '失败',
                  mode: item.outcome === 'SUCCESS' ? 'success' : 'error' })
              }.width('100%')
              Text(`${this.roleName(item.operatorRole)} #${item.operatorId}  ·  ${item.method} ${item.path}`)
                .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_SECONDARY).maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
              if (item.orderId > 0) {
                Text(`订单 #${item.orderId}  ·  操作后状态 ${item.statusAfter}`)
                  .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_SECONDARY).width('100%')
              }
              Text(`${item.status}  ·  ${this.formatTime(item.createdAt)}`)
                .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT).width('100%')
              Text(`traceId ${item.traceId}`).fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
            }
              .attributeModifier(new AppCardStyle())
              .width('100%').padding(SPACING.MD)
          }
        }, (item: AdminOperationLog) => `${this.renderVersion}-${item.id}`)
        ListItem() {
          Row({ space: SPACING.SM }) {
            Text(`已显示 ${this.logs.length} / ${this.total}`).fontSize(FONT_SIZE.XS)
              .fontColor(COLORS.TEXT_HINT).layoutWeight(1)
            if (this.hasMore) {
              Button(this.loading ? '加载中' : '加载更多')
                .attributeModifier(new AppButtonStyle()).height(40).fontSize(FONT_SIZE.XS)
                .enabled(!this.loading).id('admin-audit-load-more').onClick(() => { this.loadMore() })
            }
          }.width('100%').padding({ top: SPACING.SM, bottom: SPACING.MD })
        }
      }
        .width('100%').layoutWeight(1).scrollBar(BarState.Off)
        .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.MD, bottom: SPACING.XXL })
    }.width('100%').height('100%').backgroundColor(COLORS.BG_PRIMARY)
  }
}

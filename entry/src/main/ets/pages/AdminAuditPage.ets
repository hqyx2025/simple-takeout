import { fetchAdminOperationLogsResultApi } from '../service/ApiService'
import { PageSession } from '../service/PageSession'
import { RemoteState } from '../components/RemoteState'
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
  @State remoteFailed: boolean = false
  @State remoteLoading: boolean = false
  private remoteSession: PageSession = new PageSession()
  private remoteVisible: boolean = true

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

  @StorageLink('isLoggedIn') @Watch('onRemoteIdentityChange') loggedIn: boolean = false
  @StorageLink('user') @Watch('onRemoteIdentityChange') user: User = {
    id: 0, username: '未登录', avatar: '', phone: '', password: '', role: UserRole.CUSTOMER,
    balance: 0, coupons: [], orders: [], storeIds: []
  }
  @State logs: AdminOperationLog[] = []
  @State page: number = 1
  @State total: number = 0
  @State hasMore: boolean = false
  @State loading: boolean = false

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
    if (this.remoteLoading) { return }
    if (!this.remoteVisible || !this.remoteSession.start(UserRole.ADMIN)) { return }
    const remoteVersion: number = this.remoteSession.request()
    this.remoteLoading = true
    this.remoteFailed = false
    try {
      if (this.loading) {
        return
      }
      this.loading = true
      const result = await fetchAdminOperationLogsResultApi(1)
      if (!this.remoteSession.current(remoteVersion)) { return }
      if (result === null) { this.remoteFailed = true; return }

      this.logs = result.list
      this.page = result.page
      this.total = result.total
      this.hasMore = result.hasMore
      this.loading = false
    } catch (_) { if (this.remoteSession.current(remoteVersion)) { this.remoteFailed = true } }
    finally { if (this.remoteSession.current(remoteVersion)) { this.remoteLoading = false; this.loading = false } }
  }

  private async loadMore(): Promise<void> {
    if (this.remoteLoading) { return }
    if (!this.remoteVisible || !this.remoteSession.start(UserRole.ADMIN)) { return }
    const remoteVersion: number = this.remoteSession.request()
    this.remoteLoading = true
    this.remoteFailed = false
    try {
      if (this.loading || !this.hasMore) {
        return
      }
      this.loading = true
      const result = await fetchAdminOperationLogsResultApi(this.page + 1)
      if (!this.remoteSession.current(remoteVersion)) { return }
      if (result === null) { this.remoteFailed = true; return }

      this.logs = this.logs.concat(result.list)
      this.page = result.page
      this.total = result.total
      this.hasMore = result.hasMore
      this.loading = false
    } catch (_) { if (this.remoteSession.current(remoteVersion)) { this.remoteFailed = true } }
    finally { if (this.remoteSession.current(remoteVersion)) { this.remoteLoading = false; this.loading = false } }
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

  onRemoteIdentityChange(): void {
    if (!this.remoteSession.matchesIdentity()) {
      this.remoteSession.pause()
      this.remoteVisible = false
      this.remoteLoading = false
      this.remoteFailed = false
      this.loading = false
      this.logs = []
      router.replaceUrl({ url: 'pages/Index' })
    }
  }
  onPageHide(): void { this.remoteVisible = false; this.remoteSession.pause(); this.loading = false; this.remoteLoading = false }
  onPageShow(): void { this.remoteVisible = true; if (!this.loading) { this.refresh() } }
  aboutToDisappear(): void { this.onPageHide() }

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
      if (this.remoteFailed || (this.remoteLoading && !(this.logs.length > 0))) {
        RemoteState({ loading: this.remoteLoading, failed: this.remoteFailed, hasData: this.logs.length > 0,
          retryId: 'AdminAuditPage-retry', onRetry: () => { this.refresh() } })
      }

      List({ space: SPACING.SM }) {
        if (this.logs.length === 0 && !this.remoteFailed && !this.remoteLoading && !this.loading) {
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
        }, (item: AdminOperationLog) => `${item.id}`)
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

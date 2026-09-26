/**
 * 隐私政策同意页（启动首屏）。
 * 用独立路由页承载同意流程，而不是在首页内叠一层 if 覆盖层：
 * 覆盖层依赖构建时机与状态缓存，实测中出现过"门禁生效但弹窗从不渲染"的静默故障
 * （首页数据被挡住、用户却看不到任何提示）。路由页是确定性的，且同意前完全不发起业务请求。
 */
import { AppMotion } from '../common/theme/AppMotion'
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS } from '../common/Constants'
import { initLogger, setPrivacyConsent, logInfo } from '../service/AppLogger'
import { loadAllData, savePrivacyConsent, saveAllData } from '../service/DataPersistence'

@Entry
@Component
export struct ConsentPage {
  pageTransition() {
    PageTransitionEnter(AppMotion.pageEnter(RouteType.Push))
      .translate({ x: AppMotion.distance(AppMotion.PAGE_OFFSET) })
      .opacity(0)
    PageTransitionExit(AppMotion.pageExit(RouteType.Push))
      .translate({ x: -AppMotion.distance(AppMotion.RETURN_OFFSET) })
      .opacity(0)
    PageTransitionEnter(AppMotion.pageEnter(RouteType.Pop))
      .translate({ x: -AppMotion.distance(AppMotion.RETURN_OFFSET) })
      .opacity(0)
    PageTransitionExit(AppMotion.pageExit(RouteType.Pop))
      .translate({ x: AppMotion.distance(AppMotion.PAGE_OFFSET) })
      .opacity(0)
  }

  @State submitting: boolean = false

  private async accept(): Promise<void> {
    if (this.submitting) {
      return
    }
    this.submitting = true
    // 顺序很重要：先把同意状态落盘，再 loadAllData。
    // loadAllData 依据该标记决定是否恢复用户/令牌；若先 load 后 save，
    // 会读到空的持久化标记并把刚设置的 true 覆盖回 false，导致首页数据永远被门禁挡住。
    setPrivacyConsent(true)
    AppStorage.setOrCreate<boolean>('privacyConsent', true)
    await savePrivacyConsent(true)
    initLogger()
    await loadAllData()
    await saveAllData()
    logInfo('Consent', '用户已同意隐私政策，进入首页')
    promptAction.showToast({ message: '已同意隐私政策', duration: 1500 })
    router.replaceUrl({ url: 'pages/Index' })
  }

  private reject(): void {
    promptAction.showToast({ message: '未同意隐私政策，无法使用登录、定位与下单服务', duration: 3000 })
  }

  build() {
    Column({ space: SPACING.MD }) {
      Row() {
        Text('简单外卖').fontSize(FONT_SIZE.XXL).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
      }
      .width('100%')
      .padding({ bottom: SPACING.SM })

      Text('隐私政策提示')
        .fontSize(FONT_SIZE.XL)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLORS.TEXT_PRIMARY)
        .width('100%')
        .textAlign(TextAlign.Center)

      Text('为了提供登录、定位、配送、下单与评价服务，我们需要按照《隐私政策》处理必要的账号与订单信息。请阅读并同意后继续使用。')
        .fontSize(FONT_SIZE.MD)
        .fontColor(COLORS.TEXT_SECONDARY)
        .width('100%')
        .textAlign(TextAlign.Start)

      Text('查看《隐私政策》全文')
        .fontSize(FONT_SIZE.MD)
        .fontColor(COLORS.PRIMARY)
        .width('100%')
        .textAlign(TextAlign.Center)
        .onClick(() => { router.pushUrl({ url: 'pages/PrivacyPolicyPage' }) })

      Row({ space: SPACING.MD }) {
        Button('暂不同意')
          .id('privacy-reject')
          .layoutWeight(1)
          .height(44)
          .backgroundColor(COLORS.BG_PRIMARY)
          .fontColor(COLORS.TEXT_SECONDARY)
          .borderRadius(BORDER_RADIUS.ROUND)
          .type(ButtonType.Capsule)
          .onClick(() => { this.reject() })

        Button(this.submitting ? '处理中…' : '同意并继续')
          .id('privacy-accept')
          .layoutWeight(1)
          .height(44)
          .backgroundColor(COLORS.PRIMARY)
          .fontColor(COLORS.TEXT_WHITE)
          .borderRadius(BORDER_RADIUS.ROUND)
          .type(ButtonType.Capsule)
          .enabled(!this.submitting)
          .onClick(() => { this.accept() })
      }
      .width('100%')
      .margin({ top: SPACING.MD })
    }
    .width('100%')
    .height('100%')
    .padding(SPACING.XL)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(COLORS.BG_WHITE)
  }
}

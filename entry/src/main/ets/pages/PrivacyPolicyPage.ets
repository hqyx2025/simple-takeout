import { PageHeader } from '../components/PageHeader'
/** 简单外卖隐私政策页面 */
import { AppMotion } from '../common/theme/AppMotion'
import { routerCompat as router } from '../common/UiNavigation'
import { SPACING, FONT_SIZE } from '../common/Constants'
import { AppTheme, AppCardStyle } from '../common/theme/AppTheme'

@Entry
@Component
export struct PrivacyPolicyPage {
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

  @Builder
  policySection(title: string, content: string) {
    Column({ space: SPACING.MD }) {
      Row({ space: SPACING.SM }) {
        Column()
          .width(3)
          .height(18)
          .backgroundColor(AppTheme.ACCENT)
          .borderRadius(2)
        Text(title)
          .fontSize(FONT_SIZE.LG)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.TEXT)
          .layoutWeight(1)
      }
      .width('100%')

      Text(content)
        .fontSize(FONT_SIZE.MD)
        .lineHeight(24)
        .fontColor(AppTheme.MUTED)
        .width('100%')
        .textAlign(TextAlign.Start)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(SPACING.XL)
    .attributeModifier(new AppCardStyle())
  }

  build() {
    Column() {
      PageHeader({ title: '隐私政策', onBack: () => { router.back() } })

      Scroll() {
        Column({ space: SPACING.LG }) {
          Column({ space: SPACING.LG }) {
            Image($r('app.media.login_shield_active'))
              .width(48)
              .height(48)
              .padding(SPACING.MD)
              .backgroundColor(AppTheme.ACCENT_SOFT)
              .borderRadius(AppTheme.CONTROL_RADIUS)

            Column({ space: SPACING.SM }) {
              Text('简单外卖隐私政策')
                .fontSize(FONT_SIZE.TITLE)
                .fontWeight(FontWeight.Bold)
                .fontColor(AppTheme.TEXT)
              Text('生效日期：2026年10月18日')
                .fontSize(FONT_SIZE.SM)
                .fontColor(AppTheme.MUTED)
            }
            .alignItems(HorizontalAlign.Start)

            Text('我们重视您的隐私。本政策说明简单外卖如何收集、使用、保存和保护您在使用点餐、定位、订单和账户功能时提供的信息。')
              .fontSize(FONT_SIZE.MD)
              .lineHeight(24)
              .fontColor(AppTheme.MUTED)
              .width('100%')
              .textAlign(TextAlign.Start)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ top: SPACING.SM, bottom: SPACING.SM })

          this.policySection('1. 我们收集的信息',
            '为完成登录、配送和订单服务，我们可能处理手机号、邮箱、账户信息、收货地址、订单记录以及您主动授权的前台位置信息。邮箱用于注册验证、找回密码和在账户资料中展示。')
          this.policySection('2. 信息使用',
            '上述信息仅用于身份验证（包括邮箱验证码）、找回密码、展示附近店铺、计算配送范围、完成下单和售后服务，不会用于与服务无关的目的。')
          this.policySection('3. 权限说明',
            '定位权限仅在您使用定位功能时申请和使用。您可以在系统设置中随时关闭权限；关闭后仍可手动选择收货地址。\n\n网络权限用于访问店铺、商品和订单服务。\n\n交互手感知使用系统手势感知能力，仅在导航可见且应用位于前台时，根据正在操作页面的左手或右手调整导航位置。交互手数据不保存、不上传；也可在应用设置的导航位置中切换为手动靠左、靠右或居中。')
          this.policySection('4. 信息保护与删除',
            '我们通过本地持久化和服务端访问控制保护数据。您可以在设置中退出登录、清理本地缓存，或通过项目维护者渠道申请删除账户相关数据；删除账户时，关联的手机号、邮箱及订单资料会按法律要求处理。')

          Text('如您不同意本政策，请停止使用需要个人信息的功能。')
            .fontSize(FONT_SIZE.SM)
            .lineHeight(20)
            .fontColor(AppTheme.MUTED)
            .width('100%')
            .padding(SPACING.LG)
            .backgroundColor(AppTheme.INPUT)
            .borderRadius(AppTheme.CONTROL_RADIUS)
        }
        .width('100%')
        .constraintSize({ maxWidth: 640 })
        .alignItems(HorizontalAlign.Start)
        .padding({ left: SPACING.XL, right: SPACING.XL, top: SPACING.XL, bottom: SPACING.XXL })
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.PAGE)
  }
}

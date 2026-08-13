/** 简单外卖隐私政策页面 */
import router from '@ohos.router'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS } from '../common/Constants'

@Entry
@Component
export struct PrivacyPolicyPage {
  build() {
    Column() {
      Row() {
        Text('‹ 返回')
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_PRIMARY)
          .onClick(() => { router.back() })
        Text('隐私政策')
          .fontSize(FONT_SIZE.LG)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Text('   ').fontSize(FONT_SIZE.MD)
      }
      .width('100%')
      .height(44)
      .padding({ left: SPACING.LG, right: SPACING.LG })
      .backgroundColor(COLORS.BG_WHITE)

      Scroll() {
        Column({ space: SPACING.MD }) {
          Text('简单外卖隐私政策')
            .fontSize(FONT_SIZE.XXL)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLORS.TEXT_PRIMARY)
          Text('生效日期：2026年8月13日')
            .fontSize(FONT_SIZE.SM)
            .fontColor(COLORS.TEXT_HINT)
          Text('我们重视您的隐私。本政策说明简单外卖如何收集、使用、保存和保护您在使用点餐、定位、订单和账户功能时提供的信息。')
            .fontSize(FONT_SIZE.MD)
            .fontColor(COLORS.TEXT_SECONDARY)
          Text('1. 我们收集的信息')
            .fontSize(FONT_SIZE.LG)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLORS.TEXT_PRIMARY)
          Text('为完成登录、配送和订单服务，我们可能处理手机号、账户信息、收货地址、订单记录以及您主动授权的前台位置信息。')
            .fontSize(FONT_SIZE.MD)
            .fontColor(COLORS.TEXT_SECONDARY)
          Text('2. 信息使用')
            .fontSize(FONT_SIZE.LG)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLORS.TEXT_PRIMARY)
          Text('上述信息仅用于身份验证、展示附近店铺、计算配送范围、完成下单和售后服务，不会用于与服务无关的目的。')
            .fontSize(FONT_SIZE.MD)
            .fontColor(COLORS.TEXT_SECONDARY)
          Text('3. 权限说明')
            .fontSize(FONT_SIZE.LG)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLORS.TEXT_PRIMARY)
          Text('定位权限仅在您使用定位功能时申请和使用。您可以在系统设置中随时关闭权限；关闭后仍可手动选择收货地址。网络权限用于访问店铺、商品和订单服务。')
            .fontSize(FONT_SIZE.MD)
            .fontColor(COLORS.TEXT_SECONDARY)
          Text('4. 信息保护与删除')
            .fontSize(FONT_SIZE.LG)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLORS.TEXT_PRIMARY)
          Text('我们通过本地持久化和服务端访问控制保护数据。您可以在设置中退出登录、清理本地缓存，或通过项目维护者渠道申请删除账户相关数据。')
            .fontSize(FONT_SIZE.MD)
            .fontColor(COLORS.TEXT_SECONDARY)
          Text('如您不同意本政策，请停止使用需要个人信息的功能。')
            .fontSize(FONT_SIZE.MD)
            .fontColor(COLORS.TEXT_SECONDARY)
        }
        .width('100%')
        .padding(SPACING.LG)
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(COLORS.BG_PRIMARY)
  }
}

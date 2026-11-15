import { PageHeader } from '../components/PageHeader'
import { AppButtonStyle } from '../common/theme/AppTheme'
import { COLORS, SPACING } from '../common/Constants'
import { routerCompat as router } from '../common/UiNavigation'
import { User, createEmptyUser } from '../model/Models'

@Entry
@Component
export struct AccountSecurityPage {
  @StorageLink('user') user: User = createEmptyUser()
  @StorageLink('isLoggedIn') loggedIn: boolean = false

  aboutToAppear(): void { if (!this.loggedIn) { router.replaceUrl({ url: 'pages/Index' }) } }

  build() {
    Column() {
      PageHeader({ title: '账号安全', backId: 'account-security-back', onBack: () => { router.back() } })
      Scroll() {
        Column({ space: SPACING.MD }) {
          Button('修改登录密码').attributeModifier(new AppButtonStyle()).width('100%').height(48)
            .id('account-login-task').onClick(() => { router.pushUrl({ url: 'pages/ChangeLoginPasswordPage' }) })
          Button('支付密码').attributeModifier(new AppButtonStyle()).width('100%').height(48)
            .id('account-payment-task').onClick(() => { router.pushUrl({ url: 'pages/PaymentPasswordPage' }) })
          if (this.user.role === 0) {
            Button('注销账号').attributeModifier(new AppButtonStyle()).width('100%').height(48)
              .fontColor(COLORS.ERROR).backgroundColor(COLORS.ERROR_LIGHT)
              .id('account-closure-task').onClick(() => { router.pushUrl({ url: 'pages/CloseAccountPage' }) })
          }
        }.width('100%').padding(SPACING.LG)
      }.layoutWeight(1).width('100%').align(Alignment.Top)
    }.width('100%').height('100%').backgroundColor(COLORS.BG_PRIMARY)
  }
}

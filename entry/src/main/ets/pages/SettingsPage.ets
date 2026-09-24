/**
 * 设置页面
 * 包含：清除缓存、修改密码、退出登录、关于我们
 */
import { CartItem } from '../model/Models'
import { logout, changePasswordRemote, getLastRemoteErrorMessage } from '../service/AppStorageManager'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS } from '../common/Constants'
import { ConfirmDialog } from '../components/ConfirmDialog'
import { PageHeader } from '../components/PageHeader'
import { logInfo } from '../service/AppLogger'
import { routerCompat as router, promptCompat as promptAction } from '../common/UiNavigation'

@Entry
@Component
export struct SettingsPage {
  @StorageLink('isLoggedIn') loggedIn: boolean = false
  @State showAbout: boolean = false
  @State showLogoutConfirm: boolean = false
  @State cacheSize: string = '0KB'
  @State showPwdDialog: boolean = false
  @State oldPwd: string = ''
  @State newPwd: string = ''
  @State confirmPwd: string = ''
  @State pwdSaving: boolean = false
  onBack: () => void = () => { router.back() }
  onLogout: () => void = () => {}

  aboutToAppear() {
    logInfo('Page', '进入设置页 SettingsPage')
    this.calculateCacheSize()
  }

  calculateCacheSize() {
    const cart: CartItem[] = AppStorage.get<CartItem[]>('cartItems') || []
    // 简单估算：每个购物车项约 0.5KB
    const sizeKB: number = cart.length * 0.5
    this.cacheSize = sizeKB.toFixed(1) + 'KB'
  }

  clearCache() {
    // 清空购物车和搜索历史等非必要数据
    AppStorage.setOrCreate<CartItem[]>('cartItems', [])
    // 显示提示
    this.cacheSize = '0KB'
    logInfo('Settings', '清除缓存（清空购物车）')
  }

  doLogout() {
    logout()
    this.loggedIn = false
    this.showLogoutConfirm = false
    this.onLogout()
    logInfo('Settings', '设置页退出登录')
  }

  openPwdDialog() {
    this.oldPwd = ''
    this.newPwd = ''
    this.confirmPwd = ''
    this.showPwdDialog = true
  }

  /**
   * 修改密码：成功后服务端已把旧 token 全部判为失效，必须清理登录态回登录页
   */
  async submitPasswordChange() {
    if (this.pwdSaving) {
      return
    }
    if (this.oldPwd === '' || this.newPwd === '' || this.confirmPwd === '') {
      promptAction.showToast({ message: '请填写原密码、新密码与确认新密码', duration: 3000 })
      return
    }
    if (this.newPwd.length < 6) {
      promptAction.showToast({ message: '新密码长度至少 6 位', duration: 3000 })
      return
    }
    if (this.newPwd !== this.confirmPwd) {
      promptAction.showToast({ message: '两次输入的新密码不一致', duration: 3000 })
      return
    }
    if (this.newPwd === this.oldPwd) {
      promptAction.showToast({ message: '新密码不能与原密码相同', duration: 3000 })
      return
    }
    this.pwdSaving = true
    try {
      const ok: boolean = await changePasswordRemote(this.oldPwd, this.newPwd)
      if (!ok) {
        const reason: string = getLastRemoteErrorMessage()
        promptAction.showToast({ message: reason !== '' ? reason : '修改密码失败，请稍后重试', duration: 3000 })
        return
      }
      promptAction.showToast({ message: '密码已修改，请用新密码重新登录', duration: 3000 })
      this.showPwdDialog = false
      logInfo('Settings', '修改密码成功，旧 token 已失效')
      this.doLogout()
    } catch (err) {
      promptAction.showToast({ message: '修改密码失败，请检查网络后重试', duration: 3000 })
    } finally {
      this.pwdSaving = false
    }
  }

  build() {
    Stack() {
      // 主内容
      Column() {
        // 导航栏
        PageHeader({ title: '设置', onBack: () => { this.onBack() } })

        // 设置项列表
        Column() {
          // 清除缓存
          this.SettingItem('🗑', '清除缓存', this.cacheSize, false, () => {
            this.clearCache()
          })

          // 退出登录（仅登录时显示）
          if (this.loggedIn) {
            // 修改密码
            this.SettingItem('🔑', '修改密码', '', false, () => {
              this.openPwdDialog()
            })
            this.SettingItem('🚪', '退出登录', '', true, () => {
              this.showLogoutConfirm = true
            })
          }

          // 关于我们
          this.SettingItem('ℹ️', '关于我们', '', false, () => {
            this.showAbout = true
          })
          this.SettingItem('🔒', '隐私政策', '', false, () => {
            router.pushUrl({ url: 'pages/PrivacyPolicyPage' })
          })
        }
        .width('100%')
        .margin({ top: SPACING.SM })
        .backgroundColor(COLORS.BG_WHITE)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(COLORS.BG_PRIMARY)

      // 关于弹窗
      if (this.showAbout) {
        Stack() {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor(COLORS.OVERLAY)
            .onClick(() => { this.showAbout = false })

          Column({ space: SPACING.MD }) {
            Text('🍜').fontSize(60)
            Text('简单外卖')
              .fontSize(FONT_SIZE.XXL)
              .fontWeight(FontWeight.Bold)
              .fontColor(COLORS.TEXT_PRIMARY)
            Text('v1.0.0')
              .fontSize(FONT_SIZE.MD)
              .fontColor(COLORS.TEXT_HINT)
            Text('一款便捷学生点外卖的鸿蒙App')
              .fontSize(FONT_SIZE.MD)
              .fontColor(COLORS.TEXT_SECONDARY)
              .textAlign(TextAlign.Center)
            Text('HarmonyOS NEXT 毕业设计项目')
              .fontSize(FONT_SIZE.SM)
              .fontColor(COLORS.TEXT_HINT)
            Button('关闭')
              .height(40)
              .fontSize(FONT_SIZE.MD)
              .fontColor(COLORS.PRIMARY)
              .backgroundColor(Color.Transparent)
              .borderWidth(1)
              .borderColor(COLORS.PRIMARY)
              .borderRadius(BORDER_RADIUS.ROUND)
              .type(ButtonType.Capsule)
              .margin({ top: SPACING.LG })
              .onClick(() => { this.showAbout = false })
          }
          .width('80%')
          .padding(SPACING.XXL)
          .backgroundColor(COLORS.BG_WHITE)
          .borderRadius(BORDER_RADIUS.XL)
          .alignItems(HorizontalAlign.Center)
        }
        .width('100%')
        .height('100%')
        .alignContent(Alignment.Center)
      }

      // 修改密码弹窗
      if (this.showPwdDialog) {
        Stack() {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor(COLORS.OVERLAY)
            .onClick(() => {
              if (!this.pwdSaving) {
                this.showPwdDialog = false
              }
            })

          Column({ space: SPACING.SM }) {
            Text('修改密码')
              .fontSize(FONT_SIZE.XL)
              .fontWeight(FontWeight.Bold)
              .fontColor(COLORS.TEXT_PRIMARY)
            Text('修改成功后本机登录会失效，需要用新密码重新登录。')
              .fontSize(FONT_SIZE.SM)
              .fontColor(COLORS.TEXT_HINT)

            Text('原密码（必填）')
              .fontSize(FONT_SIZE.SM)
              .fontColor(COLORS.TEXT_SECONDARY)
              .width('100%')
              .margin({ top: SPACING.SM })
            TextInput({ placeholder: '请输入当前登录密码', text: this.oldPwd })
              .type(InputType.Password)
              .height(44)
              .fontSize(FONT_SIZE.MD)
              .backgroundColor(COLORS.BG_PRIMARY)
              .borderRadius(BORDER_RADIUS.MD)
              .onChange((value: string) => { this.oldPwd = value })

            Text('新密码（必填，至少 6 位）')
              .fontSize(FONT_SIZE.SM)
              .fontColor(COLORS.TEXT_SECONDARY)
              .width('100%')
              .margin({ top: SPACING.SM })
            TextInput({ placeholder: '请输入新密码，如：takeout2026', text: this.newPwd })
              .type(InputType.Password)
              .height(44)
              .fontSize(FONT_SIZE.MD)
              .backgroundColor(COLORS.BG_PRIMARY)
              .borderRadius(BORDER_RADIUS.MD)
              .onChange((value: string) => { this.newPwd = value })

            Text('确认新密码（必填）')
              .fontSize(FONT_SIZE.SM)
              .fontColor(COLORS.TEXT_SECONDARY)
              .width('100%')
              .margin({ top: SPACING.SM })
            TextInput({ placeholder: '请再次输入新密码', text: this.confirmPwd })
              .type(InputType.Password)
              .height(44)
              .fontSize(FONT_SIZE.MD)
              .backgroundColor(COLORS.BG_PRIMARY)
              .borderRadius(BORDER_RADIUS.MD)
              .onChange((value: string) => { this.confirmPwd = value })

            Row({ space: SPACING.MD }) {
              Button('取消')
                .layoutWeight(1)
                .height(44)
                .fontSize(FONT_SIZE.MD)
                .fontColor(COLORS.TEXT_SECONDARY)
                .backgroundColor(Color.Transparent)
                .borderWidth(1)
                .borderColor(COLORS.DIVIDER)
                .borderRadius(BORDER_RADIUS.ROUND)
                .type(ButtonType.Capsule)
                .enabled(!this.pwdSaving)
                .onClick(() => { this.showPwdDialog = false })
              Button(this.pwdSaving ? '提交中…' : '确认修改')
                .layoutWeight(1)
                .height(44)
                .fontSize(FONT_SIZE.MD)
                .fontColor(COLORS.TEXT_WHITE)
                .backgroundColor(COLORS.PRIMARY)
                .borderRadius(BORDER_RADIUS.ROUND)
                .type(ButtonType.Capsule)
                .enabled(!this.pwdSaving)
                .onClick(() => { this.submitPasswordChange() })
            }
            .width('100%')
            .margin({ top: SPACING.LG })
          }
          .width('86%')
          .padding(SPACING.XXL)
          .backgroundColor(COLORS.BG_WHITE)
          .borderRadius(BORDER_RADIUS.XL)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .height('100%')
        .alignContent(Alignment.Center)
      }

      // 退出确认弹窗
      if (this.showLogoutConfirm) {
        ConfirmDialog({
          title: '确认退出',
          content: '确定要退出登录吗？',
          confirmText: '退出',
          cancelText: '取消',
          onConfirm: () => { this.doLogout() },
          onCancel: () => { this.showLogoutConfirm = false }
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  SettingItem(icon: string, title: string, value: string, isDanger: boolean, onClick: () => void) {
    Row({ space: SPACING.MD }) {
      Text(icon).fontSize(20)
      Text(title)
        .fontSize(FONT_SIZE.LG)
        .fontColor(isDanger ? COLORS.ERROR : COLORS.TEXT_PRIMARY)
        .layoutWeight(1)
      if (value !== '') {
        Text(value).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT)
      }
      Text('›').fontSize(20).fontColor(COLORS.TEXT_HINT)
    }
    .width('100%')
    .height(56)
    .padding({ left: SPACING.LG, right: SPACING.LG })
    .backgroundColor(COLORS.BG_WHITE)
    .onClick(() => { onClick() })
  }
}

/**
 * 修改密码弹窗（四端共用）。
 * 调用方在 Stack 中放置本组件并在修改成功后执行 logout + 跳转登录页。
 */
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS } from '../common/Constants'
import { promptCompat as promptAction } from '../common/UiNavigation'
import { changePasswordRemote, getLastRemoteErrorMessage } from '../service/AppStorageManager'
import { logInfo } from '../service/AppLogger'

@Component
export struct ChangePasswordDialog {
  /** 修改成功后回调（通常用于 logout + replaceUrl） */
  onSuccess: () => void = () => {}
  /** 关闭弹窗 */
  onClose: () => void = () => {}
  @State oldPwd: string = ''
  @State newPwd: string = ''
  @State confirmPwd: string = ''
  @State saving: boolean = false

  private async submit(): Promise<void> {
    if (this.saving) {
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
    this.saving = true
    try {
      const ok: boolean = await changePasswordRemote(this.oldPwd, this.newPwd)
      if (!ok) {
        const reason: string = getLastRemoteErrorMessage()
        promptAction.showToast({ message: reason !== '' ? reason : '修改密码失败，请稍后重试', duration: 3000 })
        return
      }
      promptAction.showToast({ message: '密码已修改，请用新密码重新登录', duration: 3000 })
      logInfo('Account', '修改密码成功，旧 token 已失效')
      this.onSuccess()
    } catch (err) {
      promptAction.showToast({ message: '修改密码失败，请检查网络后重试', duration: 3000 })
    } finally {
      this.saving = false
    }
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(COLORS.OVERLAY)
        .onClick(() => {
          if (!this.saving) {
            this.onClose()
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
            .enabled(!this.saving)
            .onClick(() => { this.onClose() })

          Button(this.saving ? '提交中...' : '确认修改')
            .layoutWeight(1)
            .height(44)
            .fontSize(FONT_SIZE.MD)
            .fontColor(COLORS.TEXT_WHITE)
            .backgroundColor(COLORS.PRIMARY)
            .borderRadius(BORDER_RADIUS.ROUND)
            .type(ButtonType.Capsule)
            .enabled(!this.saving)
            .onClick(() => { this.submit() })
        }
        .width('100%')
        .margin({ top: SPACING.MD })
      }
      .width('86%')
      .padding(SPACING.XL)
      .backgroundColor(COLORS.BG_WHITE)
      .borderRadius(BORDER_RADIUS.XL)
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Center)
  }
}

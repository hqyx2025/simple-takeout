/**
 * 个人信息编辑页
 * 修改昵称和手机号
 */
import router from '@ohos.router'
import { promptAction } from '@kit.ArkUI'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS } from '../common/Constants'
import { User, UserRole } from '../model/Models'
import { getCurrentUser, updateUserProfile } from '../service/AppStorageManager'

@Component
export struct ProfileEditPage {
  @State username: string = ''
  @State phone: string = ''
  @State role: UserRole = UserRole.CUSTOMER

  aboutToAppear() {
    const user: User | undefined = getCurrentUser()
    if (user !== undefined && user !== null) {
      this.username = user.username
      this.phone = user.phone
      this.role = user.role
    }
  }

  private getAvatarLetter(): string {
    if (this.username.length > 0) {
      return this.username.charAt(0).toUpperCase()
    }
    return '用'
  }

  private getRoleText(): string {
    if (this.role === UserRole.MERCHANT) {
      return '商户'
    }
    return '普通用户'
  }

  private handleSave(): void {
    const name: string = this.username.trim()
    if (name.length === 0) {
      promptAction.showToast({ message: '请输入昵称' })
      return
    }
    const phoneRegex: RegExp = /^1\d{10}$/
    if (!phoneRegex.test(this.phone)) {
      promptAction.showToast({ message: '请输入正确的11位手机号' })
      return
    }
    updateUserProfile(name, this.phone)
    promptAction.showToast({ message: '保存成功' })
    router.back()
  }

  build() {
    Column() {
      // 导航栏
      this.NavBar()

      Scroll() {
        Column({ space: SPACING.MD }) {
          // 头像卡片
          this.AvatarCard()
          // 表单卡片
          this.FormCard()
        }
        .width('100%')
        .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.MD, bottom: SPACING.XL })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)

      // 底部保存按钮
      this.SaveButton()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(COLORS.BG_PRIMARY)
  }

  @Builder
  NavBar() {
    Row() {
      Text('‹')
        .fontSize(FONT_SIZE.BIG_TITLE)
        .fontColor(COLORS.TEXT_PRIMARY)
        .onClick(() => { router.back() })
      Text('编辑个人信息')
        .fontSize(FONT_SIZE.XL)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLORS.TEXT_PRIMARY)
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
      Text(' ')
        .fontSize(FONT_SIZE.BIG_TITLE)
        .width(28)
    }
    .width('100%')
    .height(56)
    .padding({ left: SPACING.LG, right: SPACING.LG })
    .backgroundColor(COLORS.BG_WHITE)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  AvatarCard() {
    Column({ space: SPACING.MD }) {
      Stack() {
        Circle({ width: 72, height: 72 }).fill(COLORS.PRIMARY)
        Text(this.getAvatarLetter())
          .fontSize(FONT_SIZE.TITLE)
          .fontColor(COLORS.TEXT_WHITE)
          .fontWeight(FontWeight.Bold)
      }
      .width(72)
      .height(72)

      Text(this.username)
        .fontSize(FONT_SIZE.LG)
        .fontColor(COLORS.TEXT_PRIMARY)
        .fontWeight(FontWeight.Medium)
    }
    .width('100%')
    .padding(SPACING.XL)
    .backgroundColor(COLORS.BG_WHITE)
    .borderRadius(BORDER_RADIUS.LG)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  FormCard() {
    Column({ space: SPACING.MD }) {
      // 昵称
      Row() {
        Text('昵称')
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_SECONDARY)
          .width(72)
        TextInput({ placeholder: '请输入昵称', text: this.username })
          .layoutWeight(1)
          .height(44)
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_PRIMARY)
          .backgroundColor(Color.Transparent)
          .borderRadius(BORDER_RADIUS.SM)
          .maxLength(20)
          .onChange((value: string) => { this.username = value })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Divider().color(COLORS.DIVIDER)

      // 手机号
      Row() {
        Text('手机号')
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_SECONDARY)
          .width(72)
        TextInput({ placeholder: '请输入手机号', text: this.phone })
          .layoutWeight(1)
          .height(44)
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_PRIMARY)
          .backgroundColor(Color.Transparent)
          .borderRadius(BORDER_RADIUS.SM)
          .maxLength(11)
          .type(InputType.PhoneNumber)
          .onChange((value: string) => { this.phone = value })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Divider().color(COLORS.DIVIDER)

      // 用户角色（不可编辑）
      Row() {
        Text('用户角色')
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_SECONDARY)
          .width(72)
        Text(this.getRoleText())
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_PRIMARY)
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding(SPACING.LG)
    .backgroundColor(COLORS.BG_WHITE)
    .borderRadius(BORDER_RADIUS.LG)
  }

  @Builder
  SaveButton() {
    Row() {
      Button('保存')
        .width('100%')
        .height(48)
        .fontSize(FONT_SIZE.LG)
        .fontColor(COLORS.TEXT_WHITE)
        .backgroundColor(COLORS.PRIMARY)
        .borderRadius(BORDER_RADIUS.ROUND)
        .type(ButtonType.Capsule)
        .onClick(() => { this.handleSave() })
    }
    .width('100%')
    .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.MD, bottom: SPACING.LG })
    .backgroundColor(COLORS.BG_WHITE)
  }
}

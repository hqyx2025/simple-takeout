import { FormInput } from '../components/FormInput'
import { AppButtonStyle, AppCardStyle, AppInputStyle } from '../common/theme/AppTheme'
/**
 * 个人信息编辑页
 * 修改昵称和手机号
 */
import { AppMotion } from '../common/theme/AppMotion'
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS } from '../common/Constants'
import { User, UserRole } from '../model/Models'
import { getCurrentUser, updateUserProfileRemote, logout } from '../service/AppStorageManager'
import { logInfo } from '../service/AppLogger'
import { PageHeader } from '../components/PageHeader'
import { photoAccessHelper } from '@kit.MediaLibraryKit'
import { uploadImageApi } from '../service/ApiService'
import { ApiResponse, getApiBaseUrl, getAuthSessionEpoch, getLastApiErrorMessage } from '../service/HttpClient'
import { ContactVerificationStatus, fetchContactVerificationApi, sendContactCodeApi,
  verifyCurrentContactApi } from '../service/api/AuthApi'
import { updateUserAvatarRemote } from '../service/AppStorageManager'
import { UploadResult } from '../model/Models'
import { AvatarCropDialog } from '../components/AvatarCropDialog'

@Entry
@Component
export struct ProfileEditPage {
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

  @StorageLink('isLoggedIn') loggedIn: boolean = false
  @State username: string = ''
  @State phone: string = ''
  @State email: string = ''
  @State currentPassword: string = ''
  @State phoneCode: string = ''
  @State emailCode: string = ''
  @State phoneVerified: boolean = false
  @State emailVerified: boolean = false
  @State phoneAvailable: boolean = false
  @State contactsLoaded: boolean = false
  @State contactBusy: boolean = false
  @State contactCooldown: number = 0
  private originalPhone: string = ''
  private originalEmail: string = ''
  private contactTimer: number = -1
  @State role: UserRole = UserRole.CUSTOMER
  @State avatar: string = ''
  @State avatarFailed: boolean = false
  @State avatarUploading: boolean = false
  @State avatarProgress: number = 0
  private alive: boolean = true
  private selectedAvatarUri: string = ''
  private avatarEpoch: number = 0
  private avatarCropDialog: CustomDialogController = new CustomDialogController({
    builder: AvatarCropDialog({ uri: this.selectedAvatarUri,
      onConfirm: (path: string): Promise<boolean> => this.uploadAvatar(path, this.avatarEpoch) }),
    autoCancel: false, customStyle: true, alignment: DialogAlignment.Center
  })

  aboutToAppear() {
    this.alive = true
    logInfo('Page', '进入个人信息编辑页 ProfileEditPage')
    if (!this.loggedIn) {
      promptAction.showToast({ message: '请先登录后编辑个人资料', duration: 1800 })
      router.back()
      return
    }
    const user: User | undefined = getCurrentUser()
    if (user !== undefined && user !== null) {
      this.username = user.username
      this.phone = user.phone
      this.email = user.email ?? ''
      this.originalPhone = user.phone
      this.originalEmail = (user.email ?? '').trim().toLowerCase()
      this.role = user.role
      this.avatar = user.avatar ?? ''
    }
    this.loadContactStatus()
  }

  aboutToDisappear(): void {
    this.alive = false
    this.avatarCropDialog.close()
    if (this.contactTimer !== -1) { clearInterval(this.contactTimer); this.contactTimer = -1 }
    this.currentPassword = ''; this.phoneCode = ''; this.emailCode = ''
  }

  private async loadContactStatus(): Promise<void> {
    const epoch: number = getAuthSessionEpoch()
    const status: ContactVerificationStatus | null = await fetchContactVerificationApi()
    if (!this.alive || epoch !== getAuthSessionEpoch()) { return }
    this.contactsLoaded = status !== null
    this.phoneAvailable = status?.phoneAvailable ?? false
    this.phoneVerified = status?.phoneVerified ?? false
    this.emailVerified = status?.emailVerified ?? false
  }

  private contactValue(kind: string): string {
    return kind === 'PHONE' ? this.phone : this.email.trim().toLowerCase()
  }

  private async contactAction(kind: string, verify: boolean): Promise<void> {
    if (this.contactBusy || this.saving || !this.loggedIn || (!verify && this.contactCooldown > 0)) { return }
    if (kind === 'PHONE' && !this.phoneAvailable) {
      promptAction.showToast({ message: '短信验证暂不可用，暂不能修改手机号' }); return
    }
    const value: string = this.contactValue(kind)
    if (!(kind === 'PHONE' ? /^1\d{10}$/.test(value) : /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(value))) {
      promptAction.showToast({ message: kind === 'PHONE' ? '请输入正确的手机号' : '请输入正确的邮箱' }); return
    }
    if (!this.currentPassword) { promptAction.showToast({ message: '请先填写当前登录密码' }); return }
    const code: string = kind === 'PHONE' ? this.phoneCode : this.emailCode
    if (verify && !/^\d{6}$/.test(code)) { promptAction.showToast({ message: '请输入 6 位验证码' }); return }
    const epoch: number = getAuthSessionEpoch()
    this.contactBusy = true
    try {
      const response: ApiResponse<string> = verify
        ? await verifyCurrentContactApi(kind, value, this.currentPassword, code)
        : await sendContactCodeApi(kind, value, this.currentPassword)
      if (!this.alive || epoch !== getAuthSessionEpoch() || value !== this.contactValue(kind)) { return }
      if (response.code !== 200) {
        promptAction.showToast({ message: response.message || '验证未完成，请重试' }); return
      }
      if (verify) {
        if (kind === 'PHONE') { this.phoneVerified = true; this.phoneCode = '' }
        else { this.emailVerified = true; this.emailCode = '' }
        promptAction.showToast({ message: '联系方式已验证' })
      } else {
        this.contactCooldown = 60
        this.contactTimer = setInterval(() => {
          this.contactCooldown = Math.max(0, this.contactCooldown - 1)
          if (this.contactCooldown === 0) { clearInterval(this.contactTimer); this.contactTimer = -1 }
        }, 1000)
        promptAction.showToast({ message: '验证码已发送' })
      }
    } finally { if (this.alive && epoch === getAuthSessionEpoch()) { this.contactBusy = false } }
  }

  private async changeAvatar(): Promise<void> {
    if (this.avatarUploading || this.saving || !this.loggedIn) { return }
    const epoch: number = getAuthSessionEpoch()
    this.avatarUploading = true
    this.avatarProgress = -1
    try {
      const picker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker()
      const options: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions()
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE
      options.maxSelectNumber = 1
      const selected: photoAccessHelper.PhotoSelectResult = await picker.select(options)
      if (!this.alive || epoch !== getAuthSessionEpoch() || !selected.photoUris.length) { return }
      this.selectedAvatarUri = selected.photoUris[0]
      this.avatarEpoch = epoch
      this.avatarCropDialog.open()
    } catch (_) {
      if (this.alive && epoch === getAuthSessionEpoch()) { promptAction.showToast({ message: '选图失败，请重试' }) }
    } finally { if (this.alive) { this.avatarUploading = false } }
  }

  private async uploadAvatar(path: string, epoch: number): Promise<boolean> {
    if (!this.alive || epoch !== getAuthSessionEpoch() || !this.loggedIn || this.avatarUploading) { return false }
    this.avatarUploading = true
    this.avatarProgress = 0
    try {
      const result: UploadResult | null = await uploadImageApi(path, false, (percent: number) => {
        if (this.alive && epoch === getAuthSessionEpoch()) { this.avatarProgress = percent }
      })
      if (!this.alive || epoch !== getAuthSessionEpoch()) { return false }
      if (result === null) {
        promptAction.showToast({ message: getLastApiErrorMessage() || '头像上传失败，请重试' })
        return false
      }
      const updated: User | undefined = await updateUserAvatarRemote(result.url)
      if (!this.alive || epoch !== getAuthSessionEpoch()) { return false }
      if (updated === undefined) {
        promptAction.showToast({ message: getLastApiErrorMessage() || '头像保存失败，请重试' })
        return false
      }
      this.avatar = updated.avatar
      this.avatarFailed = false
      promptAction.showToast({ message: '头像已更新' })
      return true
    } catch (_) {
      if (this.alive && epoch === getAuthSessionEpoch()) { promptAction.showToast({ message: '更换头像失败，请重试' }) }
      return false
    } finally {
      if (this.alive) { this.avatarUploading = false }
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

  @State saving: boolean = false

  private async handleSave(): Promise<void> {
    if (this.saving || this.avatarUploading || this.contactBusy) {
      return
    }
    const name: string = this.username.trim()
    if (name.length === 0) {
      promptAction.showToast({ message: '请输入账号' })
      return
    }
    const phoneRegex: RegExp = /^1\d{10}$/
    if (!phoneRegex.test(this.phone)) {
      promptAction.showToast({ message: '请输入正确的11位手机号' })
      return
    }
    const email: string = this.email.trim().toLowerCase()
    const phoneChanged: boolean = this.phone !== this.originalPhone
    const emailChanged: boolean = email !== this.originalEmail
    if (email !== '' && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
      promptAction.showToast({ message: '请输入正确的邮箱地址' })
      return
    }
    if (phoneChanged && !this.phoneAvailable) {
      promptAction.showToast({ message: '短信验证暂不可用，暂不能修改手机号' }); return
    }
    if ((phoneChanged || emailChanged) && !this.currentPassword) {
      promptAction.showToast({ message: '修改联系方式需要填写当前登录密码' }); return
    }
    if ((phoneChanged && !/^\d{6}$/.test(this.phoneCode)) || (emailChanged && !/^\d{6}$/.test(this.emailCode))) {
      promptAction.showToast({ message: '请获取并填写新联系方式的 6 位验证码' }); return
    }
    const epoch: number = getAuthSessionEpoch()
    this.saving = true
    try {
      const updated: User | undefined = await updateUserProfileRemote(name, this.phone, email, this.currentPassword,
        this.phoneCode, this.emailCode)
      if (!this.alive || epoch !== getAuthSessionEpoch()) { return }
      if (updated === undefined) {
        promptAction.showToast({ message: getLastApiErrorMessage() || '保存失败，请稍后重试' })
        return
      }
      this.currentPassword = ''; this.phoneCode = ''; this.emailCode = ''
      logInfo('Profile', '个人资料保存成功')
      if (phoneChanged || emailChanged) { logout() }
      promptAction.showToast({ message: phoneChanged || emailChanged ? '联系方式已更新，请重新登录' : '保存成功' })
      // 此页面由“我的”页面进入，保存成功后返回上一页并触发首页 onPageShow 刷新资料。
      router.back()
    } catch (_) {
      if (this.alive && epoch === getAuthSessionEpoch()) { promptAction.showToast({ message: '保存失败，请稍后重试' }) }
    } finally {
      if (this.alive) { this.saving = false }
    }
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
      }.align(Alignment.Top)
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
    PageHeader({ title: '编辑个人信息', onBack: () => { router.back() } })
  }

  @Builder
  AvatarCard() {
    Column({ space: SPACING.MD }) {
      Button({ type: ButtonType.Normal }) {
        Stack() {
        Circle({ width: 72, height: 72 }).fill(COLORS.PRIMARY)
        Text(this.getAvatarLetter())
          .fontSize(FONT_SIZE.TITLE)
          .fontColor(COLORS.ON_PRIMARY)
          .fontWeight(FontWeight.Bold)
          if (this.avatar !== '' && !this.avatarFailed) {
            Image(this.avatar.startsWith('/') ? getApiBaseUrl() + this.avatar : this.avatar)
              .width(72).height(72).objectFit(ImageFit.Cover).borderRadius(36)
              .onError(() => { this.avatarFailed = true }).id('profile-avatar-image')
          }
        }
      }
      .width(72)
      .height(72)
      .padding(0).borderRadius(36).backgroundColor(COLORS.PRIMARY)
      .enabled(!this.saving && !this.avatarUploading).accessibilityText('更换头像')
      .id('profile-avatar-picker').onClick(() => { this.changeAvatar() })

      Button(this.avatarUploading ? (this.avatarProgress < 0 ? '选择图片…' : this.avatarProgress >= 100 ? '保存头像中…' : '上传中 ' + this.avatarProgress + '%') : '更换头像')
        .attributeModifier(new AppButtonStyle()).height(44)
        .fontColor(COLORS.PRIMARY).backgroundColor(COLORS.BG_PRIMARY)
        .enabled(!this.saving && !this.avatarUploading).id('profile-avatar-change')
        .onClick(() => { this.changeAvatar() })

      Text(this.username)
        .fontSize(FONT_SIZE.LG)
        .fontColor(COLORS.TEXT_PRIMARY)
        .fontWeight(FontWeight.Medium)
    }
      .attributeModifier(new AppCardStyle())
    .width('100%')
    .padding(SPACING.XL)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  FormCard() {
    Column({ space: SPACING.MD }) {
      // 昵称
      Row() {

        FormInput({ label: '用户名',
          value: this.username,
          placeholder: '唯一账号，例如 takeout_user',
          maxLength: 64,
          onChange: (value: string) => { this.username = value },
          fieldId: 'ProfileEditPage-username',
          required: true }).layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Divider().color(COLORS.DIVIDER)

      Row() {

        FormInput({ label: '当前登录密码',
          value: this.currentPassword,
          placeholder: '修改手机号或邮箱时必填',
          inputType: InputType.Password,
          onChange: (value: string) => { this.currentPassword = value },
          fieldId: 'ProfileEditPage-currentPassword' }).layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Divider().color(COLORS.DIVIDER)

      // 找回密码邮箱
      Row() {

        FormInput({ label: '邮箱',
          value: this.email,
          placeholder: '用于找回密码',
          inputType: InputType.Email,
          onChange: (value: string) => { this.email = value; this.emailCode = '' },
          isEnabled: !this.saving && !this.contactBusy,
          fieldId: 'ProfileEditPage-email' }).layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.email.trim().toLowerCase() !== this.originalEmail || !this.emailVerified) {
        this.ContactCode('EMAIL')
      } else {
        Text('邮箱已验证').fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY).width('100%')
      }

      Divider().color(COLORS.DIVIDER)

      // 手机号
      Row() {

        FormInput({ label: '手机号',
          value: this.phone,
          placeholder: '请输入手机号',
          inputType: InputType.PhoneNumber,
          maxLength: 11,
          onChange: (value: string) => { this.phone = value; this.phoneCode = '' },
          isEnabled: this.phoneAvailable && !this.saving && !this.contactBusy,
          fieldId: 'ProfileEditPage-phone',
          required: true }).layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (!this.contactsLoaded) {
        Button('重新读取验证状态').attributeModifier(new AppButtonStyle())
          .onClick(() => { this.loadContactStatus() })
      } else if (!this.phoneAvailable) {
        Text('短信验证暂不可用，暂不能修改手机号').fontSize(FONT_SIZE.SM)
          .fontColor(COLORS.TEXT_SECONDARY).width('100%')
      } else if (this.phone !== this.originalPhone || !this.phoneVerified) {
        this.ContactCode('PHONE')
      } else {
        Text('手机号已验证').fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY).width('100%')
      }

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
          .padding({ left: SPACING.LG })
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
      .attributeModifier(new AppCardStyle())
    .width('100%')
    .padding(SPACING.LG)
  }

  @Builder
  ContactCode(kind: string) {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        FormInput({ label: kind === 'PHONE' ? '手机验证码' : '邮箱验证码',
          value: kind === 'PHONE' ? this.phoneCode : this.emailCode,
          placeholder: '6 位验证码', maxLength: 6, oneTimeCode: true,
          isEnabled: !this.saving && !this.contactBusy,
          fieldId: kind === 'PHONE' ? 'profile-phone-code' : 'profile-email-code',
          onChange: (value: string) => { if (kind === 'PHONE') { this.phoneCode = value } else { this.emailCode = value } }
        }).layoutWeight(1)
        Button(this.contactCooldown > 0 ? this.contactCooldown + ' 秒后重发' : '获取验证码')
          .attributeModifier(new AppButtonStyle()).height(48).margin({ top: 24 })
          .enabled(!this.saving && !this.contactBusy && this.contactCooldown === 0)
          .id(kind === 'PHONE' ? 'profile-phone-send' : 'profile-email-send')
          .onClick(() => { this.contactAction(kind, false) })
      }.width('100%').alignItems(VerticalAlign.Top)
      if ((kind === 'PHONE' && this.phone === this.originalPhone) ||
        (kind === 'EMAIL' && this.email.trim().toLowerCase() === this.originalEmail && this.originalEmail !== '')) {
        Button(kind === 'PHONE' ? '验证当前手机号' : '验证当前邮箱')
          .attributeModifier(new AppButtonStyle()).height(44)
          .enabled(!this.saving && !this.contactBusy)
          .id(kind === 'PHONE' ? 'profile-phone-verify' : 'profile-email-verify')
          .onClick(() => { this.contactAction(kind, true) })
      }
    }.width('100%')
  }

  @Builder
  SaveButton() {
    Row() {
      Button(this.saving ? '保存中…' : '保存')
        .attributeModifier(new AppButtonStyle())
        .width('100%')
        .height(48)
        .fontSize(FONT_SIZE.LG).fontColor(COLORS.ON_PRIMARY)
        .backgroundColor(COLORS.PRIMARY)
        .borderRadius(BORDER_RADIUS.ROUND)
        .enabled(!this.saving && !this.avatarUploading && !this.contactBusy)
        .onClick(() => { this.handleSave() })
    }
    .width('100%')
    .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.MD, bottom: SPACING.LG })
    .backgroundColor(COLORS.BG_WHITE)
  }
}

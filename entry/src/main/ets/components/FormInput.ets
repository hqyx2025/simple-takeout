import { AppInputStyle, AppTheme } from '../common/theme/AppTheme'
import { PASSWORD_HINT, newPasswordError, passwordStrength } from '../common/PasswordPolicy'

/** 固定标签与定位 ID 随输入内容保留，供业务表单和设备测试共同使用。 */
@Component
export struct FormInput {
  @Prop label: string = ''
  @Prop @Watch('updatePasswordFeedback') value: string = ''
  @Prop placeholder: string = ''
  @Prop fieldId: string = ''
  @Prop inputType: InputType = InputType.Normal
  @Prop maxLength: number = 100
  @Prop isEnabled: boolean = true
  @Prop errorMessage: string = ''
  @Prop compact: boolean = false
  @Prop passwordRules: boolean = false
  icon?: Resource
  @State focused: boolean = false
  @State strength: number = 0
  @State passwordError: string = ''
  onChange: (value: string) => void = () => {}
  onInputBlur: () => void = () => {}

  aboutToAppear(): void { this.updatePasswordFeedback() }

  private updatePasswordFeedback(): void {
    if (!this.passwordRules) { return }
    this.strength = passwordStrength(this.value)
    this.passwordError = this.value ? newPasswordError(this.value) : ''
  }

  @Builder
  private strengthCell(level: number) {
    Row().width(20).height(5).borderRadius(2)
      .backgroundColor(this.strength < level ? AppTheme.BORDER : this.strength === 1 ? AppTheme.ERROR
        : this.strength === 2 ? AppTheme.PASSWORD_MEDIUM : AppTheme.SUCCESS)
      .id(this.fieldId + '-strength-' + level)
  }

  build() {
    Column({ space: this.compact ? 3 : 6 }) {
      Row({ space: 8 }) {
        Text(this.label).fontSize(this.compact ? 13 : 14).fontColor(AppTheme.TEXT).layoutWeight(1)
        if (this.passwordRules && this.value) {
          Row({ space: 4 }) {
            this.strengthCell(1)
            this.strengthCell(2)
            this.strengthCell(3)
            Text(this.strength === 1 ? '弱' : this.strength === 2 ? '中' : this.strength === 3 ? '强' : '字符无效')
              .fontSize(12).fontColor(AppTheme.MUTED).id(this.fieldId + '-strength-label')
          }.accessibilityText('密码强度：' + (this.strength === 1 ? '弱' : this.strength === 2 ? '中' : this.strength === 3 ? '强' : '字符无效'))
        }
      }.width('100%')
      if (this.icon !== undefined) {
        Row({ space: 10 }) {
          Image(this.icon).width(20).height(20).objectFit(ImageFit.Contain).accessibilityLevel('no')
          TextInput({ text: this.value, placeholder: this.placeholder })
            .fontSize(16).fontColor(AppTheme.TEXT).placeholderColor(AppTheme.MUTED).caretColor(AppTheme.ACCENT)
            .layoutWeight(1).height(44).padding(0).backgroundColor(Color.Transparent).borderRadius(0)
            .type(this.inputType).maxLength(this.maxLength).enabled(this.isEnabled)
            .id(this.fieldId).accessibilityText(this.label)
            .onChange((value: string) => { this.value = value; this.updatePasswordFeedback(); this.onChange(value) })
            .onFocus(() => { this.focused = true }).onBlur(() => { this.focused = false; this.onInputBlur() })
        }.width('100%').height(44).padding({ left: 14, right: 14 }).backgroundColor(AppTheme.INPUT)
          .border({ width: this.errorMessage || this.passwordError || this.focused ? 1.5 : 1,
            color: this.errorMessage || this.passwordError ? AppTheme.ERROR : this.focused ? AppTheme.ACCENT : AppTheme.BORDER })
          .borderRadius(AppTheme.CONTROL_RADIUS)
      } else {
        TextInput({ text: this.value, placeholder: this.placeholder })
          .attributeModifier(new AppInputStyle()).type(this.inputType).maxLength(this.maxLength)
          .height(this.compact ? 44 : AppTheme.CONTROL_HEIGHT)
          .borderColor(this.errorMessage || this.passwordError ? AppTheme.ERROR : this.focused ? AppTheme.ACCENT : AppTheme.BORDER)
          .width('100%').enabled(this.isEnabled).id(this.fieldId).accessibilityText(this.label)
          .onChange((value: string) => { this.value = value; this.updatePasswordFeedback(); this.onChange(value) })
          .onFocus(() => { this.focused = true }).onBlur(() => { this.focused = false; this.onInputBlur() })
      }
      if (this.passwordRules && this.focused) {
        Text(PASSWORD_HINT).fontSize(12).fontColor(AppTheme.MUTED).width('100%').id(this.fieldId + '-rules')
      }
      if (this.passwordRules && this.passwordError) {
        Text(this.passwordError).fontSize(13).fontColor(AppTheme.ERROR).width('100%').id(this.fieldId + '-error')
      } else if (this.errorMessage) {
        Text(this.errorMessage).fontSize(13).fontColor(AppTheme.ERROR).width('100%').id(this.fieldId + '-error')
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}

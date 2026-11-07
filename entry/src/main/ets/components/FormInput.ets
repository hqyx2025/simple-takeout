import { AppTheme } from '../common/theme/AppTheme'
import { PASSWORD_HINT, newPasswordError, passwordStrength } from '../common/PasswordPolicy'

/** 浮动标签、帮助和失焦反馈；页面仍负责提交校验与业务规则。 */
@Component
export struct FormInput {
  @Prop label: string = ''
  @Prop @Watch('valueChanged') value: string = ''
  @Prop placeholder: string = ''
  @Prop helpText: string = ''
  @Prop fieldId: string = ''
  @Prop inputType: InputType = InputType.Normal
  @Prop maxLength: number = 100
  @Prop isEnabled: boolean = true
  @Prop errorMessage: string = ''
  @Prop compact: boolean = false
  @Prop passwordRules: boolean = false
  @Prop required: boolean = false
  @Prop multiline: boolean = false
  @Prop inputHeight: number = 100
  @Prop showPassword: boolean = true
  @Prop filter: string = ''
  @Prop oneTimeCode: boolean = false
  icon?: Resource
  @State focused: boolean = false
  @State localError: string = ''
  @State strength: number = 0
  onChange: (value: string) => void = () => {}
  onInputBlur: () => void = () => {}
  onInputSubmit: () => void = () => {}
  validator: (value: string) => string = (): string => ''

  private valueChanged(): void {
    if ((this.inputType !== InputType.PhoneNumber && this.inputType !== InputType.Password)
      || this.hasCompleteValue(this.value)) { this.localError = '' }
    this.strength = this.passwordRules ? passwordStrength(this.value) : 0
  }

  private hasCompleteValue(value: string): boolean {
    if (this.inputType === InputType.PhoneNumber) { return /^1\d{10}$/.test(value.trim()) }
    if (this.inputType !== InputType.Password || !value) { return false }
    return (!this.passwordRules || newPasswordError(value) === '') && this.validator(value) === ''
      && (this.maxLength !== 6 || /^\d{6}$/.test(value))
  }

  @Builder
  private strengthCell(level: number) {
    Row().width(20).height(5).borderRadius(2)
      .backgroundColor(this.strength < level ? AppTheme.BORDER : this.strength === 1 ? AppTheme.ERROR
        : this.strength === 2 ? AppTheme.PASSWORD_MEDIUM : AppTheme.SUCCESS)
      .id(this.fieldId + '-strength-' + level)
  }

  private change(value: string): void {
    this.value = value
    this.valueChanged()
    this.onChange(value)
  }

  private validateOnBlur(): void {
    this.focused = false
    const text: string = this.value.trim()
    this.localError = this.required && !text ? '请填写' + this.label : ''
    if (text && !this.localError) {
      if (this.oneTimeCode && !/^\d{6}$/.test(text)) { this.localError = '请输入完整的 6 位验证码' }
      else if (this.inputType === InputType.PhoneNumber && !/^1\d{10}$/.test(text)) { this.localError = '请输入 11 位手机号' }
      else if (this.inputType === InputType.Email && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(text)) { this.localError = '请输入完整邮箱，例如 name@example.com' }
      else if (this.passwordRules) { this.localError = newPasswordError(this.value) }
      else if (this.inputType === InputType.Password && this.maxLength === 6 && !/^\d{6}$/.test(this.value)) { this.localError = '请输入 6 位数字密码' }
      else if ((this.inputType === InputType.Number || this.inputType === InputType.NUMBER_DECIMAL)
        && (!Number.isFinite(Number(text)) || Number(text) < 0)) { this.localError = '请输入不小于 0 的数字' }
    }
    if (!this.localError) { this.localError = this.validator(this.value) }
    this.onInputBlur()
  }

  build() {
    Column({ space: 4 }) {
      Stack({ alignContent: Alignment.TopStart }) {
        if (this.multiline) {
          TextArea({ text: this.value })
            .width('100%').height(this.inputHeight).fontSize(16).fontColor(AppTheme.TEXT)
            .backgroundColor(Color.Transparent).padding({ left: 14, right: 14, top: 24, bottom: 10 })
            .maxLength(this.maxLength).enabled(this.isEnabled).caretColor(AppTheme.ACCENT)
            .id(this.fieldId).accessibilityText(this.label)
            .onChange((value: string) => { this.change(value) })
            .onFocus(() => { this.focused = true }).onBlur(() => { this.validateOnBlur() })
        } else {
          TextInput({ text: this.value })
            .width('100%').height(56).fontSize(16).fontColor(AppTheme.TEXT)
            .backgroundColor(Color.Transparent).padding({ left: 14, right: 14, top: 19, bottom: 3 })
            .type(this.oneTimeCode ? InputType.ONE_TIME_CODE : this.inputType)
            .enableAutoFill(true).showPasswordIcon(this.showPassword).inputFilter(this.filter)
            .maxLength(this.maxLength).enabled(this.isEnabled).caretColor(AppTheme.ACCENT)
            .id(this.fieldId).accessibilityText(this.label)
            .onChange((value: string) => { this.change(value) })
            .onFocus(() => { this.focused = true }).onBlur(() => { this.validateOnBlur() })
            .onSubmit(() => { this.validateOnBlur(); this.onInputSubmit() })
        }
        Text(this.label)
          .fontSize(this.focused || this.value ? 12 : 16)
          .fontColor(this.focused ? AppTheme.ACCENT : AppTheme.MUTED)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ left: 14, right: 14, top: this.focused || this.value ? 5 : 18 })
          .hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
      }.width('100%').backgroundColor(AppTheme.INPUT).borderRadius(AppTheme.CONTROL_RADIUS)
        .border({ width: this.focused ? 1.5 : 1,
          color: this.localError || this.errorMessage ? AppTheme.ERROR
            : this.focused ? AppTheme.ACCENT : AppTheme.BORDER })
      if (!(this.localError || this.errorMessage) && (this.helpText || this.placeholder || this.passwordRules)
        && !this.hasCompleteValue(this.value)) {
        Text(this.passwordRules ? PASSWORD_HINT : this.helpText || this.placeholder)
          .fontSize(12).fontColor(AppTheme.MUTED).width('100%').id(this.fieldId + (this.passwordRules ? '-rules' : '-help'))
      }
      if (this.passwordRules && this.value) {
        Row({ space: 4 }) {
          this.strengthCell(1)
          this.strengthCell(2)
          this.strengthCell(3)
          Text('密码强度：' + (this.strength < 2 ? '弱' : this.strength === 2 ? '中' : '强'))
            .fontSize(12).fontColor(AppTheme.MUTED).id(this.fieldId + '-strength-label')
        }
      }
      if (this.localError || this.errorMessage) {
        Text(this.localError || this.errorMessage).fontSize(13).fontColor(AppTheme.ERROR)
          .width('100%').id(this.fieldId + '-error').accessibilityText(this.label + '：' + (this.localError || this.errorMessage))
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}

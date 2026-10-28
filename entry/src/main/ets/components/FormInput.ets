import { AppInputStyle, AppTheme } from '../common/theme/AppTheme'

/** 固定标签与定位 ID 随输入内容保留，供业务表单和设备测试共同使用。 */
@Component
export struct FormInput {
  @Prop label: string = ''
  @Prop value: string = ''
  @Prop placeholder: string = ''
  @Prop fieldId: string = ''
  @Prop inputType: InputType = InputType.Normal
  @Prop maxLength: number = 100
  @Prop isEnabled: boolean = true
  onChange: (value: string) => void = () => {}

  build() {
    Column({ space: 6 }) {
      Text(this.label).fontSize(14).fontColor(AppTheme.TEXT).width('100%')
      TextInput({ text: this.value, placeholder: this.placeholder })
        .attributeModifier(new AppInputStyle()).type(this.inputType).maxLength(this.maxLength)
        .width('100%').enabled(this.isEnabled).id(this.fieldId).accessibilityText(this.label)
        .onChange((value: string) => { this.onChange(value) })
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}

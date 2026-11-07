import { AppTheme } from '../common/theme/AppTheme'
import { FormInput } from './FormInput'

@Component
export struct TagInput {
  @Prop value: string = ''
  @Prop maxLength: number = 32
  @Prop isEnabled: boolean = true
  @State draft: string = ''
  @State error: string = ''
  onChange: (value: string) => void = () => {}

  private add(): void {
    const tag: string = this.draft.trim().replace(/[,，]/g, ' ')
    const tags: string[] = this.value.split(',').filter((item: string) => item.length > 0)
    if (!tag || tags.includes(tag)) { this.draft = ''; return }
    const next: string = tags.concat([tag]).join(',')
    if (next.length > this.maxLength) { this.error = '标签总长度不能超过 ' + this.maxLength + ' 字'; return }
    this.value = next; this.onChange(next); this.draft = ''; this.error = ''
  }

  @Builder
  private tag(text: string) {
    Button(text + ' ×').fontSize(14).fontColor(AppTheme.ACCENT).backgroundColor(AppTheme.ACCENT_SOFT)
      .constraintSize({ minHeight: 44 }).enabled(this.isEnabled).accessibilityText('删除标签 ' + text)
      .onClick(() => {
        this.value = this.value.split(',').filter((item: string) => item !== text).join(',')
        this.onChange(this.value)
      })
  }

  build() {
    Column({ space: 6 }) {
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.value.split(',').filter((item: string) => item.length > 0), (text: string) => { this.tag(text) })
      }.width('100%')
      Row({ space: 8 }) {
        FormInput({ label: '商品标签', value: this.draft, isEnabled: this.isEnabled,
          maxLength: this.maxLength, helpText: '输入关键词后按回车或点添加', errorMessage: this.error,
          onChange: (value: string) => { this.draft = value; this.error = '' },
          onInputSubmit: () => { this.add() } }).layoutWeight(1)
        Button('添加').height(44).enabled(this.isEnabled).onClick(() => { this.add() })
      }.width('100%').alignItems(VerticalAlign.Top)
    }.width('100%')
  }
}

import { AppTheme } from '../common/theme/AppTheme'
import { FormInput } from './FormInput'
import { MatchText } from './MatchText'

/** 少量选项保留原生下拉；大量选项搜索后仍返回原始索引。 */
@Component
export struct FormSelect {
  @Prop label: string = ''
  @Prop options: SelectOption[] = []
  @Prop selected: number = -1
  @Prop isEnabled: boolean = true
  @Prop fieldId: string = ''
  @State query: string = ''
  @State open: boolean = false
  onSelect: (index: number, value: string) => void = () => {}

  @Builder
  private option(option: SelectOption, index: number) {
    if (!this.query || String(option.value).toLocaleLowerCase().includes(this.query.toLocaleLowerCase())) {
      Button({ type: ButtonType.Normal }) {
        MatchText({ text: String(option.value), query: this.query })
      }.width('100%').constraintSize({ minHeight: 44 }).backgroundColor(AppTheme.INPUT)
        .onClick(() => { this.onSelect(index, String(option.value)); this.open = false; this.query = '' })
    }
  }

  build() {
    Column({ space: 4 }) {
      Text(this.label).fontSize(12).fontColor(AppTheme.MUTED).width('100%')
      if (this.options.length <= 8) {
        Select(this.options).selected(this.selected)
          .value(this.selected >= 0 && this.selected < this.options.length ? this.options[this.selected].value : '请选择')
          .width('100%').height(52).fontColor(AppTheme.TEXT).backgroundColor(AppTheme.INPUT)
          .enabled(this.isEnabled).id(this.fieldId)
          .onSelect((index: number) => { this.onSelect(index, String(this.options[index].value)) })
      } else {
        Button(this.selected >= 0 && this.selected < this.options.length ? String(this.options[this.selected].value) : '请选择')
          .width('100%').constraintSize({ minHeight: 52 }).fontColor(AppTheme.TEXT).backgroundColor(AppTheme.INPUT)
          .enabled(this.isEnabled).id(this.fieldId).accessibilityText(this.label)
          .onClick(() => { this.open = !this.open; this.query = '' })
        if (this.open) {
          FormInput({ label: '搜索' + this.label, value: this.query, fieldId: this.fieldId + '-query',
            onChange: (value: string) => { this.query = value } })
          Scroll() {
            Column() {
              ForEach(this.options, (option: SelectOption, index: number) => { this.option(option, index) })
            }.width('100%')
          }.width('100%').constraintSize({ maxHeight: 220 })
          if (!this.options.some((option: SelectOption): boolean => String(option.value).toLocaleLowerCase().includes(this.query.toLocaleLowerCase()))) {
            Text('没有匹配项，请换个关键词').fontSize(13).fontColor(AppTheme.MUTED)
          }
        }
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}

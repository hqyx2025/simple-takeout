import { AppButtonStyle, AppTheme } from '../common/theme/AppTheme'

@Component
export struct DateTimeField {
  @Prop label: string = ''
  @Prop value: string = ''
  @Prop fieldId: string = ''
  @Prop isEnabled: boolean = true
  onChange: (value: string) => void = () => {}

  private chooseDate(): void {
    const parsed: Date = new Date(this.value.replace(' ', 'T'))
    const selected: Date = Number.isNaN(parsed.getTime()) ? new Date() : parsed
    this.getUIContext().showDatePickerDialog({
      selected: selected,
      onDateAccept: (date: Date): void => {
        this.getUIContext().showTimePickerDialog({
          selected: selected, useMilitaryTime: true,
          onAccept: (time: TimePickerResult): void => {
            const day: string = date.getFullYear().toString() + '-'
              + (date.getMonth() + 1).toString().padStart(2, '0') + '-'
              + date.getDate().toString().padStart(2, '0')
            this.onChange(day + ' ' + (time.hour ?? 0).toString().padStart(2, '0')
              + ':' + (time.minute ?? 0).toString().padStart(2, '0') + ':00')
          }
        })
      }
    })
  }

  build() {
    Column({ space: 6 }) {
      Text(this.label).fontSize(14).fontColor(AppTheme.TEXT).width('100%')
      Button(this.value === '' ? '选择日期和时间' : this.value, { type: ButtonType.Normal })
        .attributeModifier(new AppButtonStyle()).width('100%')
        .constraintSize({ minHeight: AppTheme.CONTROL_HEIGHT }).padding(14)
        .fontSize(16).fontColor(this.value === '' ? AppTheme.MUTED : AppTheme.TEXT)
        .backgroundColor(AppTheme.INPUT).border({ width: 1, color: AppTheme.BORDER })
        .borderRadius(AppTheme.CONTROL_RADIUS).id(this.fieldId).enabled(this.isEnabled)
        .accessibilityText(this.label + '，' + (this.value === '' ? '未选择' : this.value))
        .onClick(() => { this.chooseDate() })
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}

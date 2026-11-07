import { AppTheme } from '../common/theme/AppTheme'

@Component
export struct MatchText {
  @Prop text: string = ''
  @Prop query: string = ''

  build() {
    Text() {
      if (this.query && this.text.toLocaleLowerCase().includes(this.query.toLocaleLowerCase())) {
        Span(this.text.substring(0, this.text.toLocaleLowerCase().indexOf(this.query.toLocaleLowerCase())))
        Span(this.text.substring(this.text.toLocaleLowerCase().indexOf(this.query.toLocaleLowerCase()),
          this.text.toLocaleLowerCase().indexOf(this.query.toLocaleLowerCase()) + this.query.length))
          .fontColor(AppTheme.ACCENT).fontWeight(FontWeight.Bold)
        Span(this.text.substring(this.text.toLocaleLowerCase().indexOf(this.query.toLocaleLowerCase()) + this.query.length))
      } else {
        Span(this.text)
      }
    }.fontSize(16).fontColor(AppTheme.TEXT)
  }
}

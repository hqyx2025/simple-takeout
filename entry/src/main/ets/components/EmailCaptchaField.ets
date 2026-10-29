import { AppTheme, AppInputStyle, AppButtonStyle } from '../common/theme/AppTheme'
import { fetchCaptchaApi } from '../service/api/AuthApi'
import { CaptchaResult } from '../model/server/Contracts'

@Component
export struct EmailCaptchaField {
  @Link captchaId: string
  @Link captchaCode: string
  @Prop @Watch('reload') refreshVersion: number = 0
  @State image: string = ''
  @State loading: boolean = false
  @State error: string = ''
  private version: number = 0

  aboutToAppear(): void { this.reload() }
  aboutToDisappear(): void { this.version++; this.captchaId = ''; this.captchaCode = '' }

  private async reload(): Promise<void> {
    const version: number = ++this.version
    this.captchaId = ''; this.captchaCode = ''; this.loading = true; this.error = ''
    try {
      const result: CaptchaResult | null = await fetchCaptchaApi()
      if (version !== this.version) { return }
      if (result === null || !result.id || !result.image.startsWith('data:image/png;base64,')) {
        this.error = '校对码加载失败，请点击重试'
        this.image = ''
        return
      }
      this.captchaId = result.id; this.image = result.image
    } catch (_) {
      if (version === this.version) { this.error = '校对码加载失败，请点击重试'; this.image = '' }
    } finally {
      if (version === this.version) { this.loading = false }
    }
  }

  build() {
    Column({ space: 6 }) {
      Text('图片校对码').fontSize(13).fontWeight(FontWeight.Medium).fontColor(AppTheme.TEXT).width('100%')
      Row({ space: 8 }) {
        TextInput({ text: this.captchaCode, placeholder: '输入右图 5 位字符' })
          .attributeModifier(new AppInputStyle()).maxLength(5).layoutWeight(1).height(44)
          .id('email-captcha-input').onChange((value: string) => { this.captchaCode = value })
        Button().attributeModifier(new AppButtonStyle()).width(120).height(44)
          .enabled(!this.loading).id('email-captcha-refresh').accessibilityText('更换图片校对码')
          .onClick(() => { this.reload() })
          .overlay(this.captchaImage())
      }.width('100%')
      if (this.error) { Text(this.error).fontSize(13).fontColor(AppTheme.ERROR).width('100%') }
    }.width('100%')
  }

  @Builder
  private captchaImage() {
    if (this.loading || !this.image) {
      Text(this.loading ? '加载中…' : '点击重试').fontSize(13).fontColor(AppTheme.TEXT)
        .hitTestBehavior(HitTestMode.None)
    } else {
      Image(this.image).width(116).height(40).objectFit(ImageFit.Contain)
        .hitTestBehavior(HitTestMode.None).accessibilityText('图片校对码')
    }
  }
}

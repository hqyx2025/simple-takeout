import { formInfo, formProvider } from '@kit.FormKit'

@Entry({ useSharedStorage: true })
@Component
struct DeliveryLive {
  @LocalStorageProp('formId') formId: string = ''
  @LocalStorageProp('formRect') rect: formInfo.Rect = { left: 0, top: 0, width: 160, height: 160 }
  @LocalStorageProp('radius') radius: number = 20
  @State distance: number = -28

  aboutToAppear(): void {
    this.getUIContext().animateTo({ duration: 1000, iterations: 2, playMode: PlayMode.Alternate,
      curve: Curve.EaseInOut }, () => { this.distance = 28 })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column({ space: 10 }) {
        Text('简单外卖').fontSize(16).fontColor($r('app.color.text_primary'))
        Image($r('app.media.delivery_rider')).width(80).height(64).translate({ x: this.distance })
        Text('骑手动画 · 非实时位置').fontSize(12).fontColor($r('app.color.text_secondary'))
        Text('点击收起').fontSize(12).fontColor($r('app.color.text_secondary'))
      }.justifyContent(FlexAlign.Center).width(this.rect.width).height(this.rect.height)
        .position({ x: this.rect.left, y: this.rect.top })
        .backgroundColor($r('app.color.bg_primary')).borderRadius(this.radius)
        .onClick(() => { formProvider.cancelOverflow(this.formId).catch(() => {}) })
    }.width('100%').height('100%')
  }
}

const storage: LocalStorage = new LocalStorage()

@Entry(storage)
@Component
struct DeliveryCard {
  @LocalStorageProp('statusText') statusText: string = '打开应用同步订单'
  @LocalStorageProp('syncedText') syncedText: string = '暂无订单快照'

  build() {
    Column({ space: 6 }) {
      Text('简单外卖 · 订单配送').fontSize(14).fontColor($r('app.color.text_primary'))
      Image($r('app.media.delivery_rider')).width(64).height(48)
        .accessibilityText('点击播放骑手动画，非实时位置')
        .onClick(() => { postCardAction(this, { action: 'message', params: { message: 'rider' } }) })
      Text(this.statusText).fontSize(16).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
      Text(this.syncedText).fontSize(10).maxLines(2).fontColor($r('app.color.text_secondary'))
      Text('快照可能已过期，请打开应用刷新').fontSize(10).maxLines(2).fontColor($r('app.color.text_secondary'))
      Text('查看我的订单 ›').fontSize(14).fontColor($r('app.color.primary'))
        .onClick(() => { postCardAction(this, {
          action: 'router', abilityName: 'EntryAbility', params: { deliveryOrders: 'true' }
        }) })
    }.width('100%').height('100%').padding(12).justifyContent(FlexAlign.Center)
      .backgroundColor($r('app.color.bg_primary')).borderRadius(20)
  }
}

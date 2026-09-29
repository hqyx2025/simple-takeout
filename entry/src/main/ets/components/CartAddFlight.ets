import { AppTheme } from '../common/theme/AppTheme'
import { AppMotion } from '../common/theme/AppMotion'

export class CartAddAnimator {
  play: (sourceId: string) => Promise<boolean> = (): Promise<boolean> => Promise.resolve(false)
  cancel: () => void = () => {}
}

/** 原生路径插值；只绘制一个浮层，不逐帧刷新商品列表。 */
@Component
export struct CartAddFlight {
  animator: CartAddAnimator = new CartAddAnimator()
  @StorageLink('appReduceMotion') @Watch('onMotionChange') reducedMotion: boolean = false
  @State x: number = 0
  @State y: number = 0
  @State sizeScale: number = 1
  @State visible: boolean = false
  @State path: string = ''
  private request: number = 0
  private startTimer: number = -1
  private complete: (landed: boolean) => void = () => {}

  aboutToAppear(): void {
    this.animator.play = (sourceId: string): Promise<boolean> => this.fly(sourceId)
    this.animator.cancel = () => { this.finish(false) }
  }

  aboutToDisappear(): void {
    this.finish(false)
    this.animator.play = (): Promise<boolean> => Promise.resolve(false)
    this.animator.cancel = () => {}
  }

  private onMotionChange(): void {
    if (this.reducedMotion) {
      this.finish(true)
    }
  }

  private finish(landed: boolean): void {
    this.request += 1
    clearTimeout(this.startTimer)
    this.visible = false
    const callback: (landed: boolean) => void = this.complete
    this.complete = () => {}
    callback(landed)
  }

  private fly(sourceId: string): Promise<boolean> {
    if (AppMotion.isReduced()) {
      return Promise.resolve(true)
    }
    this.finish(false)
    const ui = this.getUIContext()
    try {
      const utils = ui.getComponentUtils()
      const root = utils.getRectangleById('store-detail-content')
      const source = utils.getRectangleById(sourceId)
      const target = utils.getRectangleById('store-cart-target')
      if (source.size.width <= 0 || target.size.width <= 0) {
        return Promise.resolve(true)
      }
      const startX: number = source.windowOffset.x + source.size.width / 2 - root.windowOffset.x - ui.vp2px(16)
      const startY: number = source.windowOffset.y + source.size.height / 2 - root.windowOffset.y - ui.vp2px(16)
      const endX: number = target.windowOffset.x + target.size.width / 2 - root.windowOffset.x - ui.vp2px(16)
      const endY: number = target.windowOffset.y + target.size.height / 2 - root.windowOffset.y - ui.vp2px(16)
      this.path = ''
      this.x = ui.px2vp(startX)
      this.y = ui.px2vp(startY)
      this.sizeScale = 1
      this.visible = true
      const version: number = this.request
      return new Promise<boolean>((resolve: (landed: boolean) => void) => {
        this.complete = resolve
        // 首帧提交起点后交给渲染引擎插值；完成回调才允许写入购物车。
        this.startTimer = setTimeout(() => {
          this.path = `Mstart.x start.y Q${startX - ui.vp2px(70)} ${Math.max(0, startY - ui.vp2px(96))} end.x end.y`
          ui.animateTo({ duration: AppMotion.CART_ADD, curve: Curve.EaseIn,
            onFinish: () => { if (version === this.request) { this.finish(true) } }
          }, () => {
            this.x = ui.px2vp(endX)
            this.y = ui.px2vp(endY)
            this.sizeScale = 0.35
          })
        }, 16)
      })
    } catch (_) {
      this.visible = false
      return Promise.resolve(true)
    }
  }

  build() {
    Text('+')
      .fontSize(24).fontWeight(FontWeight.Bold).fontColor(AppTheme.PRIMARY_TEXT)
      .textAlign(TextAlign.Center).width(32).height(32)
      .backgroundColor(AppTheme.PRIMARY).borderRadius(16)
      .position({ x: this.x, y: this.y })
      .motionPath({ path: this.path, from: 0, to: 1, rotatable: false })
      .scale({ x: this.sizeScale, y: this.sizeScale })
      .opacity(this.visible ? 1 : 0)
      .id('cart-add-flight')
      .hitTestBehavior(HitTestMode.None)
      .accessibilityLevel('no')
  }
}

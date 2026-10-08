import { AppTheme } from '../common/theme/AppTheme'
import { AppMotion } from '../common/theme/AppMotion'

const MAX_CART_FLIGHTS: number = 20

export class CartAddAnimator {
  play: (sourceId: string) => Promise<boolean> = (): Promise<boolean> => Promise.resolve(false)
  cancel: () => void = () => {}
}

class CartFlightData {
  id: number = 0
  startX: number = 0
  startY: number = 0
  endX: number = 0
  endY: number = 0
  path: string = ''
  complete: (landed: boolean) => void = () => {}
}

/** 每次点击独立播放，最多同时绘制 20 个浮层；业务请求不等待动画。 */
@Component
export struct CartAddFlight {
  animator: CartAddAnimator = new CartAddAnimator()
  @StorageLink('appReduceMotion') @Watch('onMotionChange') reducedMotion: boolean = false
  @State flights: CartFlightData[] = []
  private nextId: number = 0

  aboutToAppear(): void {
    this.animator.play = (sourceId: string): Promise<boolean> => this.fly(sourceId)
    this.animator.cancel = () => { this.clearFlights(false) }
  }

  aboutToDisappear(): void {
    this.clearFlights(false)
    this.animator.play = (): Promise<boolean> => Promise.resolve(false)
    this.animator.cancel = () => {}
  }

  private onMotionChange(): void {
    if (this.reducedMotion) {
      this.clearFlights(true)
    }
  }

  private clearFlights(landed: boolean): void {
    const previous: CartFlightData[] = this.flights
    this.flights = []
    for (const flight of previous) {
      flight.complete(landed)
    }
  }

  private finish(id: number): void {
    const flight: CartFlightData | undefined = this.flights.find((item: CartFlightData) => item.id === id)
    if (flight === undefined) {
      return
    }
    this.flights = this.flights.filter((item: CartFlightData) => item.id !== id)
    flight.complete(true)
  }

  private fly(sourceId: string): Promise<boolean> {
    if (AppMotion.isReduced()) {
      return Promise.resolve(true)
    }
    if (this.flights.length >= MAX_CART_FLIGHTS) {
      return Promise.resolve(false)
    }
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
      const flight: CartFlightData = new CartFlightData()
      flight.id = ++this.nextId
      flight.startX = ui.px2vp(startX)
      flight.startY = ui.px2vp(startY)
      flight.endX = ui.px2vp(endX)
      flight.endY = ui.px2vp(endY)
      flight.path = `Mstart.x start.y Q${startX - ui.vp2px(70)} ${Math.max(0, startY - ui.vp2px(96))} end.x end.y`
      return new Promise<boolean>((resolve: (landed: boolean) => void) => {
        flight.complete = resolve
        this.flights = this.flights.concat([flight])
      })
    } catch (_) {
      return Promise.resolve(true)
    }
  }

  @Builder
  FlightItem(flight: CartFlightData) {
    CartFlightParticle({ flight: flight, onFinish: () => { this.finish(flight.id) } })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      ForEach(this.flights, (flight: CartFlightData) => {
        this.FlightItem(flight)
      }, (flight: CartFlightData) => flight.id.toString())
    }
    .width('100%').height('100%')
    .id('cart-add-flight')
    .hitTestBehavior(HitTestMode.None)
    .accessibilityLevel('no')
  }
}

/** 动画状态放在各自组件中，重叠播放不会重启动画或刷新商品列表。 */
@Component
struct CartFlightParticle {
  flight: CartFlightData = new CartFlightData()
  onFinish: () => void = () => {}
  @State x: number = 0
  @State y: number = 0
  @State sizeScale: number = 1
  @State path: string = ''
  private startTimer: number = -1
  private active: boolean = false

  aboutToAppear(): void {
    this.active = true
    this.x = this.flight.startX
    this.y = this.flight.startY
    this.startTimer = setTimeout(() => {
      if (!this.active) {
        return
      }
      this.path = this.flight.path
      this.getUIContext().animateTo({ duration: AppMotion.CART_ADD, curve: Curve.EaseIn,
        onFinish: () => { if (this.active) { this.onFinish() } }
      }, () => {
        this.x = this.flight.endX
        this.y = this.flight.endY
        this.sizeScale = 0.35
      })
    }, 16)
  }

  aboutToDisappear(): void {
    this.active = false
    clearTimeout(this.startTimer)
  }

  build() {
    Text('+')
      .fontSize(24).fontWeight(FontWeight.Bold).fontColor(AppTheme.PRIMARY_TEXT)
      .textAlign(TextAlign.Center).width(32).height(32)
      .backgroundColor(AppTheme.PRIMARY).borderRadius(16)
      .position({ x: this.x, y: this.y })
      .motionPath({ path: this.path, from: 0, to: 1, rotatable: false })
      .scale({ x: this.sizeScale, y: this.sizeScale })
      .id(`cart-add-particle-${this.flight.id}`)
      .hitTestBehavior(HitTestMode.None)
      .accessibilityLevel('no')
  }
}

import { motion } from '@kit.MultimodalAwarenessKit'
import { COLORS } from '../common/Constants'
import { FloatingNavigationMaterial, FloatingTabBarTheme } from '../common/theme/FloatingTabBarTheme'

/** 跟随系统识别的页面交互手；不支持时可手动选择导航位置。 */
@Component
export struct AdaptiveTabBar {
  @Prop selected: number = 0
  @Prop @Watch('updateListening') active: boolean = true
  @StorageLink('appForeground') @Watch('updateListening') foreground: boolean = true
  @StorageLink('appReduceMotion') reduceMotion: boolean = false
  @StorageLink('navigationHandMode') @Watch('updateListening') mode: string = 'auto'
  @State side: number = 0
  @State widthVp: number = 360
  @State lightX: number = FloatingTabBarTheme.WIDTH / 2
  @State lightOpacity: number = 0
  private listening: boolean = false
  private pressed: boolean = false
  private pressedFinger: number = -1
  private pendingSide: number = 0
  private settleTimer: number = -1
  onSelect: (index: number) => void = () => {}

  private handleTouch(event: TouchEvent): void {
    if (!this.active || !this.foreground) { return }
    if (event.type === TouchType.Down && !this.pressed) {
      const point: TouchObject | undefined = event.changedTouches[0]
      if (point === undefined) { return }
      this.pressed = true
      this.pressedFinger = point.id
      this.moveLight(point.x)
      this.getUIContext().animateTo({ duration: this.reduceMotion ? 0 : 90, curve: Curve.EaseOut }, () => {
        this.lightOpacity = 1
      })
    } else if (event.type === TouchType.Move && this.pressed) {
      const point: TouchObject | undefined = event.touches.find((touch: TouchObject) => touch.id === this.pressedFinger)
      if (point !== undefined) { this.moveLight(point.x) }
    } else if (event.type === TouchType.Cancel || (event.type === TouchType.Up &&
      event.changedTouches.some((touch: TouchObject) => touch.id === this.pressedFinger))) {
      const released: TouchObject | undefined = event.type === TouchType.Up
        ? event.changedTouches.find((touch: TouchObject) => touch.id === this.pressedFinger)
        : undefined
      this.pressed = false
      this.pressedFinger = -1
      this.getUIContext().animateTo({ duration: this.reduceMotion ? 0 : 200, curve: Curve.EaseOut }, () => {
        this.lightOpacity = 0
      })
      if (released !== undefined) { this.selectAtRelease(released) }
      this.scheduleMove()
    }
  }

  private moveLight(x: number): void {
    this.lightX = Math.max(0, Math.min(x, Math.min(FloatingTabBarTheme.WIDTH, this.widthVp - 24)))
  }

  private selectAtRelease(point: TouchObject): void {
    const width: number = Math.min(FloatingTabBarTheme.WIDTH, this.widthVp - 24)
    if (point.x < 0 || point.x > width || point.y < 0 || point.y > FloatingTabBarTheme.HEIGHT) { return }
    const itemWidth: number = (width - 14) / 4
    const index: number = Math.max(0, Math.min(3, Math.floor((point.x - 3) / (itemWidth + 2))))
    this.onSelect(index)
  }

  private onHandChanged = (status: motion.OperatingHandStatus): void => {
    if (status !== motion.OperatingHandStatus.LEFT_HAND_OPERATED &&
      status !== motion.OperatingHandStatus.RIGHT_HAND_OPERATED) {
      return
    }
    this.pendingSide = status === motion.OperatingHandStatus.LEFT_HAND_OPERATED ? -1 : 1
    this.scheduleMove()
  }

  private scheduleMove(): void {
    clearTimeout(this.settleTimer)
    this.settleTimer = setTimeout(() => {
      this.settleTimer = -1
      if (this.listening && !this.pressed && this.active && this.foreground && this.mode === 'auto') {
        this.side = this.pendingSide
      }
    }, 450)
  }

  aboutToAppear(): void { this.updateListening() }

  updateListening(): void {
    this.stopListening()
    if (this.mode !== 'auto') {
      this.side = this.mode === 'left' ? -1 : this.mode === 'right' ? 1 : 0
      return
    }
    if (!this.active || !this.foreground || !(AppStorage.get<boolean>('privacyConsent') ?? false)) {
      return
    }
    this.pendingSide = this.side
    if (!canIUse('SystemCapability.MultimodalAwareness.Motion')) {
      this.side = 0
      return
    }
    try {
      motion.on('operatingHandChanged', this.onHandChanged)
      this.listening = true
    } catch (_) {
      this.side = 0
      return
    }
    // 最近状态读取失败不影响已经成功注册的实时监听。
    try { this.onHandChanged(motion.getRecentOperatingHandStatus()) } catch (_) {}
  }

  private stopListening(): void {
    this.pressed = false
    this.pressedFinger = -1
    this.lightOpacity = 0
    clearTimeout(this.settleTimer)
    this.settleTimer = -1
    if (this.listening) {
      try { motion.off('operatingHandChanged', this.onHandChanged) } catch (_) {}
      this.listening = false
    }
  }

  aboutToDisappear(): void { this.stopListening() }

  private icon(index: number): Resource {
    if (index === 0) { return this.selected === index ? $r('app.media.home_nav_home_active') : $r('app.media.home_nav_home') }
    if (index === 1) { return this.selected === index ? $r('app.media.home_nav_assistant_active') : $r('app.media.home_nav_assistant') }
    if (index === 2) { return this.selected === index ? $r('app.media.home_nav_cart_active') : $r('app.media.home_nav_cart') }
    return this.selected === index ? $r('app.media.home_nav_profile_active') : $r('app.media.home_nav_profile')
  }

  @Builder
  tab(title: string, index: number) {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 2 }) {
        Image(this.icon(index)).width(22).height(22).objectFit(ImageFit.Contain).draggable(false)
        Text(title).fontSize(11).maxLines(1)
          .fontColor(this.selected === index ? COLORS.PRIMARY : COLORS.TEXT_SECONDARY)
      }.width('100%').justifyContent(FlexAlign.Center)
    }
    .layoutWeight(1).height(48).padding(0).stateEffect(false).hoverEffect(HoverEffect.None)
    .backgroundColor(Color.Transparent)
    .borderRadius(24).id(`tab-${index}`).accessibilityText(title)
    .accessibilitySelected(this.selected === index)
    .onClick((event: ClickEvent) => {
      if (event.source !== SourceType.TouchScreen && this.active && this.foreground) { this.onSelect(index) }
    })
  }

  build() {
    Column() {
      Stack() {
      Row() {}
        .width('100%').height('100%')
        .backgroundEffect({ radius: FloatingTabBarTheme.GLASS_BLUR_RADIUS,
          saturation: FloatingTabBarTheme.GLASS_SATURATION, color: FloatingTabBarTheme.GLASS_COLOR })
        .borderRadius(30).hitTestBehavior(HitTestMode.None)
      Row() {}
        .width('100%').height('100%')
        .radialGradient({ center: [this.lightX, '50%'], radius: 100,
          colors: [[FloatingTabBarTheme.PRESS_LIGHT, 0.25], ['#00FFFFFF', 1]] })
        .opacity(this.lightOpacity).borderRadius(30).clip(true).hitTestBehavior(HitTestMode.None)
      Row({ space: 2 }) {
        this.tab('首页', 0)
        this.tab('AI助手', 1)
        this.tab('购物车', 2)
        this.tab('我的', 3)
      }
      .padding(4).width('100%').height('100%')
      .borderRadius(30)
      }
      .height(FloatingTabBarTheme.HEIGHT)
      .width(Math.min(FloatingTabBarTheme.WIDTH, this.widthVp - 24))
      .borderRadius(30).border({ width: 0.5, color: COLORS.DIVIDER })
      .shadow({ radius: 12, color: '#18000000', offsetY: 3 })
      .attributeModifier(new FloatingNavigationMaterial())
      .translate({ x: this.side * Math.max(0, (this.widthVp - FloatingTabBarTheme.WIDTH) / 2 - 12) })
      .animation({ duration: this.reduceMotion ? 0 : 280, curve: Curve.EaseOut })
      .scale({ x: this.reduceMotion ? 1 : 1 + this.lightOpacity * 0.025,
        y: this.reduceMotion ? 1 : 1 + this.lightOpacity * 0.04 })
      .id('adaptive-navigation')
      // 抢占底层页面的横向手势，松手后的目标仍由 onTouch 坐标决定。
      .priorityGesture(
        PanGesture({ direction: PanDirection.Horizontal, fingers: 1, distance: 12 })
          .onActionStart(() => {})
          .onActionEnd(() => {})
          .onActionCancel(() => {})
      )
      .onTouch((event: TouchEvent) => { this.handleTouch(event) })
    }.width('100%').height(FloatingTabBarTheme.CONTENT_INSET)
    .justifyContent(FlexAlign.End).padding({ bottom: FloatingTabBarTheme.BOTTOM_MARGIN })
    .hitTestBehavior(HitTestMode.Transparent)
    .onAreaChange((_: Area, area: Area) => { this.widthVp = Number(area.width) })
  }
}

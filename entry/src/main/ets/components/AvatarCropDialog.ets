import { image } from '@kit.ImageKit'
import { common } from '@kit.AbilityKit'
import { fileIo } from '@kit.CoreFileKit'
import { AppTheme, AppButtonStyle } from '../common/theme/AppTheme'
import { AvatarCrop, AvatarPlacement } from '../common/AvatarCrop'
import { loadAvatarImage, saveAvatarCrop } from '../service/AvatarImage'
import { PageHeader } from './PageHeader'

@CustomDialog
export struct AvatarCropDialog {
  controller?: CustomDialogController
  uri: string = ''
  onConfirm: (path: string) => Promise<boolean> = (_path: string): Promise<boolean> => Promise.resolve(false)
  @State pixelMap: image.PixelMap | undefined = undefined
  @State diameter: number = 240
  @State displayWidth: number = 240
  @State displayHeight: number = 240
  @State displayX: number = 0
  @State displayY: number = 0
  @State zoom: number = 1
  @State busy: boolean = false
  @State error: string = ''
  private crop: AvatarCrop = new AvatarCrop(1, 1)
  private alive: boolean = true
  private dragX: number = 0
  private dragY: number = 0
  private pinchZoom: number = 1

  async aboutToAppear(): Promise<void> {
    let loaded: image.PixelMap | undefined = undefined
    try {
      const pixelMap: image.PixelMap = await loadAvatarImage(this.uri)
      loaded = pixelMap
      if (!this.alive) { await pixelMap.release(); return }
      const info: image.ImageInfo = await pixelMap.getImageInfo()
      if (!this.alive) { await pixelMap.release(); return }
      this.pixelMap = pixelMap
      this.crop = new AvatarCrop(info.size.width, info.size.height)
      this.refreshPreview()
    } catch (_) {
      if (loaded !== undefined && this.pixelMap === undefined) { await loaded.release() }
      if (this.alive) { this.error = '无法读取图片，请返回重新选择' }
    }
  }

  aboutToDisappear(): void {
    this.alive = false
    if (!this.busy) { this.releaseImage() }
  }

  private releaseImage(): void {
    if (this.pixelMap !== undefined) { this.pixelMap.release().catch(() => {}) }
  }

  private refreshPreview(): void {
    const placement: AvatarPlacement = this.crop.placement(this.diameter)
    this.displayWidth = placement.width; this.displayHeight = placement.height
    this.displayX = placement.x; this.displayY = placement.y; this.zoom = this.crop.zoom
  }

  private resize(value: number): void {
    if (value <= 0 || value === this.diameter) { return }
    this.diameter = value
    this.refreshPreview()
  }

  private setZoom(value: number): void {
    if (this.busy) { return }
    this.crop.setZoom(value)
    this.refreshPreview()
  }

  private async confirm(): Promise<void> {
    if (this.busy || this.pixelMap === undefined) { return }
    this.busy = true
    this.error = ''
    let path: string = ''
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext
      path = await saveAvatarCrop(this.pixelMap, this.crop, context.cacheDir)
      if (this.alive && await this.onConfirm(path) && this.alive) { this.controller?.close() }
    } catch (_) { if (this.alive) { this.error = '头像处理失败，请重试' } }
    finally {
      if (path !== '') { try { await fileIo.unlink(path) } catch (_) {} }
      if (this.alive) { this.busy = false } else { this.releaseImage() }
    }
  }

  build() {
    Column() {
      PageHeader({ title: '调整头像', backText: '取消', backId: 'avatar-crop-cancel', topPadding: 0,
        onBack: () => { if (!this.busy) { this.controller?.close() } } })
      Scroll() {
        Column({ space: 20 }) {
          Stack({ alignContent: Alignment.Center }) {
            if (this.pixelMap !== undefined) {
              Image(this.pixelMap).width(this.displayWidth).height(this.displayHeight).objectFit(ImageFit.Fill)
                .translate({ x: this.displayX, y: this.displayY }).accessibilityLevel('no')
            } else if (this.error === '') { LoadingProgress().width(40).height(40) }
          }.width('100%').aspectRatio(1).constraintSize({ maxWidth: 320 })
            .backgroundColor(Color.White).borderRadius(this.diameter / 2).clip(true)
            .border({ width: 2, color: AppTheme.ACCENT }).id('avatar-crop-preview')
            .accessibilityText('圆形范围为头像实际显示区域')
            .onAreaChange((_: Area, area: Area) => { this.resize(Number(area.width)) })
            .gesture(GestureGroup(GestureMode.Parallel,
              PanGesture({ fingers: 1, direction: PanDirection.All })
                .onActionStart(() => { this.dragX = this.crop.offsetX; this.dragY = this.crop.offsetY })
                .onActionUpdate((event: GestureEvent) => {
                  if (!this.busy) { this.crop.move(this.dragX + event.offsetX / this.diameter,
                    this.dragY + event.offsetY / this.diameter); this.refreshPreview() }
                }),
              PinchGesture({ fingers: 2 })
                .onActionStart(() => { this.pinchZoom = this.crop.zoom })
                .onActionUpdate((event: GestureEvent) => { this.setZoom(this.pinchZoom * event.scale) })
            ))
          Text('拖动调整位置，双指或滑杆缩放').fontSize(14).fontColor(AppTheme.MUTED)
          Row() {
            Text('缩放').fontSize(14).fontColor(AppTheme.TEXT)
            Slider({ value: this.zoom, min: 0.5, max: 4, step: 0.01 }).layoutWeight(1)
              .selectedColor(AppTheme.ACCENT).enabled(this.pixelMap !== undefined && !this.busy)
              .id('avatar-crop-zoom').onChange((value: number) => { this.setZoom(value) })
            Text(Math.round(this.zoom * 100) + '%').fontSize(14).fontColor(AppTheme.MUTED).width(48).id('avatar-crop-scale')
          }.width('100%')
          Button('重置').attributeModifier(new AppButtonStyle()).height(44)
            .fontColor(AppTheme.TEXT).backgroundColor(AppTheme.INPUT)
            .enabled(this.pixelMap !== undefined && !this.busy).id('avatar-crop-reset')
            .onClick(() => { this.crop.reset(); this.refreshPreview() })
          if (this.error !== '') { Text(this.error).fontSize(14).fontColor(AppTheme.ERROR).id('avatar-crop-error') }
        }.width('100%').padding(20)
      }.width('100%').layoutWeight(1).scrollBar(BarState.Auto)
      Button(this.busy ? '保存头像中…' : '确定并使用').attributeModifier(new AppButtonStyle())
        .width('100%').height(48).backgroundColor(AppTheme.ACCENT).fontColor(AppTheme.PRIMARY_TEXT)
        .enabled(this.pixelMap !== undefined && !this.busy).id('avatar-crop-confirm')
        .onClick(() => { this.confirm() }).margin({ top: 8, bottom: 16 })
    }.width('90%').height('85%').constraintSize({ maxWidth: 460, maxHeight: 700 })
      .padding({ left: 16, right: 16, top: 16 }).backgroundColor(AppTheme.CARD).borderRadius(24)
      .id('avatar-crop-dialog')
  }
}

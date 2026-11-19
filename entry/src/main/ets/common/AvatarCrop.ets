export interface AvatarPlacement {
  width: number
  height: number
  x: number
  y: number
}

/** 预览与导出共用同一组坐标；缩小后留白，允许完整的方形 Logo 放入圆内。 */
export class AvatarCrop {
  zoom: number = 1
  offsetX: number = 0
  offsetY: number = 0
  private width: number
  private height: number

  constructor(width: number, height: number) {
    this.width = Math.max(1, width)
    this.height = Math.max(1, height)
  }

  reset(): void { this.zoom = 1; this.offsetX = 0; this.offsetY = 0 }

  setZoom(value: number): void {
    if (!Number.isFinite(value)) { return }
    this.zoom = Math.max(0.5, Math.min(4, value))
    this.move(this.offsetX, this.offsetY)
  }

  move(x: number, y: number): void {
    const scale: number = this.zoom / Math.min(this.width, this.height)
    const maxX: number = Math.abs(this.width * scale - 1) / 2
    const maxY: number = Math.abs(this.height * scale - 1) / 2
    this.offsetX = Math.max(-maxX, Math.min(maxX, Number.isFinite(x) ? x : 0))
    this.offsetY = Math.max(-maxY, Math.min(maxY, Number.isFinite(y) ? y : 0))
  }

  placement(size: number): AvatarPlacement {
    const scale: number = size * this.zoom / Math.min(this.width, this.height)
    return { width: this.width * scale, height: this.height * scale,
      x: this.offsetX * size, y: this.offsetY * size }
  }
}

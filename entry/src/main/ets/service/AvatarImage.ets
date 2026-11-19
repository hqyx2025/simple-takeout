import { image } from '@kit.ImageKit'
import { fileIo } from '@kit.CoreFileKit'
import { LengthMetricsUnit } from '@kit.ArkUI'
import { AvatarCrop, AvatarPlacement } from '../common/AvatarCrop'

/** 限制解码大小，并在预览前统一处理相机照片方向。 */
export async function loadAvatarImage(uri: string): Promise<image.PixelMap> {
  const file: fileIo.File = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY)
  let source: image.ImageSource | undefined = undefined
  let pixelMap: image.PixelMap | undefined = undefined
  try {
    source = image.createImageSource(file.fd)
    const info: image.ImageInfo = await source.getImageInfo()
    const scale: number = Math.min(1, 2048 / Math.max(info.size.width, info.size.height))
    const options: image.DecodingOptions = { editable: true,
      desiredSize: { width: Math.max(1, Math.round(info.size.width * scale)), height: Math.max(1, Math.round(info.size.height * scale)) } }
    pixelMap = await source.createPixelMap(options)
    let orientation: number = 1
    try { orientation = Number(await source.getImageProperty(image.PropertyKey.ORIENTATION, { defaultValue: '1' })) } catch (_) {}
    if (orientation === 3) { await pixelMap.rotate(180) }
    if (orientation === 6 || orientation === 5 || orientation === 7) { await pixelMap.rotate(90) }
    if (orientation === 8) { await pixelMap.rotate(270) }
    if (orientation === 2 || orientation === 5) { await pixelMap.flip(true, false) }
    if (orientation === 4 || orientation === 7) { await pixelMap.flip(false, true) }
    return pixelMap
  } catch (error) {
    if (pixelMap !== undefined) { await pixelMap.release() }
    throw new Error('头像图片解码失败')
  } finally {
    if (source !== undefined) { await source.release() }
    await fileIo.close(file)
  }
}

/** 输出与圆形预览完全相同的方形图片，圆角仅由头像控件呈现。 */
export async function saveAvatarCrop(pixelMap: image.PixelMap, crop: AvatarCrop, cacheDir: string): Promise<string> {
  const size: number = 512
  const context: OffscreenCanvasRenderingContext2D = new OffscreenCanvasRenderingContext2D(
    size, size, new RenderingContextSettings(true), LengthMetricsUnit.PX)
  const placement: AvatarPlacement = crop.placement(size)
  context.fillStyle = '#FFFFFF'
  context.fillRect(0, 0, size, size)
  context.drawImage(pixelMap, (size - placement.width) / 2 + placement.x,
    (size - placement.height) / 2 + placement.y, placement.width, placement.height)
  const result: image.PixelMap = context.getPixelMap(0, 0, size, size)
  const packer: image.ImagePacker = image.createImagePacker()
  const path: string = cacheDir + '/avatar-crop-' + Date.now() + '.jpg'
  let file: fileIo.File | undefined = undefined
  try {
    file = await fileIo.open(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
    await packer.packToFile(result, file.fd, { format: 'image/jpeg', quality: 92 })
    return path
  } catch (error) {
    try { await fileIo.unlink(path) } catch (_) {}
    throw new Error('头像图片导出失败')
  } finally {
    if (file !== undefined) { await fileIo.close(file) }
    await packer.release()
    await result.release()
  }
}

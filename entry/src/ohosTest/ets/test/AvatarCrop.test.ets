import { describe, it, expect } from '@ohos/hypium'
import { abilityDelegatorRegistry, Driver, ON, Component } from '@kit.TestKit'
import { window, UIContext, ComponentContent } from '@kit.ArkUI'
import { UIAbility, ConfigurationConstant } from '@kit.AbilityKit'
import { image } from '@kit.ImageKit'
import { fileIo } from '@kit.CoreFileKit'
import { AvatarCrop } from '../../../main/ets/common/AvatarCrop'
import { loadAvatarImage, saveAvatarCrop } from '../../../main/ets/service/AvatarImage'
import { AvatarCropDialog } from '../../../main/ets/components/AvatarCropDialog'
import { launchAppUnderTest, requireComponent } from './UiTestHelper'

class AvatarDialogFixture {
  uri: string
  narrow: boolean
  constructor(uri: string, narrow: boolean = false) { this.uri = uri; this.narrow = narrow }
}

@Builder
function cropTestView(params: AvatarDialogFixture) {
  if (params.narrow) {
    Column() { AvatarCropDialog({ uri: params.uri }) }.width(320).height(600)
  } else { AvatarCropDialog({ uri: params.uri }) }
}

async function fixture(): Promise<image.PixelMap> {
  const colors: Uint8Array = new Uint8Array(100 * 100 * 4)
  for (let y: number = 0; y < 100; y++) {
    for (let x: number = 0; x < 100; x++) {
      const index: number = (y * 100 + x) * 4
      colors[index] = x < 50 ? 240 : 10
      colors[index + 1] = x < 50 ? 10 : 210
      colors[index + 2] = 10
      colors[index + 3] = 255
    }
  }
  return image.createPixelMap(colors.buffer, { size: { width: 100, height: 100 },
    srcPixelFormat: image.PixelMapFormat.RGBA_8888, pixelFormat: image.PixelMapFormat.RGBA_8888, editable: true })
}

async function pixels(pixelMap: image.PixelMap): Promise<Uint8Array> {
  const info: image.ImageInfo = await pixelMap.getImageInfo()
  const buffer: ArrayBuffer = new ArrayBuffer(info.size.width * info.size.height * 4)
  await pixelMap.readPixelsToBuffer(buffer)
  return new Uint8Array(buffer)
}

export default function avatarCropTest() {
  describe('AvatarCrop', () => {
    it('AvatarCrop_circle_preview_pinch_and_reset_are_visible_on_device', 0, async () => {
      const driver: Driver = Driver.create()
      await launchAppUnderTest(driver)
      const ability: UIAbility = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility()
      const context: UIContext = (await window.getLastWindow(ability.context)).getUIContext()
      const source: image.PixelMap = await fixture()
      const path: string = await saveAvatarCrop(source, new AvatarCrop(100, 100), ability.context.cacheDir)
      await source.release()
      const content: ComponentContent<AvatarDialogFixture> = new ComponentContent(context, wrapBuilder(cropTestView), new AvatarDialogFixture(path))
      try {
        await context.getPromptAction().openCustomDialog(content, { autoCancel: false, alignment: DialogAlignment.Center })
        const scale: Component = requireComponent(await driver.waitForComponent(ON.id('avatar-crop-scale'), 8000), 'crop scale')
        expect(await scale.getText()).assertEqual('100%')
        const preview: Component = requireComponent(await driver.findComponent(ON.id('avatar-crop-preview')), 'circle preview')
        await preview.pinchIn(0.7)
        const zoomed: Component = requireComponent(await driver.findComponent(ON.id('avatar-crop-scale')), 'changed scale')
        expect(Number((await zoomed.getText()).replace('%', '')) < 100).assertTrue()
        const confirm: Component = requireComponent(await driver.findComponent(ON.id('avatar-crop-confirm')), 'confirm button')
        const size = await driver.getDisplaySize()
        const bounds = await confirm.getBounds()
        expect(bounds.top >= 0 && bounds.bottom <= size.y).assertTrue()
        expect(await driver.screenCap(ability.context.filesDir + '/avatar-crop-preview.png')).assertTrue()
        await (requireComponent(await driver.findComponent(ON.id('avatar-crop-reset')), 'reset')).click()
        const reset: Component = requireComponent(await driver.waitForComponent(ON.id('avatar-crop-scale').text('100%'), 3000), 'reset scale')
        expect(await reset.getText()).assertEqual('100%')
        console.info('[AvatarCrop] circular preview, pinch, reset and visible confirm button verified; screenshot=' + ability.context.filesDir + '/avatar-crop-preview.png')
      } finally {
        await context.getPromptAction().closeCustomDialog(content)
        content.dispose()
        await fileIo.unlink(path)
      }
    })
    it('AvatarCrop_dark_narrow_layout_keeps_controls_and_preview_visible', 0, async () => {
      const driver: Driver = Driver.create()
      await launchAppUnderTest(driver)
      const ability: UIAbility = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility()
      const context: UIContext = (await window.getLastWindow(ability.context)).getUIContext()
      const source: image.PixelMap = await fixture()
      const path: string = await saveAvatarCrop(source, new AvatarCrop(100, 100), ability.context.cacheDir)
      await source.release()
      const content: ComponentContent<AvatarDialogFixture> = new ComponentContent(context, wrapBuilder(cropTestView), new AvatarDialogFixture(path, true))
      const mode: string = AppStorage.get<string>('appearanceColorMode') ?? 'system'
      try {
        ability.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK)
        await context.getPromptAction().openCustomDialog(content, { autoCancel: false, alignment: DialogAlignment.Center })
        const confirm: Component = requireComponent(await driver.waitForComponent(ON.id('avatar-crop-confirm'), 8000), 'narrow confirm')
        const preview: Component = requireComponent(await driver.findComponent(ON.id('avatar-crop-preview')), 'narrow preview')
        const previewBounds = await preview.getBounds()
        const confirmBounds = await confirm.getBounds()
        const size = await driver.getDisplaySize()
        expect(Math.abs(previewBounds.right - previewBounds.left - (previewBounds.bottom - previewBounds.top)) < 3).assertTrue()
        expect(confirmBounds.bottom <= size.y && confirmBounds.top > previewBounds.top).assertTrue()
        expect(await driver.screenCap(ability.context.filesDir + '/avatar-crop-dark-narrow.png')).assertTrue()
        console.info('[AvatarCrop] dark 320x600vp layout verified; screenshot=' + ability.context.filesDir + '/avatar-crop-dark-narrow.png')
      } finally {
        await context.getPromptAction().closeCustomDialog(content)
        content.dispose()
        ability.context.getApplicationContext().setColorMode(mode === 'dark' ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
          : mode === 'light' ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT : ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET)
        await fileIo.unlink(path)
      }
    })
    it('AvatarCrop_native_export_keeps_padding_and_position_at_512_pixels', 0, async () => {
      const source: image.PixelMap = await fixture()
      const crop: AvatarCrop = new AvatarCrop(100, 100)
      crop.setZoom(0.5)
      const cacheDir: string = abilityDelegatorRegistry.getAbilityDelegator().getAppContext().cacheDir
      let path: string = ''
      let decoded: image.PixelMap | undefined = undefined
      try {
        path = await saveAvatarCrop(source, crop, cacheDir)
        decoded = await loadAvatarImage(path)
        const info: image.ImageInfo = await decoded.getImageInfo()
        expect(info.size.width).assertEqual(512)
        expect(info.size.height).assertEqual(512)
        const bytes: Uint8Array = await pixels(decoded)
        const outside: number = (40 * 512 + 256) * 4
        console.info('[AvatarCrop] export format=' + info.pixelFormat + ' outside=' + Array.from(bytes.slice(outside, outside + 4)).join(','))
        expect(bytes[outside] > 245 && bytes[outside + 1] > 245 && bytes[outside + 2] > 245).assertTrue()
        const left: number = (256 * 512 + 180) * 4
        const right: number = (256 * 512 + 330) * 4
        console.info('[AvatarCrop] left=' + Array.from(bytes.slice(left, left + 4)).join(',') + ' right=' + Array.from(bytes.slice(right, right + 4)).join(','))
        expect(bytes[left] > 200 && bytes[left + 1] < 40).assertTrue()
        expect(bytes[right] < 40 && bytes[right + 1] > 170).assertTrue()
        expect(fileIo.statSync(path).size < 5 * 1024 * 1024).assertTrue()
        console.info('[AvatarCrop] exported 512x512 JPEG; white padding and red/green positions verified')
      } finally {
        await source.release()
        if (decoded !== undefined) { await decoded.release() }
        if (path !== '') { await fileIo.unlink(path) }
      }
    })
    it('AvatarCrop_native_drag_exports_the_selected_region_without_modifying_the_source', 0, async () => {
      const source: image.PixelMap = await fixture()
      const crop: AvatarCrop = new AvatarCrop(100, 100)
      crop.setZoom(2)
      crop.move(0.5, 0)
      const cacheDir: string = abilityDelegatorRegistry.getAbilityDelegator().getAppContext().cacheDir
      let path: string = ''
      let decoded: image.PixelMap | undefined = undefined
      try {
        path = await saveAvatarCrop(source, crop, cacheDir)
        decoded = await loadAvatarImage(path)
        const bytes: Uint8Array = await pixels(decoded)
        const center: number = (256 * 512 + 256) * 4
        console.info('[AvatarCrop] dragged center=' + Array.from(bytes.slice(center, center + 4)).join(','))
        expect(bytes[center] > 200 && bytes[center + 1] < 40).assertTrue()
        expect((await source.getImageInfo()).size.width).assertEqual(100)
        console.info('[AvatarCrop] zoom and drag exported the red half; original PixelMap stayed 100x100')
      } finally {
        await source.release()
        if (decoded !== undefined) { await decoded.release() }
        if (path !== '') { await fileIo.unlink(path) }
      }
    })
  })
}

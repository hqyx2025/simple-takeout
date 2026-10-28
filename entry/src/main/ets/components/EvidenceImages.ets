import { photoAccessHelper } from '@kit.MediaLibraryKit'
import { AppButtonStyle } from '../common/theme/AppTheme'
import { COLORS, SPACING, FONT_SIZE } from '../common/Constants'
import { User, UploadResult } from '../model/Models'
import { uploadImageApi } from '../service/ApiService'
import { getAuthSessionEpoch, getApiBaseUrl } from '../service/HttpClient'

@Component
export struct EvidenceImages {
  @Link images: string[]
  @Link uploading: boolean
  disabled: boolean = false
  contextVersion: () => number = (): number => 0
  @State errorText: string = ''
  private alive: boolean = true
  private version: number = 0

  aboutToAppear(): void { this.alive = true }
  aboutToDisappear(): void { this.alive = false; this.version += 1 }

  private current(epoch: number, owner: number, version: number, contextVersion: number): boolean {
    return this.alive && epoch === getAuthSessionEpoch() && version === this.version && contextVersion === this.contextVersion()
      && AppStorage.get<boolean>('isLoggedIn') === true && AppStorage.get<User>('user')?.id === owner
  }

  private async choose(): Promise<void> {
    if (this.uploading || this.disabled || this.images.length >= 3) { return }
    const epoch: number = getAuthSessionEpoch()
    const owner: number = AppStorage.get<User>('user')?.id ?? 0
    if (owner <= 0 || AppStorage.get<boolean>('isLoggedIn') !== true) { return }
    const version: number = ++this.version
    const contextVersion: number = this.contextVersion()
    this.uploading = true
    this.errorText = ''
    try {
      const options: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions()
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE
      options.maxSelectNumber = 3 - this.images.length
      const picker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker()
      const selected: photoAccessHelper.PhotoSelectResult = await picker.select(options)
      if (!this.current(epoch, owner, version, contextVersion)) { return }
      for (const uri of selected.photoUris.slice(0, options.maxSelectNumber)) {
        const result: UploadResult | null = await uploadImageApi(uri, false)
        if (!this.current(epoch, owner, version, contextVersion)) { return }
        if (result === null) { this.errorText = '图片上传失败，请重新选择重试'; continue }
        const base: string = getApiBaseUrl()
        const relative: string = result.url.startsWith(base + '/') ? result.url.substring(base.length) : result.url
        if (!relative.startsWith('/') || relative.startsWith('//')) { this.errorText = '图片地址无效，请重试'; continue }
        this.images = this.images.concat([relative])
      }
    } catch (_) {
      if (this.current(epoch, owner, version, contextVersion)) { this.errorText = '选择图片失败，请重试' }
    } finally {
      if (this.current(epoch, owner, version, contextVersion)) { this.uploading = false }
    }
  }

  build() {
    Column({ space: SPACING.SM }) {
      Text('图片证据（选填，最多3张）').fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_PRIMARY)
      ForEach(this.images, (url: string) => {
        Row({ space: SPACING.SM }) {
          Image(getApiBaseUrl() + url).width(64).height(64).objectFit(ImageFit.Cover)
          Button('删除').attributeModifier(new AppButtonStyle()).enabled(!this.disabled && !this.uploading)
            .onClick(() => { this.images = this.images.filter((item: string) => item !== url) })
        }
      }, (url: string) => url)
      Button(this.uploading ? '上传中…' : '添加图片').attributeModifier(new AppButtonStyle())
        .enabled(!this.disabled && !this.uploading && this.images.length < 3).onClick(() => { this.choose() })
      if (this.errorText !== '') { Text(this.errorText).fontSize(FONT_SIZE.SM).fontColor(COLORS.ERROR) }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}

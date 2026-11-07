import { photoAccessHelper } from '@kit.MediaLibraryKit'
import { unifiedDataChannel, uniformTypeDescriptor } from '@kit.ArkData'
import { AppTheme, AppButtonStyle } from '../common/theme/AppTheme'
import { uploadImageApi } from '../service/ApiService'
import { getApiBaseUrl, getAuthSessionEpoch, getLastApiErrorMessage } from '../service/HttpClient'
import { UploadResult } from '../model/Models'

class PendingImage {
  id: number
  uri: string
  percent: number = 0
  error: string = ''
  constructor(id: number, uri: string) { this.id = id; this.uri = uri }
}

@Component
export struct ImageUpload {
  @Prop images: string[] = []
  @Prop maxFiles: number = 3
  @Prop disabled: boolean = false
  @Prop fieldId: string = 'image-upload'
  @Prop imageIdPrefix: string = ''
  @Prop helpId: string = ''
  @State pending: PendingImage[] = []
  @State error: string = ''
  private alive: boolean = true
  private sequence: number = 0
  contextVersion: () => number = (): number => 0
  onChange: (images: string[]) => void = () => {}
  onBusy: (busy: boolean) => void = () => {}

  aboutToDisappear(): void { this.alive = false }

  private publish(): void { this.onChange(this.images) }
  private busy(): void { this.onBusy(this.pending.some((item: PendingImage) => !item.error)) }

  private current(epoch: number, context: number, id: number): boolean {
    return this.alive && epoch === getAuthSessionEpoch() && context === this.contextVersion()
      && this.pending.some((row: PendingImage) => row.id === id)
  }

  private async choose(): Promise<void> {
    if (this.disabled) { return }
    const epoch: number = getAuthSessionEpoch()
    const context: number = this.contextVersion()
    try {
      const picker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker()
      const options: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions()
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE
      options.maxSelectNumber = Math.max(1, this.maxFiles - this.images.length - this.pending.length)
      const result: photoAccessHelper.PhotoSelectResult = await picker.select(options)
      if (this.alive && epoch === getAuthSessionEpoch() && context === this.contextVersion() && !this.disabled) { this.add(result.photoUris) }
    } catch (_) { this.error = '选图失败，请重试' }
  }

  private drop(event: DragEvent): void {
    if (this.disabled) { return }
    try {
      const uris: string[] = []
      for (const record of event.getData().getRecords()) {
        if (record.getType() === uniformTypeDescriptor.UniformDataType.IMAGE) {
          uris.push((record as unifiedDataChannel.Image).imageUri)
        }
      }
      if (!uris.length) { this.error = '请拖入 JPG、PNG、WebP 或 GIF 图片'; return }
      this.add(uris)
    } catch (_) { this.error = '无法读取拖入的图片，请点击选择' }
  }

  private add(uris: string[]): void {
    const free: number = this.maxFiles - this.images.length - this.pending.length
    if (uris.length > free) { this.error = '最多上传 ' + this.maxFiles + ' 张，请删除后再添加' }
    else { this.error = '' }
    for (const uri of uris.slice(0, Math.max(0, free))) {
      const item: PendingImage = new PendingImage(++this.sequence, uri)
      this.pending = this.pending.concat([item]); this.busy(); this.upload(item)
    }
  }

  private async upload(item: PendingImage): Promise<void> {
    const epoch: number = getAuthSessionEpoch()
    const context: number = this.contextVersion()
    const active = (): boolean => this.current(epoch, context, item.id)
    const result: UploadResult | null = await uploadImageApi(item.uri, false, (percent: number) => {
      if (active()) { item.percent = percent; this.pending = this.pending.slice() }
    })
    if (!active()) {
      if (this.alive) { this.pending = this.pending.filter((row: PendingImage) => row.id !== item.id); this.busy() }
      return
    }
    if (result === null) { item.error = getLastApiErrorMessage() || '上传失败，请删除后重试'; this.pending = this.pending.slice() }
    else {
      const base: string = getApiBaseUrl()
      const url: string = result.url.startsWith(base + '/') ? result.url.substring(base.length) : result.url
      if (!url.startsWith('/uploads/') || url.includes('..')) { item.error = '图片地址无效，请重试'; this.pending = this.pending.slice() }
      else { this.images = this.images.concat([url]); this.pending = this.pending.filter((row: PendingImage) => row.id !== item.id); this.publish() }
    }
    this.busy()
  }

  @Builder
  private uploaded(url: string, index: number) {
    Row({ space: 8 }) {
      Image(url.startsWith('/') ? getApiBaseUrl() + url : url).width(52).height(52).objectFit(ImageFit.Cover)
      Column({ space: 4 }) {
        Text('图片 ' + (index + 1) + ' · 已上传').fontSize(13).fontColor(AppTheme.TEXT)
        Progress({ value: 100, total: 100, type: ProgressType.Linear }).width('100%').color(AppTheme.ACCENT)
      }.layoutWeight(1)
      Button('删除').attributeModifier(new AppButtonStyle()).height(44).enabled(!this.disabled)
        .id((this.imageIdPrefix || this.fieldId) + '-remove-' + index).onClick(() => { this.images = this.images.filter((url: string, i: number) => i !== index); this.publish() })
    }.width('100%').id((this.imageIdPrefix || this.fieldId) + '-' + index)
  }

  @Builder
  private uploading(item: PendingImage) {
    Row({ space: 8 }) {
      Image(item.uri).width(52).height(52).objectFit(ImageFit.Cover)
      Column({ space: 4 }) {
        Text(item.error || (item.percent >= 99 ? '正在确认上传…' : '上传中 ' + item.percent + '%'))
          .fontSize(13).fontColor(item.error ? AppTheme.ERROR : AppTheme.TEXT)
        Progress({ value: item.percent, total: 100, type: ProgressType.Linear }).width('100%').color(AppTheme.ACCENT)
      }.layoutWeight(1)
      Button('删除').attributeModifier(new AppButtonStyle()).height(44).enabled(!this.disabled)
        .onClick(() => { this.pending = this.pending.filter((row: PendingImage) => row.id !== item.id); this.busy() })
    }.width('100%')
  }

  build() {
    Column({ space: 8 }) {
      Button({ type: ButtonType.Normal }) {
        Column({ space: 6 }) {
          Text('点击或拖拽上传图片').fontSize(16).fontColor(AppTheme.TEXT)
          Text('JPG、PNG、WebP、GIF · 每张不超过 5MB · 最多 ' + this.maxFiles + ' 张')
            .fontSize(12).fontColor(AppTheme.MUTED).id(this.helpId || this.fieldId + '-help')
        }.width('100%').padding(16)
      }.width('100%').backgroundColor(AppTheme.INPUT).border({ width: 1, color: AppTheme.BORDER, style: BorderStyle.Dashed })
        .borderRadius(AppTheme.CONTROL_RADIUS).enabled(!this.disabled && this.images.length + this.pending.length < this.maxFiles)
        .id(this.fieldId).onClick(() => { this.choose() }).onDrop((event: DragEvent) => { this.drop(event) })
      ForEach(this.images, (url: string, index: number) => { this.uploaded(url, index) })
      ForEach(this.pending, (item: PendingImage) => { this.uploading(item) }, (item: PendingImage) => item.id.toString())
      if (this.error) { Text(this.error).fontSize(13).fontColor(AppTheme.ERROR).width('100%') }
    }.width('100%')
  }
}

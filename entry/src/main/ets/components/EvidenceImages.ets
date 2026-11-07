import { ImageUpload } from './ImageUpload'
@Component
export struct EvidenceImages {
  @Link images: string[]
  @Link uploading: boolean
  @Prop disabled: boolean = false
  contextVersion: () => number = (): number => 0
  build() {
    ImageUpload({ images: this.images, maxFiles: 3, disabled: this.disabled, contextVersion: this.contextVersion,
      onChange: (images: string[]) => { this.images = images },
      onBusy: (busy: boolean) => { this.uploading = busy } })
  }
}

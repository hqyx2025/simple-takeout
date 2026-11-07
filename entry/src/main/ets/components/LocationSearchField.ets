import { FormInput } from './FormInput'
import { MatchText } from './MatchText'
import { RegionPicker } from './RegionPicker'
import { AppTheme } from '../common/theme/AppTheme'
import { searchAddress, AddressSearchResult } from '../service/LocationService'
import { getAuthSessionEpoch } from '../service/HttpClient'

@Component
export struct LocationSearchField {
  @Prop value: string = ''
  @Prop fieldId: string = 'location-search'
  @State region: string = ''
  @State showRegions: boolean = false
  @State matches: AddressSearchResult[] = []
  @State message: string = ''
  private timer: number = -1
  private version: number = 0
  onChange: (value: string) => void = () => {}
  onSelect: (place: AddressSearchResult) => void = () => {}

  aboutToDisappear(): void { clearTimeout(this.timer); this.version++ }

  private change(value: string): void {
    this.value = value; this.onChange(value); this.matches = []; this.message = ''
    clearTimeout(this.timer)
    const version: number = ++this.version
    if (!value.trim()) { return }
    this.timer = setTimeout(() => { this.search(version) }, 300)
  }

  private async search(version: number): Promise<void> {
    const epoch: number = getAuthSessionEpoch()
    this.message = '正在搜索地点…'
    const results: AddressSearchResult[] = await searchAddress((this.region + this.value.trim()).substring(0, 80), false)
    if (version !== this.version || epoch !== getAuthSessionEpoch()) { return }
    this.matches = results
    this.message = results.length ? '' : '未找到可用地点，请更换关键词或使用地图定位'
  }

  @Builder
  private result(place: AddressSearchResult) {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 4 }) {
        MatchText({ text: place.name, query: this.value })
        Text(place.district + ' ' + place.address).fontSize(12).fontColor(AppTheme.MUTED)
      }.width('100%').alignItems(HorizontalAlign.Start)
    }.width('100%').constraintSize({ minHeight: 52 }).backgroundColor(AppTheme.INPUT)
      .onClick(() => {
        clearTimeout(this.timer); this.version++; this.matches = []; this.message = ''
        this.onSelect(place)
      })
  }

  build() {
    Column({ space: 6 }) {
      Button(this.region || '选择省 / 市 / 区').fontSize(14).fontColor(AppTheme.ACCENT)
        .backgroundColor(Color.Transparent).height(44).onClick(() => { this.showRegions = !this.showRegions })
      if (this.showRegions) {
        RegionPicker({ onChange: (region: string) => { this.region = region; this.change('') } })
      }
      FormInput({ label: '地图位置', value: this.value, fieldId: this.fieldId, maxLength: 80,
        helpText: '输入小区、街道或学校名，从匹配地点中选择以保存坐标', required: true,
        onChange: (value: string) => { this.change(value) } })
      if (this.matches.length > 0) {
        Scroll() {
          Column({ space: 4 }) {
            ForEach(this.matches, (place: AddressSearchResult) => { this.result(place) })
          }.width('100%')
        }.width('100%').constraintSize({ maxHeight: 240 })
      }
      if (this.message) { Text(this.message).fontSize(13).fontColor(AppTheme.MUTED) }
    }.width('100%')
  }
}

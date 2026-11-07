import { get, ApiResponse } from '../service/HttpClient'
import { AppTheme } from '../common/theme/AppTheme'
import { FormSelect } from './FormSelect'

interface District {
  name: string
  adcode: string
  districts: District[]
}
interface DistrictResponse { status: string; districts: District[] }

@Component
export struct RegionPicker {
  @State provinces: District[] = []
  @State cities: District[] = []
  @State districts: District[] = []
  @State province: number = -1
  @State city: number = -1
  @State district: number = -1
  @State error: string = ''
  @State loading: boolean = false
  private version: number = 0
  onChange: (region: string) => void = () => {}

  aboutToAppear(): void { this.load('中国', 0) }
  aboutToDisappear(): void { this.version++ }

  private async load(parent: string, level: number): Promise<void> {
    const version: number = ++this.version
    this.loading = true; this.error = ''
    const response: ApiResponse<DistrictResponse> = await get<DistrictResponse>('/api/location/districts?parent=' + encodeURIComponent(parent), false)
    if (version !== this.version) { return }
    this.loading = false
    if (response.code !== 200 || response.data?.status !== '1') { this.error = '地区加载失败，点击重试；也可直接搜索地点'; return }
    const children: District[] = response.data?.districts?.[0]?.districts ?? []
    if (level === 0) { this.provinces = children }
    else if (level === 1) { this.cities = children }
    else { this.districts = children }
  }

  private selectedRegion(): string {
    return (this.provinces[this.province]?.name ?? '') + (this.cities[this.city]?.name ?? '') + (this.districts[this.district]?.name ?? '')
  }

  private options(rows: District[]): SelectOption[] {
    return rows.map((row: District): SelectOption => { return { value: row.name } })
  }

  build() {
    Column({ space: 8 }) {
      FormSelect({ label: '省 / 自治区 / 直辖市', options: this.options(this.provinces), selected: this.province,
        isEnabled: !this.loading, fieldId: 'region-province', onSelect: (index: number) => {
          this.province = index; this.city = -1; this.district = -1; this.cities = []; this.districts = []
          this.onChange(this.selectedRegion()); this.load(this.provinces[index].adcode, 1)
        } })
      if (this.province >= 0) {
        FormSelect({ label: '城市', options: this.options(this.cities), selected: this.city,
          isEnabled: !this.loading, fieldId: 'region-city', onSelect: (index: number) => {
            this.city = index; this.district = -1; this.districts = []
            this.onChange(this.selectedRegion()); this.load(this.cities[index].adcode, 2)
          } })
      }
      if (this.city >= 0 && this.districts.length > 0) {
        FormSelect({ label: '区 / 县', options: this.options(this.districts), selected: this.district,
          isEnabled: !this.loading, fieldId: 'region-district', onSelect: (index: number) => {
            this.district = index; this.onChange(this.selectedRegion())
          } })
      }
      if (this.loading) { Text('正在加载地区…').fontSize(13).fontColor(AppTheme.MUTED) }
      if (this.error) {
        Button(this.error).fontSize(13).fontColor(AppTheme.ERROR).backgroundColor(Color.Transparent)
          .onClick(() => { this.load(this.city >= 0 ? this.cities[this.city].adcode : this.province >= 0 ? this.provinces[this.province].adcode : '中国', this.city >= 0 ? 2 : this.province >= 0 ? 1 : 0) })
      }
    }.width('100%')
  }
}

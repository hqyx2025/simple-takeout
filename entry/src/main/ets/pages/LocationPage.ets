/**
 * 选择位置页面
 * 功能：
 * 1. 进入页面自动实时定位手机当前位置（系统定位 + 高德逆地理编码）
 * 2. 支持搜索并选择任意地点作为配送地址（高德输入提示API）
 * 选择结果保存为当前配送地址，返回首页后顶部地址栏联动更新
 */
import { Address } from '../model/Models'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS } from '../common/Constants'
import { GeoPosition, SearchPlace, getCurrentPosition, reverseGeocode, searchPlaces } from '../service/LocationService'
import { EmptyState } from '../components/EmptyState'
import { promptAction } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import router from '@ohos.router'
import { logInfo } from '../service/AppLogger'

@Entry
@Component
export struct LocationPage {
  // 定位状态
  @State isLocating: boolean = false
  @State currentAddressText: string = ''
  @State currentPosition: GeoPosition | null = null
  @State locateError: string = ''
  // 搜索状态
  @State keyword: string = ''
  @State isSearching: boolean = false
  @State searchResults: SearchPlace[] = []
  @State searched: boolean = false
  // 选中的搜索结果
  @State selectedPlace: SearchPlace | null = null

  aboutToAppear() {
    this.locateCurrent()
  }

  // 定位当前手机实时位置
  private async locateCurrent(): Promise<void> {
    this.isLocating = true
    this.locateError = ''
    this.currentAddressText = ''
    this.currentPosition = null
    try {
      const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext
      const position: GeoPosition = await getCurrentPosition(context)
      this.currentPosition = position
      const addressText: string = await reverseGeocode(position)
      this.currentAddressText = addressText
      logInfo('LocationPage', '定位当前位置成功')
    } catch (err) {
      let msg: string = ''
      if (err instanceof Error) {
        msg = err.message
      }
      this.locateError = msg !== '' ? msg : '定位失败，请手动搜索选择位置'
    }
    this.isLocating = false
  }

  // 按关键词搜索地点
  private async doSearch(): Promise<void> {
    const kw: string = this.keyword.trim()
    if (kw === '') {
      this.searchResults = []
      this.searched = false
      return
    }
    this.isSearching = true
    try {
      const results: SearchPlace[] = await searchPlaces(kw, this.currentPosition !== null ? this.currentPosition : undefined)
      this.searchResults = results
      this.searched = true
    } catch (err) {
      this.searchResults = []
      this.searched = true
      promptAction.showToast({ message: '搜索失败，请检查网络或API Key配置', duration: 2000 })
    }
    this.isSearching = false
  }

  // 选中搜索结果
  private selectPlace(place: SearchPlace): void {
    this.selectedPlace = place
  }

  // 使用当前位置作为配送地址
  private useCurrentLocation(): void {
    if (this.currentAddressText === '') {
      return
    }
    this.applyAddress(this.currentAddressText, '')
  }

  // 使用搜索选中的地点作为配送地址
  private useSelectedPlace(): void {
    if (this.selectedPlace === null) {
      return
    }
    const place: SearchPlace = this.selectedPlace as SearchPlace
    const addressText: string = place.district !== '' ? `${place.district}${place.address}` : place.address
    this.applyAddress(addressText, place.name)
  }

  // 保存配送地址并返回
  private applyAddress(addressText: string, detail: string): void {
    const addr: Address = {
      id: 0,
      name: '当前位置',
      phone: '',
      address: addressText,
      detail: detail,
      isDefault: false,
      tag: '定位'
    }
    AppStorage.setOrCreate<Address>('currentAddress', addr)
    logInfo('LocationPage', `已选择配送地址: ${addressText} ${detail}`)
    router.back()
  }

  build() {
    Column() {
      // 顶部导航栏
      Row() {
        Text('‹')
          .fontSize(FONT_SIZE.XXL)
          .fontColor(COLORS.TEXT_PRIMARY)
          .onClick(() => { router.back() })
        Text('选择位置')
          .fontSize(FONT_SIZE.XL)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Text('‹')
          .fontSize(FONT_SIZE.XXL)
          .fontColor(Color.Transparent)
      }
      .width('100%')
      .height(56)
      .padding({ left: SPACING.LG, right: SPACING.LG })
      .backgroundColor(COLORS.BG_WHITE)

      Scroll() {
        Column({ space: SPACING.MD }) {
          // 当前位置卡片
          Column({ space: SPACING.SM }) {
            Row() {
              Text('📍')
                .fontSize(FONT_SIZE.XL)
              Text('当前位置')
                .fontSize(FONT_SIZE.LG)
                .fontWeight(FontWeight.Bold)
                .fontColor(COLORS.TEXT_PRIMARY)
                .margin({ left: SPACING.SM })
              Blank()
              Text('重新定位')
                .fontSize(FONT_SIZE.SM)
                .fontColor(COLORS.PRIMARY)
                .onClick(() => { this.locateCurrent() })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)

            if (this.isLocating) {
              Row() {
                LoadingProgress()
                  .width(20)
                  .height(20)
                  .color(COLORS.PRIMARY)
                Text('正在定位当前实时位置...')
                  .fontSize(FONT_SIZE.MD)
                  .fontColor(COLORS.TEXT_HINT)
                  .margin({ left: SPACING.SM })
              }
              .width('100%')
            } else if (this.currentAddressText !== '') {
              Text(this.currentAddressText)
                .fontSize(FONT_SIZE.MD)
                .fontColor(COLORS.TEXT_SECONDARY)
                .width('100%')
              Button('使用当前位置')
                .width('100%')
                .height(40)
                .fontSize(FONT_SIZE.MD)
                .fontColor(Color.White)
                .backgroundColor(COLORS.PRIMARY)
                .borderRadius(BORDER_RADIUS.ROUND)
                .type(ButtonType.Capsule)
                .onClick(() => { this.useCurrentLocation() })
            } else {
              Text(this.locateError !== '' ? this.locateError : '正在准备定位...')
                .fontSize(FONT_SIZE.MD)
                .fontColor(COLORS.ERROR)
                .width('100%')
            }
          }
          .width('100%')
          .padding(SPACING.LG)
          .backgroundColor(COLORS.BG_WHITE)
          .borderRadius(BORDER_RADIUS.LG)
          .alignItems(HorizontalAlign.Start)

          // 搜索区域
          Column({ space: SPACING.SM }) {
            Row({ space: SPACING.SM }) {
              TextInput({ placeholder: '搜索地点，如：中关村', text: this.keyword })
                .layoutWeight(1)
                .height(40)
                .fontSize(FONT_SIZE.MD)
                .backgroundColor(COLORS.BG_PRIMARY)
                .borderRadius(BORDER_RADIUS.ROUND)
                .onChange((value: string) => { this.keyword = value })
                .onSubmit(() => { this.doSearch() })
              Button('搜索')
                .height(40)
                .fontSize(FONT_SIZE.MD)
                .fontColor(Color.White)
                .backgroundColor(COLORS.PRIMARY)
                .borderRadius(BORDER_RADIUS.ROUND)
                .type(ButtonType.Capsule)
                .onClick(() => { this.doSearch() })
            }
            .width('100%')

            if (!this.searched && this.searchResults.length === 0) {
              Text('可直接使用上方“当前位置”，或搜索后选择一个地点作为配送地址')
                .fontSize(FONT_SIZE.SM)
                .fontColor(COLORS.TEXT_HINT)
                .width('100%')
            }

            if (this.isSearching) {
              Column() {
                LoadingProgress()
                  .width(32)
                  .height(32)
                  .color(COLORS.PRIMARY)
                Text('搜索中...')
                  .fontSize(FONT_SIZE.MD)
                  .fontColor(COLORS.TEXT_HINT)
                  .margin({ top: SPACING.SM })
              }
              .width('100%')
              .padding({ top: SPACING.XL, bottom: SPACING.XL })
            } else if (this.searchResults.length > 0) {
              List({ space: SPACING.XS }) {
                ForEach(this.searchResults, (place: SearchPlace) => {
                  ListItem() {
                    Row({ space: SPACING.SM }) {
                      Text(this.selectedPlace === place ? '📍' : '📌')
                        .fontSize(FONT_SIZE.MD)
                      Column({ space: 2 }) {
                        Text(place.name)
                          .fontSize(FONT_SIZE.MD)
                          .fontColor(this.selectedPlace === place ? COLORS.PRIMARY : COLORS.TEXT_PRIMARY)
                          .fontWeight(this.selectedPlace === place ? FontWeight.Bold : FontWeight.Normal)
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                        Text(place.district !== '' ? `${place.district} ${place.address}` : place.address)
                          .fontSize(FONT_SIZE.SM)
                          .fontColor(COLORS.TEXT_HINT)
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                      }
                      .layoutWeight(1)
                      .alignItems(HorizontalAlign.Start)
                      if (this.selectedPlace === place) {
                        Text('✓')
                          .fontSize(FONT_SIZE.LG)
                          .fontColor(COLORS.PRIMARY)
                      }
                    }
                    .width('100%')
                    .padding(SPACING.MD)
                    .backgroundColor(this.selectedPlace === place ? '#FFF3E0' : COLORS.BG_WHITE)
                    .borderRadius(BORDER_RADIUS.MD)
                    .onClick(() => { this.selectPlace(place) })
                  }
                }, (place: SearchPlace) => `${place.name}|${place.district}|${place.address}`)
              }
              .width('100%')
              .divider({ strokeWidth: 0 })
              .scrollBar(BarState.Off)
            } else if (this.searched) {
              EmptyState({ icon: '🔍', title: '未找到相关地点', description: '换个关键词再试试' })
            }
          }
          .width('100%')
          .padding(SPACING.LG)
          .backgroundColor(COLORS.BG_WHITE)
          .borderRadius(BORDER_RADIUS.LG)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.MD, bottom: SPACING.LG })
      }
      .scrollBar(BarState.Off)
      .layoutWeight(1)

      // 底部确认按钮（选中搜索地点后显示）
      if (this.selectedPlace !== null) {
        Button('使用所选位置')
          .width('90%')
          .height(48)
          .fontSize(FONT_SIZE.LG)
          .fontColor(Color.White)
          .backgroundColor(COLORS.PRIMARY)
          .borderRadius(BORDER_RADIUS.ROUND)
          .type(ButtonType.Capsule)
          .margin({ bottom: SPACING.LG })
          .onClick(() => { this.useSelectedPlace() })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(COLORS.BG_PRIMARY)
  }
}

import { common } from '@kit.AbilityKit'
import { COLORS, SPACING, FONT_SIZE } from '../common/Constants'
import { AppTheme, AppButtonStyle, AppCardStyle } from '../common/theme/AppTheme'
import { PageHeader } from '../components/PageHeader'
import { routerCompat as router, promptCompat as promptAction } from '../common/UiNavigation'
import { saveAppearanceSettings } from '../service/AppearanceSettings'

@Entry
@Component
struct AppSettingsPage {
  @StorageLink('appearanceColorMode') colorMode: string = 'system'
  @StorageLink('appearanceFontScale') fontScale: number = 1
  @StorageLink('navigationHandMode') navigationMode: string = 'auto'
  @State saving: boolean = false

  private async updateSettings(mode: string, scale: number, navigationMode: string): Promise<void> {
    if (this.saving || (mode === this.colorMode && scale === this.fontScale &&
      navigationMode === this.navigationMode)) { return }
    this.saving = true
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext
      await saveAppearanceSettings(context, mode, scale, navigationMode)
      promptAction.showToast({ message: '设置已保存', duration: 1500 })
    } catch (_) {
      promptAction.showToast({ message: '设置保存失败，请重试', duration: 2000 })
    } finally {
      this.saving = false
    }
  }

  @Builder
  ThemeOption(mode: string, title: string, description: string) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: SPACING.MD }) {
        Column({ space: SPACING.XS }) {
          Text(title).fontSize(FONT_SIZE.LG).fontColor(COLORS.TEXT_PRIMARY)
          Text(description).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Text(this.colorMode === mode ? '已选' : '选择')
          .fontSize(FONT_SIZE.SM).fontColor(COLORS.PRIMARY)
      }.width('100%')
    }
    .attributeModifier(new AppButtonStyle())
    .width('100%').padding(SPACING.MD)
    .backgroundColor(this.colorMode === mode ? COLORS.TAG_BG : COLORS.INPUT)
    .border({ width: 1, color: this.colorMode === mode ? COLORS.PRIMARY : COLORS.DIVIDER })
    .borderRadius(AppTheme.CONTROL_RADIUS)
    .id(`app-settings-theme-${mode}`)
    .enabled(!this.saving)
    .accessibilityText(`${title}，${this.colorMode === mode ? '已选' : '未选'}`)
    .onClick(() => { this.updateSettings(mode, this.fontScale, this.navigationMode) })
  }

  @Builder
  NavigationOption(mode: string, title: string, description: string) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: SPACING.MD }) {
        Column({ space: SPACING.XS }) {
          Text(title).fontSize(FONT_SIZE.LG).fontColor(COLORS.TEXT_PRIMARY)
          Text(description).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Text(this.navigationMode === mode ? '已选' : '选择')
          .fontSize(FONT_SIZE.SM).fontColor(COLORS.PRIMARY)
      }.width('100%')
    }
    .attributeModifier(new AppButtonStyle())
    .width('100%').padding(SPACING.MD)
    .backgroundColor(this.navigationMode === mode ? COLORS.TAG_BG : COLORS.INPUT)
    .border({ width: 1, color: this.navigationMode === mode ? COLORS.PRIMARY : COLORS.DIVIDER })
    .borderRadius(AppTheme.CONTROL_RADIUS)
    .id(`app-settings-navigation-${mode}`)
    .enabled(!this.saving)
    .accessibilityText(`${title}，${this.navigationMode === mode ? '已选' : '未选'}`)
    .onClick(() => { this.updateSettings(this.colorMode, this.fontScale, mode) })
  }

  @Builder
  FontOption(scale: number, title: string, optionId: string) {
    Button(`${title} ${Math.round(scale * 100)}%`)
      .attributeModifier(new AppButtonStyle())
      .layoutWeight(1).constraintSize({ minHeight: 48 })
      .padding({ left: SPACING.SM, right: SPACING.SM, top: SPACING.MD, bottom: SPACING.MD })
      .fontSize(FONT_SIZE.MD)
      .fontColor(this.fontScale === scale ? COLORS.ON_PRIMARY : COLORS.TEXT_PRIMARY)
      .backgroundColor(this.fontScale === scale ? COLORS.PRIMARY : COLORS.INPUT)
      .border({ width: 1, color: this.fontScale === scale ? COLORS.PRIMARY : COLORS.DIVIDER })
      .borderRadius(AppTheme.CONTROL_RADIUS)
      .id(`app-settings-font-${optionId}`)
      .enabled(!this.saving)
      .accessibilityText(`${title}，${this.fontScale === scale ? '已选' : '未选'}`)
      .onClick(() => { this.updateSettings(this.colorMode, scale, this.navigationMode) })
  }

  build() {
    Column() {
      PageHeader({ title: '应用设置', backId: 'app-settings-back', onBack: () => { router.back() } })
      Scroll() {
        Column({ space: SPACING.LG }) {
          Text('修改后立即生效，下次启动仍会保留。')
            .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY).width('100%')
          Column({ space: SPACING.MD }) {
            Text('导航位置').fontSize(FONT_SIZE.XL).fontWeight(FontWeight.Bold)
              .fontColor(COLORS.TEXT_PRIMARY).width('100%')
            this.NavigationOption('auto', '跟随交互手 · 自动', '根据操作的左右手调整，不支持时保持居中')
            this.NavigationOption('left', '靠左，方便左手', '将底部导航固定在左侧')
            this.NavigationOption('right', '靠右，方便右手', '将底部导航固定在右侧')
            this.NavigationOption('center', '居中', '将底部导航固定在中间')
          }
          .attributeModifier(new AppCardStyle()).width('100%').padding(SPACING.LG)
          Column({ space: SPACING.MD }) {
            Text('深色模式').fontSize(FONT_SIZE.XL).fontWeight(FontWeight.Bold)
              .fontColor(COLORS.TEXT_PRIMARY).width('100%')
            this.ThemeOption('system', '跟随系统', '随设备的浅色或深色模式自动切换')
            this.ThemeOption('light', '浅色模式', '使用暖白背景，适合明亮环境')
            this.ThemeOption('dark', '深色模式', '使用深色背景，适合夜间阅读')
          }
          .attributeModifier(new AppCardStyle()).width('100%').padding(SPACING.LG)
          .backgroundColor(COLORS.BG_CARD)
          .border({ width: 1, color: COLORS.DIVIDER }).borderRadius(AppTheme.CARD_RADIUS)
          Column({ space: SPACING.MD }) {
            Text('字体大小').fontSize(FONT_SIZE.XL).fontWeight(FontWeight.Bold)
              .fontColor(COLORS.TEXT_PRIMARY).width('100%')
            Text('调整整个应用的文字大小，不改变图片和图标大小。')
              .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY).width('100%')
            Row({ space: SPACING.SM }) {
              this.FontOption(0.9, '小', 'small')
              this.FontOption(1, '标准', 'normal')
            }.width('100%')
            Row({ space: SPACING.SM }) {
              this.FontOption(1.15, '大', 'large')
              this.FontOption(1.3, '特大', 'extra-large')
            }.width('100%')
            Column({ space: SPACING.SM }) {
              Text('阅读预览').fontSize(FONT_SIZE.XL).fontWeight(FontWeight.Bold)
                .fontColor(COLORS.TEXT_PRIMARY)
              Text('简单外卖，让每一餐更方便。').fontSize(FONT_SIZE.LG).fontColor(COLORS.TEXT_PRIMARY)
              Text('找到适合你的字号，更舒适地阅读每一条消息。')
                .fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_SECONDARY)
            }.alignItems(HorizontalAlign.Start).width('100%').padding(SPACING.LG)
            .backgroundColor(COLORS.INPUT).borderRadius(AppTheme.CONTROL_RADIUS).id('app-settings-preview')
          }
          .attributeModifier(new AppCardStyle()).width('100%').padding(SPACING.LG)
          .backgroundColor(COLORS.BG_CARD)
          .border({ width: 1, color: COLORS.DIVIDER }).borderRadius(AppTheme.CARD_RADIUS)
        }.width('100%').constraintSize({ maxWidth: 680 }).padding(SPACING.LG)
      }.width('100%').layoutWeight(1).scrollBar(BarState.Off)
      Row() {
        Button(this.saving ? '保存中…' : '恢复默认设置')
          .attributeModifier(new AppButtonStyle()).width('100%')
          .fontColor(COLORS.ON_PRIMARY).backgroundColor(COLORS.PRIMARY)
          .constraintSize({ minHeight: 48 }).padding(SPACING.MD)
          .id('app-settings-reset').enabled(!this.saving)
          .onClick(() => { this.updateSettings('system', 1, 'auto') })
      }.width('100%').constraintSize({ maxWidth: 680 }).padding(SPACING.LG)
    }.width('100%').height('100%').backgroundColor(COLORS.BG_PRIMARY)
  }
}

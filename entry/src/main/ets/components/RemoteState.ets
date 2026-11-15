import { COLORS, SPACING, FONT_SIZE } from '../common/Constants'
import { AppButtonStyle } from '../common/theme/AppTheme'
import { EmptyState } from './EmptyState'
import { LoadingIndicator } from './LoadingIndicator'

/** Render this alongside existing data: a refresh error never replaces that data. */
@Component
export struct RemoteState {
  @Prop loading: boolean = false
  @Prop failed: boolean = false
  @Prop hasData: boolean = false
  @Prop emptyTitle: string = '暂无数据'
  @Prop errorText: string = ''
  @Prop retryId: string = 'remote-state-retry'
  onRetry: () => void = () => {}

  build() {
    if (this.failed) {
      Column({ space: SPACING.SM }) {
        Text(this.hasData ? '刷新失败，已保留原有内容' : '加载失败')
          .fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_PRIMARY)
        if (this.errorText !== '') { Text(this.errorText).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY) }
        Button('重试').attributeModifier(new AppButtonStyle()).height(44).enabled(!this.loading)
          .id(this.retryId).onClick(() => { this.onRetry() })
      }.width('100%').padding(SPACING.LG)
    } else if (this.loading && !this.hasData) {
      LoadingIndicator()
    } else if (!this.loading && !this.hasData) {
      EmptyState({ title: this.emptyTitle })
    }
  }
}

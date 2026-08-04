/**
 * 设置页面
 * 包含：清除缓存、退出登录、关于我们
 */
import { CartItem } from '../model/Models'
import { logout } from '../service/AppStorageManager'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS } from '../common/Constants'
import { ConfirmDialog } from '../components/ConfirmDialog'

@Component
export struct SettingsPage {
  @StorageLink('isLoggedIn') loggedIn: boolean = false
  @State showAbout: boolean = false
  @State showLogoutConfirm: boolean = false
  @State cacheSize: string = '0KB'
  onBack: () => void = () => {}
  onLogout: () => void = () => {}

  aboutToAppear() {
    this.calculateCacheSize()
  }

  calculateCacheSize() {
    const cart: CartItem[] = AppStorage.get<CartItem[]>('cartItems') || []
    // 简单估算：每个购物车项约 0.5KB
    const sizeKB: number = cart.length * 0.5
    this.cacheSize = sizeKB.toFixed(1) + 'KB'
  }

  clearCache() {
    // 清空购物车和搜索历史等非必要数据
    AppStorage.setOrCreate<CartItem[]>('cartItems', [])
    // 显示提示
    this.cacheSize = '0KB'
  }

  doLogout() {
    logout()
    this.loggedIn = false
    this.showLogoutConfirm = false
    this.onLogout()
  }

  build() {
    Stack() {
      // 主内容
      Column() {
        // 导航栏
        Row() {
          Text('‹ 返回')
            .fontSize(FONT_SIZE.MD)
            .fontColor(COLORS.TEXT_PRIMARY)
            .onClick(() => { this.onBack() })
          Text('设置')
            .fontSize(FONT_SIZE.LG)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLORS.TEXT_PRIMARY)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
          Text('   ')
            .fontSize(FONT_SIZE.MD) // 占位，保持标题居中
        }
        .width('100%')
        .height(44)
        .padding({ left: SPACING.LG, right: SPACING.LG })
        .backgroundColor(COLORS.BG_WHITE)

        // 设置项列表
        Column() {
          // 清除缓存
          this.SettingItem('🗑', '清除缓存', this.cacheSize, false, () => {
            this.clearCache()
          })

          // 退出登录（仅登录时显示）
          if (this.loggedIn) {
            this.SettingItem('🚪', '退出登录', '', true, () => {
              this.showLogoutConfirm = true
            })
          }

          // 关于我们
          this.SettingItem('ℹ️', '关于我们', '', false, () => {
            this.showAbout = true
          })
        }
        .width('100%')
        .margin({ top: SPACING.SM })
        .backgroundColor(COLORS.BG_WHITE)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(COLORS.BG_PRIMARY)

      // 关于弹窗
      if (this.showAbout) {
        Stack() {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('rgba(0,0,0,0.5)')
            .onClick(() => { this.showAbout = false })

          Column({ space: SPACING.MD }) {
            Text('🍜').fontSize(60)
            Text('简单外卖')
              .fontSize(FONT_SIZE.XXL)
              .fontWeight(FontWeight.Bold)
              .fontColor(COLORS.TEXT_PRIMARY)
            Text('v1.0.0')
              .fontSize(FONT_SIZE.MD)
              .fontColor(COLORS.TEXT_HINT)
            Text('一款便捷学生点外卖的鸿蒙App')
              .fontSize(FONT_SIZE.MD)
              .fontColor(COLORS.TEXT_SECONDARY)
              .textAlign(TextAlign.Center)
            Text('HarmonyOS NEXT 毕业设计项目')
              .fontSize(FONT_SIZE.SM)
              .fontColor(COLORS.TEXT_HINT)
            Button('关闭')
              .height(40)
              .fontSize(FONT_SIZE.MD)
              .fontColor(COLORS.PRIMARY)
              .backgroundColor(Color.Transparent)
              .borderWidth(1)
              .borderColor(COLORS.PRIMARY)
              .borderRadius(BORDER_RADIUS.ROUND)
              .type(ButtonType.Capsule)
              .margin({ top: SPACING.LG })
              .onClick(() => { this.showAbout = false })
          }
          .width('80%')
          .padding(SPACING.XXL)
          .backgroundColor(COLORS.BG_WHITE)
          .borderRadius(BORDER_RADIUS.XL)
          .alignItems(HorizontalAlign.Center)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }

      // 退出确认弹窗
      if (this.showLogoutConfirm) {
        ConfirmDialog({
          title: '确认退出',
          content: '确定要退出登录吗？',
          confirmText: '退出',
          cancelText: '取消',
          onConfirm: () => { this.doLogout() },
          onCancel: () => { this.showLogoutConfirm = false }
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  SettingItem(icon: string, title: string, value: string, isDanger: boolean, onClick: () => void) {
    Row({ space: SPACING.MD }) {
      Text(icon).fontSize(20)
      Text(title)
        .fontSize(FONT_SIZE.LG)
        .fontColor(isDanger ? COLORS.ERROR : COLORS.TEXT_PRIMARY)
        .layoutWeight(1)
      if (value !== '') {
        Text(value).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT)
      }
      Text('›').fontSize(20).fontColor(COLORS.TEXT_HINT)
    }
    .width('100%')
    .height(56)
    .padding({ left: SPACING.LG, right: SPACING.LG })
    .backgroundColor(COLORS.BG_WHITE)
    .onClick(() => { onClick() })
  }
}

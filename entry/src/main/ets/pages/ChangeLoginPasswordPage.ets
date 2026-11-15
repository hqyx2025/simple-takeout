import { AccountSecurityTask } from '../components/account/AccountSecurityTask'

@Entry
@Component
struct ChangeLoginPasswordPage {
  @State visible: boolean = true
  onPageShow(): void { this.visible = true }
  onPageHide(): void { this.visible = false }
  build() {
    Column() { AccountSecurityTask({ visible: this.visible, task: 'login' }) }.width('100%').height('100%')
  }
}

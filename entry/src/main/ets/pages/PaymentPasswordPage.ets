import { AccountSecurityTask } from '../components/account/AccountSecurityTask'

@Entry
@Component
struct PaymentPasswordPage {
  @State visible: boolean = true
  onPageShow(): void { this.visible = true }
  onPageHide(): void { this.visible = false }
  build() {
    Column() { AccountSecurityTask({ visible: this.visible, task: 'payment' }) }.width('100%').height('100%')
  }
}

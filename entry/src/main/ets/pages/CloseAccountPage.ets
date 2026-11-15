import { AccountSecurityTask } from '../components/account/AccountSecurityTask'

@Entry
@Component
struct CloseAccountPage {
  @State visible: boolean = true
  onPageShow(): void { this.visible = true }
  onPageHide(): void { this.visible = false }
  build() {
    Column() { AccountSecurityTask({ visible: this.visible, task: 'closure' }) }.width('100%').height('100%')
  }
}

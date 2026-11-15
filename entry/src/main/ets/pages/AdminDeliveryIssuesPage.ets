import { OrderIssueContent } from '../components/orders/OrderIssueContent'

@Entry
@Component
struct AdminDeliveryIssuesPage {
  @State visible: boolean = true
  onPageShow(): void { this.visible = true }
  onPageHide(): void { this.visible = false }
  build() {
    Column() { OrderIssueContent({ platform: true, visible: this.visible }) }.width('100%').height('100%')
  }
}

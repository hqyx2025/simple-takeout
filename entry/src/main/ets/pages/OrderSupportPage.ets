import { routerCompat as router } from '../common/UiNavigation'
import { User, UserRole } from '../model/Models'

/** Compatibility entry for older navigation stacks; new callers use named task routes. */
@Entry
@Component
struct OrderSupportPage {
  aboutToAppear(): void {
    const params = router.getParams()
    const user: User | undefined = AppStorage.get<User>('user')
    router.replaceUrl({ url: (params?.storeId ?? 0) > 0 ? 'pages/MerchantFulfillmentPage'
      : user?.role === UserRole.ADMIN ? 'pages/AdminDeliveryIssuesPage' : 'pages/OrderIssuePage', params })
  }
  build() { Column().width('100%').height('100%') }
}

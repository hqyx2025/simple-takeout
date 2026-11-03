import { describe, it, expect } from '@ohos/hypium'
import { Driver, ON, Component, abilityDelegatorRegistry } from '@kit.TestKit'
import { UIAbility } from '@kit.AbilityKit'
import { window, UIContext } from '@kit.ArkUI'
import { fileIo } from '@kit.CoreFileKit'
import BuildProfile from 'BuildProfile'
import { launchAppUnderTest, isFound, requireComponent, scrollUntilVisible } from './UiTestHelper'
import { loginRemote, logout, syncCartRemote, syncAddressesRemote, syncUserOrdersFromServer } from '../../../main/ets/service/AppStorageManager'
import { getQuickLoginAccount, QuickLoginAccount } from '../../../main/ets/common/QuickLoginConfig'
import { getApiBaseUrl, get, ApiResponse } from '../../../main/ets/service/HttpClient'
import { clearCartApi, fetchOrderDetailApi, fetchUserOrdersApi } from '../../../main/ets/service/ApiService'
import { Order, UserRole, RefundRecord } from '../../../main/ets/model/Models'

interface CampusFixture { storeId: number; storeName: string; goodsId: number; paymentPassword: string }
interface CampusConfiguration { fixtures: CampusFixture }
interface AccountBalance { balance: number }
interface RiderTotals { totalOrders: number; totalIncome: number }

async function navigateCampus(context: UIContext, driver: Driver, page: string): Promise<void> {
  await new Promise<void>((resolve, reject) => {
    context.runScopedTask((): void => {
      context.getRouter().pushUrl({ url: 'pages/' + page }).then(() => { resolve() })
        .catch(() => { reject(new Error('Route failed: ' + page)) })
    })
  })
  await driver.delayMs(1600)
}

async function campusLogin(context: UIContext, driver: Driver, role: UserRole, page: string): Promise<void> {
  logout()
  const account: QuickLoginAccount | undefined = getQuickLoginAccount(role, getApiBaseUrl())
  if (account === undefined) { throw new Error('Missing isolated account') }
  const user = await loginRemote(account.phone, account.password, ['USER', 'MERCHANT', 'ADMIN', 'RIDER'][role])
  expect(user?.role).assertEqual(role)
  await navigateCampus(context, driver, page)
  // 每个角色以独立页面栈开始，避免测试保留的隐藏 Index 实例响应下一角色的登录。
  context.runScopedTask((): void => { context.getRouter().clear() })
  await driver.delayMs(500)
}

async function campusClick(driver: Driver, id: string): Promise<void> {
  console.info('[CampusAcceptance] click ' + id)
  const control: Component = requireComponent(await scrollUntilVisible(driver, id), id)
  await control.click()
  await driver.delayMs(1200)
}

async function campusText(driver: Driver, text: string): Promise<void> {
  const controls: Component[] = await driver.findComponents(ON.text(text)) ?? []
  expect(controls.length > 0).assertTrue()
  await controls[controls.length - 1].click()
  await driver.delayMs(1200)
}

async function campusOrder(id: number, status: number, escrow: number): Promise<Order> {
  const order: Order | null = await fetchOrderDetailApi(id)
  if (order === null) { throw new Error('Order unavailable') }
  expect(order.status).assertEqual(status)
  expect(order.escrowStatus ?? 0).assertEqual(escrow)
  return order
}

async function campusCreate(context: UIContext, driver: Driver, fixture: CampusFixture): Promise<number> {
  expect(await clearCartApi() !== null).assertTrue()
  await syncCartRemote()
  await syncAddressesRemote()
  AppStorage.setOrCreate<number>('selectedStoreId', fixture.storeId)
  AppStorage.setOrCreate<string>('selectedStoreName', fixture.storeName)
  await navigateCampus(context, driver, 'StoreDetailPage')
  await campusClick(driver, 'goods-plus-' + fixture.goodsId)
  expect(await requireComponent(await driver.findComponent(ON.id('goods-qty-' + fixture.goodsId)), 'cart quantity').getText()).assertEqual('1')
  await campusClick(driver, 'store-checkout')
  requireComponent(await driver.waitForComponent(ON.id('checkout-submit'), 8000), 'checkout submit')
  await campusClick(driver, 'checkout-submit')
  requireComponent(await driver.waitForComponent(ON.id('order-detail-status'), 12000), 'created order')
  const id: number = AppStorage.get<number>('currentOrderId') ?? 0
  expect(id > 0).assertTrue()
  await campusOrder(id, 0, 0)
  console.info('[CampusAcceptance] created order=' + id)
  return id
}

export default function campusAcceptanceTest(): void {
  describe('CampusAcceptance', () => {
    it('four_roles_complete_same_order_then_review_refund_and_cancel_through_ui', 0, async () => {
      expect(BuildProfile.UI_TEST_BASE_URL.startsWith('http://10.0.2.2:')).assertTrue()
      const fixture: CampusFixture = (JSON.parse(BuildProfile.QUICK_LOGIN_CONFIG) as CampusConfiguration).fixtures
      const driver: Driver = Driver.create()
      await launchAppUnderTest(driver)
      const consent = await driver.findComponent(ON.id('privacy-accept'))
      if (isFound(consent)) { await requireComponent(consent, 'privacy notice').click(); await driver.delayMs(1500) }
      const ability: UIAbility = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility()
      const context: UIContext = (await window.getLastWindow(ability.context)).getUIContext()
      const directory: string = ability.context.filesDir + '/campus-acceptance'
      try { fileIo.mkdirSync(directory) } catch (_) {}
      try {
        await campusLogin(context, driver, UserRole.CUSTOMER, 'Index')
        const before: ApiResponse<AccountBalance> = await get<AccountBalance>('/api/auth/me')
        const balance: number = before.data?.balance ?? -1
        const orderId: number = await campusCreate(context, driver, fixture)
        const created: Order = await campusOrder(orderId, 0, 0)
        await campusClick(driver, 'order-pay-channel-BALANCE')
        await requireComponent(await driver.waitForComponent(ON.id('order-payment-password'), 5000), 'payment password').inputText('000000')
        await driver.pressBack()
        await campusClick(driver, 'order-pay')
        await campusOrder(orderId, 0, 0)
        const failed: ApiResponse<AccountBalance> = await get<AccountBalance>('/api/auth/me')
        expect(failed.data?.balance).assertEqual(balance)
        await requireComponent(await driver.findComponent(ON.id('order-payment-password')), 'payment password').inputText(fixture.paymentPassword)
        await driver.pressBack()
        await campusClick(driver, 'order-pay')
        await campusOrder(orderId, 1, 0)
        const paid: ApiResponse<AccountBalance> = await get<AccountBalance>('/api/auth/me')
        expect(paid.data?.balance).assertEqual(balance - created.payAmount)
        expect(await driver.screenCap(directory + '/01-paid.png')).assertTrue()
        console.info('[CampusAcceptance] PASS UI order, invalid payment password and balance payment')

        await campusLogin(context, driver, UserRole.MERCHANT, 'MerchantOrdersPage')
        const merchantBefore: ApiResponse<AccountBalance> = await get<AccountBalance>('/api/auth/me')
        await campusClick(driver, 'merchant-action-' + orderId)
        expect(await requireComponent(await driver.waitForComponent(ON.id('merchant-order-status-' + orderId), 5000), 'merchant preparing').getText()).assertEqual('制作中')
        await campusOrder(orderId, 2, 0)
        await campusClick(driver, 'merchant-action-' + orderId)
        requireComponent(await driver.waitForComponent(ON.id('merchant-ready-' + orderId), 5000), 'ready for rider')
        expect(await requireComponent(await driver.findComponent(ON.id('merchant-order-status-' + orderId)), 'merchant ready status').getText()).assertEqual('待骑手接单')
        expect(await driver.screenCap(directory + '/02-merchant-ready.png')).assertTrue()
        console.info('[CampusAcceptance] PASS UI merchant accept and ready order=' + orderId)

        await campusLogin(context, driver, UserRole.RIDER, 'RiderOrderPoolPage')
        const riderBefore: ApiResponse<RiderTotals> = await get<RiderTotals>('/api/rider/profile')
        await campusClick(driver, 'rider-grab-' + orderId)
        await navigateCampus(context, driver, 'RiderOrdersPage')
        await campusClick(driver, 'rider-pickup-' + orderId)
        await campusClick(driver, 'rider-deliver-' + orderId)
        await campusText(driver, '确认已交付')
        const riderAfter: ApiResponse<RiderTotals> = await get<RiderTotals>('/api/rider/profile')
        expect(riderAfter.data?.totalOrders).assertEqual((riderBefore.data?.totalOrders ?? 0) + 1)
        expect(riderAfter.data?.totalIncome).assertEqual((riderBefore.data?.totalIncome ?? 0) + created.deliveryFee)
        expect(await driver.screenCap(directory + '/03-rider-delivered.png')).assertTrue()
        console.info('[CampusAcceptance] PASS UI rider grab, pickup, deliver and totals')

        await campusLogin(context, driver, UserRole.CUSTOMER, 'OrderListPage')
        await campusOrder(orderId, 4, 0)
        AppStorage.setOrCreate<number>('currentOrderId', orderId)
        await navigateCampus(context, driver, 'OrderDetailPage')
        await campusText(driver, '确认收到')
        await campusText(driver, '确认收到')
        await campusOrder(orderId, 4, 1)
        await syncUserOrdersFromServer()
        AppStorage.setOrCreate<number>('currentOrderId', orderId)
        await navigateCampus(context, driver, 'OrderDetailPage')
        await campusClick(driver, 'order-review-entry')
        await campusClick(driver, 'review-star-5')
        await requireComponent(await scrollUntilVisible(driver, 'review-content'), 'review content').inputText('校园配送准时，餐品完好')
        await driver.pressBack()
        await campusClick(driver, 'review-submit')
        const reviewed: Order = await campusOrder(orderId, 4, 1)
        expect(reviewed.reviewed).assertEqual(1)
        console.info('[CampusAcceptance] PASS UI confirm and review')

        AppStorage.setOrCreate<number>('currentOrderId', orderId)
        await navigateCampus(context, driver, 'OrderDetailPage')
        await campusClick(driver, 'order-refund-entry')
        await requireComponent(await driver.waitForComponent(ON.id('order-refund-amount'), 5000), 'partial refund').inputText('1')
        await driver.pressBack()
        await campusClick(driver, 'order-refund-reason-OTHER')
        await requireComponent(await scrollUntilVisible(driver, 'order-refund-note'), 'refund note').inputText('隔离测试部分退款')
        await driver.pressBack()
        await campusClick(driver, 'order-refund-submit')
        const refunds: ApiResponse<RefundRecord[]> = await get<RefundRecord[]>('/api/orders/' + orderId + '/refunds')
        const records: RefundRecord[] = refunds.data ?? []
        expect(records.length).assertEqual(1)
        const refundId: number = records[0].id
        await campusLogin(context, driver, UserRole.ADMIN, 'AdminRefundPage')
        await campusClick(driver, 'admin-refund-approve-' + refundId)
        await campusText(driver, '确认退款')
        expect(await driver.screenCap(directory + '/04-admin-refund.png')).assertTrue()
        await campusLogin(context, driver, UserRole.CUSTOMER, 'OrderListPage')
        const refunded: ApiResponse<AccountBalance> = await get<AccountBalance>('/api/auth/me')
        expect(refunded.data?.balance).assertEqual(balance - created.payAmount + 1)
        const result: ApiResponse<RefundRecord[]> = await get<RefundRecord[]>('/api/orders/' + orderId + '/refunds')
        expect((result.data ?? [])[0].status).assertEqual('REFUNDED')
        await campusOrder(orderId, 4, 1)
        console.info('[CampusAcceptance] PASS UI settled partial refund through administrator')

        const cancelledId: number = await campusCreate(context, driver, fixture)
        await campusClick(driver, 'order-cancel')
        await campusText(driver, '确定取消')
        await campusOrder(cancelledId, 5, 0)
        const finalOrders: Order[] = await fetchUserOrdersApi() ?? []
        expect(finalOrders.filter((order: Order) => order.id === orderId).length).assertEqual(1)
        console.info('[CampusAcceptance] PASS UI unpaid cancellation and single order identity')
        await campusLogin(context, driver, UserRole.MERCHANT, 'MerchantStatsPage')
        const settled: ApiResponse<AccountBalance> = await get<AccountBalance>('/api/auth/me')
        expect(settled.data?.balance).assertEqual((merchantBefore.data?.balance ?? 0) + created.payAmount - created.deliveryFee - 1)
        console.info('[CampusAcceptance] PASS merchant net settlement after partial refund')
      } catch (error) {
        console.error('[CampusAcceptance] ' + (error instanceof Error ? error.stack : 'Unknown failure'))
        await driver.screenCap(directory + '/failure.png')
        throw new Error(error instanceof Error ? error.message : 'Campus acceptance failed')
      } finally { logout() }
    })
  })
}

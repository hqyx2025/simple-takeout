import { describe, it, expect } from '@ohos/hypium'
import { Driver, ON, Component, abilityDelegatorRegistry } from '@kit.TestKit'
import { UIAbility } from '@kit.AbilityKit'
import { window, UIContext } from '@kit.ArkUI'
import { fileIo } from '@kit.CoreFileKit'
import http from '@ohos.net.http'
import BuildProfile from 'BuildProfile'
import { launchAppUnderTest, requireComponent, isFound, scrollUntilVisible } from './UiTestHelper'
import { loginRemote, logout, syncCartRemote, syncAddressesRemote } from '../../../main/ets/service/AppStorageManager'
import { getQuickLoginAccount, QuickLoginAccount } from '../../../main/ets/common/QuickLoginConfig'
import { get, getApiBaseUrl, ApiResponse } from '../../../main/ets/service/HttpClient'
import { clearCartApi, addCartItemApi, fetchUserOrdersApi, fetchOrderDetailApi, cancelOrderApi } from '../../../main/ets/service/ApiService'
import { saveAppearanceSettings } from '../../../main/ets/service/AppearanceSettings'
import { Address, CartItem, Order, RefundRecord, UserRole } from '../../../main/ets/model/Models'

interface BoundaryFixtures {
  storeId: number; storeName: string; goodsId: number; controlBaseUrl: string
  labelPreparingId: number; labelReadyId: number; labelAssignedId: number
  settledRefundId: number; unsettledRefundId: number; settledOrderId: number; unsettledOrderId: number
  accountAName: string; accountBName: string; alternateAccount: QuickLoginAccount
}
interface BoundaryConfig { fixtures: BoundaryFixtures }
interface BoundaryBalance { balance: number }

async function control(fixture: BoundaryFixtures, command: string): Promise<void> {
  const request: http.HttpRequest = http.createHttp()
  try {
    const response: http.HttpResponse = await request.request(fixture.controlBaseUrl + '/' + command,
      { method: http.RequestMethod.GET, connectTimeout: 4000, readTimeout: 4000 })
    expect(response.responseCode).assertEqual(200)
  } finally { request.destroy() }
}

async function navigate(context: UIContext, driver: Driver, page: string): Promise<void> {
  await new Promise<void>((resolve, reject) => {
    context.runScopedTask((): void => {
      context.getRouter().pushUrl({ url: 'pages/' + page }).then(() => { resolve() })
        .catch(() => { reject(new Error('Route failed: ' + page)) })
    })
  })
  context.runScopedTask((): void => { context.getRouter().clear() })
  await driver.delayMs(1200)
}

async function signIn(context: UIContext, driver: Driver, role: UserRole, page: string,
  alternate: QuickLoginAccount | undefined = undefined): Promise<void> {
  logout()
  const account: QuickLoginAccount | undefined = alternate ?? getQuickLoginAccount(role, getApiBaseUrl())
  if (account === undefined) { throw new Error('Missing isolated account') }
  const user = await loginRemote(account.phone, account.password, ['USER', 'MERCHANT', 'ADMIN', 'RIDER'][role])
  expect(user?.role).assertEqual(role)
  await navigate(context, driver, page)
}

async function click(driver: Driver, id: string): Promise<void> {
  await requireComponent(await scrollUntilVisible(driver, id), id).click()
  await driver.delayMs(500)
}

async function verifyBounds(driver: Driver, id: string): Promise<void> {
  const component: Component = requireComponent(await scrollUntilVisible(driver, id), id)
  const bounds = await component.getBounds()
  const size = await driver.getDisplaySize()
  expect(bounds.left >= 0 && bounds.right <= size.x && bounds.top >= 0 && bounds.bottom <= size.y).assertTrue()
  expect(bounds.bottom > bounds.top && bounds.right > bounds.left).assertTrue()
}

export default function boundaryFlowTest(): void {
  describe('BoundaryFlow', () => {
    it('merchant_refund_light_dark_and_extra_large_text', 0, async () => {
      expect(BuildProfile.UI_TEST_BASE_URL.startsWith('http://10.0.2.2:')).assertTrue()
      const fixture: BoundaryFixtures = (JSON.parse(BuildProfile.QUICK_LOGIN_CONFIG) as BoundaryConfig).fixtures
      const driver: Driver = Driver.create()
      await launchAppUnderTest(driver)
      const consent = await driver.findComponent(ON.id('privacy-accept'))
      if (isFound(consent)) { await requireComponent(consent, 'privacy').click(); await driver.delayMs(1500) }
      const ability: UIAbility = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility()
      const context: UIContext = (await window.getLastWindow(ability.context)).getUIContext()
      const directory: string = ability.context.filesDir + '/boundary'
      try { fileIo.mkdirSync(directory) } catch (_) {}
      const mode: string = AppStorage.get<string>('appearanceColorMode') ?? 'system'
      const scale: number = AppStorage.get<number>('appearanceFontScale') ?? 1
      try {
        for (const variant of ['light', 'dark', 'light-large', 'dark-large']) {
          await saveAppearanceSettings(ability.context, variant.startsWith('dark') ? 'dark' : 'light', variant.endsWith('large') ? 1.3 : 1, 'center')
          await signIn(context, driver, UserRole.MERCHANT, 'MerchantOrdersPage')
          await driver.delayMs(800)
          expect(await driver.screenCap(directory + '/' + variant + '-merchant-entry.png')).assertTrue()
          for (const id of [fixture.labelPreparingId, fixture.labelAssignedId, fixture.labelReadyId]) {
            const expected: string = id === fixture.labelPreparingId ? '制作中' : id === fixture.labelReadyId ? '待骑手接单' : '待骑手取餐'
            const list: Component = requireComponent(await driver.findComponent(ON.type('List')), 'merchant list')
            const label = requireComponent(await list.scrollSearch(ON.id('merchant-order-status-' + id)), 'merchant progress ' + id)
            expect(await label.getText()).assertEqual(expected)
          }
          await verifyBounds(driver, 'page-title')
          await requireComponent(await driver.findComponent(ON.type('List')), 'merchant list').scrollSearch(ON.id('merchant-order-status-' + fixture.labelReadyId))
          expect(await driver.screenCap(directory + '/' + variant + '-merchant.png')).assertTrue()
          await signIn(context, driver, UserRole.ADMIN, 'AdminRefundPage')
          const policy = requireComponent(await scrollUntilVisible(driver, 'admin-refund-policy'), 'refund policy')
          expect(await policy.getText()).assertContain('已结算订单保留结算状态')
          await verifyBounds(driver, 'admin-refund-pending')
          await verifyBounds(driver, 'admin-refund-all')
          expect(await driver.screenCap(directory + '/' + variant + '-refund.png')).assertTrue()
          console.info('[BoundaryFlow] PASS appearance ' + variant + ' merchant states/refund controls')
        }
        for (const refundId of [fixture.unsettledRefundId, fixture.settledRefundId]) {
          await click(driver, 'admin-refund-reject-' + refundId)
          const policy = requireComponent(await driver.waitForComponent(ON.id('admin-refund-reject-policy'), 5000), 'rejection policy')
          expect(await policy.getText()).assertContain('未结算订单恢复为待确认收货')
          await requireComponent(await driver.findComponent(ON.id('admin-refund-reject-reason')), 'rejection reason').inputText('已核对本次隔离配送记录')
          await driver.pressBack()
          await verifyBounds(driver, 'admin-refund-reject-confirm')
          expect(await driver.screenCap(directory + '/reject-' + refundId + '-dialog.png')).assertTrue()
          await click(driver, 'admin-refund-reject-confirm')
          const result: ApiResponse<RefundRecord> = await get<RefundRecord>('/api/admin/refunds/' + refundId)
          expect(result.data?.status).assertEqual('REJECTED')
          expect(result.data?.originalEscrow).assertEqual(refundId === fixture.settledRefundId ? 1 : 0)
          expect(await driver.screenCap(directory + '/reject-' + refundId + '-result.png')).assertTrue()
        }
        await signIn(context, driver, UserRole.CUSTOMER, 'OrderListPage')
        const unsettled: Order | null = await fetchOrderDetailApi(fixture.unsettledOrderId)
        const settled: Order | null = await fetchOrderDetailApi(fixture.settledOrderId)
        expect(unsettled?.status).assertEqual(4); expect(unsettled?.escrowStatus).assertEqual(0)
        expect(settled?.status).assertEqual(4); expect(settled?.escrowStatus).assertEqual(1)
        console.info('[BoundaryFlow] PASS rejected refunds restore actual unsettled/settled server states')
      } finally {
        await saveAppearanceSettings(ability.context, mode, scale, 'auto')
        logout()
      }
    })

    it('accounts_do_not_share_address_cart_or_orders', 0, async () => {
      const fixture: BoundaryFixtures = (JSON.parse(BuildProfile.QUICK_LOGIN_CONFIG) as BoundaryConfig).fixtures
      const driver: Driver = Driver.create(); await launchAppUnderTest(driver)
      const ability: UIAbility = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility()
      const context: UIContext = (await window.getLastWindow(ability.context)).getUIContext()
      await signIn(context, driver, UserRole.CUSTOMER, 'AddressListPage')
      await clearCartApi(); await addCartItemApi(fixture.goodsId, 0, 1); await syncCartRemote(); await syncAddressesRemote()
      expect((AppStorage.get<CartItem[]>('cartItems') ?? []).length > 0).assertTrue()
      expect((AppStorage.get<Address[]>('addressList') ?? []).some((a: Address) => a.name === fixture.accountAName)).assertTrue()
      const before: Order[] = await fetchUserOrdersApi() ?? []; expect(before.length > 0).assertTrue()
      await signIn(context, driver, UserRole.CUSTOMER, 'AddressListPage', fixture.alternateAccount)
      await syncAddressesRemote(); await syncCartRemote()
      expect((AppStorage.get<Address[]>('addressList') ?? []).every((a: Address) => a.name === fixture.accountBName)).assertTrue()
      expect((AppStorage.get<Address[]>('addressList') ?? []).length).assertEqual(1)
      expect((AppStorage.get<CartItem[]>('cartItems') ?? []).length).assertEqual(0)
      expect((await fetchUserOrdersApi() ?? []).length).assertEqual(0)
      expect(isFound(await driver.findComponent(ON.text(fixture.accountAName)))).assertFalse()
      expect(await driver.screenCap(ability.context.filesDir + '/boundary/account-b.png')).assertTrue()
      await signIn(context, driver, UserRole.CUSTOMER, 'AddressListPage')
      await syncCartRemote(); await syncAddressesRemote()
      expect((AppStorage.get<CartItem[]>('cartItems') ?? []).length > 0).assertTrue()
      expect((AppStorage.get<Address[]>('addressList') ?? []).some((a: Address) => a.name === fixture.accountAName)).assertTrue()
      expect(isFound(await driver.findComponent(ON.text(fixture.accountBName)))).assertFalse()
      expect(await driver.screenCap(ability.context.filesDir + '/boundary/account-a-restored.png')).assertTrue()
      console.info('[BoundaryFlow] PASS A/B/A account address/cart/order isolation')
      logout()
    })

    it('disconnected_reads_retry_and_lost_create_response_reuses_the_order', 0, async () => {
      const fixture: BoundaryFixtures = (JSON.parse(BuildProfile.QUICK_LOGIN_CONFIG) as BoundaryConfig).fixtures
      const driver: Driver = Driver.create(); await launchAppUnderTest(driver)
      const ability: UIAbility = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility()
      const context: UIContext = (await window.getLastWindow(ability.context)).getUIContext()
      try {
        await signIn(context, driver, UserRole.ADMIN, 'AdminCenterPage')
        await control(fixture, 'offline')
        await navigate(context, driver, 'AdminRefundPage')
        requireComponent(await driver.waitForComponent(ON.id('admin-refund-retry'), 25000), 'offline retry')
        expect(await driver.screenCap(ability.context.filesDir + '/boundary/offline-read.png')).assertTrue()
        await control(fixture, 'online'); await click(driver, 'admin-refund-retry'); await driver.delayMs(1500)
        expect(isFound(await driver.findComponent(ON.id('admin-refund-retry')))).assertFalse()
        expect(await driver.screenCap(ability.context.filesDir + '/boundary/reconnected-read.png')).assertTrue()
        console.info('[BoundaryFlow] PASS interrupted API connection and explicit UI read retry')
        await signIn(context, driver, UserRole.CUSTOMER, 'Index')
        await clearCartApi(); await syncCartRemote(); await syncAddressesRemote()
        const before: Order[] = await fetchUserOrdersApi() ?? []
        const balance: ApiResponse<BoundaryBalance> = await get<BoundaryBalance>('/api/auth/me')
        AppStorage.setOrCreate<number>('selectedStoreId', fixture.storeId)
        AppStorage.setOrCreate<string>('selectedStoreName', fixture.storeName)
        await navigate(context, driver, 'StoreDetailPage')
        await click(driver, 'goods-plus-' + fixture.goodsId); await click(driver, 'store-checkout')
        requireComponent(await driver.waitForComponent(ON.id('checkout-submit'), 8000), 'checkout')
        await control(fixture, 'lose-order-response'); await click(driver, 'checkout-submit')
        const reconcile = await driver.waitForComponent(ON.text('按原信息核对提交结果'), 12000)
        if (isFound(reconcile)) {
          expect(await driver.screenCap(ability.context.filesDir + '/boundary/lost-order-response.png')).assertTrue()
          await requireComponent(reconcile, 'reconcile original intent').click()
        }
        requireComponent(await driver.waitForComponent(ON.id('order-detail-status'), 15000), 'reconciled order')
        const created: number = AppStorage.get<number>('currentOrderId') ?? 0
        const after: Order[] = await fetchUserOrdersApi() ?? []
        const current: ApiResponse<BoundaryBalance> = await get<BoundaryBalance>('/api/auth/me')
        expect(after.length).assertEqual(before.length + 1)
        expect(after.filter((o: Order) => o.id === created).length).assertEqual(1)
        expect(current.data?.balance).assertEqual(balance.data?.balance)
        expect((await fetchOrderDetailApi(created))?.status).assertEqual(0)
        expect(await driver.screenCap(ability.context.filesDir + '/boundary/reconciled-single-order.png')).assertTrue()
        expect(await cancelOrderApi(created)).assertTrue()
        console.info('[BoundaryFlow] PASS committed create response lost, original intent reconciled; one order, no debit')
      } finally { await control(fixture, 'online'); logout() }
    })
  })
}

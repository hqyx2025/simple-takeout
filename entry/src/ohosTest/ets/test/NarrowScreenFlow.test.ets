import { describe, it, expect } from '@ohos/hypium'
import { Driver, ON, Component, MatchPattern, abilityDelegatorRegistry } from '@kit.TestKit'
import { UIAbility } from '@kit.AbilityKit'
import { window, UIContext } from '@kit.ArkUI'
import { fileIo } from '@kit.CoreFileKit'
import http from '@ohos.net.http'
import BuildProfile from 'BuildProfile'
import { launchAppUnderTest, requireComponent, isFound, scrollUntilVisible } from './UiTestHelper'
import { loginRemote, logout } from '../../../main/ets/service/AppStorageManager'
import { getQuickLoginAccount, QuickLoginAccount } from '../../../main/ets/common/QuickLoginConfig'
import { get, post, getApiBaseUrl, getLastApiErrorMessage, ApiResponse } from '../../../main/ets/service/HttpClient'
import { cancelOrderApi } from '../../../main/ets/service/ApiService'
import { saveAppearanceSettings } from '../../../main/ets/service/AppearanceSettings'
import { ServerAddress, ServerOrder, ServerRiderPoolSlice, CreateOrderRequest } from '../../../main/ets/model/server/Contracts'
import { UserRole } from '../../../main/ets/model/Models'

interface NarrowFixtures { storeId: number; goodsId: number; narrowRefundOrderId: number; controlBaseUrl: string }
interface NarrowConfig { fixtures: NarrowFixtures }

async function controlNetwork(fixture: NarrowFixtures, command: string): Promise<void> {
  const request: http.HttpRequest = http.createHttp()
  try {
    const response: http.HttpResponse = await request.request(fixture.controlBaseUrl + '/' + command,
      { method: http.RequestMethod.GET, connectTimeout: 4000, readTimeout: 4000 })
    expect(response.responseCode).assertEqual(200)
  } finally { request.destroy() }
}

async function openOrder(context: UIContext, driver: Driver, id: number): Promise<void> {
  AppStorage.setOrCreate<number>('currentOrderId', id)
  await new Promise<void>((resolve, reject) => {
    context.runScopedTask((): void => {
      context.getRouter().replaceUrl({ url: 'pages/OrderDetailPage' }).then(() => { resolve() })
        .catch(() => { reject(new Error('Order route failed')) })
    })
  })
  await driver.delayMs(1600)
}

async function clearInputFocus(context: UIContext, driver: Driver): Promise<void> {
  context.runScopedTask((): void => { context.getFocusController().clearFocus() })
  await driver.delayMs(700)
}

async function visibleAboveKeyboard(driver: Driver, appWindow: window.Window, id: string): Promise<void> {
  console.info('[NarrowScreenFlow] keyboard mode ' + appWindow.getUIContext().getKeyboardAvoidMode() + ' checking ' + id)
  const component: Component = requireComponent(await driver.findComponent(ON.id(id)), id)
  const bounds = await component.getBounds()
  const size = await driver.getDisplaySize()
  const keyboard: window.Rect = appWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_KEYBOARD).bottomRect
  expect(keyboard.height > 0).assertTrue()
  const keyboardTop: number = keyboard.top
  console.info('[NarrowScreenFlow] bounds ' + id + ' ' + JSON.stringify(bounds) + ' keyboard=' + JSON.stringify(keyboard))
  expect(bounds.left >= 0 && bounds.right <= size.x && bounds.top >= 0 && bounds.bottom <= keyboardTop).assertTrue()
  expect(bounds.right > bounds.left && bounds.bottom > bounds.top).assertTrue()
}

export default function narrowScreenFlowTest(): void {
  // 隔离夹具：narrowRefundOrderId 必须属于测试顾客，已送达且允许售后；订单池至少 61 条。
  describe('NarrowScreenFlow', () => {
    it('narrow_light_dark_large_text_payment_refund_and_network_recovery', 0, async () => {
      expect(BuildProfile.UI_TEST_BASE_URL.startsWith('http://10.0.2.2:')).assertTrue()
      const fixture: NarrowFixtures = (JSON.parse(BuildProfile.QUICK_LOGIN_CONFIG) as NarrowConfig).fixtures
      const driver: Driver = Driver.create()
      await launchAppUnderTest(driver)
      const consent = await driver.findComponent(ON.id('privacy-accept'))
      if (isFound(consent)) { await requireComponent(consent, 'privacy').click(); await driver.delayMs(1200) }
      const ability: UIAbility = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility()
      const appWindow: window.Window = await window.getLastWindow(ability.context)
      const context: UIContext = appWindow.getUIContext()
      const display = await driver.getDisplaySize()
      console.info('[NarrowScreenFlow] display ' + JSON.stringify(display))
      expect(display.x < display.y).assertTrue()
      console.info('[NarrowScreenFlow] width vp ' + context.px2vp(display.x))
      expect(context.px2vp(display.x) <= 360).assertTrue()
      const directory: string = ability.context.filesDir + '/narrow'
      try { fileIo.mkdirSync(directory) } catch (_) {}
      const mode: string = AppStorage.get<string>('appearanceColorMode') ?? 'system'
      const scale: number = AppStorage.get<number>('appearanceFontScale') ?? 1
      let orderId: number = 0
      try {
        await controlNetwork(fixture, 'online')
        logout()
        const account: QuickLoginAccount | undefined = getQuickLoginAccount(UserRole.CUSTOMER, getApiBaseUrl())
        if (account === undefined) { throw new Error('Missing isolated customer') }
        expect((await loginRemote(account.phone, account.password, 'USER'))?.role).assertEqual(UserRole.CUSTOMER)
        const addresses: ApiResponse<ServerAddress[]> = await get<ServerAddress[]>('/api/addresses')
        expect(addresses.code).assertEqual(200)
        const request: CreateOrderRequest = {
          storeId: fixture.storeId, addressId: addresses.data[0].id, couponId: 0, remark: '隔离窄屏验证',
          items: [{ goodsId: fixture.goodsId, goodsName: '', price: 0, quantity: 1, image: '', specId: 0, specName: '' }],
          checkoutGoodsIds: [], expectTime: '', idempotencyKey: 'narrow-' + Date.now().toString(), deliveryType: 'DELIVERY', setmeals: []
        }
        const created: ApiResponse<ServerOrder> = await post<ServerOrder>('/api/orders', request)
        expect(created.code).assertEqual(200)
        orderId = created.data.id
        for (const variant of ['light', 'dark', 'light-large', 'dark-large']) {
          await saveAppearanceSettings(ability.context, variant.startsWith('dark') ? 'dark' : 'light', variant.endsWith('large') ? 1.3 : 1, 'center')
          await openOrder(context, driver, orderId)
          const password: Component = requireComponent(await driver.waitForComponent(ON.id('order-payment-password'), 8000), 'payment password')
          await password.click(); await password.inputText('123456'); await driver.delayMs(1200)
          await visibleAboveKeyboard(driver, appWindow, 'order-payment-password')
          await visibleAboveKeyboard(driver, appWindow, 'order-pay')
          await visibleAboveKeyboard(driver, appWindow, 'order-cancel')
          expect(await driver.screenCap(directory + '/' + variant + '-payment-keyboard.png')).assertTrue()
          await clearInputFocus(context, driver)
          await openOrder(context, driver, fixture.narrowRefundOrderId)
          expect(await driver.screenCap(directory + '/' + variant + '-refund-entry.png')).assertTrue()
          await requireComponent(await scrollUntilVisible(driver, 'order-refund-entry'), 'refund entry').click()
          await requireComponent(await driver.waitForComponent(ON.id('order-refund-amount'), 5000), 'refund amount').click()
          await driver.delayMs(1200)
          expect(await driver.screenCap(directory + '/' + variant + '-refund-keyboard-before-bounds.png')).assertTrue()
          await visibleAboveKeyboard(driver, appWindow, 'order-refund-amount')
          await visibleAboveKeyboard(driver, appWindow, 'order-refund-submit')
          await visibleAboveKeyboard(driver, appWindow, 'order-refund-cancel')
          expect(await driver.screenCap(directory + '/' + variant + '-refund-amount-keyboard.png')).assertTrue()
          await clearInputFocus(context, driver)
          await requireComponent(await scrollUntilVisible(driver, 'order-refund-reason-OTHER'), 'other reason').click()
          const note: Component = requireComponent(await scrollUntilVisible(driver, 'order-refund-note'), 'refund note')
          await note.click(); await note.inputText('隔离窄屏补充说明'); await driver.delayMs(1200)
          await visibleAboveKeyboard(driver, appWindow, 'order-refund-note')
          await visibleAboveKeyboard(driver, appWindow, 'order-refund-submit')
          expect(await driver.screenCap(directory + '/' + variant + '-refund-note-keyboard.png')).assertTrue()
          await clearInputFocus(context, driver)
          await requireComponent(await driver.findComponent(ON.id('order-refund-close')), 'refund close').click()
          console.info('[NarrowScreenFlow] PASS ' + variant + ' payment/refund keyboards and fixed actions')
        }
        for (let cycle: number = 0; cycle < 3; cycle++) {
          await controlNetwork(fixture, 'offline')
          const offline: ApiResponse<ServerAddress[]> = await get<ServerAddress[]>('/api/addresses', false)
          expect(offline.code).assertEqual(500)
          expect(offline.message).assertEqual('网络连接暂不可用，请检查网络后重试')
          expect(getLastApiErrorMessage()).assertEqual(offline.message)
          await controlNetwork(fixture, 'online')
          expect((await get<ServerAddress[]>('/api/addresses', false)).code).assertEqual(200)
          expect(getLastApiErrorMessage()).assertEqual('')
        }
        console.info('[NarrowScreenFlow] PASS 3 TCP disconnect/reconnect cycles and shared network error copy; no physical Wi-Fi switch')
      } finally {
        await controlNetwork(fixture, 'online')
        if (orderId > 0) { await cancelOrderApi(orderId) }
        await saveAppearanceSettings(ability.context, mode, scale, 'auto')
        logout()
      }
    })

    it('rider_pool_pages_retry_without_losing_loaded_orders', 0, async () => {
      expect(BuildProfile.UI_TEST_BASE_URL.startsWith('http://10.0.2.2:')).assertTrue()
      const fixture: NarrowFixtures = (JSON.parse(BuildProfile.QUICK_LOGIN_CONFIG) as NarrowConfig).fixtures
      const driver: Driver = Driver.create()
      await launchAppUnderTest(driver)
      const consent = await driver.findComponent(ON.id('privacy-accept'))
      if (isFound(consent)) { await requireComponent(consent, 'privacy').click(); await driver.delayMs(1200) }
      const ability: UIAbility = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility()
      const context: UIContext = (await window.getLastWindow(ability.context)).getUIContext()
      try { fileIo.mkdirSync(ability.context.filesDir + '/narrow') } catch (_) {}
      try {
        await controlNetwork(fixture, 'online')
        logout()
        const account: QuickLoginAccount | undefined = getQuickLoginAccount(UserRole.RIDER, getApiBaseUrl())
        if (account === undefined) { throw new Error('Missing isolated rider') }
        expect((await loginRemote(account.phone, account.password, 'RIDER'))?.role).assertEqual(UserRole.RIDER)
        const first: ApiResponse<ServerRiderPoolSlice> = await get<ServerRiderPoolSlice>('/api/rider/orders/pool/next?pageSize=30')
        const second: ApiResponse<ServerRiderPoolSlice> = await get<ServerRiderPoolSlice>(
          '/api/rider/orders/pool/next?afterId=' + first.data.nextAfterId + '&pageSize=30')
        expect(first.data.list.length).assertEqual(30)
        expect(second.data.list.length).assertEqual(30)
        expect(first.data.hasMore && second.data.hasMore).assertTrue()
        expect(first.data.list.every((a: ServerOrder) => second.data.list.every((b: ServerOrder) => a.id !== b.id))).assertTrue()
        await new Promise<void>((resolve, reject) => {
          context.runScopedTask((): void => {
            context.getRouter().replaceUrl({ url: 'pages/RiderOrderPoolPage' }).then(() => { resolve() })
              .catch(() => { reject(new Error('Pool route failed')) })
          })
        })
        await driver.delayMs(1600)
        requireComponent(await driver.waitForComponent(ON.id('rider-pool-card-' + first.data.list[0].id), 8000), 'first pool order')
        expect((await post<ServerOrder>('/api/rider/orders/' + first.data.nextAfterId + '/grab')).code).assertEqual(200)
        await controlNetwork(fixture, 'offline')
        await requireComponent(await driver.findComponent(ON.type('List')), 'pool list').scrollToBottom(12000)
        await requireComponent(await driver.findComponent(ON.id('rider-pool-load-more')), 'load more').click()
        requireComponent(await driver.waitForComponent(ON.text('加载失败，点击重试'), 15000), 'retry failed page')
        await controlNetwork(fixture, 'online')
        await requireComponent(await driver.findComponent(ON.id('rider-pool-load-more')), 'retry more').click()
        await driver.delayMs(1600)
        await requireComponent(await driver.findComponent(ON.type('List')), 'pool list').scrollToBottom(12000)
        expect(await driver.screenCap(ability.context.filesDir + '/narrow/pool-after-append.png')).assertTrue()
        const cards: Component[] = await driver.findComponents(ON.id('rider-pool-card-', MatchPattern.STARTS_WITH)) ?? []
        for (const card of cards) { console.info('[NarrowScreenFlow] visible pool ' + await card.getId()) }
        console.info('[NarrowScreenFlow] expected pool last ' + second.data.list[29].id)
        requireComponent(await driver.findComponent(ON.id('rider-pool-card-' + second.data.list[29].id)), 'second page last order')
        await requireComponent(await driver.findComponent(ON.type('List')), 'pool list').scrollToTop(12000)
        requireComponent(await driver.findComponent(ON.id('rider-pool-card-' + first.data.list[0].id)), 'first page preserved')
        await requireComponent(await driver.findComponent(ON.id('page-header-action')), 'refresh pool').click()
        await driver.delayMs(1600)
        requireComponent(await scrollUntilVisible(driver, 'rider-pool-card-' + first.data.list[0].id), 'refreshed first page')
        expect(await driver.screenCap(ability.context.filesDir + '/narrow/rider-pool.png')).assertTrue()
        console.info('[NarrowScreenFlow] PASS cursor pages 30+30 after anchor claimed, disjoint IDs, failed append retry, first page preserved and refresh')
        logout()
        await driver.delayMs(700)
        expect(isFound(await driver.findComponent(ON.id('rider-pool-card-' + first.data.list[0].id)))).assertFalse()
        console.info('[NarrowScreenFlow] PASS rider pool cleared immediately on logout')
      } finally { await controlNetwork(fixture, 'online'); logout() }
    })
  })
}

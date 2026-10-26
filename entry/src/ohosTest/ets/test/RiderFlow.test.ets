/**
 * 骑手端回归（设备端 UiTest）。
 *
 * 前置（由 scripts/device-role-regression.ps1 布置）：
 *   - 应用数据已清空（guest 态）；
 *   - 后端造一笔「已出餐、未分配骑手」的订单：用户下单+支付(1) → 商户接单(2) → 商户出餐完成(ready，写 ready_time)。
 *
 * 覆盖：同意隐私 → 一键登录骑手 → 骑手中心 → **上线开关**（离线→在线）→ 抢单大厅 →
 * 抢下 fixture 订单 → 我的配送单 → 取餐 → 送达。
 * host 侧核对：骑手 online=1、订单 status 2→3→4 且 rider 已分配、骑手累计配送/收入 +1。
 */
import { Driver, ON, Component } from '@kit.TestKit'
import { describe, it, expect } from '@ohos/hypium'
import { isFound, requireComponent, launchAppUnderTest, clickByIdOrText, clickComponentCenter, scrollUntilVisible, waitAny, openQuickLoginDialog } from './UiTestHelper'
import { loginRemote, fetchRiderProfileRemote, syncRiderPoolRemote, syncRiderOrdersRemote } from '../../../main/ets/service/AppStorageManager'
import { Order, Rider } from '../../../main/ets/model/Models'

/** 轮询等待组件文本变成期望值。 */
async function waitForText(driver: Driver, id: string, expected: string, timeoutMs: number): Promise<string> {
  let waited: number = 0
  let last: string = ''
  while (waited <= timeoutMs) {
    const component = await driver.findComponent(ON.id(id))
    if (component !== null && component !== undefined) {
      last = await component.getText()
      if (last === expected) {
        return last
      }
    }
    await driver.delayMs(1500)
    waited += 1500
  }
  console.info('[RiderFlow] waitForText timeout id=' + id + ' expected=' + expected + ' last=' + last)
  return last
}

async function waitForOrderAction(driver: Driver, id: string, timeoutMs: number): Promise<Component | null> {
  let waited: number = 0
  while (waited <= timeoutMs) {
    const found = await driver.findComponent(ON.id(id))
    if (found !== null && found !== undefined) {
      return found
    }
    await driver.delayMs(1000)
    waited += 1000
  }
  console.info('[RiderFlow] waiting for order action timed out id=' + id + ', searching scrollable list')
  return await scrollUntilVisible(driver, id, 12)
}

export default function riderFlowTest() {
  describe('RiderFlow', () => {
    it('RiderFlow_online_grab_pickup_deliver', 0, async () => {
      const driver: Driver = Driver.create()
      await launchAppUnderTest(driver)

      // ---------- 1. guest → 隐私同意 → 一键登录骑手 ----------
      const consent = await waitAny(driver, ['privacy-accept'], 8000)
      if (isFound(consent)) {
        console.info('[RiderFlow] consent page -> accept')
        expect(await clickByIdOrText(driver, 'privacy-accept', '同意并继续')).assertTrue()
        await driver.delayMs(3000)
      }
      await openQuickLoginDialog(driver)
      expect(await clickByIdOrText(driver, 'quick-login-rider', '一键登录骑手')).assertTrue()
      await driver.delayMs(8000)

      // 骑手中心：档案与上线开关
      const onlineStatus: Component = requireComponent(
        await scrollUntilVisible(driver, 'rider-online-status'), 'rider-online-status')
      const beforeOnline: string = await onlineStatus.getText()
      console.info('[RiderFlow] online status before toggle = ' + beforeOnline)
      expect(beforeOnline.indexOf('离线') >= 0).assertTrue()

      const toggle: Component = requireComponent(
        await scrollUntilVisible(driver, 'rider-online-toggle'), 'rider-online-toggle')
      expect(await clickComponentCenter(driver, toggle, 'rider-online-toggle')).assertTrue()
      const afterOnline: string = await waitForText(driver, 'rider-online-status', '● 在线，可抢单', 15000)
      console.info('[RiderFlow] online status after toggle = ' + afterOnline)
      expect(afterOnline.indexOf('在线') >= 0).assertTrue()

      // ---------- 2. 用应用自身数据定位 fixture 订单 ----------
      const rider: Rider | null = await fetchRiderProfileRemote()
      expect(rider !== null).assertTrue()
      const pool: Order[] = await syncRiderPoolRemote()
      let target: Order | null = null
      for (let i = 0; i < pool.length; i++) {
        const o: Order = pool[i]
        if (target === null || o.id > target.id) {
          target = o
        }
      }
      console.info('[RiderFlow] pool size=' + pool.length + ' target=' + (target === null ? 'none' : target.id.toString()))
      expect(target !== null).assertTrue()
      if (target === null) {
        return
      }
      const orderId: number = target.id

      // ---------- 3. 抢单大厅 → 抢单 ----------
      expect(await clickByIdOrText(driver, 'rider-pool-entry', '抢单大厅')).assertTrue()
      await driver.delayMs(4000)
      const grabId: string = 'rider-grab-' + orderId
      requireComponent(await scrollUntilVisible(driver, grabId), grabId)
      expect(await clickByIdOrText(driver, grabId, '抢单')).assertTrue()
      await driver.delayMs(4500)
      console.info('[RiderFlow] grabbed order ' + orderId)

      // ---------- 4. 我的配送单 → 取餐 → 送达 ----------
      // 抢单成功后大厅会直接打开我的配送单页。
      await driver.waitForIdle(800, 8000)

      const pickupId: string = 'rider-pickup-' + orderId
      const deliverId: string = 'rider-deliver-' + orderId
      requireComponent(await waitForOrderAction(driver, pickupId, 12000), pickupId)
      const readyStatus: Component = requireComponent(
        await driver.findComponent(ON.id('rider-order-status-' + orderId)), 'assigned order status')
      expect(await readyStatus.getText()).assertEqual('待取餐')
      requireComponent(await scrollUntilVisible(driver, 'rider-copy-address-' + orderId), 'copy recipient address')
      requireComponent(await scrollUntilVisible(driver, 'rider-store-location-' + orderId), 'store location entry')
      requireComponent(await scrollUntilVisible(driver, pickupId), pickupId)
      expect(await clickByIdOrText(driver, pickupId, '取餐')).assertTrue()
      await driver.waitForIdle(800, 8000)
      requireComponent(await waitForOrderAction(driver, deliverId, 12000), deliverId)
      expect(await clickByIdOrText(driver, deliverId, '送达')).assertTrue()
      requireComponent(await waitAny(driver, ['rider-deliver-confirm-dialog'], 5000), 'delivery confirmation')
      expect(await clickByIdOrText(driver, '', '尚未交付')).assertTrue()
      const afterCancel: Order[] = await syncRiderOrdersRemote()
      const stillDelivering: Order | undefined = afterCancel.find((order: Order) => order.id === orderId)
      expect(stillDelivering?.status).assertEqual(3)
      requireComponent(await waitForOrderAction(driver, deliverId, 12000), deliverId)
      expect(await clickByIdOrText(driver, deliverId, '送达')).assertTrue()
      expect(await clickByIdOrText(driver, '', '确认已交付')).assertTrue()
      await driver.delayMs(5000)

      const mine: Order[] = await syncRiderOrdersRemote()
      let delivered: Order | null = null
      for (let i = 0; i < mine.length; i++) {
        if (mine[i].id === orderId) {
          delivered = mine[i]
        }
      }
      console.info('[RiderFlow] order ' + orderId + ' status after deliver = ' + (delivered === null ? 'not-found' : delivered.status.toString()))
      expect(delivered !== null).assertTrue()
      expect(delivered?.status).assertEqual(4)
      requireComponent(await scrollUntilVisible(driver, 'rider-contact-hidden-' + orderId), 'recipient hidden after delivery')
      expect(isFound(await driver.findComponent(ON.id('rider-contact-' + orderId)))).assertFalse()
    })
  })
}

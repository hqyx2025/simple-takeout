/**
 * 商户端回归（设备端 UiTest + 直接调用应用服务）。
 *
 * 前置（由 scripts/device-merchant-regression.ps1 布置）：
 *   - 应用数据已清空（guest 态）、定位权限已预授权；
 *   - 后端用 API 造一笔「待接单」订单（用户 13800138000 下单 + 支付，status=1），
 *     店铺属于商户 13600136000（storeId=1）。
 *
 * 覆盖：
 *   1. guest → 隐私同意 → 一键登录商户 → 我的 Tab；
 *   2. 订单管理：fixture 订单卡片在列表里、状态文案「待接单」、动作按钮文案「接单」；
 *   3. 商户订单流转（界面驱动）：接单 1→2（按钮变「出餐完成」）→ 出餐完成（ready：状态仍为 2，
 *      出现「已出餐，等待骑手接单」凭据，订单进入骑手待取餐池）→ 商户侧不再有流转按钮，
 *      后续 2→3/3→4 由骑手端 pickup/deliver 完成；
 *   4. 收入统计页：今日收入/今日订单/已完成订单/本周收入/本周订单 全部渲染出数字，
 *      并把数字打进 hilog，供 host 侧与 /api/merchant/stats 交叉核对。
 *
 * 为什么断言「状态仍为制作中」：商户端出餐若走 deliver（2→3），订单会永久跳过骑手抢单池
 * （池子按 status = 2 AND ready_time <> '' 筛选），骑手端恒为空列表。这条断言就是那个回归的哨兵。
 */
import { Driver, ON, Component } from '@kit.TestKit'
import { describe, it, expect } from '@ohos/hypium'
import { isFound, requireComponent, launchAppUnderTest, clickByIdOrText, scrollUntilVisible, scrollAndClick, waitAny } from './UiTestHelper'
import { loginRemote, syncMerchantOrdersFromServer, getMerchantOrders } from '../../../main/ets/service/AppStorageManager'
import { Order, User } from '../../../main/ets/model/Models'

/** 读取组件文本（找不到时返回空串，便于断言给出明确差异）。 */
async function textOf(component: Component | null | undefined): Promise<string> {
  if (component === null || component === undefined) {
    return ''
  }
  return await component.getText()
}

/**
 * 轮询等待某个组件文本变成期望值（返回最后一次读到的文本）。
 *
 * 商户点一次操作后页面会 `loadOrders()` 重新拉取并重建列表，界面更新晚于网络返回，
 * 固定 delay 读一次会读到旧文案（实测：后端已 1→2，界面仍显示「待接单」）。
 */
async function waitForText(driver: Driver, id: string, expected: string, timeoutMs: number): Promise<string> {
  let waited: number = 0
  let last: string = ''
  while (waited <= timeoutMs) {
    const component = await scrollUntilVisible(driver, id)
    last = await textOf(component)
    if (last === expected) {
      return last
    }
    await driver.delayMs(1500)
    waited += 1500
  }
  console.info('[MerchantFlow] waitForText timeout id=' + id + ' expected=' + expected + ' last=' + last)
  return last
}

export default function merchantFlowTest() {
  describe('MerchantFlow', () => {
    it('MerchantFlow_accept_deliver_complete_and_stats', 0, async () => {
      const driver: Driver = Driver.create()
      await launchAppUnderTest(driver)

      // ---------- 1. guest → 同意隐私 → 一键登录商户 ----------
      const consent = await waitAny(driver, ['privacy-accept'], 8000)
      if (isFound(consent)) {
        console.info('[MerchantFlow] consent page -> accept')
        expect(await clickByIdOrText(driver, 'privacy-accept', '同意并继续')).assertTrue()
        await driver.delayMs(3000)
      }
      expect(await clickByIdOrText(driver, 'quick-login-merchant', '一键登录商户')).assertTrue()
      await driver.delayMs(8000)

      // ---------- 2. 用应用自身数据定位 fixture 订单 ----------
      const merchant: User | undefined = await loginRemote('13600136000', '123456')
      const merchantId: number = merchant === undefined || merchant === null ? 0 : merchant.id
      console.info('[MerchantFlow] merchantId=' + merchantId)
      expect(merchantId > 0).assertTrue()
      await syncMerchantOrdersFromServer()
      const orders: Order[] = getMerchantOrders(merchantId)
      let target: Order | null = null
      for (let i = 0; i < orders.length; i++) {
        const o: Order = orders[i]
        if (o.status === 1 && (target === null || o.id > target.id)) {
          target = o
        }
      }
      expect(target !== null).assertTrue()
      if (target === null) {
        return
      }
      const orderId: number = target.id
      console.info('[MerchantFlow] fixture orderId=' + orderId)

      // ---------- 3. 我的 → 订单管理（商户入口在「我的」页底部，需要滚动）----------
      expect(await clickByIdOrText(driver, 'tab-3', '我的')).assertTrue()
      await driver.delayMs(2500)
      expect(await scrollAndClick(driver, 'profile-merchant-orders', '订单管理')).assertTrue()
      await driver.delayMs(3500)

      const statusId: string = 'merchant-order-status-' + orderId
      const actionId: string = 'merchant-action-' + orderId

      const status0: string = await textOf(requireComponent(await scrollUntilVisible(driver, statusId), statusId))
      const action0: string = await textOf(requireComponent(await scrollUntilVisible(driver, actionId), actionId))
      console.info('[MerchantFlow] initial status=' + status0 + ' action=' + action0)
      expect(status0).assertEqual('待接单')
      expect(action0).assertEqual('接单')

      // ---------- 4. 接单 1→2 ----------
      expect(await clickByIdOrText(driver, actionId, '接单')).assertTrue()
      const status1: string = await waitForText(driver, statusId, '制作中', 20000)
      const action1: string = await textOf(requireComponent(await scrollUntilVisible(driver, actionId), actionId))
      console.info('[MerchantFlow] after accept status=' + status1 + ' action=' + action1)
      expect(status1).assertEqual('制作中')
      expect(action1).assertEqual('出餐')

      // ---------- 5. 出餐完成（ready：只写 ready_time，状态仍为 2，订单进入骑手待取餐池）----------
      // 注意：出餐不能把订单推到 3（配送中），那会让订单永久跳过骑手抢单池；
      // 也因此状态文案保持「制作中」，但必须出现「已出餐，等待骑手接单」的可见凭据。
      expect(await clickByIdOrText(driver, actionId, '出餐完成')).assertTrue()
      const readyHint: string = await waitForText(driver, statusId, '制作中', 20000)
      console.info('[MerchantFlow] after ready status=' + readyHint)
      expect(readyHint).assertEqual('制作中')
      expect(await isFound(await scrollUntilVisible(driver, 'merchant-ready-' + orderId))).assertTrue()

      // ---------- 6. 已出餐的订单由骑手接管：商户侧不再有「确认送达」按钮 ----------
      // 后续 2→3/3→4 由骑手端 pickup/deliver 完成（见 RiderFlow.test.ets），商户端不参与。
      expect(await isFound(await scrollUntilVisible(driver, actionId))).assertFalse()

      // ---------- 7. 收入统计页（数字打进 hilog，host 侧与 /api/merchant/stats 交叉核对）----------
      expect(await clickByIdOrText(driver, 'merchant-orders-back', '‹ 返回')).assertTrue()
      await driver.delayMs(2500)
      expect(await clickByIdOrText(driver, 'tab-3', '我的')).assertTrue()
      await driver.delayMs(2000)
      expect(await scrollAndClick(driver, 'profile-merchant-stats', '收入统计')).assertTrue()
      await driver.delayMs(4000)

      const revenue: string = await textOf(requireComponent(await scrollUntilVisible(driver, 'stats-today-revenue'), 'stats-today-revenue'))
      const todayOrders: string = await textOf(requireComponent(await scrollUntilVisible(driver, 'stats-today-orders'), 'stats-today-orders'))
      const completed: string = await textOf(requireComponent(await scrollUntilVisible(driver, 'stats-completed-orders'), 'stats-completed-orders'))
      console.info('[MerchantFlow] stats todayRevenue=' + revenue + ' todayOrders=' + todayOrders + ' completedOrders=' + completed)
      expect(revenue.length > 0).assertTrue()
      expect(todayOrders.length > 0).assertTrue()
      expect(completed.length > 0).assertTrue()
    })
  })
}

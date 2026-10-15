/** 前置：未安装支付宝，首笔待付款订单是 host 创建的“Mobile payment UI regression”测试单。 */
import { Driver, ON, Component, MatchPattern } from '@kit.TestKit'
import { describe, it, expect } from '@ohos/hypium'
import { Order } from '../../../main/ets/model/Models'
import { cancelOrderApi, fetchOrderDetailApi } from '../../../main/ets/service/ApiService'
import { launchAppUnderTest, clickByIdOrText, requireComponent, scrollUntilVisible, isFound } from './UiTestHelper'

export default function orderMobilePaymentTest(): void {
  describe('OrderMobilePayment', () => {
    it('uninstalled_alipay_requires_explicit_qr_and_polls_terminal_state', 0, async () => {
      const driver: Driver = Driver.create()
      await launchAppUnderTest(driver)
      expect(await clickByIdOrText(driver, 'tab-3', '我的')).assertTrue()
      requireComponent(await driver.waitForComponent(ON.text('待付款'), 8000), 'pending orders entry')
      expect(await clickByIdOrText(driver, '待付款', '待付款')).assertTrue()
      requireComponent(await driver.waitForComponent(ON.id('order-list-back'), 8000), 'pending list')
      let firstCardId: string = ''
      for (let attempt: number = 0; attempt < 10; attempt++) {
        const cards: Component[] = await driver.findComponents(ON.id('order-card-', MatchPattern.STARTS_WITH))
        if (cards !== null && cards !== undefined && cards.length > 0) {
          firstCardId = await cards[0].getId()
          break
        }
        await driver.delayMs(1000)
      }
      expect(firstCardId !== '').assertTrue()
      const orderId: number = Number(firstCardId.replace('order-card-', ''))
      const fixture: Order | null = await fetchOrderDetailApi(orderId)
      expect(fixture !== null && fixture.remark === 'Mobile payment UI regression').assertTrue()
      if (fixture === null || fixture.remark !== 'Mobile payment UI regression') {
        throw new Error('Test fixture missing; no customer order will be modified')
      }
      try {
        await requireComponent(await driver.findComponent(ON.id(firstCardId)), 'pending fixture').click()
        requireComponent(await driver.waitForComponent(ON.id('order-pay'), 8000), 'pay button')
        expect(await clickByIdOrText(driver, 'order-pay-channel-ALIPAY', '支付宝')).assertTrue()
        expect(await clickByIdOrText(driver, 'order-pay', '')).assertTrue()
        const fallback: Component = requireComponent(await scrollUntilVisible(driver, 'order-scan-other-device'), 'other-device payment choice')
        expect(isFound(await driver.findComponent(ON.id('order-payment-qrcode')))).assertFalse()
        await fallback.click()
        requireComponent(await driver.waitForComponent(ON.id('order-payment-qrcode'), 15000), 'explicit payment QR')
        requireComponent(await scrollUntilVisible(driver, 'order-refresh-payment'), 'manual refresh')
        expect(await clickByIdOrText(driver, 'order-refresh-payment', '刷新支付状态')).assertTrue()
        await driver.delayMs(7000)
        expect(isFound(await driver.findComponent(ON.id('order-payment-qrcode')))).assertTrue()
        expect(await cancelOrderApi(orderId)).assertTrue()
        await driver.delayMs(7000)
        expect(isFound(await driver.findComponent(ON.id('order-payment-qrcode')))).assertFalse()
        expect(isFound(await driver.findComponent(ON.id('order-pay')))).assertFalse()
        const cancelled: Order | null = await fetchOrderDetailApi(orderId)
        expect(cancelled !== null && cancelled.status === 5).assertTrue()
        console.info('[OrderMobilePayment] explicit QR, manual refresh and automatic terminal-state refresh passed')
      } finally {
        const latest: Order | null = await fetchOrderDetailApi(orderId)
        if (latest !== null && latest.status === 0) { await cancelOrderApi(orderId) }
      }
    })
  })
}

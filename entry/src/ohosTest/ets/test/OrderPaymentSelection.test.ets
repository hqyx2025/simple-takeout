/**
 * 前置：主应用已登录用户，真实服务中至少有一笔未支付的 DELIVERY 订单。
 * 仅选择渠道并检查配送信息，不点击支付按钮、不修改订单或余额。
 */
import { Driver, ON, Component, MatchPattern } from '@kit.TestKit'
import { describe, it, expect } from '@ohos/hypium'
import { launchAppUnderTest, clickByIdOrText, requireComponent, scrollToIdOrText } from './UiTestHelper'

export default function orderPaymentSelectionTest() {
  describe('OrderPaymentSelection', () => {
    it('OrderPaymentSelection_channel_and_recipient_labels', 0, async () => {
      const driver: Driver = Driver.create()
      await launchAppUnderTest(driver)
      expect(await clickByIdOrText(driver, 'tab-3', '我的')).assertTrue()
      requireComponent(await driver.waitForComponent(ON.text('待付款'), 8000), 'profile pending orders')
      expect(await clickByIdOrText(driver, '待付款', '待付款')).assertTrue()
      requireComponent(await driver.waitForComponent(ON.id('order-list-back'), 8000), 'pending order list')

      let cards: Component[] = []
      for (let attempt: number = 0; attempt < 10; attempt++) {
        const visible: Component[] = await driver.findComponents(ON.id('order-card-', MatchPattern.STARTS_WITH))
        if (visible !== null && visible !== undefined && visible.length > 0) {
          cards = visible
          break
        }
        await driver.delayMs(1000)
      }
      expect(cards.length > 0).assertTrue()
      if (cards.length === 0) {
        throw new Error('OrderPaymentSelection requires a pending DELIVERY order')
      }
      const cardId: string = await cards[0].getId()
      console.info('[OrderPaymentSelection] open pending order ' + cardId)
      await requireComponent(await driver.findComponent(ON.id(cardId)), cardId).click()
      requireComponent(await driver.waitForComponent(ON.id('order-pay'), 8000), 'order pay button')
      expect(await requireComponent(await driver.findComponent(ON.id('order-pay')), 'order pay button').isEnabled()).assertTrue()

      expect(await clickByIdOrText(driver, 'order-pay-channel-ALIPAY', '支付宝')).assertTrue()
      expect(await requireComponent(await driver.findComponent(ON.id('order-pay-channel-ALIPAY')), 'alipay channel').isSelected()).assertTrue()
      expect(await requireComponent(await driver.findComponent(ON.id('order-pay-channel-BALANCE')), 'balance channel').isSelected()).assertFalse()
      const alipayButton: string = await requireComponent(await driver.findComponent(ON.id('order-pay')), 'alipay pay button').getText()
      expect(alipayButton.startsWith('使用支付宝支付 ¥')).assertTrue()

      expect(await clickByIdOrText(driver, 'order-pay-channel-BALANCE', '余额支付')).assertTrue()
      expect(await requireComponent(await driver.findComponent(ON.id('order-pay-channel-BALANCE')), 'balance channel').isSelected()).assertTrue()
      expect(await requireComponent(await driver.findComponent(ON.id('order-pay-channel-ALIPAY')), 'alipay channel').isSelected()).assertFalse()
      const balanceButton: string = await requireComponent(await driver.findComponent(ON.id('order-pay')), 'balance pay button').getText()
      expect(balanceButton.startsWith('使用余额支付 ¥')).assertTrue()

      const body: Component = requireComponent(await driver.findComponent(ON.type('Scroll')), 'order detail scroll')
      requireComponent(await body.scrollSearch(ON.text('收货人')), 'recipient label')
      const pendingRider: Component = requireComponent(await scrollToIdOrText(driver, 'order-rider-pending', ''), 'pending rider status')
      expect(await pendingRider.getText()).assertEqual('支付后等待接单')
      console.info('[OrderPaymentSelection] selected channels and recipient/rider labels passed; no payment sent')
    })
  })
}

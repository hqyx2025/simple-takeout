/** 前置：用户已登录且购物车有商品；核对当前只承诺立即配送，不提交订单。 */
import { Driver, ON, Component } from '@kit.TestKit'
import { describe, it, expect } from '@ohos/hypium'
import { isFound, launchAppUnderTest, clickByIdOrText, requireComponent, scrollUntilVisible } from './UiTestHelper'

export default function checkoutDeliveryTimeTest(): void {
  describe('CheckoutDeliveryTime', () => {
    it('checkout_only_exposes_immediate_delivery', 0, async () => {
      const driver: Driver = Driver.create()
      await launchAppUnderTest(driver)
      expect(await clickByIdOrText(driver, 'tab-2', '购物车')).assertTrue()
      requireComponent(await driver.waitForComponent(ON.id('cart-checkout'), 10000), 'cart checkout')
      expect(await clickByIdOrText(driver, 'cart-checkout', '去结算')).assertTrue()
      const immediate: Component = requireComponent(
        await scrollUntilVisible(driver, 'checkout-delivery-immediate'), 'immediate delivery')
      expect(await immediate.getText()).assertEqual('立即送达')
      const policy: Component = requireComponent(
        await driver.findComponent(ON.id('checkout-delivery-policy')), 'immediate delivery policy')
      expect(await policy.getText()).assertEqual('当前仅支持立即配送')
      expect(isFound(await driver.findComponent(ON.id('checkout-delivery-custom')))).assertFalse()
      expect(isFound(await driver.findComponent(ON.id('checkout-delivery-1')))).assertFalse()
      requireComponent(await driver.findComponent(ON.id('checkout-submit')), 'submit remains accessible')
    })
  })
}

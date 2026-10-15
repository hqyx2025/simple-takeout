/** 前置：用户已登录且购物车有商品；只选择送达时间，不提交订单。 */
import { Driver, ON, Component } from '@kit.TestKit'
import { describe, it, expect } from '@ohos/hypium'
import { launchAppUnderTest, clickByIdOrText, requireComponent, scrollUntilVisible } from './UiTestHelper'

export default function checkoutDeliveryTimeTest(): void {
  describe('CheckoutDeliveryTime', () => {
    it('calendar_time_selection_and_cancel_preserve_choice', 0, async () => {
      const driver: Driver = Driver.create()
      await launchAppUnderTest(driver)
      expect(await clickByIdOrText(driver, 'tab-2', '购物车')).assertTrue()
      requireComponent(await driver.waitForComponent(ON.id('cart-checkout'), 10000), 'cart checkout')
      expect(await clickByIdOrText(driver, 'cart-checkout', '去结算')).assertTrue()
      const custom: Component = requireComponent(await scrollUntilVisible(driver, 'checkout-delivery-custom'), 'custom delivery time')
      await custom.click()
      const calendar: Component = requireComponent(await driver.waitForComponent(ON.type('Calendar'), 8000), 'calendar grid')
      expect(await calendar.isEnabled()).assertTrue()
      expect(await clickByIdOrText(driver, '确定', '确定')).assertTrue()
      requireComponent(await driver.waitForComponent(ON.type('TimePicker'), 8000), 'delivery clock picker')
      expect(await clickByIdOrText(driver, '确定', '确定')).assertTrue()
      await driver.delayMs(1000)
      await driver.waitForIdle(500, 5000)
      const chosen: Component = requireComponent(await driver.waitForComponent(ON.id('checkout-delivery-selected-time'), 8000), 'chosen delivery time')
      const before: string = await chosen.getText()
      expect(before.startsWith('预约送达：')).assertTrue()
      expect(before.length > 18).assertTrue()
      expect(await clickByIdOrText(driver, 'checkout-delivery-custom', '自选时间')).assertTrue()
      requireComponent(await driver.waitForComponent(ON.type('Calendar'), 8000), 'reopened calendar')
      expect(await clickByIdOrText(driver, '取消', '取消')).assertTrue()
      await driver.delayMs(1000)
      const preserved: Component = requireComponent(await driver.findComponent(ON.id('checkout-delivery-selected-time')), 'preserved delivery time')
      expect(await preserved.getText()).assertEqual(before)
      expect(await clickByIdOrText(driver, 'checkout-delivery-0', '立即送达')).assertTrue()
      await driver.delayMs(500)
      const presetIds: string[] = ['checkout-delivery-0', 'checkout-delivery-1', 'checkout-delivery-2', 'checkout-delivery-3', 'checkout-delivery-4']
      const presetLabels: string[] = ['立即送达', '半小时后', '1小时后', '2小时后', '5小时后']
      for (let i = 0; i < presetIds.length; i++) {
        expect(await clickByIdOrText(driver, presetIds[i], presetLabels[i])).assertTrue()
        await driver.delayMs(200)
        const selected: Component = requireComponent(await driver.findComponent(ON.id('checkout-delivery-selected-time')), 'preset delivery time')
        expect((await selected.getText()).startsWith('预约送达：')).assertTrue()
      }
      requireComponent(await driver.findComponent(ON.id('checkout-submit')), 'submit remains accessible')
    })
  })
}

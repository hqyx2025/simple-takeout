import { Driver, ON } from '@kit.TestKit'
import { describe, it, expect } from '@ohos/hypium'

export default function checkoutGuardTest() {
  describe('CheckoutGuard', () => {
    // 在真机执行前置条件：已进入结算页并准备好至少一个可结算商品。
    it('checkout page exposes submit action for end-to-end validation', 0, async () => {
      const driver: Driver = Driver.create()
      const submit = await driver.findComponent(ON.id('checkout-submit'))
      expect(submit !== undefined).assertTrue()
    })
  })
}

/**
 * 结算页入口契约守卫（设备端 UiTest）。
 *
 * 前置（由 scripts/device-checkout-regression.ps1 布置）：购物车至少有一行商品。
 * 用例自己走「购物车 Tab → 去结算」，断言结算页确实给出了提交按钮。
 *
 * 说明：端到端的下单链路（起送价拦截、待付款订单、库存/余额/请求次数核对）在
 * CheckoutFlow 里；这里只守「结算页能进得去、提交按钮在」这条最小契约，
 * 用组件匹配器驱动，不再依赖会失真的 `!== undefined` 断言。
 */
import { Driver, ON } from '@kit.TestKit'
import { describe, it, expect } from '@ohos/hypium'
import { isFound, requireComponent, launchAppUnderTest, clickByIdOrText, waitAny } from './UiTestHelper'

export default function checkoutGuardTest() {
  describe('CheckoutGuard', () => {
    it('CheckoutGuard_cart_entry_reaches_checkout_page', 0, async () => {
      const driver: Driver = Driver.create()
      await launchAppUnderTest(driver)
      const consent = await waitAny(driver, ['privacy-accept'], 8000)
      if (isFound(consent)) {
        await clickByIdOrText(driver, 'privacy-accept', '同意并继续')
        await driver.delayMs(2000)
      }
      // 测试环境快捷登录：触发登录页 UI 登录后跳首页（loginRemote 只写登录态不跳页，会卡在登录页）
      expect(await clickByIdOrText(driver, 'quick-login-user', '一键登录用户')).assertTrue()
      await driver.delayMs(3000)

      // 购物车已收敛为底部 Tab（tab-2），不再是「我的」页里的购物车行
      expect(await clickByIdOrText(driver, 'tab-2', '购物车')).assertTrue()
      await driver.delayMs(2500)
      expect(await clickByIdOrText(driver, 'cart-checkout', '去结算')).assertTrue()
      await driver.delayMs(2500)

      const submit = requireComponent(
        await driver.waitForComponent(ON.id('checkout-submit'), 10000), 'checkout-submit')
      expect(isFound(submit)).assertTrue()
    })
  })
}

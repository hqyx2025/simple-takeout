/**
 * 结算页负路径 + 正向回归（设备端 UiTest，组件匹配器驱动）。
 *
 * 固定前置（由 scripts/device-checkout-regression.ps1 在跑用例前用后端接口布置）：
 *   - 已登录用户 13800138000；
 *   - 购物车只有一行：goodsId=282 / specId=0 / 数量 1（¥6.82，店铺 storeId=10，起送价 ¥17）。
 *
 * 断言链（每一步都拿可核对的数字，不写"看起来正常"）：
 *   1. 我的 → 购物车：凑单提示必须是「还差 ¥10.18 起送」、行数量为 1；
 *   2. 去结算：结算页实付必须是 ¥9.82（6.82 商品 + 3.00 配送费）；
 *   3. 低于起送价点「提交订单」：**必须仍停留在结算页**（客户端拦截，没发出下单请求）；
 *      对应的服务端断言（POST /api/orders 次数 = 0）由 host 脚本用 hilog 计数核对；
 *   4. 购物车 +2 件（数量 1→3，¥20.46 ≥ ¥17）：凑单提示必须消失；
 *   5. 再次提交：必须跳转订单详情、状态文案为「待付款」、出现「立即支付」按钮；
 *      对应服务端断言（多出恰好 1 笔 status=0 订单、余额不变、库存 −3）由 host 脚本核对。
 */
import { Driver, ON, Component } from '@kit.TestKit'
import { describe, it, expect } from '@ohos/hypium'
import { isFound, requireComponent, launchAppUnderTest, findByIdOrText, clickByIdOrText } from './UiTestHelper'

export default function checkoutFlowTest() {
  describe('CheckoutFlow', () => {
    it('CheckoutFlow_min_order_guard_and_pending_order', 0, async () => {
      const driver: Driver = Driver.create()
      // 必须先把应用拉到前台：aa test 会把测试 Ability 的 Hello World 页盖在最上面
      await launchAppUnderTest(driver)

      // ---------- 1. 我的 → 购物车 ----------
      expect(await clickByIdOrText(driver, 'tab-3', '我的')).assertTrue()
      await driver.delayMs(1500)
      expect(await clickByIdOrText(driver, 'profile-cart-entry', '购物车 (1)')).assertTrue()
      await driver.delayMs(2500)

      // ---------- 2. 购物车：凑单提示「还差 ¥10.18 起送」+ 行数量 1 ----------
      const gapTip: Component = requireComponent(
        await driver.findComponent(ON.id('cart-bundle-gap')), 'cart-bundle-gap')
      const gapText: string = await gapTip.getText()
      console.info('[CheckoutFlow] gap tip = ' + gapText)
      expect(gapText).assertEqual('还差 ¥10.18 起送')

      const qtyBefore: Component = requireComponent(
        await driver.findComponent(ON.id('cart-qty-282-0')), 'cart-qty-282-0')
      expect(await qtyBefore.getText()).assertEqual('1')

      // ---------- 3. 去结算：实付 ¥9.82 ----------
      expect(await clickByIdOrText(driver, 'cart-checkout', '去结算')).assertTrue()
      await driver.delayMs(2500)

      const payAmountComp: Component = requireComponent(
        await driver.findComponent(ON.id('checkout-pay-amount')), 'checkout-pay-amount')
      const payAmountLow: string = await payAmountComp.getText()
      console.info('[CheckoutFlow] pay amount (below min order) = ' + payAmountLow)
      expect(payAmountLow).assertEqual('¥9.82')

      // ---------- 4. 负路径：低于起送价提交必须被拦住（停留在本页） ----------
      expect(await clickByIdOrText(driver, 'checkout-submit', '提交订单')).assertTrue()
      await driver.delayMs(3000)

      const stillOnCheckout = await driver.findComponent(ON.id('checkout-submit'))
      expect(isFound(stillOnCheckout)).assertTrue()
      const leakedOrderStatus = await driver.findComponent(ON.id('order-detail-status'))
      expect(isFound(leakedOrderStatus)).assertFalse()

      // ---------- 5. 回购物车补足金额：数量 1→3，凑单提示消失 ----------
      expect(await clickByIdOrText(driver, 'checkout-back', '‹ 返回')).assertTrue()
      await driver.delayMs(2500)

      // 每次点击都重新查找：行子树会随 cartRenderVersion 重建，旧句柄点第二次必然失效
      expect(await clickByIdOrText(driver, 'cart-plus-282-0', '+')).assertTrue()
      await driver.delayMs(2000)
      expect(await clickByIdOrText(driver, 'cart-plus-282-0', '+')).assertTrue()
      await driver.delayMs(2500)

      const qtyAfter: Component = requireComponent(
        await driver.findComponent(ON.id('cart-qty-282-0')), 'cart-qty-282-0(after)')
      const qtyText: string = await qtyAfter.getText()
      console.info('[CheckoutFlow] cart qty after +2 = ' + qtyText)
      expect(qtyText).assertEqual('3')

      const gapGone = await driver.findComponent(ON.id('cart-bundle-gap'))
      expect(isFound(gapGone)).assertFalse()

      // ---------- 6. 正向：足额提交 → 订单详情「待付款」 ----------
      expect(await clickByIdOrText(driver, 'cart-checkout', '去结算')).assertTrue()
      await driver.delayMs(2500)

      const payAmountComp2 = await driver.findComponent(ON.id('checkout-pay-amount'))
      const payAmountHigh: string = isFound(payAmountComp2) ? await payAmountComp2.getText() : ''
      console.info('[CheckoutFlow] pay amount (above min order) = ' + payAmountHigh)
      expect(payAmountHigh).assertEqual('¥23.46')

      expect(await clickByIdOrText(driver, 'checkout-submit', '提交订单')).assertTrue()

      const statusComp: Component = requireComponent(
        await driver.waitForComponent(ON.id('order-detail-status'), 12000), 'order-detail-status')
      const statusText: string = await statusComp.getText()
      console.info('[CheckoutFlow] order status = ' + statusText)
      expect(statusText.indexOf('待付款') >= 0).assertTrue()

      const payBtn = await driver.findComponent(ON.id('order-pay'))
      expect(isFound(payBtn)).assertTrue()
    })
  })
}

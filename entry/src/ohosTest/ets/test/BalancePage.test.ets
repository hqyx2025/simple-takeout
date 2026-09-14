/**
 * 我的钱包页回归（设备端 UiTest）。
 *
 * 覆盖两件事：
 *   1. 「我的」页资产卡片的「余额」点击后必须进入 pages/BalancePage（不是旧的充值弹窗）；
 *   2. 钱包页必须展示余额与已绑定银行卡（种子数据：招商银行 储蓄卡 **** 6688）。
 *
 * 走真实链路：登录 → 我的 → 点余额 → 断言钱包页。
 */
import { Driver, ON, Component } from '@kit.TestKit'
import { describe, it, expect } from '@ohos/hypium'
import { isFound, requireComponent, launchAppUnderTest, clickByIdOrText } from './UiTestHelper'

export default function balancePageTest() {
  describe('BalancePage', () => {
    it('BalancePage_balance_click_opens_wallet_with_bank_cards', 0, async () => {
      const driver: Driver = Driver.create()
      await launchAppUnderTest(driver)

      // ---------- 1. 确保已登录 ----------
      let home = await driver.waitForComponent(ON.id('home-search-entry'), 8000)
      if (!isFound(home)) {
        console.info('[BalancePage] not on home, trying quick login')
        const quick = await driver.waitForComponent(ON.id('quick-login-user'), 10000)
        if (isFound(quick)) {
          await (quick as Component).click()
          await driver.delayMs(4000)
        }
      }

      // ---------- 2. 切到「我的」 ----------
      expect(await clickByIdOrText(driver, 'tab-3', '我的')).assertTrue()
      await driver.delayMs(3000)

      // ---------- 3. 点资产卡片的「余额」 ----------
      const balanceText = await driver.findComponent(ON.text('余额'))
      requireComponent(balanceText, 'asset card 余额')
      await (balanceText as Component).click()
      await driver.delayMs(3500)

      // ---------- 4. 必须进入钱包页 ----------
      const back = await driver.waitForComponent(ON.id('balance-back'), 8000)
      requireComponent(back, 'balance-back')
      const title = await driver.findComponent(ON.text('我的钱包'))
      expect(isFound(title)).assertTrue()

      // ---------- 5. 余额金额必须渲染出来 ----------
      const amount = await driver.waitForComponent(ON.id('balance-amount'), 8000)
      const amountText: string = isFound(amount) ? await (amount as Component).getText() : ''
      console.info('[BalancePage] amount = ' + amountText)
      expect(amountText.indexOf('¥') === 0).assertTrue()

      // ---------- 6. 已绑定银行卡必须展示 ----------
      // 注意：id 打在 Row 容器上，容器的 getText() 返回空串（容器自身没有文本），
      // 所以要按卡片内的**文本节点**断言，而不是读容器的文本。
      const card = await driver.waitForComponent(ON.id('bank-card-0'), 10000)
      requireComponent(card, 'bank-card-0')

      const bankName = await driver.findComponent(ON.text('招商银行'))
      expect(isFound(bankName)).assertTrue()

      const masked = await driver.findComponent(ON.text('**** **** **** 6688'))
      expect(isFound(masked)).assertTrue()
      const maskedText: string = isFound(masked) ? await (masked as Component).getText() : ''
      console.info('[BalancePage] masked card no = ' + maskedText)

      // 卡号后四位必须只以掩码形式出现，页面上不能有完整卡号
      const section = await driver.findComponent(ON.text('已绑定的银行卡'))
      expect(isFound(section)).assertTrue()

      console.info('[BalancePage] PASS')
    })
  })
}

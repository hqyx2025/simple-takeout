/**
 * 我的钱包页回归（设备端 UiTest）。
 *
 * 覆盖两件事：
 *   1. 「我的」页资产卡片的「余额」点击后必须进入 pages/BalancePage（不是旧的充值弹窗）；
 *   2. 真实添加两张卡，重新进入钱包验证持久化，再只删除本次记录并保留原卡。
 *
 * 走真实链路：登录 → 我的 → 点余额 → 断言钱包页。
 */
import { Driver, ON, Component, MatchPattern, Rect, Point } from '@kit.TestKit'
import { describe, it, expect } from '@ohos/hypium'
import { pasteboard } from '@kit.BasicServicesKit'
import { isFound, requireComponent, launchAppUnderTest, clickByIdOrText, openQuickLoginDialog, scrollUntilVisible } from './UiTestHelper'

async function cardCount(driver: Driver): Promise<number> {
  requireComponent(await driver.waitForComponent(ON.id('wallet-add-card').enabled(true), 10000), 'wallet ready')
  requireComponent(await scrollUntilVisible(driver, 'balance-amount'), 'wallet top')
  const count: Component = requireComponent(await driver.findComponent(ON.text('^[0-9]+ 张$', MatchPattern.REG_EXP)), 'card count')
  return Number.parseInt(await count.getText())
}

async function deleteButtons(driver: Driver, count: number): Promise<string[]> {
  const ids: string[] = []
  for (let i = 0; i < count; i++) {
    const rowId: string = `bank-card-${i}`
    requireComponent(await scrollUntilVisible(driver, rowId), rowId)
    ids.push(await requireComponent(await driver.findComponent(ON.text('删除银行卡').within(ON.id(rowId))), 'delete card').getId())
  }
  return ids
}

async function findCardDelete(driver: Driver, name: string): Promise<string> {
  const count: number = await cardCount(driver)
  for (let i = 0; i < count; i++) {
    const rowId: string = `bank-card-${i}`
    requireComponent(await scrollUntilVisible(driver, rowId), rowId)
    if (isFound(await driver.findComponent(ON.text(name).within(ON.id(rowId))))) {
      return await requireComponent(await driver.findComponent(ON.text('删除银行卡').within(ON.id(rowId))), name).getId()
    }
  }
  return ''
}

async function addCard(driver: Driver, name: string, fullCardNumber: string, count: number): Promise<void> {
  expect(await clickByIdOrText(driver, 'wallet-add-card', '添加银行卡')).assertTrue()
  await requireComponent(await driver.waitForComponent(ON.id('bank-card-bank-name'), 8000), 'bank name').inputText(name)
  const form: Component = requireComponent(await driver.findComponent(ON.id('bank-card-form-scroll')), 'bank card form')
  await requireComponent(await form.scrollSearch(ON.id('bank-card-last4')), 'full card number').inputText(fullCardNumber)
  await driver.delayMs(400)
  requireComponent(await driver.findComponent(ON.id('bank-card-back')), 'still on add card page')
  const save: Component = requireComponent(await driver.waitForComponent(
    ON.id('bank-card-save').enabled(true).clickable(true), 8000), 'visible enabled save')
  const saveBounds: Rect = await save.getBounds()
  const display: Point = await driver.getDisplaySize()
  expect(saveBounds.bottom > saveBounds.top && saveBounds.top >= 0 && saveBounds.bottom <= display.y).assertTrue()
  // 键盘保持打开：保存按钮必须位于键盘上方，不能用收起键盘绕过布局回归。
  let keyboard: Component | null = await driver.findComponent(ON.id('KeyHideKbd'))
  if (!isFound(keyboard)) { keyboard = await driver.findComponent(ON.id('KeyboardCanvas')) }
  if (isFound(keyboard)) {
    const keyboardBounds: Rect = await (keyboard as Component).getBounds()
    expect(saveBounds.bottom <= keyboardBounds.top).assertTrue()
  }
  expect(await clickByIdOrText(driver, 'bank-card-save', '保存银行卡')).assertTrue()
  requireComponent(await driver.waitForComponent(ON.id('balance-back'), 10000), 'returned wallet')
  requireComponent(await driver.waitForComponent(ON.text(`${count} 张`), 10000), 'added card count')
  await cardCount(driver)
}

async function verifyCardRevealAndCopy(driver: Driver, name: string, fullCardNumber: string): Promise<void> {
  const count: number = await cardCount(driver)
  let revealId: string = ''
  for (let i = 0; i < count; i++) {
    const rowId: string = `bank-card-${i}`
    requireComponent(await scrollUntilVisible(driver, rowId), rowId)
    if (isFound(await driver.findComponent(ON.text(name).within(ON.id(rowId))))) {
      revealId = await requireComponent(await driver.findComponent(
        ON.text('显示完整卡号').within(ON.id(rowId))), 'reveal card').getId()
      expect(isFound(await driver.findComponent(ON.text(fullCardNumber).within(ON.id(rowId))))).assertFalse()
      break
    }
  }
  expect(revealId !== '').assertTrue()
  const cardId: string = revealId.replace('wallet-reveal-card-', '')
  const fullNumberId: string = `wallet-full-card-number-${cardId}`
  expect(await clickByIdOrText(driver, revealId, '')).assertTrue()
  await requireComponent(await driver.waitForComponent(ON.id('wallet-reveal-payment-password'), 5000),
    'payment password').inputText('123123')
  expect(await clickByIdOrText(driver, 'wallet-reveal-submit', '')).assertTrue()
  requireComponent(await driver.waitForComponent(ON.id(revealId).enabled(true), 10000), 'failed reveal finished')
  expect(isFound(await driver.findComponent(ON.id(fullNumberId)))).assertFalse()

  expect(await clickByIdOrText(driver, revealId, '')).assertTrue()
  await requireComponent(await driver.waitForComponent(ON.id('wallet-reveal-payment-password'), 5000),
    'payment password').inputText('726491')
  expect(await clickByIdOrText(driver, 'wallet-reveal-submit', '')).assertTrue()
  const fullNumber: Component = requireComponent(await driver.waitForComponent(ON.id(fullNumberId), 10000),
    'revealed card number')
  expect(await fullNumber.getText()).assertEqual(fullCardNumber)
  expect(await clickByIdOrText(driver, `wallet-copy-card-${cardId}`, '')).assertTrue()
  await driver.delayMs(1200)
  expect(isFound(await driver.findComponent(ON.id(fullNumberId)))).assertFalse()
  // 通过真实系统粘贴菜单验证复制内容；测试模块不额外申请读取剪贴板权限。
  expect(await clickByIdOrText(driver, 'wallet-add-card', '')).assertTrue()
  const form: Component = requireComponent(await driver.waitForComponent(ON.id('bank-card-form-scroll'), 8000),
    'bank card form for paste')
  const input: Component = requireComponent(await form.scrollSearch(ON.id('bank-card-last4')), 'full card number input')
  // 先真实聚焦输入，再注入平台 Ctrl+V；避免键盘与原生选中文字菜单同名“粘贴”节点冲突。
  await input.click()
  await driver.delayMs(600)
  await driver.triggerCombineKeys(2072, 2038)
  await driver.delayMs(1200)
  expect(await requireComponent(await driver.findComponent(ON.id('bank-card-last4')), 'pasted card input').getText())
    .assertEqual(fullCardNumber)
  expect(await clickByIdOrText(driver, 'bank-card-back', '')).assertTrue()
  requireComponent(await driver.waitForComponent(ON.id('balance-back'), 8000), 'wallet after paste')
  await pasteboard.getSystemPasteboard().clearData()
}

export default function balancePageTest() {
  describe('BalancePage', () => {
    it('BalancePage_wallet_adds_deletes_two_cards_and_preserves_original_cards', 0, async () => {
      const driver: Driver = Driver.create()
      await launchAppUnderTest(driver)

      // ---------- 1. 确保已登录 ----------
      let home = await driver.waitForComponent(ON.id('home-search-entry'), 8000)
      if (!isFound(home)) {
        console.info('[BalancePage] not on home, trying quick login')
        const quick = await driver.waitForComponent(ON.id('version-text'), 10000)
        if (isFound(quick)) {
          await openQuickLoginDialog(driver)
          const userBtn = await driver.waitForComponent(ON.id('quick-login-user'), 5000)
          if (isFound(userBtn)) {
            await (userBtn as Component).click()
            await driver.delayMs(4000)
          }
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

      const originalCount: number = await cardCount(driver)
      const originalIds: string[] = await deleteButtons(driver, originalCount)
      const runId: string = Date.now().toString()
      const names: string[] = [`UiTest银行A${runId}`, `UiTest银行B${runId}`]
      await addCard(driver, names[0], '6222021234561122', originalCount + 1)
      await addCard(driver, names[1], '6222021234563344', originalCount + 2)
      expect(await cardCount(driver)).assertEqual(originalCount + 2)
      await verifyCardRevealAndCopy(driver, names[0], '6222021234561122')
      // 重新进入页面读取接口，验证记录已经持久化。
      expect(await clickByIdOrText(driver, 'balance-back', '')).assertTrue()
      await requireComponent(await driver.waitForComponent(ON.text('余额'), 8000), 'asset balance').click()
      expect(await cardCount(driver)).assertEqual(originalCount + 2)
      for (let i = 0; i < names.length; i++) {
        expect((await findCardDelete(driver, names[i])) !== '').assertTrue()
      }
      for (let i = 0; i < names.length; i++) {
        const name: string = names[names.length - 1 - i]
        const deleteId: string = await findCardDelete(driver, name)
        expect(deleteId !== '').assertTrue()
        expect(await clickByIdOrText(driver, deleteId, '')).assertTrue()
        await requireComponent(await driver.waitForComponent(ON.text('删除').type('Button'), 5000), 'confirm delete').click()
        requireComponent(await driver.waitForComponent(ON.text(`${originalCount + 1 - i} 张`), 10000), 'updated card count')
        expect(await cardCount(driver)).assertEqual(originalCount + 1 - i)
        expect(await findCardDelete(driver, name)).assertEqual('')
      }
      const remainingIds: string[] = await deleteButtons(driver, originalCount)
      for (let i = 0; i < originalIds.length; i++) {
        expect(remainingIds.indexOf(originalIds[i]) >= 0).assertTrue()
      }
      console.info('[BalancePage] PASS: balance, persisted cards, scoped deletion and original cards preserved')
    })
  })
}

/**
 * 搜索链路回归（设备端 UiTest）。
 *
 * 前置：已登录，应用在首页（host 脚本 `aa force-stop` + `aa start` 后即为首页）。
 *
 * 为什么值得测：搜索链路上抓到过两个真缺陷——首页搜索栏被 TextInput 吞掉点击（点了没反应）、
 * 搜索页返回按钮触控区只有约 20×30px（点不中）。当时怀疑的「中文输入进不去 / 返回失效」
 * 后来确认是坐标点击与 PowerShell→hdc 的中文编码问题，不是应用缺陷；这条用例用组件匹配器 +
 * 测试进程内直接 inputText，把这两点一次性钉死。
 *
 * 断言链：
 *   1. 首页搜索栏 → 进入搜索页（`search-input` 必须存在）；
 *   2. 输入中文关键词 → 点「搜索」→ 必须给出**明确结果**（结果列表或空态，二者必居其一，
 *      不允许"点了没反应"）；host 侧再核对应用日志里 `GET /api/search` 恰好 1 次；
 *   3. 点返回 → 必须回到首页（`home-search-entry` 可见）。
 */
import { Driver, ON, Component } from '@kit.TestKit'
import { describe, it, expect } from '@ohos/hypium'
import { isFound, requireComponent, launchAppUnderTest, clickByIdOrText, findByIdOrText, waitAny, openQuickLoginDialog } from './UiTestHelper'

export default function searchFlowTest() {
  describe('SearchFlow', () => {
    it('SearchFlow_search_keyword_then_back_home', 0, async () => {
      const driver: Driver = Driver.create()
      await launchAppUnderTest(driver)

      // 确保已登录并落在首页（干净态需先同意隐私 + 快捷登录）
      const consent = await waitAny(driver, ['privacy-accept'], 8000)
      if (isFound(consent)) {
        await clickByIdOrText(driver, 'privacy-accept', '同意并继续')
        await driver.delayMs(2000)
      }
      let homeCheck = await driver.waitForComponent(ON.id('home-search-entry'), 8000)
      if (!isFound(homeCheck)) {
        const quick = await driver.waitForComponent(ON.id('version-text'), 10000)
        if (isFound(quick)) {
          await openQuickLoginDialog(driver)
          const userBtn = await driver.waitForComponent(ON.id('quick-login-user'), 5000)
          if (isFound(userBtn)) {
            await (userBtn as Component).click()
            await driver.delayMs(4000)
          }
        }
        homeCheck = await driver.waitForComponent(ON.id('home-search-entry'), 10000)
      }
      requireComponent(homeCheck, 'home-search-entry')

      // ---------- 1. 首页搜索栏 → 搜索页 ----------
      expect(await clickByIdOrText(driver, 'home-search-entry', '搜索美食、店铺')).assertTrue()
      await driver.delayMs(2500)
      const input: Component = requireComponent(
        await driver.waitForComponent(ON.id('search-input'), 10000), 'search-input')

      // ---------- 2. 输入中文关键词并搜索（测试进程内直接输入，不经 hdc 参数编码） ----------
      await input.click()
      await driver.delayMs(800)
      await input.inputText('黄焖鸡')
      await driver.delayMs(1200)
      expect(await clickByIdOrText(driver, 'search-submit', '搜索')).assertTrue()
      await driver.delayMs(3500)

      // SearchPage 结果列表是 ForEach 渲染的 StoreCard（id=search-store-<id>），没有 search-result-list 容器 id
      const resultList = await driver.findComponent(ON.id('search-store-1'))
      const emptyState = await driver.findComponent(ON.id('search-empty'))
      console.info('[SearchFlow] resultList=' + isFound(resultList) + ' emptyState=' + isFound(emptyState))
      // 必须有明确结果：结果列表或空态，不能两者都没有（那就是"点了没反应"）
      expect(isFound(resultList) || isFound(emptyState)).assertTrue()

      // ---------- 3. 返回首页（历史上返回按钮点不中） ----------
      expect(await clickByIdOrText(driver, 'search-back', '‹')).assertTrue()
      await driver.delayMs(2500)
      const homeEntry = await findByIdOrText(driver, 'home-search-entry', '搜索美食、店铺')
      console.info('[SearchFlow] back home visible=' + isFound(homeEntry))
      expect(isFound(homeEntry)).assertTrue()
    })
  })
}

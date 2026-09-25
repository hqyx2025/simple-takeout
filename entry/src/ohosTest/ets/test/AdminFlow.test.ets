/**
 * 管理端冒烟（设备端 UiTest）。
 *
 * 前置（由 scripts/device-role-regression.ps1 布置）：应用数据已清空（guest 态）。
 *
 * 覆盖：同意隐私 → 一键登录管理端 → 应用**直接进入平台管理页**（不再展示 C 端主页）→
 * 十个模块入口都在 → 逐个进入「分类管理/店铺管理/员工管理/商品监管/用户管理/订单管理/
 * 退款审批/平台统计/骑手管理/内容管理」并断言各页标题渲染，再返回平台管理页。
 */
import { Driver, ON } from '@kit.TestKit'
import { describe, it, expect } from '@ohos/hypium'
import { isFound, requireComponent, launchAppUnderTest, clickByIdOrText, scrollAndClick, scrollUntilVisible, waitAny, openQuickLoginDialog } from './UiTestHelper'

/** 模块入口：入口 id 后缀（页面名）+ 该页标题文案。 */
class AdminModule {
  page: string = ''
  title: string = ''
  static create(page: string, title: string): AdminModule {
    const m = new AdminModule()
    m.page = page
    m.title = title
    return m
  }
}

const ADMIN_MODULES: AdminModule[] = [
  AdminModule.create('AdminCategoryPage', '分类管理'),
  AdminModule.create('AdminStorePage', '店铺管理'),
  AdminModule.create('AdminOrderPage', '订单管理'),
  AdminModule.create('AdminRefundPage', '退款审批'),
  AdminModule.create('AdminStatisticsPage', '平台统计'),
  AdminModule.create('AdminContentPage', '内容管理')
]

export default function adminFlowTest() {
  describe('AdminFlow', () => {
    it('AdminFlow_platform_management_pages_smoke', 0, async () => {
      const driver: Driver = Driver.create()
      await launchAppUnderTest(driver)

      const consent = await waitAny(driver, ['privacy-accept'], 8000)
      if (isFound(consent)) {
        console.info('[AdminFlow] consent page -> accept')
        expect(await clickByIdOrText(driver, 'privacy-accept', '同意并继续')).assertTrue()
        await driver.delayMs(3000)
      }
      await openQuickLoginDialog(driver)
      expect(await clickByIdOrText(driver, 'quick-login-admin', '一键登录管理端')).assertTrue()
      await driver.delayMs(8000)

      // 平台管理页：C 端入口不应该出现（管理员直接进后台）
      const cEntry = await driver.findComponent(ON.id('home-search-entry'))
      console.info('[AdminFlow] C-end home search entry visible=' + isFound(cEntry))
      expect(isFound(cEntry)).assertFalse()

      // 十个模块入口都在（平台管理页是长列表，靠下的入口需要滚动才可见）
      const allPages: string[] = [
        'AdminCategoryPage', 'AdminStorePage', 'AdminEmployeePage', 'AdminProductPage', 'AdminUserPage',
        'AdminOrderPage', 'AdminRefundPage', 'AdminStatisticsPage', 'AdminRiderPage', 'AdminContentPage'
      ]
      for (let i = 0; i < allPages.length; i++) {
        const entry = await scrollUntilVisible(driver, 'admin-entry-' + allPages[i])
        console.info('[AdminFlow] entry ' + allPages[i] + ' visible=' + isFound(entry))
        expect(isFound(entry)).assertTrue()
      }

      // 逐个进入页面并断言标题
      for (let i = 0; i < ADMIN_MODULES.length; i++) {
        const module: AdminModule = ADMIN_MODULES[i]
        expect(await scrollAndClick(driver, 'admin-entry-' + module.page, module.title)).assertTrue()
        await driver.delayMs(3500)
        const title = await driver.findComponent(ON.text(module.title))
        console.info('[AdminFlow] page ' + module.page + ' title visible=' + isFound(title))
        expect(isFound(title)).assertTrue()
        // 管理端页面是 pushUrl 出来的，按返回回到平台管理页
        await driver.pressBack()
        await driver.delayMs(2500)
      }
    })
  })
}

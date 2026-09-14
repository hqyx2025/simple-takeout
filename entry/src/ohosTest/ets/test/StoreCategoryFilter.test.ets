/**
 * 店铺详情页「分类分区」切换回归（设备端 UiTest）。
 *
 * 背景：用户反馈点「全部」和其他分类芯片，商品列表不会跟着切换。
 *
 * 根因（在种子数据，不在 UI）：店铺详情页的分类芯片走的是美团式「店内分类」
 * （categories.type='MERCHANT' + goods.merchant_category_id），但种子数据从未
 * 创建过任何 MERCHANT 分类，1200 个商品的 merchant_category_id 全为 0 ——
 * 芯片只剩「全部 + 该店唯一的平台分类」两个，而两者返回的商品列表完全相同，
 * 于是看起来「点了没反应」。
 *
 * 修法：DataSeeder.ensureStoreMerchantCategories() 幂等补齐店内分类并把
 * 未分组商品挂上去（只改 merchant_category_id=0 的行，不覆盖商户已有分组）。
 *
 * 本用例的断言与具体商品无关，只锁「切换必须改变列表」：
 *   1. 进店后记录「全部」的商品数 N（从 goods-count-<N> 的 id 读）；
 *   2. 依次点每个分类芯片；
 *   3. 要求至少有一个分类的商品数 **严格小于 N**（修复前所有分类都等于 N）。
 *
 * 固定数据：storeId=2「星巴克咖啡」共有 30 件商品，店内分类 4 个（8/8/7/7）。
 */
import { Driver, ON, Component } from '@kit.TestKit'
import { describe, it, expect } from '@ohos/hypium'
import { isFound, requireComponent, launchAppUnderTest, clickByIdOrText } from './UiTestHelper'

const STORE_ID: number = 2
const STORE_NAME: string = '星巴克咖啡'
// 种子里补的四个店内分类；用例逐个点过去，任一分类数量与「全部」不同即通过
const CATEGORY_NAMES: string[] = ['招牌热销', '人气主食', '特色小吃', '解腻饮品']

/** 从 goods-count-<n> 的组件 id 里读回当前分类命中的商品数；没有该节点返回 -1。 */
async function readGoodsCount(driver: Driver): Promise<number> {
  // 数量直接编码在 id 上，逐个候选值试查比解析文本更稳（文本可能被省略号截断）
  for (let n = 0; n <= 60; n++) {
    const found = await driver.findComponent(ON.id('goods-count-' + n))
    if (isFound(found)) {
      return n
    }
  }
  return -1
}

export default function storeCategoryFilterTest() {
  describe('StoreCategoryFilter', () => {
    it('StoreCategoryFilter_switching_category_changes_goods_list', 0, async () => {
      const driver: Driver = Driver.create()
      await launchAppUnderTest(driver)

      // ---------- 1. 确保已登录（已登录则直接落在首页） ----------
      let home = await driver.waitForComponent(ON.id('home-search-entry'), 8000)
      if (!isFound(home)) {
        console.info('[StoreCategoryFilter] not on home, trying quick login')
        const quick = await driver.waitForComponent(ON.id('quick-login-user'), 10000)
        if (isFound(quick)) {
          await (quick as Component).click()
          await driver.delayMs(4000)
        }
        home = await driver.waitForComponent(ON.id('home-search-entry'), 10000)
      }
      requireComponent(home, 'home-search-entry')

      // ---------- 2. 首页 → 搜索 → 进店 ----------
      expect(await clickByIdOrText(driver, 'home-search-entry', '搜索美食、店铺')).assertTrue()
      await driver.delayMs(2500)
      const input: Component = requireComponent(
        await driver.waitForComponent(ON.id('search-input'), 10000), 'search-input')
      await input.click()
      await driver.delayMs(800)
      await input.inputText(STORE_NAME)
      await driver.delayMs(1000)
      expect(await clickByIdOrText(driver, 'search-submit', '搜索')).assertTrue()
      await driver.delayMs(3500)
      expect(await clickByIdOrText(driver, 'search-store-' + STORE_ID, STORE_NAME)).assertTrue()
      await driver.delayMs(4500)

      // ---------- 3. 「全部」的商品数 ----------
      const total: number = await readGoodsCount(driver)
      console.info('[StoreCategoryFilter] 全部 goods count = ' + total)
      expect(total > 0).assertTrue()

      // ---------- 4. 逐个分类芯片：必须有分类的商品数严格小于「全部」 ----------
      // 芯片用「文案」定位而不是 id：实测 ON.id('goods-cat-xxx') 取不到（横向 Scroll 内的
      // Text 节点 id 不参与匹配），而 ON.text() 能稳定拿到 5 个芯片。
      let changed: number = 0
      for (let i = 0; i < CATEGORY_NAMES.length; i++) {
        const name: string = CATEGORY_NAMES[i]
        const chip = await driver.findComponent(ON.text(name))
        if (!isFound(chip)) {
          console.info('[StoreCategoryFilter] chip not found: ' + name)
          continue
        }
        await (chip as Component).click()
        await driver.delayMs(2000)
        const n: number = await readGoodsCount(driver)
        console.info('[StoreCategoryFilter] chip ' + name + ' -> goods count = ' + n)
        expect(n > 0).assertTrue()
        if (n < total) {
          changed++
        }
      }
      console.info('[StoreCategoryFilter] categories with fewer goods than 全部 = ' + changed)

      // 修复前每个分类都等于「全部」，changed 恒为 0
      expect(changed > 0).assertTrue()

      // ---------- 5. 点回「全部」必须恢复原始数量 ----------
      const allChip = await driver.findComponent(ON.text('全部'))
      if (isFound(allChip)) {
        await (allChip as Component).click()
        await driver.delayMs(2000)
        const backToAll: number = await readGoodsCount(driver)
        console.info('[StoreCategoryFilter] back to 全部 = ' + backToAll)
        expect(backToAll).assertEqual(total)
      }
    })
  })
}

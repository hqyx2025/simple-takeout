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
 * 修法：DataSeeder.ensureStoreMerchantCategories() 补齐店内分类并把商品按店铺
 * 轮转分配。两个已踩过的坑都在这里锁住：
 *   ① 若按 is_special 全局一刀切，「整店商品全是招牌」的店铺会全部落进同一个
 *      分类（31~40 号店各 6 个商品全是招牌），芯片仍然只有一个非空项；
 *   ② 若只补 merchant_category_id=0 的行，已经被分错的店铺永远修不回来。
 *
 * 用例覆盖两家店铺，断言与具体商品无关，只锁「切换必须改变列表」：
 *   - store 2「星巴克咖啡」：主路径
 *   - store 34「武昌热干面」：追加店铺集合里的另一家店，避免只锁死一家店
 * 做法：记录「全部」的条数 N，逐个点分类芯片，要求至少有一个分类的条数严格
 * 小于 N（修复前所有分类都等于 N），且每个分类都非空、可点分类 >= 2 个，
 * 最后点回「全部」确认恢复 N。
 *
 * 说明：模拟器连的是 compose 容器库，那份数据里 40 家店都是 30 件商品、
 * 每家 6 个招牌，不存在「整店全是招牌」的形态；该形态只出现在本机 3306
 * 那份累积数据里（31~40 号店各 6 件且全是招牌），已在数据库层面核对
 * （修复后 bad_stores=0、每家店恰好 4 个非空分类），见提交说明。
 */
import { Driver, ON, Component } from '@kit.TestKit'
import { describe, it, expect } from '@ohos/hypium'
import { isFound, requireComponent, launchAppUnderTest, clickByIdOrText } from './UiTestHelper'

const STORE_ID: number = 2
const STORE_NAME: string = '星巴克咖啡'

/**
 * 从 goods-count-<n> 的组件 id 里读回当前分类命中的商品数；没有该节点返回 -1。
 * 数量直接编码在 id 上，逐个候选值试查比解析文本更稳（文本可能被省略号截断）。
 */
async function readGoodsCount(driver: Driver): Promise<number> {
  for (let n = 0; n <= 60; n++) {
    const found = await driver.findComponent(ON.id('goods-count-' + n))
    if (isFound(found)) {
      return n
    }
  }
  return -1
}

/**
 * 回到首页（第二条用例开始时应用还停在上一条的店铺详情页）。
 * 逐次按返回直到首页出现；返回按不动时再拉起一次 EntryAbility。
 */
async function goHome(driver: Driver): Promise<void> {
  for (let i = 0; i < 4; i++) {
    const found = await driver.findComponent(ON.id('home-search-entry'))
    if (isFound(found)) {
      return
    }
    try {
      await driver.pressBack()
    } catch (err) {
      console.info('[StoreCategoryFilter] pressBack failed: ' + (err as Error).message)
    }
    await driver.delayMs(1500)
  }
  const stillNotHome = await driver.findComponent(ON.id('home-search-entry'))
  if (!isFound(stillNotHome)) {
    console.info('[StoreCategoryFilter] still not home, relaunching app')
    await launchAppUnderTest(driver)
    await driver.delayMs(3000)
  }
}

/** 登录（若需要）→ 搜索 → 进入店铺详情页。 */
async function enterStore(driver: Driver, storeId: number, storeName: string): Promise<void> {
  await goHome(driver)
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

  expect(await clickByIdOrText(driver, 'home-search-entry', '搜索美食、店铺')).assertTrue()
  await driver.delayMs(2500)
  const input: Component = requireComponent(
    await driver.waitForComponent(ON.id('search-input'), 10000), 'search-input')
  await input.click()
  await driver.delayMs(800)
  await input.inputText(storeName)
  await driver.delayMs(1000)
  expect(await clickByIdOrText(driver, 'search-submit', '搜索')).assertTrue()
  await driver.delayMs(3500)
  expect(await clickByIdOrText(driver, 'search-store-' + storeId, storeName)).assertTrue()
  await driver.delayMs(4500)
}

/**
 * 核心断言：逐个点分类芯片，至少有一个分类的条数严格小于「全部」，
 * 且每个分类都非空，最后点回「全部」恢复原始条数。
 */
async function assertSwitchingWorks(driver: Driver, label: string): Promise<void> {
  const total: number = await readGoodsCount(driver)
  console.info('[StoreCategoryFilter] ' + label + ' 全部 = ' + total)
  expect(total > 0).assertTrue()

  // 芯片用「文案」定位而不是 id：实测 ON.id('goods-cat-xxx') 取不到
  // （横向 Scroll 内的 Text 节点 id 不参与匹配），而 ON.text() 能稳定拿到。
  const names: string[] = ['招牌热销', '人气主食', '特色小吃', '解腻饮品']
  let changed: number = 0
  let checked: number = 0
  for (let i = 0; i < names.length; i++) {
    const name: string = names[i]
    const chip = await driver.findComponent(ON.text(name))
    if (!isFound(chip)) {
      console.info('[StoreCategoryFilter] ' + label + ' chip not found: ' + name)
      continue
    }
    await (chip as Component).click()
    await driver.delayMs(2000)
    const n: number = await readGoodsCount(driver)
    console.info('[StoreCategoryFilter] ' + label + ' chip ' + name + ' -> ' + n)
    expect(n > 0).assertTrue()
    checked++
    if (n < total) {
      changed++
    }
  }
  console.info('[StoreCategoryFilter] ' + label + ' checked=' + checked + ' changed=' + changed)
  // 店铺至少要有 2 个可点分类，否则「切换」无从谈起
  expect(checked >= 2).assertTrue()
  // 修复前每个分类都等于「全部」，changed 恒为 0
  expect(changed > 0).assertTrue()

  const allChip = await driver.findComponent(ON.text('全部'))
  if (isFound(allChip)) {
    await (allChip as Component).click()
    await driver.delayMs(2000)
    const backToAll: number = await readGoodsCount(driver)
    console.info('[StoreCategoryFilter] ' + label + ' back to 全部 = ' + backToAll)
    expect(backToAll).assertEqual(total)
  }
}

export default function storeCategoryFilterTest() {
  describe('StoreCategoryFilter', () => {
    it('StoreCategoryFilter_switching_category_changes_goods_list', 0, async () => {
      const driver: Driver = Driver.create()
      await launchAppUnderTest(driver)
      await enterStore(driver, STORE_ID, STORE_NAME)
      await assertSwitchingWorks(driver, 'store2')
    })

    it('StoreCategoryFilter_second_store_also_switches', 0, async () => {
      // 追加店铺集合里的另一家店：确认修复不是只对某一家店生效
      const driver: Driver = Driver.create()
      await launchAppUnderTest(driver)
      await enterStore(driver, 34, '武昌热干面')
      await assertSwitchingWorks(driver, 'store34')
    })
  })
}
/**
 * 店铺详情页商品行「- 数量 +」回归（设备端 UiTest）。
 *
 * 背景：用户反馈在店铺详情页点商品行「+」后，数量数字不显示 / 显示不正确。
 *
 * 根因（两处叠加，都会导致该行不刷新）：
 *   1. getQty() 读的是 AppStorage.get('cartItems')，绕过了 ArkUI 的状态观察，
 *      行内不会建立对购物车的依赖；
 *   2. ForEach 的 key 用的是稳定的 goods.id，ArkUI 按 key 复用列表项、键不变就不重建。
 *   结果：购物车角标（@State cartCount）会变，但商品行的数字纹丝不动。
 *
 * 修法：getQty 改读被观察的 this.cartItems；并把 goodsRenderVersion 拼进 ForEach key
 *       强制重建（与 CartPage 的 cartRenderVersion、MerchantOrdersPage 的 renderVersion 同一套路）。
 *
 * 本用例的断言刻意与「初始数量」无关：先读当前数字，再点「+」，要求**恰好 +1**。
 * 修复前该断言必然失败（数字不会变），因此它能真正锁住这个缺陷。
 *
 * 固定数据（种子数据，见 DataSeeder）：storeId=2「星巴克咖啡」、goodsId=32「经典单品」
 * 是**无规格**菜品（goods_specs 为空），因此商品行渲染的是「+」而不是「选规格」。
 */
import { Driver, ON, Component } from '@kit.TestKit'
import { describe, it, expect } from '@ohos/hypium'
import { isFound, requireComponent, launchAppUnderTest, clickByIdOrText, scrollUntilVisible, openQuickLoginDialog } from './UiTestHelper'

const STORE_ID: number = 2
const STORE_NAME: string = '星巴克咖啡'
const GOODS_ID: number = 32
const QTY_ID: string = 'goods-qty-' + GOODS_ID
const PLUS_ID: string = 'goods-plus-' + GOODS_ID
const MINUS_ID: string = 'goods-minus-' + GOODS_ID

/** 读商品行上的数量；数字没显示（qty=0 时不渲染）就当作 0。 */
async function readQty(driver: Driver): Promise<number> {
  const comp: Component | null = await driver.findComponent(ON.id(QTY_ID))
  if (!isFound(comp)) {
    return 0
  }
  const text: string = await (comp as Component).getText()
  const parsed: number = parseInt(text, 10)
  // parseInt 失败得到 NaN，而 NaN > 0 为 false，正好归一到 0，不用额外判 isNaN
  return parsed > 0 ? parsed : 0
}

export default function storeDetailCartTest() {
  describe('StoreDetailCart', () => {
    it('StoreDetailCart_plus_button_updates_row_quantity', 0, async () => {
      const driver: Driver = Driver.create()
      await launchAppUnderTest(driver)

      // ---------- 1. 确保已登录（已登录则直接落在首页） ----------
      let home = await driver.waitForComponent(ON.id('home-search-entry'), 8000)
      if (!isFound(home)) {
        console.info('[StoreDetailCart] not on home, trying quick login')
        const quick = await driver.waitForComponent(ON.id('version-text'), 10000)
        if (isFound(quick)) {
          await openQuickLoginDialog(driver)
          const userBtn = await driver.waitForComponent(ON.id('quick-login-user'), 5000)
          if (isFound(userBtn)) {
            await (userBtn as Component).click()
            await driver.delayMs(4000)
          }
        }
        home = await driver.waitForComponent(ON.id('home-search-entry'), 10000)
      }
      requireComponent(home, 'home-search-entry')

      // ---------- 2. 首页 → 搜索 → 进入店铺详情 ----------
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

      // ---------- 3. 找到该无规格菜品的「+」 ----------
      const plus: Component = requireComponent(
        await scrollUntilVisible(driver, PLUS_ID), PLUS_ID)
      console.info('[StoreDetailCart] found ' + PLUS_ID)

      // ---------- 4. 点「+」后数字必须 +1（修复前这一步必然失败） ----------
      const before: number = await readQty(driver)
      console.info('[StoreDetailCart] qty before = ' + before)

      expect(await clickByIdOrText(driver, PLUS_ID, '+')).assertTrue()
      await driver.delayMs(3000)

      const after1: number = await readQty(driver)
      console.info('[StoreDetailCart] qty after 1st + = ' + after1)
      expect(after1).assertEqual(before + 1)

      // ---------- 5. 再点一次「+」必须到 +2 ----------
      expect(await clickByIdOrText(driver, PLUS_ID, '+')).assertTrue()
      await driver.delayMs(3000)

      const after2: number = await readQty(driver)
      console.info('[StoreDetailCart] qty after 2nd + = ' + after2)
      expect(after2).assertEqual(before + 2)

      // ---------- 6. 点「-」回落到 +1 ----------
      expect(await clickByIdOrText(driver, MINUS_ID, '-')).assertTrue()
      await driver.delayMs(3000)

      const after3: number = await readQty(driver)
      console.info('[StoreDetailCart] qty after - = ' + after3)
      expect(after3).assertEqual(before + 1)
    })
  })
}

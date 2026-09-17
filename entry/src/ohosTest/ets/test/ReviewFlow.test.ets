/**
 * 图文评价链路回归（设备端 UiTest + 直接调用应用服务）。
 *
 * 前置（由 scripts/device-review-regression.ps1 用后端接口布置）：
 *   - 已登录用户 13800138000；
 *   - 存在一笔「已完成且未评价」的订单（status=4 / escrow=1 / reviewed=0），店铺 1 黄焖鸡米饭。
 *
 * 一条用例按顺序覆盖整条链路（合并成一条是因为用例之间共享同一个应用实例，
 * 拆开会让「订单6 已评价」这类前置状态互相破坏）：
 *   1. 契约：应用自身数据里找出可评价订单 →「我的」页「已完成」快捷入口 → 已完成 → 订单卡片 → 订单详情 →「评价商品」→
 *      断言评价页五星评分/标签/文字评价/添加图片/图片计数 0/3/提交按钮都在（滚动区内的组件用 scrollSearch 找）；
 *   2. 上传：在应用沙箱里生成一张真实 PNG，调用**应用自己的** uploadReviewImageRemote() 上传
 *      （multipart 走 @ohos.net.http，与页面同一条代码路径），断言返回可访问地址；
 *   3. 提交：用应用自己的 submitReviewRemote() 把这笔订单评成图文评价（带刚上传的图片）；
 *   4. 渲染+预览：搜索进店 → 店铺详情评价区必须渲染出图片节点 → 点击进入 pages/ReviewImagePage
 *      全屏预览页 → 点击返回。
 *
 * 环境限制（已实测确认，不是应用缺陷）：本机模拟器图库为空（/mnt/data/100/media_fuse/Photo 下只有
 * 空的「其它」相册），没有相机应用，mediatool 也没有导入通道，因此**系统选图器里没有任何图片可选**。
 * 选图器本身能正常打开并驱动（dumpLayout 可见 photo_grid_base、"已选 0/3"、完成、拍照），
 * 所以在有图片的真机上补一步「选中第 1 张 → 完成」即可闭合选图器环节；模拟器上改为直接调用同一条
 * 上传代码路径。
 */
import { Driver, ON, Component, abilityDelegatorRegistry } from '@kit.TestKit'
import { fileIo } from '@kit.CoreFileKit'
import { describe, it, expect } from '@ohos/hypium'
import { isFound, requireComponent, launchAppUnderTest, clickByIdOrText, scrollToIdOrText, scrollUntilVisible, clickComponentCenter, logComponentsAt, waitAny } from './UiTestHelper'
import { syncUserOrdersFromServer, uploadReviewImageRemote, submitReviewRemote, syncStoreReviewsRemote } from '../../../main/ets/service/AppStorageManager'
import { Order } from '../../../main/ets/model/Models'

/** 店铺 1 在搜索结果里的店铺名（用于兜底文案匹配）。 */
const STORE_1_NAME: string = '黄焖鸡米饭'
/** 1x1 透明 PNG（67 字节），用于在不依赖系统图库的前提下产生一张真实图片文件。 */
const PNG_BYTES: number[] = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82
]

/** 在应用沙箱里写一张真实 PNG，返回可被 fileIo 直接打开的路径。 */
function writeTestPng(): string {
  const appContext = abilityDelegatorRegistry.getAbilityDelegator().getAppContext()
  const path: string = appContext.filesDir + '/dsh-review-' + Date.now() + '.png'
  const file = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
  try {
    const buffer: ArrayBuffer = new ArrayBuffer(PNG_BYTES.length)
    const view: Uint8Array = new Uint8Array(buffer)
    for (let i = 0; i < PNG_BYTES.length; i++) {
      view[i] = PNG_BYTES[i]
    }
    fileIo.writeSync(file.fd, buffer)
  } finally {
    fileIo.closeSync(file)
  }
  console.info('[ReviewFlow] test png written: ' + path)
  return path
}

/** 找出「已完成且未评价」的订单（host 脚本的 fixture 保证存在，取 id 最大的一笔）。 */
async function findReviewableOrder(): Promise<Order | null> {
  await syncUserOrdersFromServer()
  const orders: Order[] = AppStorage.get<Order[]>('orderList') || []
  let target: Order | null = null
  for (let i = 0; i < orders.length; i++) {
    const o: Order = orders[i]
    if (o.status === 4 && (o.escrowStatus ?? 0) === 1 && o.reviewed === 0) {
      if (target === null || o.id > target.id) {
        target = o
      }
    }
  }
  console.info('[ReviewFlow] reviewable order = ' + (target === null ? 'none' : target.id.toString()))
  return target
}

export default function reviewFlowTest() {
  describe('ReviewFlow', () => {
    it('ReviewFlow_contract_upload_submit_render_preview', 0, async () => {
      const driver: Driver = Driver.create()
      await launchAppUnderTest(driver)
      const consent = await waitAny(driver, ['privacy-accept'], 8000)
      if (isFound(consent)) {
        await clickByIdOrText(driver, 'privacy-accept', '同意并继续')
        await driver.delayMs(2000)
      }
      // 若仍在登录页（本次首登）点快捷登录跳首页；已登录则已在首页
      const loginBtn = await waitAny(driver, ['quick-login-user'], 5000)
      if (isFound(loginBtn)) {
        expect(await clickByIdOrText(driver, 'quick-login-user', '一键登录用户')).assertTrue()
        await driver.delayMs(3000)
      }

      // ---------- 1. 用应用自身数据找到可评价订单，并从界面走到评价页 ----------
      const order: Order | null = await findReviewableOrder()
      expect(order !== null).assertTrue()
      if (order === null) {
        return
      }
      const orderId: number = order.id
      const orderCardId: string = 'order-card-' + orderId

      // 订单列表已从底部 Tab 收敛为独立路由页（pages/OrderListPage），改从「我的」页「已完成」快捷入口进入（自带 status=4 过滤）
      expect(await clickByIdOrText(driver, 'tab-3', '我的')).assertTrue()
      await driver.delayMs(1500)
      expect(await clickByIdOrText(driver, '已完成', '已完成')).assertTrue()
      await driver.delayMs(2500)
      expect(await clickByIdOrText(driver, 'order-filter-4', '已完成')).assertTrue()
      await driver.delayMs(2500)
      expect(await scrollToIdOrText(driver, orderCardId, STORE_1_NAME) !== null).assertTrue()
      expect(await clickByIdOrText(driver, orderCardId, STORE_1_NAME)).assertTrue()
      await driver.delayMs(3000)
      expect(await clickByIdOrText(driver, 'order-review-entry', '评价商品')).assertTrue()
      await driver.delayMs(3000)
      requireComponent(await driver.findComponent(ON.id('review-submit')), 'review-submit')

      // 评价页契约：评分/标签/文字评价/添加图片/计数
      requireComponent(await driver.findComponent(ON.id('review-star-5')), 'review-star-5')
      requireComponent(await driver.findComponent(ON.id('review-tag-0')), 'review-tag-0')
      // 文字评价与图片评价卡片在 Scroll 底部，必须滚动后才有节点
      requireComponent(await scrollToIdOrText(driver, 'review-content', ''), 'review-content')
      requireComponent(await scrollToIdOrText(driver, 'review-add-image', '添加图片'), 'review-add-image')
      const counter: Component = requireComponent(
        await scrollToIdOrText(driver, 'review-image-count', ''), 'review-image-count')
      const counterText: string = await counter.getText()
      console.info('[ReviewFlow] image counter = ' + counterText)
      expect(counterText).assertEqual('0/3')

      // ---------- 2. 用应用自己的上传代码路径上传一张真实 PNG ----------
      const pngPath: string = writeTestPng()
      const imageUrl: string = await uploadReviewImageRemote(pngPath)
      console.info('[ReviewFlow] uploaded image url = ' + imageUrl)
      expect(imageUrl.indexOf('/uploads/') >= 0).assertTrue()

      // ---------- 3. 用应用自己的提交接口写一条带图评价 ----------
      const goodsId: number = order.items[0].goods.id
      const tags: string[] = ['味道好']
      const images: string[] = [imageUrl]
      const submitted: boolean = await submitReviewRemote(orderId, goodsId, 5, 'DSH 设备实测图文评价', tags, images, 0)
      console.info('[ReviewFlow] submitReviewRemote orderId=' + orderId + ' ok=' + submitted)
      expect(submitted).assertTrue()
      await syncStoreReviewsRemote(order.storeId)

      // ---------- 4. 界面侧：店铺详情评价区渲染图片 → 全屏预览 → 返回 ----------
      // 当前停在评价页（独立路由页，没有底部 Tab），逐级点返回控件回到订单列表，再切到首页 Tab。
      expect(await clickByIdOrText(driver, 'review-back', '‹ 返回')).assertTrue()
      await driver.delayMs(2500)
      expect(await clickByIdOrText(driver, 'order-detail-back', '‹')).assertTrue()
      await driver.delayMs(2500)
      // 订单列表现在是独立路由页（OrderListPage，从「我的」pushUrl 进入），
      // 比旧「订单 Tab」多一层路由，需再点一次返回才回到底部 Tab。
      expect(await clickByIdOrText(driver, 'order-list-back', '‹ 返回')).assertTrue()
      await driver.delayMs(2500)
      expect(await clickByIdOrText(driver, 'tab-0', '首页')).assertTrue()
      await driver.delayMs(2500)
      expect(await clickByIdOrText(driver, 'home-search-entry', '搜索美食、店铺')).assertTrue()
      await driver.delayMs(2500)
      const input: Component = requireComponent(
        await driver.waitForComponent(ON.id('search-input'), 10000), 'search-input')
      await input.click()
      await driver.delayMs(800)
      await input.inputText('黄焖鸡')
      await driver.delayMs(1000)
      expect(await clickByIdOrText(driver, 'search-submit', '搜索')).assertTrue()
      await driver.delayMs(3500)
      expect(await clickByIdOrText(driver, 'search-store-' + order.storeId, STORE_1_NAME)).assertTrue()
      await driver.delayMs(4500)

      const reviewImage: Component = requireComponent(
        await scrollUntilVisible(driver, 'store-review-image-0'), 'store-review-image-0')
      console.info('[ReviewFlow] review image rendered in store detail')
      const bounds = await reviewImage.getBounds()
      const cx: number = Math.floor((bounds.left + bounds.right) / 2)
      const cy: number = Math.floor((bounds.top + bounds.bottom) / 2)
      console.info('[ReviewFlow] review image bounds = [' + bounds.left + ',' + bounds.top + '][' + bounds.right + ',' + bounds.bottom + '] center=(' + cx + ',' + cy + ')')
      await logComponentsAt(driver, cx, cy)

      expect(await clickComponentCenter(driver, reviewImage, 'store-review-image-0')).assertTrue()
      let previewPage = await driver.waitForComponent(ON.id('review-image-page'), 6000)
      if (!isFound(previewPage)) {
        // 中心点点击没生效时改用组件点击重试一次（两者走的注入通道略有差异）
        console.info('[ReviewFlow] center click did not navigate, retry with component.click()')
        const again = requireComponent(
          await scrollToIdOrText(driver, 'store-review-image-0', ''), 'store-review-image-0(retry)')
        await again.click()
        previewPage = await driver.waitForComponent(ON.id('review-image-page'), 6000)
      }
      const previewImage = await driver.findComponent(ON.id('review-image-preview'))
      console.info('[ReviewFlow] preview page visible=' + isFound(previewPage) + ' preview image visible=' + isFound(previewImage))
      expect(isFound(previewPage)).assertTrue()
      expect(isFound(previewImage)).assertTrue()

      // 点击任意位置返回店铺详情
      const previewRoot: Component = requireComponent(previewPage, 'review-image-page')
      await clickComponentCenter(driver, previewRoot, 'review-image-page')
      await driver.delayMs(2500)
      expect(isFound(await driver.findComponent(ON.id('review-image-preview')))).assertFalse()
    })
  })
}

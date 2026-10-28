import { describe, it, expect } from '@ohos/hypium'
import { Driver, ON, Component, abilityDelegatorRegistry } from '@kit.TestKit'
import { window, UIContext } from '@kit.ArkUI'
import { UIAbility } from '@kit.AbilityKit'
import BuildProfile from 'BuildProfile'
import { launchAppUnderTest, isFound, requireComponent, clickByIdOrText, scrollUntilVisible } from './UiTestHelper'
import { User, UserRole, Order, StoreItem } from '../../../main/ets/model/Models'
import { loginRemote, logout, syncStoresFromServer, syncUserOrdersFromServer, syncCartRemote } from '../../../main/ets/service/AppStorageManager'
import { getApiBaseUrl } from '../../../main/ets/service/HttpClient'
import { getQuickLoginAccount, QuickLoginAccount } from '../../../main/ets/common/QuickLoginConfig'
import { saveAppearanceSettings } from '../../../main/ets/service/AppearanceSettings'
import { clearCartApi, addCartItemApi } from '../../../main/ets/service/ApiService'
import { common } from '@kit.AbilityKit'
import { fileIo } from '@kit.CoreFileKit'

let screenshotDirectory: string = ''

interface ReviewFixtures {
  storeId: number
  storeName: string
  goodsId: number
  reviewOrderId: number
  partialOrderId: number
  unpaidOrderId: number
  giftActivityId: number
  image: string
  addressId: number
}
interface ReviewConfiguration { fixtures: ReviewFixtures }

class ReviewTarget {
  page: string
  title: string
  constructor(page: string, title: string) { this.page = page; this.title = title }
}

function targets(role: UserRole, fixture: ReviewFixtures): ReviewTarget[] {
  let definitions: string[] = []
  if (role === UserRole.CUSTOMER) {
    definitions = ['SearchPage|搜索','LocationPage|选择位置','AddressListPage|收货地址','CheckoutPage|确认订单',
      'OrderDetailPage|订单详情','OrderSupportPage|订单配送与售后','OrderListPage|我的订单','CouponCenterPage|优惠券中心',
      'FavoriteListPage|我的收藏','ReviewPage|订单评价','ProfileEditPage|编辑个人信息','BalancePage|我的钱包',
      'AddBankCardPage|添加银行卡','SettingsPage|设置','AccountSecurityPage|账号安全','PasswordResetPage|找回登录密码',
      'AppSettingsPage|应用设置','PrivacyPolicyPage|隐私政策','ContactCustomerServicePage|售后帮助',
      'ProductListPage|附近全部商品','StoreDetailPage|' + fixture.storeName,'RankingPage|榜单','ReviewImagePage|评价图片','ConsentPage|']
  } else if (role === UserRole.MERCHANT) {
    definitions = ['MerchantOrdersPage|订单管理','MerchantStatsPage|收入统计','MerchantMarketingPage|营销活动',
      'MerchantCenterPage|商户中心','MerchantAddGoodsPage|添加商品','MerchantEditGoodsPage|编辑商品','MerchantReviewsPage|评价管理']
  } else if (role === UserRole.ADMIN) {
    definitions = ['AdminCenterPage|平台管理','AdminCategoryPage|分类管理','AdminStorePage|店铺管理','AdminEmployeePage|员工管理',
      'AdminProductPage|商品监管','AdminUserPage|用户管理','AdminStatisticsPage|平台统计','AdminOrderPage|订单管理',
      'AdminRefundPage|退款审批','AdminMarketingPage|营销监管','AdminAuditPage|操作审计','AdminRiderPage|骑手管理',
      'AdminContentPage|内容管理','AdminAssistantPage|AI 助手设置']
  } else { definitions = ['RiderCenterPage|骑手中心','RiderOrderPoolPage|抢单大厅','RiderOrdersPage|我的配送单'] }
  return definitions.map((definition: string): ReviewTarget => {
    const parts: string[] = definition.split('|')
    return new ReviewTarget(parts[0], parts[1])
  })
}

async function navigate(context: UIContext, page: string, fixture: ReviewFixtures): Promise<void> {
  await new Promise<void>((resolve, reject) => {
    context.runScopedTask((): void => {
      context.getRouter().pushUrl({ url: 'pages/' + page, params: { orderId: fixture.partialOrderId } }).then(() => { resolve() }).catch(() => { reject(new Error('Route failed: ' + page)) })
    })
  })
}

async function verifyScreen(driver: Driver, context: UIContext, target: ReviewTarget, name: string): Promise<void> {
  await waitLoaded(driver)
  const marker: string = target.page === 'ConsentPage' ? 'privacy-accept' : 'page-title'
  const title: Component = target.title === ''
    ? requireComponent(await driver.waitForComponent(ON.id(marker), 10000), target.page + ' marker')
    : await waitTitle(driver, target.title)
  if (target.title !== '') { expect(await title.getText()).assertEqual(target.title) }
  expect((context.getRouter().getState().name ?? '').includes(target.page)).assertTrue()
  const size = await driver.getDisplaySize()
  const bounds = await title.getBounds()
  expect(bounds.left >= 0 && bounds.right <= size.x && bounds.top >= 0 && bounds.bottom <= size.y).assertTrue()
  expect(await driver.screenCap(screenshotDirectory + '/' + name + '.png')).assertTrue()
  console.info('[AllPagesReview] PASS ' + name)
}

async function waitLoaded(driver: Driver): Promise<void> {
  await driver.delayMs(800)
  const messages: string[] = ['加载中', '加载中…', '正在加载…', '正在加载退款记录…',
    '正在加载评价…', '正在加载订单…', '正在从服务端加载统计…', '正在加载可抢订单…', '正在加载附近地点…']
  for (let attempt: number = 0; attempt < 60; attempt++) {
    let loading: boolean = false
    for (const message of messages) {
      if (isFound(await driver.findComponent(ON.text(message)))) { loading = true; break }
    }
    if (!loading) { await driver.waitForIdle(500, 5000); return }
    await driver.delayMs(500)
  }
  throw new Error('Page content did not finish loading')
}

async function waitTitle(driver: Driver, expected: string): Promise<Component> {
  for (let attempt: number = 0; attempt < 30; attempt++) {
    try {
      const component: Component | null = await driver.findComponent(ON.id('page-title').text(expected))
      if (component !== null) { return component }
    } catch (_) {}
    await driver.delayMs(200)
  }
  throw new Error('Expected page title not reached: ' + expected)
}

async function waitEnabled(driver: Driver, id: string): Promise<Component> {
  for (let attempt: number = 0; attempt < 40; attempt++) {
    try {
      const component: Component | null = await driver.findComponent(ON.id(id))
      if (component !== null && await component.isEnabled()) { return component }
    } catch (_) {}
    await driver.delayMs(200)
  }
  throw new Error('Enabled control not reached: ' + id)
}

async function roleReview(role: UserRole): Promise<void> {
  expect(BuildProfile.UI_TEST_BASE_URL.startsWith('http://10.0.2.2:')).assertTrue()
  const config: ReviewConfiguration = JSON.parse(BuildProfile.QUICK_LOGIN_CONFIG) as ReviewConfiguration
  const fixture: ReviewFixtures = config.fixtures
  const driver: Driver = Driver.create()
  await launchAppUnderTest(driver)
  const ability: UIAbility = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility()
  const mainWindow: window.Window = await window.getLastWindow(ability.context)
  const context: UIContext = mainWindow.getUIContext()
  const host: common.UIAbilityContext = ability.context
  screenshotDirectory = host.filesDir + '/ui-review'
  try { fileIo.mkdirSync(screenshotDirectory) } catch (_) {}
  const account: QuickLoginAccount | undefined = getQuickLoginAccount(role, getApiBaseUrl())
  if (account === undefined) { throw new Error('Isolated role credential unavailable') }
  const user: User | undefined = await loginRemote(account.phone, account.password, role === 0 ? 'USER' : role === 1 ? 'MERCHANT' : role === 2 ? 'ADMIN' : 'RIDER')
  expect(user?.role).assertEqual(role)
  await syncStoresFromServer()
  if (role === UserRole.CUSTOMER) { await syncUserOrdersFromServer(); await syncCartRemote() }
  if (role === UserRole.CUSTOMER) {
    await navigate(context, 'SettingsPage', fixture)
    context.runScopedTask((): void => { context.getRouter().clear() })
    await driver.delayMs(1000)
  }
  AppStorage.setOrCreate<number>('selectedStoreId', fixture.storeId)
  AppStorage.setOrCreate<string>('selectedStoreName', fixture.storeName)
  AppStorage.setOrCreate<number>('merchantGoodsStoreId', fixture.storeId)
  AppStorage.setOrCreate<number>('merchantEditGoodsId', fixture.goodsId)
  AppStorage.setOrCreate<number>('currentOrderId', fixture.reviewOrderId)
  AppStorage.setOrCreate<number>('checkoutStoreId', fixture.storeId)
  AppStorage.setOrCreate<string>('passwordResetMode', 'login')
  AppStorage.setOrCreate<string>('productListTitle', '附近全部商品')
  AppStorage.setOrCreate<string>('reviewPreviewUrl', fixture.image.startsWith('http') ? fixture.image : getApiBaseUrl() + fixture.image)
  const previousMode: string = AppStorage.get<string>('appearanceColorMode') ?? 'system'
  const previousScale: number = AppStorage.get<number>('appearanceFontScale') ?? 1
  const previousNavigation: string = AppStorage.get<string>('navigationHandMode') ?? 'auto'
  try {
    for (const variant of ['light','dark','light-large','dark-large']) {
      await saveAppearanceSettings(host, variant.startsWith('dark') ? 'dark' : 'light', variant.endsWith('large') ? 1.3 : 1, 'center')
      for (const target of targets(role, fixture)) {
        AppStorage.setOrCreate<number>('currentOrderId', fixture.reviewOrderId)
        AppStorage.setOrCreate<number>('selectedStoreId', fixture.storeId)
        AppStorage.setOrCreate<string>('selectedStoreName', fixture.storeName)
        AppStorage.setOrCreate<number>('checkoutStoreId', fixture.storeId)
        AppStorage.setOrCreate<number>('merchantGoodsStoreId', fixture.storeId)
        AppStorage.setOrCreate<number>('merchantEditGoodsId', fixture.goodsId)
        await navigate(context, target.page, fixture)
        await verifyScreen(driver, context, target, role.toString() + '-' + variant + '-' + target.page)
        if (target.page === 'BalancePage') { expect(isFound(await driver.findComponent(ON.text('立即充值')))).assertFalse() }
        context.runScopedTask((): void => { context.getRouter().back() })
        // 页面返回会触发首页真实刷新，留出间隔，避免批量巡检耗尽浏览限流预算。
        await driver.delayMs(role === UserRole.CUSTOMER ? 1500 : 350)
      }
      if (role === UserRole.CUSTOMER) {
        await navigate(context, 'Index', fixture)
        expect(await clickByIdOrText(driver, 'tab-0', '首页')).assertTrue()
        expect(isFound(await driver.waitForComponent(ON.id('home-search-entry'), 10000))).assertTrue()
        expect(await driver.screenCap(screenshotDirectory + '/0-' + variant + '-Index.png')).assertTrue()
        console.info('[AllPagesReview] PASS 0-' + variant + '-Index')
        for (const tab of [new ReviewTarget('2', '购物车'), new ReviewTarget('1', 'AI 智能助手')]) {
          expect(await clickByIdOrText(driver, 'tab-' + tab.page, '')).assertTrue()
          await driver.waitForIdle(500, 5000)
          const heading = await waitTitle(driver, tab.title)
          expect(await heading.getText()).assertEqual(tab.title)
          expect(await driver.screenCap(screenshotDirectory + '/0-' + variant + '-' + (tab.page === '2' ? 'CartPage' : 'AssistantPage') + '.png')).assertTrue()
          console.info('[AllPagesReview] PASS 0-' + variant + '-' + (tab.page === '2' ? 'CartPage' : 'AssistantPage'))
        }
        expect(await clickByIdOrText(driver, 'tab-3', '我的')).assertTrue()
        requireComponent(await driver.waitForComponent(ON.id('profile-account'), 5000), 'profile account')
        expect(await driver.screenCap(screenshotDirectory + '/0-' + variant + '-ProfileMainPage.png')).assertTrue()
        console.info('[AllPagesReview] PASS 0-' + variant + '-ProfileMainPage')
        logout()
        expect(isFound(await driver.waitForComponent(ON.id('login-phone'), 10000))).assertTrue()
        await driver.delayMs(800)
        expect(isFound(await driver.findComponent(ON.id('profile-account')))).assertFalse()
        expect(await driver.screenCap(screenshotDirectory + '/0-' + variant + '-LoginPage.png')).assertTrue()
        expect(await clickByIdOrText(driver, 'login-mode-register', '注册')).assertTrue()
        requireComponent(await driver.waitForComponent(ON.id('login-email'), 5000), 'registration form')
        await driver.delayMs(800)
        expect(isFound(await driver.findComponent(ON.id('login-role-merchant')))).assertFalse()
        expect(isFound(await driver.findComponent(ON.id('login-role-rider')))).assertFalse()
        expect(await driver.screenCap(screenshotDirectory + '/0-' + variant + '-Registration.png')).assertTrue()
        console.info('[AllPagesReview] PASS 0-' + variant + '-LoginPage')
        await loginRemote(account.phone, account.password, 'USER')
        await syncStoresFromServer()
        await syncUserOrdersFromServer()
        await syncCartRemote()
        context.runScopedTask((): void => { context.getRouter().replaceUrl({ url: 'pages/SettingsPage' }) })
        await driver.delayMs(500)
      }
    }
    if (role === UserRole.MERCHANT) {
      await navigate(context, 'MerchantMarketingPage', fixture)
      const edit = requireComponent(await scrollUntilVisible(driver, 'marketing-edit-' + fixture.giftActivityId.toString()), 'gift edit')
      await edit.click()
      const threshold = requireComponent(await driver.waitForComponent(ON.id('marketing-threshold'), 5000), 'gift threshold')
      expect(await threshold.getText()).assertEqual('75')
      expect(isFound(await driver.findComponent(ON.id('marketing-gift-goods')))).assertTrue()
      const submit = requireComponent(await driver.findComponent(ON.id('marketing-submit')), 'marketing submit')
      const rect = await submit.getBounds(); const display = await driver.getDisplaySize()
      expect(rect.bottom <= display.y && rect.top >= 0).assertTrue()
      await submit.click()
      await driver.delayMs(1500)
      expect(await requireComponent(await driver.findComponent(ON.id('page-title')), 'marketing list').getText()).assertEqual('营销活动')
      console.info('[AllPagesReview] PASS gift-native-edit-save')
      await navigate(context, 'MerchantCenterPage', fixture)
      await waitTitle(driver, '商户中心')
      const manageGoods = requireComponent(await scrollUntilVisible(driver, 'merchant-store-goods-' + fixture.storeId.toString()), 'goods management entry')
      await manageGoods.click()
      await waitTitle(driver, '商品管理')
      expect(await clickByIdOrText(driver, 'page-header-action', '添加商品')).assertTrue()
      await waitTitle(driver, '添加商品')
      requireComponent(await driver.findComponent(ON.id('merchant-goods-name')), 'stable goods form field')
      console.info('[AllPagesReview] PASS shared-goods-header-and-add-entry')
    }
  } finally {
    await saveAppearanceSettings(host, previousMode, previousScale, previousNavigation)
    logout()
    await driver.delayMs(800)
    context.runScopedTask((): void => { context.getRouter().replaceUrl({ url: 'pages/Index' }) })
  }
}

export default function allPagesReviewTest(): void {
  describe('UiReviewStates', () => {
    it('labels_empty_actions_history_and_native_date_picker', 0, async () => {
      expect(BuildProfile.UI_TEST_BASE_URL.startsWith('http://10.0.2.2:')).assertTrue()
      const fixture: ReviewFixtures = (JSON.parse(BuildProfile.QUICK_LOGIN_CONFIG) as ReviewConfiguration).fixtures
      const driver: Driver = Driver.create()
      if (isFound(await driver.findComponent(ON.text('退出应用')))) {
        await requireComponent(await driver.findComponent(ON.text('退出应用')), 'decline input method').click()
      }
      await launchAppUnderTest(driver)
      const ability: UIAbility = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility()
      const context: UIContext = (await window.getLastWindow(ability.context)).getUIContext()
      screenshotDirectory = ability.context.filesDir + '/ui-review'
      try { fileIo.mkdirSync(screenshotDirectory) } catch (_) {}
      const customer: QuickLoginAccount | undefined = getQuickLoginAccount(UserRole.CUSTOMER, getApiBaseUrl())
      const merchant: QuickLoginAccount | undefined = getQuickLoginAccount(UserRole.MERCHANT, getApiBaseUrl())
      if (customer === undefined || merchant === undefined) { throw new Error('Isolated credentials missing') }
      await loginRemote(customer.phone, customer.password, 'USER')
      await syncStoresFromServer(); await syncUserOrdersFromServer(); await syncCartRemote()
      await saveAppearanceSettings(ability.context, 'dark', 1.3, 'center')
      try {
        await navigate(context, 'AccountSecurityPage', fixture)
        await waitTitle(driver, '账号安全')
        const password = requireComponent(await driver.waitForComponent(ON.id('account-old-password'), 5000), 'old password')
        await password.inputText('ui-review-draft')
        expect(isFound(await driver.findComponent(ON.text('当前登录密码')))).assertTrue()
        await driver.pressBack()
        expect(await driver.screenCap(screenshotDirectory + '/states-password-label.png')).assertTrue()
        console.info('[AllPagesReview] PASS password-label-after-input')
        await navigate(context, 'AddressListPage', fixture)
        expect(await clickByIdOrText(driver, 'address-edit-' + fixture.addressId.toString(), '编辑')).assertTrue()
        const name = requireComponent(await driver.waitForComponent(ON.id('address-name'), 5000), 'address name')
        expect((await name.getText()).length > 0).assertTrue()
        await driver.screenCap(screenshotDirectory + '/states-address-filled.png')
        expect(isFound(await driver.findComponent(ON.text('收货人')))).assertTrue()
        expect(isFound(await driver.findComponent(ON.text('联系电话')))).assertTrue()
        expect(await clickByIdOrText(driver, 'address-form-cancel', '取消')).assertTrue()
        console.info('[AllPagesReview] PASS address-labels-with-saved-values')
        expect(await clearCartApi() !== null).assertTrue()
        await syncCartRemote()
        await navigate(context, 'Index', fixture)
        expect(await clickByIdOrText(driver, 'tab-2', '购物车')).assertTrue()
        await waitTitle(driver, '购物车')
        expect(await clickByIdOrText(driver, 'empty-state-action', '去逛店铺')).assertTrue()
        expect(isFound(await driver.waitForComponent(ON.id('home-search-entry'), 5000))).assertTrue()
        expect(await addCartItemApi(fixture.goodsId, 0, 2) !== null).assertTrue()
        await syncCartRemote()
        console.info('[AllPagesReview] PASS empty-cart-action-reaches-home')
        await navigate(context, 'ContactCustomerServicePage', fixture)
        expect(await clickByIdOrText(driver, 'support-refund-progress', '查看退款 / 售后进度')).assertTrue()
        await waitTitle(driver, '我的订单')
        expect(AppStorage.get<number>('orderFilterStatus')).assertEqual(-1)
        requireComponent(await scrollUntilVisible(driver, 'order-card-' + fixture.partialOrderId.toString()), 'completed partial refund remains findable')
        console.info('[AllPagesReview] PASS after-sales-includes-partially-refunded-order')
        logout()
        await navigate(context, 'FavoriteListPage', fixture)
        expect(await clickByIdOrText(driver, 'empty-state-action', '去登录')).assertTrue()
        expect(isFound(await driver.waitForComponent(ON.id('login-phone'), 5000))).assertTrue()
        console.info('[AllPagesReview] PASS logged-out-empty-action-reaches-login')
        await loginRemote(merchant.phone, merchant.password, 'MERCHANT')
        await navigate(context, 'MerchantMarketingPage', fixture)
        await waitTitle(driver, '营销活动')
        const create = await waitEnabled(driver, 'page-header-action')
        await create.click()
        await waitTitle(driver, '新建活动')
        expect(await clickByIdOrText(driver, 'marketing-start', '选择日期和时间')).assertTrue()
        const acceptDate = requireComponent(await driver.waitForComponent(ON.text('确定'), 5000), 'native date confirmation')
        await acceptDate.click()
        await driver.waitForIdle(500, 5000)
        const acceptTime = requireComponent(await driver.waitForComponent(ON.text('确定'), 5000), 'native time confirmation')
        await acceptTime.click()
        await driver.delayMs(400)
        const date = requireComponent(await driver.findComponent(ON.id('marketing-start')), 'selected start date')
        expect(/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:00$/.test(await date.getText())).assertTrue()
        expect(await clickByIdOrText(driver, 'marketing-submit', '保存')).assertTrue()
        const validation = requireComponent(await driver.waitForComponent(ON.id('marketing-error'), 5000), 'inline validation')
        expect(await validation.getText()).assertEqual('请选择开始和结束时间')
        const submit = requireComponent(await driver.findComponent(ON.id('marketing-submit')), 'footer remains accessible')
        const bounds = await submit.getBounds(); const size = await driver.getDisplaySize()
        expect(bounds.bottom <= size.y && bounds.top >= 0).assertTrue()
        expect(await driver.screenCap(screenshotDirectory + '/states-native-date-and-validation.png')).assertTrue()
        expect(await clickByIdOrText(driver, 'marketing-cancel', '取消')).assertTrue()
        console.info('[AllPagesReview] PASS native-date-picker-and-inline-error-footer')
        const editGift = requireComponent(await scrollUntilVisible(driver, 'marketing-edit-' + fixture.giftActivityId.toString()), 'gift edit')
        await editGift.click()
        await waitTitle(driver, '编辑活动')
        expect(await requireComponent(await driver.findComponent(ON.id('marketing-threshold')), 'preserved threshold').getText()).assertEqual('75')
        expect(await clickByIdOrText(driver, 'marketing-submit', '保存')).assertTrue()
        await waitTitle(driver, '营销活动')
        console.info('[AllPagesReview] PASS gift-native-edit-save')
      } catch (error) {
        await driver.screenCap(screenshotDirectory + '/states-failure.png')
        throw new Error(error instanceof Error ? error.message : 'UI state check failed; see states-failure.png')
      } finally { await saveAppearanceSettings(ability.context, 'system', 1, 'auto') }
    })
  })
  describe('AllPagesUser', () => { it('all_user_pages_in_four_appearance_variants', 0, async () => { await roleReview(UserRole.CUSTOMER) }) })
  describe('AllPagesMerchant', () => { it('all_merchant_pages_and_gift_save', 0, async () => { await roleReview(UserRole.MERCHANT) }) })
  describe('AllPagesAdmin', () => { it('all_admin_pages_in_four_appearance_variants', 0, async () => { await roleReview(UserRole.ADMIN) }) })
  describe('AllPagesRider', () => { it('all_rider_pages_in_four_appearance_variants', 0, async () => { await roleReview(UserRole.RIDER) }) })
  describe('AllPagesReview', () => {
    it('main_window_router_reaches_settings', 0, async () => {
      const driver: Driver = Driver.create()
      await launchAppUnderTest(driver)
      const ability: UIAbility = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility()
      console.info('[AllPagesReview] top=' + ability.context.abilityInfo.name)
      const mainWindow: window.Window = await window.getLastWindow(ability.context)
      const context: UIContext = mainWindow.getUIContext()
      context.runScopedTask((): void => { context.getRouter().pushUrl({ url: 'pages/SettingsPage' }) })
      expect(isFound(await driver.waitForComponent(ON.id('settings-back'), 10000))).assertTrue()
      console.info('[AllPagesReview] router=' + context.getRouter().getState().name)
      context.runScopedTask((): void => { context.getRouter().back() })
    })
  })
}

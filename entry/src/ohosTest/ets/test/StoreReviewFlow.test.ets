import { describe, it, expect } from '@ohos/hypium'
import { Driver, ON, abilityDelegatorRegistry } from '@kit.TestKit'
import { UIAbility } from '@kit.AbilityKit'
import { window, UIContext } from '@kit.ArkUI'
import { fileIo } from '@kit.CoreFileKit'
import BuildProfile from 'BuildProfile'
import { launchAppUnderTest, isFound, requireComponent, clickByIdOrText, scrollUntilVisible } from './UiTestHelper'
import { loginRemote, logout } from '../../../main/ets/service/AppStorageManager'
import { getApiBaseUrl, get, ApiResponse } from '../../../main/ets/service/HttpClient'
import { getQuickLoginAccount, QuickLoginAccount } from '../../../main/ets/common/QuickLoginConfig'
import { UserRole } from '../../../main/ets/model/Models'
import { saveAppearanceSettings } from '../../../main/ets/service/AppearanceSettings'

interface StoreReviewFixture { storeId: number }
interface StoreReviewConfiguration { fixtures: StoreReviewFixture }
interface ReviewStore { id: number; reviewStatus: number; platformStatus: number }

async function openRole(context: UIContext, driver: Driver, role: UserRole, page: string): Promise<void> {
  logout()
  const account: QuickLoginAccount | undefined = getQuickLoginAccount(role, getApiBaseUrl())
  if (account === undefined) { throw new Error('Isolated test account missing') }
  const user = await loginRemote(account.phone, account.password, role === UserRole.ADMIN ? 'ADMIN' : 'MERCHANT')
  expect(user?.role).assertEqual(role)
  await new Promise<void>((resolve, reject) => {
    context.runScopedTask((): void => {
      context.getRouter().replaceUrl({ url: 'pages/' + page }).then(() => { resolve() })
        .catch(() => { reject(new Error('Navigation failed')) })
    })
  })
  await driver.delayMs(1600)
}

export default function storeReviewFlowTest(): void {
  describe('StoreReviewFlow', () => {
    it('reject_resubmit_approve_and_platform_control_use_real_server', 0, async () => {
      expect(BuildProfile.UI_TEST_BASE_URL.startsWith('http://10.0.2.2:')).assertTrue()
      const fixture: StoreReviewFixture = (JSON.parse(BuildProfile.QUICK_LOGIN_CONFIG) as StoreReviewConfiguration).fixtures
      const driver: Driver = Driver.create()
      await launchAppUnderTest(driver)
      if (isFound(await driver.findComponent(ON.id('privacy-accept')))) {
        expect(await clickByIdOrText(driver, 'privacy-accept', '同意并继续')).assertTrue()
        await driver.delayMs(1000)
      }
      const ability: UIAbility = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility()
      const context: UIContext = (await window.getLastWindow(ability.context)).getUIContext()
      const directory: string = ability.context.filesDir + '/store-review'
      try { fileIo.mkdirSync(directory) } catch (_) {}
      try {
        await saveAppearanceSettings(ability.context, 'light', 1, 'auto')
        await openRole(context, driver, UserRole.ADMIN, 'AdminStorePage')
        expect(await clickByIdOrText(driver, 'admin-store-reject-open-' + fixture.storeId, '驳回申请')).assertTrue()
        await requireComponent(await driver.waitForComponent(ON.id('admin-store-review-reason'), 5000), 'reason').inputText('请核实门牌')
        await driver.pressBack()
        const reject = requireComponent(await scrollUntilVisible(driver, 'admin-store-reject-' + fixture.storeId), 'reject')
        await reject.click()
        await driver.delayMs(1800)
        expect(await driver.screenCap(directory + '/admin-rejected-light.png')).assertTrue()
        await openRole(context, driver, UserRole.MERCHANT, 'MerchantCenterPage')
        expect(isFound(await driver.findComponent(ON.text('请核实门牌')))).assertTrue()
        const resubmit = requireComponent(await scrollUntilVisible(driver, 'merchant-store-resubmit-' + fixture.storeId), 'resubmit')
        await resubmit.click()
        await driver.delayMs(1800)
        expect(isFound(await driver.findComponent(ON.text('待审核')))).assertTrue()
        await openRole(context, driver, UserRole.ADMIN, 'AdminStorePage')
        const approve = requireComponent(await scrollUntilVisible(driver, 'admin-store-approve-' + fixture.storeId), 'approve')
        await approve.click()
        await driver.delayMs(1800)
        expect(isFound(await driver.findComponent(ON.text('审核通过')))).assertTrue()
        expect(await clickByIdOrText(driver, 'admin-store-platform-' + fixture.storeId, '平台停用')).assertTrue()
        await driver.delayMs(1800)
        await saveAppearanceSettings(ability.context, 'dark', 1, 'auto')
        await driver.delayMs(1500)
        await openRole(context, driver, UserRole.ADMIN, 'AdminStorePage')
        expect(await driver.screenCap(directory + '/admin-disabled-dark.png')).assertTrue()
        await openRole(context, driver, UserRole.MERCHANT, 'MerchantCenterPage')
        expect(isFound(await driver.findComponent(ON.text('平台已停用')))).assertTrue()
        const response: ApiResponse<ReviewStore[]> = await get<ReviewStore[]>('/api/merchant/stores')
        expect(response.code).assertEqual(200)
        const stores: ReviewStore[] = response.data ?? []
        const store: ReviewStore | undefined = stores.find((item: ReviewStore) => item.id === fixture.storeId)
        expect(store?.reviewStatus).assertEqual(1)
        expect(store?.platformStatus).assertEqual(0)
        expect(await driver.screenCap(directory + '/merchant-disabled-dark.png')).assertTrue()
      } finally {
        await saveAppearanceSettings(ability.context, 'system', 1, 'auto')
        logout()
      }
    })
  })
}

/**
 * 设备端 UiTest 公共助手。
 *
 * 两个已实测确认的坑（不处理就会「用例全绿但其实什么都没测」）：
 *
 * 1. `aa test` 会把 ohosTest 模板生成的 TestAbility（`testability/pages/Index`，页面内容只有
 *    "Hello World"）拉到前台，**盖住被测应用**。此时 Driver 只能看到测试 Ability 的窗口树，
 *    应用的组件一个都找不到。因此每个用例都必须先用 AbilityDelegator.startAbility 把
 *    EntryAbility 拉回前台，再等目标组件出现。
 * 2. `driver.findComponent` 未命中时返回的是 **null**（部分版本是 undefined）。历史用例写的
 *    `expect(comp !== undefined).assertTrue()` 在 null 情况下恒真 → 用例空跑还报 Pass。
 *    统一改用 `isFound()`。
 *
 * 复现证据（Round 28）：
 *   `[Probe] id=tab-3 found=false / Text component count=5`，同时并发 dumpLayout 拿到的页面是
 *   `testability/pages/Index` + `Hello World`。
 */
import { Driver, ON, Component, abilityDelegatorRegistry } from '@kit.TestKit'
import { Want } from '@kit.AbilityKit'
import { expect } from '@ohos/hypium'

export const BUNDLE_NAME: string = 'com.example.jiandanwaimai'
export const ENTRY_ABILITY: string = 'EntryAbility'

/** findComponent 未命中返回 null（部分版本返回 undefined），两者都算「没找到」。 */
export function isFound(component: Component | null | undefined): boolean {
  return component !== null && component !== undefined
}

/**
 * 把被测应用拉到前台；否则驱动看到的是测试 Ability 的 Hello World 空壳页。
 *
 * 注意：这里**不做**「按返回退到首页」的兜底。曾经这么干过，结果在隐私同意页/登录页上
 * 连续按返回直接把应用退到桌面，后面的断言全都在找不存在的控件（LoginFlow 因此红过一次）。
 * 需要干净起点的做法是 host 侧 `aa force-stop` + `aa start`：进程重启后页面栈从 pages/Index 重新开始。
 */
export async function launchAppUnderTest(driver: Driver): Promise<void> {
  const delegator = abilityDelegatorRegistry.getAbilityDelegator()
  const want: Want = { bundleName: BUNDLE_NAME, abilityName: ENTRY_ABILITY }
  await delegator.startAbility(want)
  await driver.delayMs(3000)
  await driver.waitForIdle(800, 8000)
}

/** 优先按 id 查找，找不到再退回文案匹配（id 被漏掉时能给出更有用的失败信息）。 */
export async function findByIdOrText(driver: Driver, id: string, text: string): Promise<Component | null> {
  const byId = await driver.findComponent(ON.id(id))
  if (isFound(byId)) {
    return byId
  }
  return await driver.findComponent(ON.text(text))
}

/**
 * 断言组件存在并把类型收窄成非空：ArkTS 不会因为自定义的 isFound() 收窄类型，
 * 直接 `x.click()` 会报 `'x' is possibly 'null'`（已经踩过一次）。
 */
export function requireComponent(component: Component | null | undefined, label: string): Component {
  if (component === null || component === undefined) {
    expect(false).assertTrue()
    throw new Error('UiTest component not found: ' + label)
  }
  return component
}

/**
 * 点按：每次点击前重新查找。
 *
 * 为什么不能复用同一个 Component 句柄：购物车行的 ForEach key 带 `cartRenderVersion`，点一次
 * `+` 会触发 refreshFromDatabase → version++ → 整棵行子树重建，上一次拿到的 Component 立刻失效，
 * 第二次点击会报 `... does not exist on current UI! ... (NoCandidates)`（已经踩过）。
 */
export async function clickByIdOrText(driver: Driver, id: string, text: string, attempts: number = 3): Promise<boolean> {
  for (let attempt = 1; attempt <= attempts; attempt++) {
    const found = await findByIdOrText(driver, id, text)
    // 这里必须写原生判空：ArkTS 不会因为自定义的 isFound() 收窄类型
    if (found !== null && found !== undefined) {
      try {
        await found.click()
        return true
      } catch (err) {
        console.info('[UiTest] click retry id=' + id + ' attempt=' + attempt + ' err=' + (err as Error).message)
      }
    } else {
      console.info('[UiTest] click target not found yet id=' + id + ' attempt=' + attempt)
    }
    await driver.delayMs(1200)
  }
  return false
}

/** 等待任一组件出现（用于「同意弹窗可能出现也可能不出现」这类分支）。 */
export async function waitAny(driver: Driver, ids: string[], timeoutMs: number): Promise<Component | null> {
  const deadline: number = timeoutMs
  const step: number = 1000
  let waited: number = 0
  while (waited <= deadline) {
    for (let i = 0; i < ids.length; i++) {
      const found = await driver.findComponent(ON.id(ids[i]))
      if (isFound(found)) {
        return found
      }
    }
    await driver.delayMs(step)
    waited += step
  }
  return null
}

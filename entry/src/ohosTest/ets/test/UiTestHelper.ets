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
import { Driver, ON, Component, Point, abilityDelegatorRegistry } from '@kit.TestKit'
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
    // 先落一条日志再断言：hypium 的失败信息不带 label，只有这行 hilog 能告诉你是哪个组件没找到
    console.info('[UiTest] MISSING component: ' + label)
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

/**
 * 查找可能位于滚动区**屏幕外**的组件：先直接找，找不到就在各个 Scroll 里 scrollSearch。
 *
 * 为什么需要：UiTest 的组件树只包含**当前可见**的节点。评价页的「图片评价」卡片在 Scroll 底部，
 * 直接 findComponent 恒返回 null（已实测：review-content / review-add-image 都找不到，
 * 而同一个页面上固定的「提交评价」按钮能找到），滚动后才能拿到。
 */
export async function scrollToIdOrText(driver: Driver, id: string, text: string): Promise<Component | null> {
  const direct = await findByIdOrText(driver, id, text)
  if (isFound(direct)) {
    return direct
  }
  const containers: Component[] = []
  // findComponents 未命中同样返回 null（不是空数组），直接 .length 会抛 Cannot read property length of null
  const scrolls = await driver.findComponents(ON.type('Scroll'))
  if (scrolls !== null && scrolls !== undefined) {
    for (let i = 0; i < scrolls.length; i++) {
      containers.push(scrolls[i])
    }
  }
  const lists = await driver.findComponents(ON.type('List'))
  if (lists !== null && lists !== undefined) {
    for (let i = 0; i < lists.length; i++) {
      containers.push(lists[i])
    }
  }
  console.info('[UiTest] scrollSearch for ' + id + ' across ' + containers.length + ' scrollable container(s)')
  for (let i = 0; i < containers.length; i++) {
    try {
      const found = await containers[i].scrollSearch(ON.id(id))
      if (isFound(found)) {
        return found
      }
    } catch (err) {
      console.info('[UiTest] scrollSearch failed on container[' + i + ']: ' + (err as Error).message)
    }
  }
  return null
}

/**
 * 点击组件几何中心（坐标从组件自身的 bounds 算出来，不是手写坐标）。
 *
 * 用途：某些嵌套在滚动/列表里的节点，Component.click() 会点不中（例如店铺详情评价区的 72×72
 * 缩略图），改用 driver.click(x, y) 更稳；失败时回退到 Component.click()。
 */
export async function clickComponentCenter(driver: Driver, component: Component, label: string): Promise<boolean> {
  try {
    const rect = await component.getBounds()
    const x: number = Math.floor((rect.left + rect.right) / 2)
    const y: number = Math.floor((rect.top + rect.bottom) / 2)
    console.info('[UiTest] click center of ' + label + ' at (' + x + ',' + y + ')')
    await driver.click(x, y)
    return true
  } catch (err) {
    console.info('[UiTest] center click failed for ' + label + ': ' + (err as Error).message + ' -> fallback to component.click()')
    try {
      await component.click()
      return true
    } catch (err2) {
      console.info('[UiTest] component.click also failed for ' + label + ': ' + (err2 as Error).message)
      return false
    }
  }
}

/**
 * 诊断用：打印坐标 (x,y) 处所有可点击组件（id/文本/边界）。
 *
 * 用于「节点找到了、点击却没反应」这类问题——能看出该坐标上到底压着谁，
 * 比反复猜「是不是点击没生效」靠谱得多。
 */
export async function logComponentsAt(driver: Driver, x: number, y: number): Promise<void> {
  const found = await driver.findComponents(ON.clickable(true))
  if (found === null || found === undefined) {
    console.info('[UiTest] no clickable components found at all')
    return
  }
  console.info('[UiTest] clickable components total=' + found.length + ', probing (' + x + ',' + y + ')')
  for (let i = 0; i < found.length; i++) {
    try {
      const rect = await found[i].getBounds()
      if (x >= rect.left && x <= rect.right && y >= rect.top && y <= rect.bottom) {
        const id: string = await found[i].getId()
        const text: string = await found[i].getText()
        console.info('[UiTest] at(' + x + ',' + y + ') candidate id=' + id + ' text=' + text +
          ' bounds=[' + rect.left + ',' + rect.top + '][' + rect.right + ',' + rect.bottom + ']')
      }
    } catch (err) {
      // 单个节点取属性失败不影响整体诊断
    }
  }
}

/**
 * 滚动直到目标**真正可见**（边界小于整屏），返回其句柄。
 *
 * 为什么不能只 findComponent：长页面（店铺详情：店铺信息 → 公告 → 商品列表 → 用户评价）里，
 * 评价图片远在屏幕外，但驱动**仍会返回一个节点**，其 getBounds() 是全屏 [0,117][1320,2232] ——
 * 拿它算出来的中心点去点击，自然什么都不会发生（已实测：点完没有任何 app 日志）。
 * 这里用 fling 手势逐屏上滑，并且只接受「边界明显小于整屏」的节点。
 */
export async function scrollUntilVisible(driver: Driver, id: string, maxScrolls: number = 8): Promise<Component | null> {
  const size = await driver.getDisplaySize()
  const midX: number = Math.floor(size.x / 2)
  const nearTop: number = Math.floor(size.y * 0.32)
  const nearBottom: number = Math.floor(size.y * 0.78)
  const up: Point = { x: midX, y: nearBottom }
  const down: Point = { x: midX, y: nearTop }
  // 1) 先直接找一次：绝大多数调用目标已经在屏幕上，避免每次都白做「滚回顶部」的开销
  const direct = await driver.findComponent(ON.id(id))
  if (direct !== null && direct !== undefined) {
    try {
      const rect = await direct.getBounds()
      const sane: boolean = (rect.right - rect.left) < size.x && (rect.bottom - rect.top) < size.y
      if (sane) {
        return direct
      }
    } catch (err) {
      console.info('[UiTest] getBounds failed for ' + id + ': ' + (err as Error).message)
    }
  }
  // 2) 找不到就先滚回顶部：否则上一次查找把页面留在底部时，位于上方的目标永远找不到
  //    （管理端平台管理页 10 个入口，前面断言过的入口在下面就会踩这个坑）。
  for (let i = 0; i < 3; i++) {
    try {
      await driver.fling(down, up, 40, 3000)
    } catch (err) {
      console.info('[UiTest] reset fling failed: ' + (err as Error).message)
    }
    await driver.delayMs(700)
  }
  for (let step = 0; step <= maxScrolls; step++) {
    const found = await driver.findComponent(ON.id(id))
    if (found !== null && found !== undefined) {
      try {
        const rect = await found.getBounds()
        const sane: boolean = (rect.right - rect.left) < size.x && (rect.bottom - rect.top) < size.y
        console.info('[UiTest] scrollUntilVisible ' + id + ' step=' + step + ' bounds=[' + rect.left + ',' + rect.top +
          '][' + rect.right + ',' + rect.bottom + '] sane=' + sane)
        if (sane) {
          return found
        }
      } catch (err) {
        console.info('[UiTest] getBounds failed for ' + id + ': ' + (err as Error).message)
      }
    }
    if (step === maxScrolls) {
      break
    }
    try {
      await driver.fling(up, down, 40, 3000)
    } catch (err) {
      console.info('[UiTest] fling failed: ' + (err as Error).message)
    }
    await driver.delayMs(1200)
  }
  console.info('[UiTest] scrollUntilVisible failed for ' + id)
  return null
}

/**
 * 滚动到可见后再点击（长页面里的入口专用，例如「我的」页底部的商户管理入口）。
 * 先 scrollUntilVisible，再用组件自身 bounds 的中心点点击；失败时退回普通 clickByIdOrText。
 */
export async function scrollAndClick(driver: Driver, id: string, text: string): Promise<boolean> {
  const found = await scrollUntilVisible(driver, id)
  if (found !== null && found !== undefined) {
    if (await clickComponentCenter(driver, found, id)) {
      return true
    }
  }
  return await clickByIdOrText(driver, id, text)
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

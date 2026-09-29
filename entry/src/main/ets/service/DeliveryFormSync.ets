import { formBindingData, formProvider } from '@kit.FormKit'
import { Order, User, UserRole } from '../model/Models'

// Only these two strings cross into the launcher. Never copy an Order or credentials.
export class DeliverySnapshot {
  statusText: string = '打开应用同步订单'
  syncedText: string = '暂无订单快照'
}

let revision: number = 0
let publishQueue: Promise<void> = Promise.resolve()

export function deliveryRevision(): number { return revision }

export function deliveryCustomerId(): number {
  const user: User | undefined = AppStorage.get<User>('user')
  return AppStorage.get<boolean>('privacyConsent') === true &&
    AppStorage.get<boolean>('isLoggedIn') === true && user?.role === UserRole.CUSTOMER ? user.id : 0
}

export function deliveryStatus(order: Order): string {
  if (order.escrowStatus === 2) { return '已退款' }
  switch (order.status) {
    case 0: return '待付款'
    case 1: return '等待商家接单'
    case 2: return order.readyTime ? '已出餐 · 等待取餐' : '商家制作中'
    case 3: return '骑手配送中'
    case 4: return order.escrowStatus === 1 ? '已完成' : '已送达 · 待确认'
    case 5: return '已取消'
    case 6: return '退款中'
    default: return '请在应用查看状态'
  }
}

function publish(snapshot: DeliverySnapshot, expected: number): void {
  // Serialize writes: a logout clear always follows an already submitted update.
  publishQueue = publishQueue.catch(() => {}).then(async () => {
    if (expected !== revision) { return }
    const forms = await formProvider.getPublishedRunningFormInfos()
    for (const form of forms) {
      if (expected !== revision) { return }
      if (form.abilityName === 'DeliveryFormAbility') {
        try { await formProvider.updateForm(form.formId, formBindingData.createFormBindingData(snapshot)) } catch (_) {}
      }
    }
  }).catch(() => {})
}

export function clearDeliveryForms(): void {
  revision += 1
  publish(new DeliverySnapshot(), revision)
}

export function syncDeliveryForms(orders: Order[], owner: number, expected: number): void {
  if (owner <= 0 || owner !== deliveryCustomerId() || expected !== revision) { return }
  const snapshot: DeliverySnapshot = new DeliverySnapshot()
  const active: Order | undefined = orders.find((order: Order) =>
    ((order.status >= 0 && order.status <= 4) || order.status === 6) && order.escrowStatus !== 2 &&
    !(order.status === 4 && order.escrowStatus === 1))
  snapshot.statusText = active === undefined ? '暂无进行中订单' : deliveryStatus(active)
  snapshot.syncedText = '同步于 ' + new Date().toLocaleString()
  publish(snapshot, expected)
}

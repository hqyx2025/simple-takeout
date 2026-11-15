import { OrderActionSource, UserRole } from '../model/Models'

export interface OrderDisplayState {
  code: string
  label: string
}

/** Presentation is independent of server status values and never grants an action. */
export function orderDisplayState(status: number, escrow: number = 0,
  role: UserRole = UserRole.CUSTOMER): OrderDisplayState {
  if (escrow === 2) { return { code: 'REFUNDED', label: '已退款' } }
  if (status === 0) { return { code: 'UNPAID', label: '待付款' } }
  if (status === 1) { return { code: 'ACCEPTING', label: '待接单' } }
  if (status === 2) { return { code: 'PREPARING', label: role === UserRole.RIDER ? '待取餐' : '制作中' } }
  if (status === 3) { return { code: 'DELIVERING', label: '配送中' } }
  if (status === 4) {
    return escrow === 1 ? { code: 'COMPLETED', label: '已完成' }
      : { code: 'CONFIRMING', label: role === UserRole.MERCHANT ? '已送达，待用户确认' : '已送达，待确认收货' }
  }
  if (status === 5) { return { code: 'CANCELLED', label: '已取消' } }
  if (status === 6) { return { code: 'AFTER_SALES', label: '退款处理中' } }
  return { code: 'UNKNOWN', label: '状态待更新' }
}

export function refundDisplayText(status: string): string {
  if (status === 'PENDING') { return '待审核' }
  if (status === 'APPROVED') { return '退款处理中' }
  if (status === 'REFUNDED') { return '已退款' }
  if (status === 'REJECTED') { return '已驳回' }
  return '状态待更新'
}

export function canOrderAction(order: OrderActionSource, action: string, legacy: boolean): boolean {
  if (order.capabilities === undefined) { return legacy }
  if (order.capabilities === null || typeof order.capabilities !== 'object' || Array.isArray(order.capabilities)) { return false }
  const actions: string[] = order.capabilities.allowedActions
  return Array.isArray(actions) && actions.every((item: string) => typeof item === 'string') && actions.includes(action)
}

import { OrderActionSource } from '../model/Models'

export function canOrderAction(order: OrderActionSource, action: string, legacy: boolean): boolean {
  if (order.capabilities === undefined) { return legacy }
  if (order.capabilities === null || typeof order.capabilities !== 'object' || Array.isArray(order.capabilities)) { return false }
  const actions: string[] = order.capabilities.allowedActions
  return Array.isArray(actions) && actions.every((item: string) => typeof item === 'string') && actions.includes(action)
}

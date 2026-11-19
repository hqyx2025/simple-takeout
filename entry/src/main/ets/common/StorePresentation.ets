import { Address, StoreItem } from '../model/Models'
import { DELIVERY_RANGE } from './Constants'

export function storeRatingText(rating: number, count: number): string {
  return count > 0 ? `${rating.toFixed(1)} 分 · ${count} 人评分` : '暂无评分'
}

function validPoint(latitude: number, longitude: number): boolean {
  return Math.abs(latitude) <= 90 && Math.abs(longitude) <= 180 && (latitude !== 0 || longitude !== 0)
}

export function storeDeliveryText(store: StoreItem | null, address: Address | null): string {
  const lat: number = address?.latitude ?? NaN
  const lon: number = address?.longitude ?? NaN
  if (!validPoint(lat, lon)) { return '收货地址未定位，无法判断配送范围' }
  const storeLat: number = store?.latitude ?? NaN
  const storeLon: number = store?.longitude ?? NaN
  const meters: number = store?.deliveryRadius ?? 0
  if (!validPoint(storeLat, storeLon) || meters <= 0 || !Number.isFinite(meters)) { return '暂无法判断配送范围' }
  // 仅用于预览；门店生效半径来自服务端，下单仍由服务端校验。
  const r: number = Math.PI / 180
  const a: number = Math.pow(Math.sin((storeLat - lat) * r / 2), 2) +
    Math.cos(lat * r) * Math.cos(storeLat * r) * Math.pow(Math.sin((storeLon - lon) * r / 2), 2)
  const distance: number = 12742 * Math.asin(Math.sqrt(Math.min(1, Math.max(0, a))))
  const label: string = `直线 ${distance.toFixed(1)} 公里`
  if (distance > meters / 1000 + 1e-9) { return `${label} · 超出配送范围` }
  return distance > DELIVERY_RANGE.ORDER_CONFIRM_KM + 1e-9 ? `${label} · 可配送，下单需确认` : `${label} · 可配送`
}

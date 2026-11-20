import { Address, StoreItem } from '../model/Models'
import { DELIVERY_RANGE } from './Constants'

export function storeRatingText(rating: number, count: number): string {
  return count > 0 ? `${rating.toFixed(1)} 分 · ${count} 人评分${count < 5 ? ' · 评价较少' : ''}` : '暂无评分'
}

function validPoint(latitude: number, longitude: number): boolean {
  return Math.abs(latitude) <= 90 && Math.abs(longitude) <= 180 && (latitude !== 0 || longitude !== 0)
}

export function hasLocatedAddress(address: Address | null): boolean {
  return validPoint(address?.latitude ?? NaN, address?.longitude ?? NaN)
}

function deliveryDistance(store: StoreItem | null, address: Address | null): number {
  const lat: number = address?.latitude ?? NaN
  const lon: number = address?.longitude ?? NaN
  const storeLat: number = store?.latitude ?? NaN
  const storeLon: number = store?.longitude ?? NaN
  if (!validPoint(lat, lon) || !validPoint(storeLat, storeLon)) { return -1 }
  // 仅用于预览；门店生效半径来自服务端，下单仍由服务端校验。
  const r: number = Math.PI / 180
  const a: number = Math.pow(Math.sin((storeLat - lat) * r / 2), 2) +
    Math.cos(lat * r) * Math.cos(storeLat * r) * Math.pow(Math.sin((storeLon - lon) * r / 2), 2)
  return 12742 * Math.asin(Math.sqrt(Math.min(1, Math.max(0, a))))
}

function insideRadius(distance: number, meters: number): boolean {
  return distance >= 0 && Number.isFinite(meters) && meters > 0 && distance <= meters / 1000 + 1e-9
}

export function canDeliverTo(store: StoreItem, address: Address | null): boolean {
  return insideRadius(deliveryDistance(store, address), store.deliveryRadius ?? 0)
}

export function storeDeliveryText(store: StoreItem | null, address: Address | null, compact: boolean = false): string {
  if (!hasLocatedAddress(address)) { return compact ? '收货地址未定位' : '收货地址未定位，无法判断配送范围' }
  const distance: number = deliveryDistance(store, address)
  const meters: number = store?.deliveryRadius ?? 0
  if (distance < 0 || meters <= 0 || !Number.isFinite(meters)) { return '暂无法判断配送范围' }
  const label: string = `直线 ${distance.toFixed(1)} 公里`
  if (!insideRadius(distance, meters)) { return `${label} · 超出配送范围` }
  if (compact) { return `${label} · 可配送` }
  return distance > DELIVERY_RANGE.ORDER_CONFIRM_KM + 1e-9 ? `${label} · 可配送，下单需确认` : `${label} · 可配送`
}

import { Order } from './Models'

/** 订单列表共用的可视区懒加载数据源。 */
export class OrderDataSource implements IDataSource {
  private list: Order[] = []
  private listeners: DataChangeListener[] = []

  totalCount(): number {
    return this.list.length
  }

  getData(index: number): Order {
    return this.list[index]
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) { this.listeners.push(listener) }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((item: DataChangeListener) => item !== listener)
  }

  setData(data: Order[]): void {
    this.list = data
    this.listeners.forEach((listener: DataChangeListener) => listener.onDataReloaded())
  }
}

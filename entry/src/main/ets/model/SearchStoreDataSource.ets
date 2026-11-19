import { StoreItem } from './Models'

export class SearchStoreDataSource implements IDataSource {
  private stores: StoreItem[] = []
  private listeners: DataChangeListener[] = []
  private revision: number = 0

  totalCount(): number { return this.stores.length }

  getData(index: number): StoreItem { return this.stores[index] }

  keyFor(store: StoreItem): string { return store.id.toString() + ':' + this.revision.toString() }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) { this.listeners.push(listener) }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((item: DataChangeListener) => item !== listener)
  }

  setData(stores: StoreItem[]): void {
    this.stores = stores
    this.revision += 1
    this.listeners.forEach((listener: DataChangeListener) => listener.onDataReloaded())
  }
}

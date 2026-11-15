import { User, UserRole } from '../model/Models'
import { getAuthSessionEpoch } from './HttpClient'

/** A page request belongs to one authenticated identity and one visible page generation. */
export class PageSession {
  private owner: number = 0
  private role: UserRole = UserRole.CUSTOMER
  private epoch: number = -1
  private version: number = 0
  private active: boolean = false

  start(role: UserRole): boolean {
    const user: User | undefined = AppStorage.get<User>('user')
    this.owner = user?.id ?? 0
    this.role = role
    this.epoch = getAuthSessionEpoch()
    this.active = this.owner > 0 && user?.role === role && (AppStorage.get<boolean>('isLoggedIn') ?? false)
    return this.active
  }

  request(): number { this.active = true; return ++this.version }
  pause(): void { this.active = false; this.version += 1 }

  matchesIdentity(): boolean {
    const user: User | undefined = AppStorage.get<User>('user')
    return this.owner === 0 || ((AppStorage.get<boolean>('isLoggedIn') ?? false) && user?.id === this.owner
      && user?.role === this.role && this.epoch === getAuthSessionEpoch())
  }

  current(version: number): boolean {
    const user: User | undefined = AppStorage.get<User>('user')
    return this.active && version === this.version && this.owner > 0 && user?.id === this.owner
      && user?.role === this.role && this.epoch === getAuthSessionEpoch()
      && (AppStorage.get<boolean>('isLoggedIn') ?? false)
  }
}

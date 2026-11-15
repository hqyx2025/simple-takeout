import { COLORS } from '../common/Constants'
import preferences from '@ohos.data.preferences'
import common from '@ohos.app.ability.common'
import { UIContext } from '@kit.ArkUI'
import { User } from '../model/Models'
import { getAuthSessionEpoch } from './HttpClient'

export interface StoredFormDraft {
  schema: number
  savedAt: number
  fields: Record<string, string>
}

let draftWrites: Promise<void> = Promise.resolve()

/** Only explicitly selected, non-sensitive fields cross this persistence boundary. */
export class FormDraftStore {
  private owner: number = 0
  private role: number = -1
  private epoch: number = -1
  private key: string = ''
  private fields: string[] = []
  private lastSaved: string = ''
  private ready: boolean = false

  private current(): boolean {
    const user: User | undefined = AppStorage.get<User>('user')
    return this.owner > 0 && user?.id === this.owner && user?.role === this.role
      && this.epoch === getAuthSessionEpoch() && (AppStorage.get<boolean>('privacyConsent') ?? false)
      && (AppStorage.get<boolean>('isLoggedIn') ?? false)
  }

  private async prefs(): Promise<preferences.Preferences> {
    const context: common.UIAbilityContext = AppStorage.get<common.UIAbilityContext>('appContext') as common.UIAbilityContext
    return preferences.getPreferences(context, 'takeout_form_drafts')
  }

  async open(scope: string, initial: Record<string, string>): Promise<StoredFormDraft | null> {
    const user: User | undefined = AppStorage.get<User>('user')
    this.owner = user?.id ?? 0
    this.role = user?.role ?? -1
    this.epoch = getAuthSessionEpoch()
    this.key = `${this.owner}:${this.role}:${scope}`
    this.fields = Object.keys(initial)
    this.lastSaved = JSON.stringify(initial)
    if (!this.current()) { return null }
    await draftWrites
    const prefs: preferences.Preferences = await this.prefs()
    const raw: string = await prefs.get(this.key, '') as string
    if (!this.current()) { return null }
    if (raw === '') { this.ready = true; return null }
    try {
      const draft: StoredFormDraft = JSON.parse(raw) as StoredFormDraft
      if (draft.schema !== 1 || !Number.isFinite(draft.savedAt) || draft.fields === null
        || typeof draft.fields !== 'object' || Array.isArray(draft.fields)
        || !Object.keys(draft.fields).every((key: string): boolean => this.fields.includes(key)
          && typeof draft.fields[key] === 'string')) { throw new Error('Invalid draft') }
      return draft
    } catch (_) {
      throw new Error('本地草稿无法读取，请丢弃草稿后重试')
    }
  }

  resume(fields: Record<string, string>): void { this.lastSaved = JSON.stringify(fields); this.ready = true }

  async save(fields: Record<string, string>): Promise<boolean> {
    if (!this.ready || !this.current()) { return true }
    const selected: Record<string, string> = {}
    this.fields.forEach((key: string) => { selected[key] = fields[key] ?? '' })
    const fingerprint: string = JSON.stringify(selected)
    if (fingerprint === this.lastSaved) { return true }
    const draft: StoredFormDraft = { schema: 1, savedAt: Date.now(), fields: selected }
    const ok: boolean = await this.write(JSON.stringify(draft))
    if (ok) { this.lastSaved = fingerprint }
    return ok
  }

  async clear(): Promise<boolean> {
    this.ready = false
    return this.write(null)
  }

  private async write(value: string | null): Promise<boolean> {
    let ok: boolean = false
    const operation: Promise<void> = draftWrites.then(async (): Promise<void> => {
      if (!this.current()) { return }
      const prefs: preferences.Preferences = await this.prefs()
      if (!this.current()) { return }
      if (value === null) { await prefs.delete(this.key) } else { await prefs.put(this.key, value) }
      await prefs.flush()
      ok = true
    })
    draftWrites = operation.catch((): void => {})
    await draftWrites
    return ok
  }
}

export async function askToRestoreDraft(context: UIContext, draft: StoredFormDraft): Promise<boolean> {
  const choice = await context.getPromptAction().showDialog({
    title: '恢复草稿？', message: `保存于 ${new Date(draft.savedAt).toLocaleString()}，恢复后仍需确认保存。`,
    buttons: [{ text: '丢弃', color: COLORS.TEXT_SECONDARY }, { text: '恢复', color: COLORS.PRIMARY }]
  })
  return choice.index === 1
}

export async function discardUnreadableDraft(context: UIContext, store: FormDraftStore): Promise<boolean> {
  try {
    const choice = await context.getPromptAction().showDialog({ title: '草稿无法读取',
      message: '本地草稿格式无效。丢弃后可从服务端最新内容继续编辑。',
      buttons: [{ text: '保留并返回', color: COLORS.TEXT_SECONDARY }, { text: '丢弃草稿', color: COLORS.PRIMARY }] })
    return choice.index === 1 && await store.clear()
  } catch (_) { return false }
}

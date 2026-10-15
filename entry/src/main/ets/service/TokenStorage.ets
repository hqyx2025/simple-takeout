import { huks } from '@kit.UniversalKeystoreKit'
import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import preferences from '@ohos.data.preferences'
import common from '@ohos.app.ability.common'

export interface StoredAuthTokens {
  accessToken: string
  refreshToken: string
}

const STORE_NAME: string = 'takeout_auth_tokens'
const TOKEN_KEY: string = 'encrypted_tokens_v1'
const KEY_ALIAS: string = 'takeout.auth.tokens.v1'
const NONCE_BYTES: number = 12
const TAG_BYTES: number = 16
const NONCE_PREFIX_BYTES: number = NONCE_BYTES
const AAD: Uint8Array = new Uint8Array([116, 97, 107, 101, 111, 117, 116, 45, 97, 117, 116, 104, 45, 118, 49])

let prefsInstance: preferences.Preferences | null = null

async function getPrefs(): Promise<preferences.Preferences> {
  if (prefsInstance !== null) { return prefsInstance }
  const context: common.UIAbilityContext | undefined = AppStorage.get<common.UIAbilityContext>('appContext')
  if (context === undefined || context === null) { throw new Error('App context is not ready') }
  prefsInstance = await preferences.getPreferences(context, STORE_NAME)
  return prefsInstance
}

function parameter(tag: huks.HuksTag, value: number | Uint8Array): huks.HuksParam {
  return { tag: tag, value: value }
}

async function ensureKey(): Promise<void> {
  const exists: boolean = await huks.hasKeyItem(KEY_ALIAS, { properties: [] })
  if (exists) { return }
  const properties: huks.HuksParam[] = [
    parameter(huks.HuksTag.HUKS_TAG_ALGORITHM, huks.HuksKeyAlg.HUKS_ALG_AES),
    parameter(huks.HuksTag.HUKS_TAG_PURPOSE,
      huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT | huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT),
    parameter(huks.HuksTag.HUKS_TAG_KEY_SIZE, huks.HuksKeySize.HUKS_AES_KEY_SIZE_256),
    parameter(huks.HuksTag.HUKS_TAG_BLOCK_MODE, huks.HuksCipherMode.HUKS_MODE_GCM),
    parameter(huks.HuksTag.HUKS_TAG_PADDING, huks.HuksKeyPadding.HUKS_PADDING_NONE)
  ]
  await huks.generateKeyItem(KEY_ALIAS, { properties: properties })
}

function asciiBytes(value: string): Uint8Array {
  const bytes: Uint8Array = new Uint8Array(value.length)
  for (let i = 0; i < value.length; i++) {
    const code: number = value.charCodeAt(i)
    if (code > 127) { throw new Error('Token payload is not ASCII') }
    bytes[i] = code
  }
  return bytes
}

function asciiString(bytes: Uint8Array): string {
  let value: string = ''
  for (let i = 0; i < bytes.length; i++) { value += String.fromCharCode(bytes[i]) }
  return value
}

function toHex(bytes: Uint8Array): string {
  let value: string = ''
  for (let i = 0; i < bytes.length; i++) { value += bytes[i].toString(16).padStart(2, '0') }
  return value
}

function fromHex(value: string): Uint8Array {
  if (value.length % 2 !== 0 || !/^[0-9a-f]+$/i.test(value)) { throw new Error('Invalid token ciphertext') }
  const bytes: Uint8Array = new Uint8Array(value.length / 2)
  for (let i = 0; i < bytes.length; i++) { bytes[i] = parseInt(value.substring(i * 2, i * 2 + 2), 16) }
  return bytes
}

function combine(first: Uint8Array, second: Uint8Array): Uint8Array {
  const combined: Uint8Array = new Uint8Array(first.length + second.length)
  combined.set(first, 0)
  combined.set(second, first.length)
  return combined
}

function baseProperties(purpose: huks.HuksKeyPurpose, nonce: Uint8Array): huks.HuksParam[] {
  return [
    parameter(huks.HuksTag.HUKS_TAG_ALGORITHM, huks.HuksKeyAlg.HUKS_ALG_AES),
    parameter(huks.HuksTag.HUKS_TAG_PURPOSE, purpose),
    parameter(huks.HuksTag.HUKS_TAG_KEY_SIZE, huks.HuksKeySize.HUKS_AES_KEY_SIZE_256),
    parameter(huks.HuksTag.HUKS_TAG_PADDING, huks.HuksKeyPadding.HUKS_PADDING_NONE),
    parameter(huks.HuksTag.HUKS_TAG_BLOCK_MODE, huks.HuksCipherMode.HUKS_MODE_GCM),
    parameter(huks.HuksTag.HUKS_TAG_NONCE, nonce),
    parameter(huks.HuksTag.HUKS_TAG_AE_TAG_LEN, TAG_BYTES),
    parameter(huks.HuksTag.HUKS_TAG_ASSOCIATED_DATA, AAD)
  ]
}

async function encrypt(plainText: string): Promise<string> {
  await ensureKey()
  const random = await cryptoFramework.createRandom().generateRandom(NONCE_BYTES)
  const nonce: Uint8Array = random.data
  const cipherText: Uint8Array = await cryptTokenBytes(huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT,
    nonce, asciiBytes(plainText))
  return 'v1:' + toHex(combine(nonce, cipherText))
}

async function decrypt(value: string): Promise<string> {
  if (!value.startsWith('v1:')) { throw new Error('Unsupported token storage version') }
  const payload: Uint8Array = fromHex(value.substring(3))
  if (payload.length <= NONCE_PREFIX_BYTES + TAG_BYTES) { throw new Error('Invalid token ciphertext') }
  await ensureKey()
  const nonce: Uint8Array = payload.slice(0, NONCE_PREFIX_BYTES)
  const cipherText: Uint8Array = payload.slice(NONCE_PREFIX_BYTES, payload.length - TAG_BYTES)
  return asciiString(await cryptTokenBytes(huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT, nonce, cipherText,
    payload.slice(payload.length - TAG_BYTES)))
}

async function cryptTokenBytes(purpose: huks.HuksKeyPurpose, nonce: Uint8Array, input: Uint8Array,
  tag?: Uint8Array): Promise<Uint8Array> {
  const properties: huks.HuksParam[] = baseProperties(purpose, nonce)
  if (tag !== undefined) { properties.push(parameter(huks.HuksTag.HUKS_TAG_AE_TAG, tag)) }
  const session: huks.HuksSessionHandle = await huks.initSession(KEY_ALIAS, { properties: properties })
  try {
    const updated: huks.HuksReturnResult = await huks.updateSession(session.handle, { inData: input })
    const finished: huks.HuksReturnResult = await huks.finishSession(session.handle, {})
    // HUKS may return null when a stage has no output; plaintext leaves only after authentication succeeds.
    return combine(updated?.outData ?? new Uint8Array(0), finished?.outData ?? new Uint8Array(0))
  } catch (_) {
    try { await huks.abortSession(session.handle, {}) } catch (_) {}
    throw new Error('Device credential operation failed')
  }
}

export async function saveAuthTokens(accessToken: string, refreshToken: string): Promise<void> {
  if (accessToken === '') { await clearAuthTokens(); return }
  const prefs: preferences.Preferences = await getPrefs()
  const value: string = JSON.stringify({ accessToken: accessToken, refreshToken: refreshToken })
  await prefs.put(TOKEN_KEY, await encrypt(value))
  await prefs.flush()
}

export async function loadAuthTokens(): Promise<StoredAuthTokens | null> {
  const prefs: preferences.Preferences = await getPrefs()
  const value: string = await prefs.get(TOKEN_KEY, '') as string
  if (value === '') { return null }
  try {
    const tokens: StoredAuthTokens = JSON.parse(await decrypt(value)) as StoredAuthTokens
    if (typeof tokens.accessToken !== 'string' || typeof tokens.refreshToken !== 'string') {
      throw new Error('Invalid stored token payload')
    }
    return tokens
  } catch (_) {
    await prefs.delete(TOKEN_KEY)
    await prefs.flush()
    return null
  }
}

export async function clearAuthTokens(): Promise<void> {
  const prefs: preferences.Preferences = await getPrefs()
  await prefs.delete(TOKEN_KEY)
  await prefs.flush()
}

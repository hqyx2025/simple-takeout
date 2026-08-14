/**
 * 应用日志服务（增强版）
 * 功能：
 * 1. 控制台输出（DevEco Studio Log 窗口 / hdc hilog 可见）
 * 2. 日志文件按天分文件：log/app-YYYY-MM-DD.log
 * 3. 单文件大小限制：超过 2MB 自动压缩归档为 zip 并新建文件继续写入
 * 4. 日志文件位于应用沙箱 filesDir/log/，可通过 DevEco Device File Manager 或 hdc 导出查看
 */
import common from '@ohos.app.ability.common'
import fs from '@ohos.file.fs'
import zlib from '@ohos.zlib'

const LOG_TAG: string = 'TakeoutApp'
const LOG_DIR_NAME: string = 'log'
const LOG_FILE_PREFIX: string = 'app'
const MAX_LOG_SIZE: number = 2 * 1024 * 1024  // 单文件最大 2MB，超过则压缩归档

let logDirPath: string = ''
let logFilePath: string = ''
let loggerReady: boolean = false
let currentDateKey: string = ''
let privacyConsentGranted: boolean = false

export function setPrivacyConsent(granted: boolean): void {
  privacyConsentGranted = granted
  if (!granted) {
    loggerReady = false
  }
}

// 格式化时间 YYYY-MM-DD HH:mm:ss.SSS
function formatTime(): string {
  const date: Date = new Date()
  const y: number = date.getFullYear()
  const m: string = String(date.getMonth() + 1).padStart(2, '0')
  const d: string = String(date.getDate()).padStart(2, '0')
  const h: string = String(date.getHours()).padStart(2, '0')
  const min: string = String(date.getMinutes()).padStart(2, '0')
  const s: string = String(date.getSeconds()).padStart(2, '0')
  const ms: string = String(date.getMilliseconds()).padStart(3, '0')
  return `${y}-${m}-${d} ${h}:${min}:${s}.${ms}`
}

// 当天日期 key：YYYY-MM-DD
function todayKey(): string {
  const date: Date = new Date()
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`
}

/**
 * 初始化日志目录（须在 AppStorage 设置 appContext 后调用，建议在 EntryAbility.onCreate 调用）
 */
export function initLogger(): void {
  if (!privacyConsentGranted) {
    loggerReady = false
    return
  }
  try {
    const context: common.UIAbilityContext = AppStorage.get<common.UIAbilityContext>('appContext') as common.UIAbilityContext
    if (context === undefined || context === null) {
      console.error(`[${LOG_TAG}][Error][Log] initLogger failed: appContext not set`)
      return
    }
    logDirPath = context.filesDir + '/' + LOG_DIR_NAME
    // 目录不存在时创建（已存在会抛错，忽略即可）
    try {
      fs.mkdirSync(logDirPath, true)
    } catch (e) {
      // 目录已存在，忽略
    }
    currentDateKey = todayKey()
    logFilePath = logDirPath + '/' + LOG_FILE_PREFIX + '-' + currentDateKey + '.log'
    loggerReady = true
    console.info(`[${LOG_TAG}][Info][Log] Logger initialized, log file: ${logFilePath}`)
  } catch (err) {
    loggerReady = false
    console.error(`[${LOG_TAG}][Error][Log] initLogger failed: ${JSON.stringify(err)}`)
  }
}

/**
 * 检查日志文件是否需要轮转：
 * 1. 跨天：切换为当天新文件（旧文件保留在目录中）
 * 2. 单文件超过大小阈值：压缩归档为 zip 后新建文件继续写入
 */
function checkRotation(): void {
  if (!loggerReady || logDirPath === '') {
    return
  }
  const today: string = todayKey()
  if (today !== currentDateKey) {
    // 跨天切换文件
    currentDateKey = today
    logFilePath = logDirPath + '/' + LOG_FILE_PREFIX + '-' + today + '.log'
    return
  }
  // 大小检查：超过阈值则压缩归档
  try {
    const stat: fs.Stat = fs.statSync(logFilePath)
    if (stat.size >= MAX_LOG_SIZE) {
      archiveCurrentFile()
    }
  } catch (e) {
    // 文件不存在（首次写入前），忽略
  }
}

/**
 * 压缩归档当前日志文件：
 * 1. 将当前文件重命名为 .old（后续日志写入新文件，避免压缩期间写入冲突）
 * 2. 异步压缩 .old 为 zip 归档
 * 3. 压缩成功后删除 .old
 */
function archiveCurrentFile(): void {
  const oldPath: string = logFilePath
  const backupPath: string = oldPath + '.old'
  try {
    fs.renameSync(oldPath, backupPath)
    // 新文件继续写入
    logFilePath = logDirPath + '/' + LOG_FILE_PREFIX + '-' + currentDateKey + '-' + Date.now() + '.log'
    // 归档文件名：app-YYYY-MM-DD-<时间戳>.zip
    const zipPath: string = logDirPath + '/' + LOG_FILE_PREFIX + '-' + currentDateKey + '-' + Date.now() + '.zip'
    // 全部字段可选，使用默认压缩参数
    const options: zlib.Options = {}
    zlib.compressFile(backupPath, zipPath, options).then(() => {
      try {
        fs.unlinkSync(backupPath)
      } catch (e) {
        // 忽略删除异常
      }
      console.info(`[${LOG_TAG}][Info][Log] 日志文件已压缩归档: ${zipPath}`)
    }).catch((err: Object) => {
      console.error(`[${LOG_TAG}][Error][Log] 日志压缩失败: ${JSON.stringify(err)}`)
    })
  } catch (err) {
    console.error(`[${LOG_TAG}][Error][Log] 日志归档失败: ${JSON.stringify(err)}`)
  }
}

// 写入日志文件
function writeToFile(level: string, message: string): void {
  if (!loggerReady || logFilePath === '') {
    return
  }
  // 每次写入前检查跨天与大小（日志频率低，直接检查开销可忽略）
  checkRotation()
  let file: fs.File | null = null
  try {
    const line: string = `[${formatTime()}][${level}] ${message}\n`
    file = fs.openSync(logFilePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.APPEND)
    fs.writeSync(file.fd, line)
  } catch (err) {
    console.error(`[${LOG_TAG}][Error][Log] write log file failed: ${JSON.stringify(err)}`)
  } finally {
    if (file !== null) {
      try {
        fs.closeSync(file)
      } catch (e) {
        // 忽略关闭异常
      }
    }
  }
}

// 通用日志输出（控制台 + 文件）
function log(level: string, tag: string, message: string): void {
  const safeMessage: string = redactSensitive(message)
  const full: string = `[${LOG_TAG}][${level}][${tag}] ${safeMessage}`
  if (level === 'Error') {
    console.error(full)
  } else if (level === 'Warn') {
    console.warn(full)
  } else {
    console.info(full)
  }
  writeToFile(level, `[${tag}] ${safeMessage}`)
}

function redactSensitive(message: string): string {
  let safe: string = message
  safe = safe.replace(/(phone=|手机号[=:：]?|手机号码[=:：]?)\s*1\d{10}/g, '$1[REDACTED_PHONE]')
  safe = safe.replace(/(Bearer\s+|token[=:：]?\s*)[A-Za-z0-9._-]+/gi, '$1[REDACTED_TOKEN]')
  safe = safe.replace(/((?:地址|address|detail)[=:：]\s*)[^|]+/gi, '$1[REDACTED_ADDRESS]')
  return safe
}

/** 信息日志 */
export function logInfo(tag: string, message: string): void {
  log('Info', tag, message)
}

/** 警告日志 */
export function logWarn(tag: string, message: string): void {
  log('Warn', tag, message)
}

/** 错误日志 */
export function logError(tag: string, message: string, detail?: Object): void {
  let msg: string = message
  if (detail !== undefined && detail !== null) {
    msg = `${message} | detail=${JSON.stringify(detail)}`
  }
  log('Error', tag, msg)
}

/**
 * 应用日志服务
 * 所有关键业务操作统一通过本服务记录日志：
 * 1. 控制台输出（DevEco Studio Log 窗口 / hdc hilog 可见）
 * 2. 写入日志文件（应用沙箱 filesDir/log/app.log，可通过 DevEco Device File Manager 或 hdc 导出查看）
 */
import common from '@ohos.app.ability.common'
import fs from '@ohos.file.fs'

const LOG_TAG: string = 'TakeoutApp'
const LOG_DIR_NAME: string = 'log'
const LOG_FILE_NAME: string = 'app.log'

let logDirPath: string = ''
let logFilePath: string = ''
let loggerReady: boolean = false

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

/**
 * 初始化日志目录（须在 AppStorage 设置 appContext 后调用，建议在 EntryAbility.onCreate 调用）
 */
export function initLogger(): void {
  try {
    const context: common.UIAbilityContext = AppStorage.get<common.UIAbilityContext>('appContext') as common.UIAbilityContext
    if (context === undefined || context === null) {
      console.error(`[${LOG_TAG}][Error] initLogger failed: appContext not set`)
      return
    }
    logDirPath = context.filesDir + '/' + LOG_DIR_NAME
    // 目录不存在时创建（已存在会抛错，忽略即可）
    try {
      fs.mkdirSync(logDirPath, true)
    } catch (e) {
      // 目录已存在，忽略
    }
    logFilePath = logDirPath + '/' + LOG_FILE_NAME
    loggerReady = true
    console.info(`[${LOG_TAG}][Info] Logger initialized, log file: ${logFilePath}`)
  } catch (err) {
    loggerReady = false
    console.error(`[${LOG_TAG}][Error] initLogger failed: ${JSON.stringify(err)}`)
  }
}

// 写入日志文件
function writeToFile(level: string, message: string): void {
  if (!loggerReady || logFilePath === '') {
    return
  }
  let file: fs.File | null = null
  try {
    const line: string = `[${formatTime()}][${level}] ${message}\n`
    file = fs.openSync(logFilePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.APPEND)
    fs.writeSync(file.fd, line)
  } catch (err) {
    console.error(`[${LOG_TAG}][Error] write log file failed: ${JSON.stringify(err)}`)
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
  const full: string = `[${LOG_TAG}][${level}][${tag}] ${message}`
  if (level === 'Error') {
    console.error(full)
  } else if (level === 'Warn') {
    console.warn(full)
  } else {
    console.info(full)
  }
  writeToFile(level, `[${tag}] ${message}`)
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

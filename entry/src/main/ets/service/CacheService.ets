import { common } from '@kit.AbilityKit'
import fs from '@ohos.file.fs'

async function visitCacheDirectory(directory: string, remove: boolean): Promise<number> {
  const names: string[] = await fs.listFile(directory)
  let size: number = 0
  for (const name of names) {
    const path: string = directory + '/' + name
    const stat: fs.Stat = await fs.lstat(path)
    if (stat.isDirectory() && !stat.isSymbolicLink()) {
      size += await visitCacheDirectory(path, remove)
      if (remove) {
        await fs.rmdir(path)
      }
    } else {
      size += stat.size
      if (remove) {
        await fs.unlink(path)
      }
    }
  }
  return size
}

function cacheDirectory(context: common.UIAbilityContext): string {
  const directory: string = context.cacheDir
  if (directory === '' || directory === '/') {
    throw new Error('应用缓存目录不可用')
  }
  return directory
}

export async function getCacheSize(context: common.UIAbilityContext): Promise<number> {
  return visitCacheDirectory(cacheDirectory(context), false)
}

export async function clearAppCache(context: common.UIAbilityContext): Promise<void> {
  // 只清理缓存目录内容，保留目录本身和 filesDir 中的持久化业务数据。
  await visitCacheDirectory(cacheDirectory(context), true)
}

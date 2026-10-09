import { ApiResponse, get, post, put } from './HttpClient'

/** 管理接口只返回密钥是否存在，不读取或缓存真实密钥。 */
export interface AssistantAdminConfig {
  enabled: boolean
  endpoint: string
  model: string
  hasApiKey: boolean
}

export interface AssistantAdminConfigRequest {
  enabled: boolean
  endpoint: string
  model: string
  apiKey: string
  clearApiKey: boolean
}

export async function fetchAssistantAdminConfig(): Promise<ApiResponse<AssistantAdminConfig>> {
  return get<AssistantAdminConfig>('/api/admin/assistant/config')
}

export async function saveAssistantAdminConfig(config: AssistantAdminConfigRequest): Promise<ApiResponse<AssistantAdminConfig>> {
  return put<AssistantAdminConfig>('/api/admin/assistant/config', config)
}

export async function testAssistantAdminConnection(): Promise<ApiResponse<string>> {
  return post<string>('/api/admin/assistant/test', undefined, true, 25000)
}

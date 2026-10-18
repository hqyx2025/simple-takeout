import { post, ApiResponse } from '../HttpClient'

import { AssistantHistoryMessage, AssistantAction, AssistantAskRequest, ServerAssistantReply } from '../../model/server/Contracts'

/** 助手回答的前端结构：不依赖后端字段名，避免字段缺失时渲染崩溃。 */
export class AssistantReply {
  answer: string = ''
  suggestions: string[] = []
  actions: AssistantAction[] = []
  source: string = 'LOCAL'
}

/**
 * 向智能助手提问。
 * 通过服务端调用管理员配置的模型；业务查询与导航由服务端处理。
 */
export async function askAssistantApi(question: string,
  history: AssistantHistoryMessage[] = []): Promise<AssistantReply | null> {
  const req: AssistantAskRequest = { question: question, history: history.slice(-10) }
  const resp: ApiResponse<ServerAssistantReply> = await post<ServerAssistantReply>('/api/assistant/chat', req, false, 25000)
  if (resp.code !== 200 || resp.data === null || resp.data === undefined) {
    return null
  }
  const reply: AssistantReply = new AssistantReply()
  reply.answer = typeof resp.data.answer === 'string' ? resp.data.answer : ''
  reply.suggestions = Array.isArray(resp.data.suggestions)
    ? resp.data.suggestions.filter((item: string) => typeof item === 'string').slice(0, 4) : []
  reply.actions = Array.isArray(resp.data.actions)
    ? resp.data.actions.filter((item: AssistantAction) => item !== null && typeof item.label === 'string'
      && typeof item.target === 'string' && item.label.trim() !== '').slice(0, 5) : []
  reply.source = resp.data.source === 'AI' ? 'AI' : 'LOCAL'
  return reply
}

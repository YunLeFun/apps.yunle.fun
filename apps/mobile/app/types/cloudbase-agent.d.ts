import type { AgentRunInput, AgentStreamEvent } from './agent'

declare module '@cloudbase/ai' {
  interface CloudbaseAgentStreamResult {
    dataStream: AsyncIterable<AgentStreamEvent>
    eventSourceStream?: AsyncIterable<unknown>
    textStream?: AsyncIterable<string>
  }

  interface Bot {
    sendMessage: (
      props: AgentRunInput,
      options?: { timeout?: number },
    ) => Promise<CloudbaseAgentStreamResult>
  }
}

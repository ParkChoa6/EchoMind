<template>
  <section class="side-card inspector" aria-label="执行记录">
    <header class="inspector-header">
      <div>
        <h2>执行记录</h2>
        <code v-if="response?.requestId">{{ response.requestId }}</code>
      </div>
      <span v-if="response" class="inspector-time">{{ response.latencyMs }} ms</span>
    </header>

    <p v-if="pending" class="inspector-state" role="status">正在等待本次请求的结果。</p>
    <p v-else-if="error" class="inspector-state error-state" role="alert">{{ error }}</p>
    <div v-else-if="!response" class="inspector-state">
      运行一个示例，或从对话中选中一条回复，就能查看它的路由和工具记录。
    </div>
    <template v-else>
      <ol class="execution-flow">
        <li>
          <div>
            <h3>意图识别</h3>
            <div class="execution-meta">
              <span class="execution-chip">{{ intentName(response.intent) }}</span>
              <span>意图置信度 {{ percent(response.intentConfidence) }}</span>
            </div>
          </div>
        </li>
        <li>
          <div>
            <h3>Agent 路由</h3>
            <div class="execution-meta">
              <span class="execution-chip">主路由 · {{ agentName(response.primaryAgent || response.agentType) }}</span>
              <span v-for="agent in response.supportingAgents" :key="agent" class="execution-chip neutral-chip">
                协作 · {{ agentName(agent) }}
              </span>
            </div>
            <p v-if="response.agentType && response.primaryAgent && response.agentType !== response.primaryAgent">
              最终返回 · {{ agentName(response.agentType) }}
            </p>
            <details v-if="response.routingReason" class="inspector-details">
              <summary>查看路由原因</summary>
              <pre>{{ response.routingReason }}</pre>
            </details>
          </div>
        </li>
        <li>
          <div>
            <h3>检索与工具</h3>
            <p v-if="prefetchLabel">{{ prefetchLabel }}</p>
            <p v-if="entry.tracePending" role="status">正在读取工具 Trace…</p>
            <p v-else-if="!entry.trace">工具 Trace 不可用。</p>
            <p v-else-if="!calls.length">本次没有记录到 Agent 工具调用。</p>
            <details v-for="(call, index) in calls" :key="call.tool_use_id || index" class="inspector-details tool-details">
              <summary>
                <span>{{ toolName(call.tool_name) }}</span>
                <span :class="toolState(call).tone">{{ toolState(call).label }}</span>
                <span v-if="Number.isFinite(call.latency_ms)">{{ call.latency_ms }} ms</span>
              </summary>
              <p v-if="call.error">{{ call.error }}</p>
              <pre>{{ formatJson(call.input) }}</pre>
            </details>

            <div v-if="sources.length" class="source-list" aria-label="本次检索证据">
              <details v-for="source in sources" :key="source.key" class="inspector-details evidence-details">
                <summary>
                  <strong>{{ source.title }}</strong>
                  <span>{{ source.stages.join(' / ') }}</span>
                </summary>
                <p>{{ source.snippet }}</p>
              </details>
            </div>
            <p v-else-if="response.knowledgeUsed">后端记录了真实检索命中，本次回包没有可展示的片段明细。</p>
          </div>
        </li>
        <li>
          <div>
            <h3>最终回复</h3>
            <p>{{ response.escalated ? '已返回回复，标记转人工。' : '回复已显示在对话中。' }}</p>
          </div>
        </li>
      </ol>

      <details class="inspector-details raw-details">
        <summary>查看原始回包</summary>
        <pre>{{ formatJson({ response: response.raw, trace: entry.trace?.raw }) }}</pre>
      </details>
    </template>
  </section>
</template>

<script setup>
import { computed } from 'vue'

const props = defineProps({
  entry: { type: Object, default: null },
  pending: Boolean,
  error: { type: String, default: '' }
})

const response = computed(() => props.entry?.response)
const calls = computed(() => props.entry?.trace?.trace?.toolCalls || [])
const prefetchLabel = computed(() => ({
  skipped: '本次跳过了预检索。',
  hit: '预检索命中知识库。',
  partial: '预检索返回了真实片段，部分召回发生降级。',
  empty: '预检索未返回可用片段。',
  degraded: '预检索已降级，没有返回真实片段。',
  error: '预检索执行异常。'
})[response.value?.knowledgePrefetch?.status])

const sources = computed(() => {
  const merged = new Map()
  const add = (items, stage) => {
    for (const item of items || []) {
      const key = JSON.stringify([item.title, item.snippet])
      if (!merged.has(key)) merged.set(key, { ...item, key, stages: [] })
      const stages = merged.get(key).stages
      if (!stages.includes(stage)) stages.push(stage)
    }
  }
  add(response.value?.knowledgePrefetch?.sources, '预检索')
  for (const call of calls.value) add(call.knowledge_sources, 'Agent 工具')
  return [...merged.values()]
})

function agentName(value) {
  return ({ general: '通用', technical: '技术支持', billing: '账单', escalation: '人工升级' })[value] || value || '未知'
}

function intentName(value) {
  return ({
    greeting: '问候', billing: '账单咨询', refund: '退款', invoice: '发票', payment_issue: '支付异常',
    technical: '技术问题', technical_login: '登录故障', technical_crash: '应用故障',
    order_status: '订单状态', logistics: '物流', human_handoff: '转人工', other: '其他'
  })[value] || value || '未知'
}

function toolName(value) {
  return value === 'search_knowledge_base' ? '检索知识库' : value || '工具'
}

function toolState(call) {
  if (!call.success) return { label: '执行失败', tone: 'danger' }
  if (call.fallback_used) return {
    label: call.knowledge_hit ? '部分降级' : '已降级',
    tone: 'warning-text'
  }
  if (call.result_success === false) return {
    label: call.tool_name === 'search_knowledge_base' && !call.error ? '未命中' : '结果失败',
    tone: 'danger'
  }
  return { label: '已完成', tone: 'success' }
}

function percent(value) {
  return Number.isFinite(value) ? `${(value * 100).toFixed(1)}%` : '—'
}

function formatJson(value) { return JSON.stringify(value ?? {}, null, 2) }
</script>

<style scoped>
.inspector { display: grid; gap: 16px; padding: 18px; }
.inspector-header { display: flex; align-items: flex-start; justify-content: space-between; gap: 12px; }
.inspector-header h2 { margin: 0; font-size: 18px; letter-spacing: -.02em; }
.inspector-header code { display: inline-block; margin-top: 4px; color: var(--muted); font-size: 11px; }
.inspector-time,
.execution-chip {
  display: inline-flex; align-items: center; padding: 4px 8px; border-radius: 6px;
  background: var(--accent-soft); color: #b9bfff; line-height: 1.4; font-size: 12px;
}
.inspector-time { font-variant-numeric: tabular-nums; white-space: nowrap; }
.neutral-chip { background: var(--panel-3); color: var(--text-soft); }
.inspector-state { margin: 0; color: var(--text-soft); font-size: 13px; line-height: 1.65; }
.error-state { color: var(--red); overflow-wrap: anywhere; }
.execution-flow { padding: 0; margin: 0; list-style: none; }
.execution-flow > li { position: relative; padding: 0 0 16px 22px; }
.execution-flow > li:not(:last-child)::before {
  position: absolute; left: 4px; top: 12px; bottom: -5px; width: 1px;
  content: ""; background: var(--line-strong);
}
.execution-flow > li::after {
  position: absolute; left: 0; top: 5px; width: 9px; height: 9px; border-radius: 50%;
  border: 2px solid var(--accent); background: var(--panel); content: "";
}
.execution-flow > li:last-child { padding-bottom: 0; }
.execution-flow h3 { font-size: 13px; margin: 0 0 6px; }
.execution-flow p { margin: 5px 0 0; color: var(--text-soft); font-size: 12px; line-height: 1.6; overflow-wrap: anywhere; }
.execution-meta { display: flex; flex-wrap: wrap; align-items: center; gap: 5px 8px; color: var(--muted); font-size: 12px; }
.inspector-details { margin-top: 7px; color: var(--text-soft); font-size: 12px; }
.inspector-details summary { cursor: pointer; line-height: 1.55; }
.inspector-details pre { margin: 6px 0 0; padding: 8px; border-radius: 8px; background: var(--bg-soft); overflow: auto; white-space: pre-wrap; overflow-wrap: anywhere; max-height: 250px; }
.tool-details { padding: 6px 8px; border: 1px solid var(--line); border-radius: 8px; }
.tool-details summary span + span { margin-left: 7px; }
.warning-text { color: #edbc75; }
.source-list { margin-top: 9px; }
.evidence-details { padding: 7px 9px; border-left: 2px solid var(--green); background: rgba(65, 201, 140, .06); border-radius: 0 6px 6px 0; }
.evidence-details summary strong { color: var(--text); overflow-wrap: anywhere; }
.evidence-details summary span { display: block; margin-left: 13px; color: var(--muted); font-size: 11px; }
.raw-details { margin: 0; padding-top: 11px; border-top: 1px solid var(--line); }
</style>

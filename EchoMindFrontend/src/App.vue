<template>
  <main :class="['app-shell', `app-shell-${activeView}`]">
    <header class="topbar">
      <a class="brand" href="#" aria-label="EchoMind 首页" @click.prevent="activeView = 'chat'">
        <span class="brand-mark">E</span>
        <span class="brand-name">EchoMind</span>
      </a>

      <nav class="view-nav" aria-label="工作区">
        <button :class="{ active: activeView === 'chat' }" @click="activeView = 'chat'">对话</button>
        <button :class="{ active: activeView === 'knowledge' }" @click="activeView = 'knowledge'">知识库</button>
        <button :class="{ active: activeView === 'evaluation' }" @click="activeView = 'evaluation'">评测</button>
      </nav>

      <div class="topbar-tools">
        <span class="environment-pill">
          <i :class="healthOk ? 'online' : 'offline'"></i>
          {{ healthLabel }}
        </span>
        <a class="docs-link" :href="docsUrl" target="_blank" rel="noreferrer">API 文档</a>
        <button class="avatar-button" title="当前用户">{{ userInitial }}</button>
      </div>
    </header>

    <div v-if="toast" class="toast" role="status">{{ toast }}</div>

    <section v-if="activeView === 'chat'" class="page page-chat">
      <div class="page-heading">
        <div class="heading-copy">
          <h1>客服对话</h1>
          <p>发起一次请求，查看意图、Agent 路由和知识库证据。</p>
        </div>
        <div class="heading-actions">
          <span class="session-label">{{ settings.conversationId || '新会话' }}</span>
          <button class="quiet-button" :disabled="chatPending" @click="clearConversation">清空</button>
        </div>
      </div>

      <div class="chat-layout">
        <section class="chat-stage">
          <div class="stage-bar">
            <div class="stage-context">
              <span class="context-dot"></span>
              <span>{{ apiBaseUrl() }}</span>
            </div>
            <span>{{ messages.length }} 条消息</span>
          </div>

          <div class="messages" ref="messageList">
            <article v-for="item in messages" :key="item.id" :class="['message', item.role]">
              <div class="message-meta">
                <span>{{ item.role === 'user' ? '你' : 'Agent' }}</span>
                <small v-if="item.meta">{{ item.meta }}</small>
              </div>
              <p>{{ item.content }}</p>
              <button v-if="item.response" class="message-inspect quiet-button" type="button"
                :aria-pressed="selectedRequestId === item.id" @click="selectRequest(item.id)">
                {{ selectedRequestId === item.id ? '正在查看执行记录' : '查看执行记录' }}
              </button>
            </article>

            <div v-if="messages.length === 0" class="empty-state">
              <h2>运行一个客服示例</h2>
              <p>点击即发送。你也可以输入自己的问题。</p>
              <div class="starter-prompts">
                <button :disabled="busy" @click="runExample('根据知识库，退款审核通过后多久能到账？')">查询退款政策 ↗</button>
                <button :disabled="busy" @click="runExample('登录时报 401，应该怎么排查？')">排查登录故障 ↗</button>
                <button :disabled="busy" @click="runExample('登录报错 401，同时订单被重复扣款 99 元，怎么分别处理？')">处理跨领域请求 ↗</button>
              </div>
            </div>
          </div>

          <form class="composer" @submit.prevent="sendMessage">
            <textarea
              v-model="draft"
              rows="3"
              placeholder="输入消息..."
              @keydown.meta.enter.prevent="sendMessage"
              @keydown.ctrl.enter.prevent="sendMessage"
            ></textarea>
            <div class="composer-bottom">
              <span>⌘ / Ctrl + Enter 发送</span>
              <button type="submit" :disabled="busy || !draft.trim()">{{ busy ? '处理中' : '发送' }}</button>
            </div>
          </form>
        </section>

        <aside class="chat-sidebar">
          <div class="chat-sidebar-scroll">
            <div ref="inspectorAnchor">
              <RequestInspector :entry="selectedRequest" :pending="chatPending" :error="chatError" />
            </div>
            <details class="side-card connection-settings">
              <summary>会话与连接配置</summary>
              <div class="connection-card">
              <label>
                <span>用户 ID</span>
                <input v-model="settings.userId" :disabled="chatPending" @change="persist" placeholder="u1001" />
              </label>
              <label>
                <span>会话 ID</span>
                <input v-model="settings.conversationId" :disabled="chatPending" @change="persist" placeholder="自动生成" />
              </label>
              <div class="side-actions">
                <button @click="checkHealth">检查连接</button>
                <button class="quiet-button" @click="refreshConsole">刷新</button>
              </div>

              <!-- 错误详情出口：接口失败时只弹一句「检索失败」是没法排查的，
                   真实原因（状态码、后端报错、字段名不匹配）都在这里。 -->
              <div v-if="statusText" class="status-detail-block">
                <button class="link-button" @click="statusOpen = !statusOpen">
                  {{ statusOpen ? '收起详情' : '查看响应 / 错误详情' }}
                </button>
                <pre v-if="statusOpen" class="status-detail">{{ statusText }}</pre>
              </div>
              </div>
            </details>

            <section class="side-card monitor-card">
              <div class="card-heading">
                <div>
                  <h2>运行状态</h2>
                </div>
                <button class="link-button" @click="loadMonitor">刷新</button>
              </div>
              <div v-if="monitorAvailable" class="mini-stats">
                <div><strong>{{ totalRequests }}</strong><span>Agent 执行</span></div>
                <div><strong>{{ agentCount }}</strong><span>Agent</span></div>
                <div><strong>{{ activeAlerts.length }}</strong><span>告警</span></div>
              </div>
              <p v-if="!monitorAvailable" class="healthy-note">监控数据暂不可用。</p>
              <div v-else-if="activeAlerts.length" class="alert-note">{{ activeAlerts[0].message }}</div>
              <p v-else class="healthy-note">当前没有活跃告警。</p>
            </section>
          </div>
        </aside>
      </div>
    </section>

    <section v-else-if="activeView === 'knowledge'" class="page page-knowledge">
      <div class="page-heading">
        <div class="heading-copy">
          <h1>知识库</h1>
          <p>搜索、补充和维护客服 Agent 使用的知识片段。</p>
        </div>
        <div class="count-display"><strong>{{ knowledgeCount }}</strong><span>知识片段</span></div>
      </div>

      <div class="knowledge-layout">
        <section class="workspace-card search-workspace">
          <div class="card-heading">
            <h2>检索知识</h2>
          </div>
          <div class="search-line">
            <input v-model="searchQuery" placeholder="例如：退款多久到账" @keydown.enter="searchKnowledge" />
            <button @click="searchKnowledge" :disabled="busy || !searchQuery.trim()">搜索</button>
          </div>
          <p v-if="searchFeedback" class="workspace-feedback" :class="searchFeedback.tone" role="status">
            {{ searchFeedback.message }}
          </p>
          <div v-if="searchResults.length" class="result-list">
            <details v-for="(item, index) in searchResults" :key="item.id || index"
              class="result-item knowledge-result" :open="index === 0">
              <summary class="result-title">
                <strong>{{ item.title || '未命名文档' }}</strong>
                <small v-if="Number.isFinite(item.score)">向量相似分 {{ item.score }}</small>
              </summary>
              <p>{{ item.content }}</p>
            </details>
          </div>
          <div v-else-if="!searchFeedback" class="workspace-empty">输入一个问题，查看实际召回的文档片段。</div>
        </section>

        <section class="workspace-card import-workspace">
          <div class="card-heading">
            <h2>添加知识</h2>
            <code>ChromaDB</code>
          </div>
          <label><span>标题</span><input v-model="docTitle" placeholder="退款补充政策" /></label>
          <label><span>内容</span><textarea v-model="docContent" rows="7" placeholder="输入客服规范、产品说明或排障流程"></textarea></label>
          <div class="side-actions">
            <button @click="submitKnowledge" :disabled="busy || !docTitle.trim() || !docContent.trim()">添加文档</button>
            <label class="upload-button">上传文件<input type="file" accept=".txt,.md,.json" @change="handleUpload" /></label>
          </div>
        </section>
      </div>

      <section class="workspace-card skills-workspace">
        <div class="card-heading">
          <h2>已加载 Skills</h2>
          <button class="link-button" @click="reloadSkillSet">重新加载</button>
        </div>
        <div class="skill-table">
          <div v-for="skill in skillsData.skills" :key="skill.name" class="skill-item">
            <span class="skill-dot"></span><strong>{{ skill.name }}</strong><span>{{ skill.description || '业务规范能力' }}</span><small>{{ skill.content_chars || 0 }} chars</small>
          </div>
          <div v-if="!skillsData.skills.length" class="workspace-empty">暂无已加载 Skill。</div>
        </div>
      </section>
    </section>

    <section v-else class="page page-evaluation">
      <div class="page-heading">
        <div class="heading-copy">
          <h1>评测 Agent</h1>
          <p>运行 FastAPI 内置评测，查看意图识别、对话质量和回归结果。</p>
        </div>
        <button @click="runEvaluation" :disabled="busy">{{ evaluationPending ? '运行中…' : '运行评测' }}</button>
      </div>

      <div v-if="evalData" class="evaluation-content">
        <div class="evaluation-summary">
          <div class="score-hero"><span>报告条目通过率</span><strong>{{ formatPercent(evalData.pass_rate) }}</strong><small>意图汇总及对话轮次合计</small></div>
          <div><span>通过条目</span><strong>{{ evalData.passed }}</strong></div>
          <div><span>报告条目</span><strong>{{ evalData.total }}</strong></div>
          <div><span>回归</span><strong :class="evalData.regressions?.length ? 'danger' : 'success'">{{ evalData.regressions?.length || 0 }}</strong></div>
        </div>
        <div class="evaluation-layout">
          <section class="workspace-card">
            <div class="card-heading"><h2>指标汇总</h2></div>
            <div class="score-list">
              <div v-for="(value, key) in evalData.avg_scores" :key="key"><span>{{ evaluationMetricNames[key] || key }}</span><i><b :style="{ width: `${Math.min(Number(value) * 100, 100)}%` }"></b></i><strong>{{ Number(value).toFixed(2) }}</strong></div>
            </div>
          </section>
          <section class="workspace-card">
            <div class="card-heading"><h2>回归与建议</h2></div>
            <ul v-if="evalData.regressions?.length" class="regression-list">
              <li v-for="item in evalData.regressions" :key="item">{{ item }}</li>
            </ul>
            <div v-if="evalData.recommendations?.length" class="recommendations"><p v-for="(item, index) in evalData.recommendations" :key="index">{{ item }}</p></div>
            <div v-else class="workspace-empty">本次评测没有返回额外建议。</div>
          </section>
        </div>
        <EvaluationDetails :report="evalData" />
      </div>
      <div v-else class="evaluation-empty" role="status">
        <h2>{{ evaluationPending ? '正在运行评测' : '还没有评测结果' }}</h2>
        <p>{{ evaluationPending ? '正在生成对话回复并逐轮评分。' : '运行内置评测后，可查看逐题对照和模型裁判结果。' }}</p>
      </div>
      <p v-if="evaluationError" class="workspace-feedback danger" role="alert">{{ evaluationError }}</p>
    </section>
  </main>
</template>

<script setup>
import { computed, nextTick, onMounted, reactive, ref, watch } from 'vue'
import EvaluationDetails from './EvaluationDetails.vue'
import RequestInspector from './RequestInspector.vue'
import {
  addKnowledge,
  apiBaseUrl,
  createInitialSettings,
  reloadSkills,
  requestChat,
  requestHealth,
  requestKnowledgeStats,
  requestMonitor,
  requestSearch,
  requestToolTrace,
  requestSkills,
  runEvaluation as requestEvaluation,
  saveSettings,
  uploadKnowledge
} from './lib/api'

const settings = reactive(createInitialSettings())
const activeView = ref('chat')
const messages = ref([])
const draft = ref('')
const busy = ref(false)
const chatPending = ref(false)
const chatError = ref('')
const healthOk = ref(false)
const healthLabel = ref('未检查')
const statusText = ref('')
const knowledgeCount = ref('-')
const searchQuery = ref('退款多久能到账')
const searchResults = ref([])
const searchFeedback = ref(null)
const docTitle = ref('退款补充政策')
const docContent = ref('大促期间退款审核时间可能延长到 3-5 个工作日。')
const messageList = ref(null)
const inspectorAnchor = ref(null)
const monitorData = ref({ agent_stats: {}, tool_stats: {}, active_alerts: [], suggestions: [] })
const monitorAvailable = ref(false)
const skillsData = ref({ count: 0, skills: [], errors: [] })
const selectedRequestId = ref(null)
const evalData = ref(null)
const evaluationPending = ref(false)
const evaluationError = ref('')
const evaluationMetricNames = {
  relevance: '相关性', accuracy: '答案准确性', completeness: '完整性',
  helpfulness: '有用性', intent_accuracy: '意图准确率'
}
const toast = ref('')
const statusOpen = ref(false)
let toastTimer
let messageSequence = 0

const docsUrl = computed(() => `${apiBaseUrl()}/docs`)
const userInitial = computed(() => (settings.userId || 'U').slice(0, 1).toUpperCase())
const activeAlerts = computed(() => monitorData.value.active_alerts || [])
const agentCount = computed(() => Object.keys(monitorData.value.agent_stats || {}).length)
const totalRequests = computed(() => Object.values(monitorData.value.agent_stats || {}).reduce((sum, item) => sum + Number(item.total || 0), 0))
const selectedRequest = computed(() => messages.value.find(item => item.id === selectedRequestId.value) || null)

watch(() => settings.conversationId, persist)
// 侧栏高度不再用 JS 计算：原实现用 ResizeObserver 观察侧栏自身，
// 再把量到的高度写回 --sidebar-height，而 CSS 又用这个变量决定侧栏自身的
// height —— 自己改自己触发自己，是条自反馈回路。
// 实际上 .chat-layout 是 grid 且 align-items: stretch，侧栏只要 height:100%
// 就会自动跟上行高，窗口变化时由浏览器重排，不需要 JS 参与。
onMounted(() => {
  refreshConsole()
})

function persist() { saveSettings(settings) }

async function refreshConsole() {
  await Promise.allSettled([checkHealth(), loadStats(), loadMonitor(), loadSkills()])
}

async function checkHealth() {
  try {
    const data = await requestHealth()
    healthOk.value = data.status === 'ok'
    healthLabel.value = data.status || 'ok'
    statusText.value = JSON.stringify(data, null, 2)
  } catch (error) {
    healthOk.value = false
    healthLabel.value = '不可用'
    statusText.value = error.message
  }
}

async function loadStats() {
  try {
    const data = await requestKnowledgeStats()
    knowledgeCount.value = data.total_chunks ?? '-'
  } catch {
    knowledgeCount.value = '-'
  }
}

async function loadMonitor() {
  try {
    monitorData.value = await requestMonitor()
    monitorAvailable.value = true
  } catch {
    monitorAvailable.value = false
  }
}

async function loadSkills() {
  try {
    skillsData.value = await requestSkills()
  } catch {
    skillsData.value = { count: 0, skills: [], errors: [] }
  }
}

async function reloadSkillSet() {
  busy.value = true
  try {
    skillsData.value = await reloadSkills()
    showToast('Skills 已重新加载')
  } catch (error) {
    statusText.value = error.message
    statusOpen.value = true
    showToast('Skills 加载失败')
  } finally { busy.value = false }
}

async function sendMessage() {
  const content = draft.value.trim()
  if (!content || busy.value) return
  messages.value.push({ id: createMessageId(), role: 'user', content })
  draft.value = ''
  busy.value = true
  chatPending.value = true
  chatError.value = ''
  try {
    const response = await requestChat(settings, content)
    if (response.conversationId && !settings.conversationId) {
      settings.conversationId = response.conversationId
      persist()
    }
    const meta = [response.intent, response.primaryAgent || response.agentType, response.knowledgeUsed ? 'RAG' : '', response.escalated ? '转人工' : ''].filter(Boolean).join(' · ')
    const messageId = createMessageId()
    messages.value.push({
      id: messageId, role: 'assistant', content: response.response, meta, response,
      trace: null, tracePending: Boolean(response.requestId)
    })
    selectedRequestId.value = messageId
    // 回复立即展示；补充信息独立加载，也不阻塞下一轮发送。
    if (response.requestId) {
      void loadToolTrace(response.requestId).then((trace) => {
        const item = messages.value.find(entry => entry.id === messageId)
        if (item) {
          item.trace = trace
          item.tracePending = false
        }
      })
    }
    void loadMonitor()
  } catch (error) {
    chatError.value = error.message
    statusText.value = error.message
    statusOpen.value = true
    messages.value.push({ id: createMessageId(), role: 'assistant', content: error.message, meta: '请求失败' })
  } finally {
    busy.value = false
    chatPending.value = false
    await nextTick()
    messageList.value?.scrollTo({ top: messageList.value.scrollHeight, behavior: 'smooth' })
  }
}

function runExample(prompt) {
  draft.value = prompt
  return sendMessage()
}

function selectRequest(id) {
  selectedRequestId.value = id
  chatError.value = ''
  inspectorAnchor.value?.scrollIntoView({ block: 'nearest' })
}

function clearConversation() {
  messages.value = []
  selectedRequestId.value = null
  chatError.value = ''
  settings.conversationId = ''
  persist()
}

async function searchKnowledge() {
  const query = searchQuery.value.trim()
  if (busy.value || !query) return
  busy.value = true
  searchResults.value = []
  searchFeedback.value = { message: '正在检索…' }
  try {
    const data = await requestSearch(query, 5)
    const results = Array.isArray(data.results) ? data.results : []
    searchResults.value = results.filter(item => item?.content && !item.fallback)
    const count = searchResults.value.length
    searchFeedback.value = data.fallback_used || results.some(item => item?.fallback)
      ? { message: count ? `部分检索发生降级 · 保留 ${count} 条真实片段` : '检索已降级 · 没有真实片段', tone: 'warning-text' }
      : { message: count ? `命中 ${count} 条文档片段` : '未返回可用片段。', tone: count ? 'success' : 'muted' }
  } catch (error) {
    statusText.value = error.message
    statusOpen.value = true
    searchFeedback.value = { message: `检索失败 · ${error.message}`, tone: 'danger' }
  } finally { busy.value = false }
}

async function submitKnowledge() {
  busy.value = true
  try {
    const data = await addKnowledge([{ title: docTitle.value.trim(), content: docContent.value.trim() }])
    statusText.value = JSON.stringify(data, null, 2)
    await loadStats()
    showToast('文档已添加')
  } catch (error) {
    statusText.value = error.message
    statusOpen.value = true
    showToast('文档导入失败')
  } finally { busy.value = false }
}

async function handleUpload(event) {
  const file = event.target.files?.[0]
  event.target.value = ''
  if (!file) return
  busy.value = true
  try {
    const data = await uploadKnowledge(file)
    statusText.value = JSON.stringify(data, null, 2)
    await loadStats()
    showToast(`${file.name} 导入成功`)
  } catch (error) {
    statusText.value = error.message
    statusOpen.value = true
    showToast('文件导入失败')
  } finally { busy.value = false }
}

async function runEvaluation() {
  busy.value = true
  evaluationPending.value = true
  evaluationError.value = ''
  try {
    evalData.value = await requestEvaluation()
    showToast('评测完成')
  } catch (error) {
    statusText.value = error.message
    statusOpen.value = true
    evaluationError.value = `评测运行失败 · ${error.message}`
  } finally {
    evaluationPending.value = false
    busy.value = false
  }
}

async function loadToolTrace(requestId) {
  try {
    const data = await requestToolTrace(requestId)
    // 未命中的 request_id 后端也会返回 trace 骨架，只有 found=true 才说明真有记录，
    // 否则消息里会出现“已生成 trace 但没有工具输入”的空块。
    return data?.found ? data : null
  } catch {
    return null
  }
}

function formatPercent(value) {
  const number = Number(value || 0)
  return `${(number <= 1 ? number * 100 : number).toFixed(1)}%`
}

function createMessageId() {
  messageSequence += 1
  return `message-${Date.now()}-${messageSequence}`
}

function showToast(message) {
  toast.value = message
  clearTimeout(toastTimer)
  toastTimer = setTimeout(() => { toast.value = '' }, 2600)
}
</script>

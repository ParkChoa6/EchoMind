<template>
  <section class="workspace-card evaluation-details">
    <div class="report-heading">
      <div>
        <h2>逐题结果</h2>
        <p>{{ intentCases.length }} 条意图样本 · {{ dialogCases.length }} 个对话轮次</p>
      </div>
      <div class="report-filters" aria-label="结果筛选">
        <button class="quiet-button" :aria-pressed="!onlyIssues" @click="onlyIssues = false">全部</button>
        <button class="quiet-button" :aria-pressed="onlyIssues" @click="onlyIssues = true">只看异常</button>
      </div>
    </div>
    <p v-if="judgeFailures" class="report-notice">有 {{ judgeFailures }} 个对话轮次裁判调用失败，汇总分可能包含占位评分。</p>
    <p v-if="!visibleIntents.length && !visibleDialogs.length" class="report-notice">
      {{ onlyIssues ? '没有符合筛选条件的结果。' : '本次报告没有逐题数据。' }}
    </p>

    <div v-if="visibleIntents.length" class="report-group">
      <h3>意图识别 · 标注对照</h3>
      <article v-for="(item, index) in visibleIntents" :key="index" class="report-row intent-row">
        <strong>{{ item.message }}</strong>
        <span>标注 <code>{{ item.expected }}</code></span>
        <span>预测 <code>{{ item.predicted }}</code></span>
        <span :class="item.expected === item.predicted ? 'success' : 'danger'">
          {{ item.expected === item.predicted ? '正确' : '误判' }}
        </span>
      </article>
    </div>
    <div v-if="visibleDialogs.length" class="report-group">
      <h3>对话质量 · 模型裁判</h3>
      <details v-for="item in visibleDialogs" :key="item.test_id" class="report-row dialog-row">
        <summary>
          <strong>{{ item.metadata?.question || item.test_id }}</strong>
          <span :class="isIssue(item) ? 'danger' : 'success'">{{ verdict(item) }}</span>
        </summary>
        <p v-if="item.metadata?.judge_failed" class="report-notice">
          {{ item.metadata.judge_error || '裁判调用失败，评分仅为占位值。' }}
        </p>
        <p v-if="item.metadata?.response" class="report-answer">{{ item.metadata.response }}</p>
        <div v-if="!item.metadata?.judge_failed" class="report-scores">
          <span v-for="(value, key) in item.scores" :key="key">{{ scoreNames[key] || key }} {{ Number(value).toFixed(2) }}</span>
        </div>
      </details>
    </div>
  </section>
</template>

<script setup>
import { computed, ref } from 'vue'

const props = defineProps({ report: { type: Object, required: true } })
const onlyIssues = ref(false)
const results = computed(() => props.report.results || [])
const intentCases = computed(() => results.value.find(item => item.test_id === 'intent_recognition')?.metadata?.cases || [])
const dialogCases = computed(() => results.value.filter(item => item.test_id !== 'intent_recognition'))
const visibleIntents = computed(() => onlyIssues.value
  ? intentCases.value.filter(item => item.expected !== item.predicted)
  : intentCases.value)
const visibleDialogs = computed(() => onlyIssues.value ? dialogCases.value.filter(isIssue) : dialogCases.value)
const judgeFailures = computed(() => dialogCases.value.filter(item => item.metadata?.judge_failed).length)
const scoreNames = { relevance: '相关性', accuracy: '准确性', completeness: '完整性', helpfulness: '有用性', overall: '综合分' }

function isIssue(item) { return Boolean(item.metadata?.judge_failed || !item.passed) }
function verdict(item) {
  if (item.metadata?.judge_failed) return '裁判失败'
  return item.passed ? '通过' : '未达标'
}
</script>

<style scoped>
.evaluation-details { display: grid; gap: 16px; padding: 18px; }
.report-heading { display: flex; flex-wrap: wrap; justify-content: space-between; align-items: center; gap: 8px 16px; }
.report-heading h2 { margin: 0; font-size: 18px; }
.report-heading p { margin: 4px 0 0; color: var(--text-soft); font-size: 13px; }
.report-filters { display: flex; gap: 6px; }
.report-filters button { min-height: 32px; font-size: 12px; }
.report-filters [aria-pressed="true"] { color: #c2c6ff; border-color: var(--accent); background: var(--accent-soft); }
.report-notice { margin: 0; color: #edbc75; font-size: 13px; line-height: 1.6; overflow-wrap: anywhere; }
.report-group { display: grid; gap: 7px; }
.report-group h3 { margin: 0 0 3px; font-size: 14px; }
.report-row { padding: 10px 12px; border: 1px solid var(--line); border-radius: 8px; color: var(--text-soft); font-size: 12px; }
.report-row strong { color: var(--text); font-weight: 600; }
.intent-row { display: grid; grid-template-columns: minmax(0, 2fr) minmax(0, 1fr) minmax(0, 1fr) auto; gap: 7px 12px; align-items: baseline; overflow-wrap: anywhere; }
.dialog-row summary { display: grid; grid-template-columns: minmax(0, 1fr) auto; gap: 8px; cursor: pointer; }
.dialog-row summary::-webkit-details-marker { display: none; }
.dialog-row summary strong::before { content: "›"; display: inline-block; margin-right: 7px; }
.dialog-row[open] summary strong::before { transform: rotate(90deg); }
.dialog-row p { margin: 10px 0 0; }
.report-answer { white-space: pre-wrap; line-height: 1.65; }
.report-scores { display: flex; flex-wrap: wrap; gap: 6px 12px; margin-top: 10px; }
@media (max-width: 720px) {
  .intent-row { grid-template-columns: repeat(2, minmax(0, 1fr)) auto; }
  .intent-row > strong { grid-column: 1 / -1; }
}
</style>

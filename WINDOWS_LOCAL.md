# Windows 本地部署

这条启动路径用于在 Windows 上用本机模型学习和调试 EchoMind。后端依赖单独锁定为 ChromaDB 1.0.20，使用 Windows 预编译包。知识库、情景记忆和用户画像通过本机 Ollama 的 `bge-m3:latest` 生成向量，默认对话模型为 `qwen2:7b`。意图识别的独立向量分支沿用原项目实现。

## 准备环境

- Python 3.12 和 `uv`。
- 启动 Ollama，确认本机端口为 `11434`。首次使用可执行 `ollama pull qwen2:7b` 与 `ollama pull bge-m3`。
- 本机可运行的 `redis-server.exe`。若已加入 PATH，可省略启动时的 `-RedisExe`。同目录有 `redis-cli.exe` 时，停止脚本会请求 Redis 保存后退出。
- 使用网页时准备 Node.js 和 npm。可用 `-WithFrontend` 启用 Vue 调试界面。

在仓库根目录执行：

```powershell
uv venv --python 3.12 .\EchoMind\.venv
uv pip install --python .\EchoMind\.venv\Scripts\python.exe -r .\EchoMind\requirements-windows.txt
npm.cmd --prefix .\EchoMindFrontend ci
.\Local.ps1 -Action Start -RedisExe 'C:\path\to\redis-server.exe' -WithFrontend
```

| 组件 | 地址 |
| --- | --- |
| Vue 调试界面 | http://127.0.0.1:15174 |
| FastAPI Swagger | http://127.0.0.1:18010/docs |
| ChromaDB 心跳 | http://127.0.0.1:18011/api/v2/heartbeat |
| Redis | 127.0.0.1:16380 |

各服务绑定本机回环地址。日志、进程记录、Redis 数据、ChromaDB 数据与本地评测基线位于仓库下的 `.runtime/windows/`。生成模型通过本机 Ollama 的 Anthropic 兼容接口调用，启动脚本使用本地占位凭据。

## 验证、停止和重启

```powershell
.\Local.ps1 -Action Status -WithFrontend
.\EchoMind\.venv\Scripts\python.exe -X utf8 .\EchoMind\verify_local.py --via-frontend
.\Local.ps1 -Action Stop
.\Local.ps1 -Action Start -RedisExe 'C:\path\to\redis-server.exe' -WithFrontend
```

只跑后端时，启动、状态检查和验证命令省略各自的前端参数。验证脚本通过真实接口导入并检索一条合成文档，完成同会话两轮对话，检查 Trace、Redis 写入和聊天指标。每次使用独立的测试会话，合成文档采用稳定内容重复导入。停止后持久化数据保留在 `.runtime/windows/`。

离线回归测试使用本地隔离环境：

```powershell
uv pip install --python .\EchoMind\.venv\Scripts\python.exe pytest==8.3.4
Push-Location .\EchoMind
.\.venv\Scripts\python.exe -m pytest -q
Pop-Location
```

## 已验证的运行结果

在 Windows 和 Python 3.12 下，现有 44 项后端回归测试全部通过，Vue 生产构建通过。使用本机 Ollama 和真实存储执行冒烟测试，网页代理成功完成文档导入与检索、两轮对话、Trace 查询和聊天指标查询。停止并重启后，Redis 中的 4 条会话消息以及 ChromaDB 知识片段均可读取。这些结果覆盖本机运行与持久化验证。

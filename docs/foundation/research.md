# Registro de pesquisa e evidências

`checked_at: 2026-08-28`  
`policy: fontes oficiais/primárias; afirmações voláteis devem ser revalidadas nos gatilhos indicados`

## Síntese

- **FACT:** GPT-5.6 Sol existe e é o modelo Codex recomendado para trabalho complexo; a máquina está configurada para Sol/Ultra.
- **FACT:** Claude Opus 5 existe, seu ID fixo é `claude-opus-5`, e Claude Code 2.1.251 suporta esforço `max`.
- **FACT:** MCP 2026-07-28 mudou negociação e compatibilidade de forma material; o CLI Codex local ainda marca esse suporte como em desenvolvimento.
- **FACT:** A2A 1.0 é estável, mas não existe peer remoto concreto para a primeira fatia.
- **FACT:** Tauri e Electron protegem a fronteira do renderer, não confinam automaticamente o subprocesso do agente.
- **INFERENCE:** Tauri/Rust é a baseline coerente para o núcleo privilegiado, condicionada a spikes de processo, WebView, PTY e packaging.
- **INFERENCE:** SQLite é suficiente para V1 com um writer lógico, WAL local, transações curtas, FTS5 e backup pela API.

## Evidências

| ID | Achado | Fonte primária | Aplicabilidade e limitações | Confiança |
|---|---|---|---|---|
| `EVD-001` | Sol/Terra/Luna são os modelos Codex 5.6; Sol é indicado para trabalho complexo; Max e Ultra não são necessários na maioria das tarefas. | [OpenAI Docs — Models](https://learn.chatgpt.com/docs/models) | Disponibilidade depende da conta; revalidar em mudança de modelo ou provider. | alta |
| `EVD-002` | `codex exec` suporta sandbox explícito, JSONL, `--output-schema` e autenticação de automação; API keys não devem entrar em jobs com código não confiável. | [OpenAI Docs — Non-interactive mode](https://learn.chatgpt.com/docs/non-interactive-mode) | A semântica exata deve ser confirmada contra a versão instalada. | alta |
| `EVD-003` | Opus 5 foi lançado em 2026-07-24; ID `claude-opus-5`, contexto de 1M e esforço até `max`. | [Anthropic — Opus 5](https://www.anthropic.com/news/claude-opus-5), [Claude Platform — Opus 5](https://platform.claude.com/docs/en/models/opus-5/whats-new-opus-5) | Recursos dependem de plano/backend; o acesso local foi confirmado por execução. | alta |
| `EVD-004` | Claude Code resolve aliases por backend e permite pinning/capability declaration. | [Claude Code — Model configuration](https://code.claude.com/docs/en/model-config) | `opus` é alias móvel; use ID fixo para reprodutibilidade. | alta |
| `EVD-005` | MCP 2026-07-28 usa núcleo stateless e negociação por requisição; clientes antigos não interoperam automaticamente. | [Release](https://blog.modelcontextprotocol.io/posts/2026-07-28/), [architecture](https://modelcontextprotocol.io/specification/2026-07-28/architecture), [versioning](https://modelcontextprotocol.io/specification/2026-07-28/basic/versioning), [transports](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports) | Implementações locais podem estar na revisão anterior; capability detection é obrigatória. | alta |
| `EVD-006` | A2A possui protocolo estável 1.0 e patch v1.0.1; Task/Message/Artifact e bindings são externos ao modelo interno APF. | [A2A specification](https://a2a-protocol.org/latest/specification/), [releases](https://github.com/a2aproject/A2A/releases) | Sem peer real em V1; adapter adiado. | alta |
| `EVD-007` | Skills usam `SKILL.md` nos dois ecossistemas, mas manifestos, descoberta e extensões de plugins não são portáveis. | [OpenAI skills](https://learn.chatgpt.com/docs/build-skills), [OpenAI plugins](https://developers.openai.com/plugins/build/plugins), [Claude skills](https://code.claude.com/docs/en/skills), [Claude plugins](https://code.claude.com/docs/en/plugins-reference) | Não existe manifesto universal oficial; overlays por provider são necessários depois da V1. | alta |
| `EVD-008` | Tauri 2 possui permissions/scopes/capabilities e Runtime Authority para IPC; sidecars não são sandbox. | [releases](https://v2.tauri.app/release/), [architecture](https://v2.tauri.app/concept/architecture/), [Runtime Authority](https://v2.tauri.app/security/runtime-authority/), [sidecars](https://v2.tauri.app/develop/sidecar/) | Matriz WebView e packaging precisam de protótipo real. | alta para mecanismo; média para escolha |
| `EVD-009` | Electron oferece renderer sandbox/context isolation, mas o main process mantém privilégio e releases têm cadência curta. | [releases](https://releases.electronjs.org/?channel=stable), [process model](https://www.electronjs.org/docs/latest/tutorial/process-model), [sandbox](https://www.electronjs.org/docs/latest/tutorial/sandbox), [security](https://www.electronjs.org/docs/latest/tutorial/security) | Fallback real se Tauri falhar em WebView, PTY, acessibilidade ou packaging. | alta |
| `EVD-010` | SQLite atual é 3.53.4; WAL mantém um writer e leitores concorrentes; FTS5 e Online Backup atendem o Brain local. | [downloads](https://www.sqlite.org/download.html), [WAL](https://www.sqlite.org/wal.html), [FTS5](https://www.sqlite.org/fts5.html), [backup](https://www.sqlite.org/backup.html), [limits](https://www.sqlite.org/limits.html) | WAL não é apropriado para filesystem de rede; readers longos impedem checkpoint. | alta |
| `EVD-011` | Rust estável observado nas fontes é 1.98.0 e `std::process::Command` permite argv sem shell. | [Rust 1.98](https://blog.rust-lang.org/2026/08/20/Rust-1.98.0/), [Rust std::process](https://doc.rust-lang.org/std/process/struct.Command.html) | Rust reduz classes de erro; não cria sandbox. | alta |
| `EVD-012` | Isolamento real exige primitivas específicas: AppContainer/Job Objects, App Sandbox/XPC, ou Landlock/bubblewrap/seccomp/cgroups. | [Windows AppContainer](https://learn.microsoft.com/en-us/windows/win32/secauthz/appcontainer-isolation), [Job Objects](https://learn.microsoft.com/en-us/windows/win32/procthread/job-objects), [Apple App Sandbox](https://developer.apple.com/documentation/security/app-sandbox), [Linux Landlock](https://www.kernel.org/doc/html/latest/userspace-api/landlock.html), [bubblewrap](https://github.com/containers/bubblewrap) | Não há allowlist uniforme por domínio/path; cada backend exige teste adversarial. | alta |
| `EVD-013` | MIT é permissiva e curta; Apache-2.0 acrescenta grant de patente e obrigações de notices; MPL-2.0 aplica copyleft por arquivo. | [MIT/OSI](https://opensource.org/license/mit), [Apache-2.0](https://www.apache.org/licenses/LICENSE-2.0), [MPL FAQ](https://www.mozilla.org/en-US/MPL/2.0/FAQ/) | Isto é análise de licença, não aconselhamento jurídico. Decisão humana antes de contribuições externas. | alta sobre textos; média sobre adequação |

## Versões verificadas

| Componente | Versão em 2026-08-28 | Freshness trigger |
|---|---:|---|
| Tauri core / CLI | 2.11.5 / 2.11.4 | antes do bootstrap ou release |
| Electron | 44.0.0 | antes de qualquer spike Electron |
| Rust | 1.98.0 | antes de fixar `rust-toolchain.toml` |
| SQLite | 3.53.4 | em todo release; conferir `sqlite_version()` |
| Claude Code local | 2.1.251 | quando o binário mudar |
| Codex CLI local | 0.150.0-alpha.12.2 | quando extensão/CLI mudar |
| MCP | 2026-07-28 | antes de implementar adapter |
| A2A | wire 1.0; release 1.0.1 | antes de implementar adapter |

## Dívida de pesquisa

- `RES-DEBT-001`: termos específicos para orquestração programática de assinaturas Codex/Claude ainda precisam de revisão antes de distribuição pública.
- `RES-DEBT-002`: compatibilidade real dos CLIs com MCP 2026-07-28 não foi provada.
- `RES-DEBT-003`: containment de Codex/Claude com AppContainer, App Sandbox e Landlock não foi prototipado.
- `RES-DEBT-004`: tamanho, memória, cold start, acessibilidade e PTY do APF real não foram medidos.
- `RES-DEBT-005`: preços são deliberadamente ausentes; serão pesquisados somente quando houver decisão financeira concreta.

## Evidência local de integração

- `EVD-LOCAL-001` — o Codex recusou o schema canônico APF-CP como `response_format` porque seu subset de Structured Outputs exige que todo campo declarado esteja em `required`. Isso confirma a necessidade de separar envelope canônico e payload model-facing. A falha foi explícita (`invalid_json_schema`, HTTP 400), sem efeitos no workspace.
- `EVD-LOCAL-002` — Codex e Claude produziram com sucesso o mesmo payload estruturado reduzido. Usage/custo chega somente no evento/envelope após a geração e deve sobrescrever valores model-generated. Ver [provider-capability-probe.md](provider-capability-probe.md).

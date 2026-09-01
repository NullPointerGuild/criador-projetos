# APF-CP V1

Status: `FOUNDATION CANDIDATE`  
Normative schema: [`spec/apf-cp/v1/message.schema.json`](../../spec/apf-cp/v1/message.schema.json)

Provider-facing result schema: [`provider-result.schema.json`](../../spec/apf-cp/v1/provider-result.schema.json). Ele é deliberadamente menor e torna todos os campos declarados obrigatórios (valores indisponíveis usam `null`) para caber no subset de Structured Outputs observado. Telemetria não faz parte dele: o adapter captura usage/custo fora do modelo, e o Core valida, sanitiza os campos textuais destinados a logs/UI e envolve o payload no envelope canônico. Structured Output limita forma; não torna texto do provider confiável ou canônico.

`MUST`, `MUST NOT`, `SHOULD` e `MAY` têm sentido normativo neste documento.

## Finalidade

APF-CP é o contrato interno de governança entre o Core e workers/adapters. Em V1 ele é um registro JSON versionado e persistido no Project Brain. Não é um protocolo de rede, message broker, linguagem de chat, substituto de MCP ou concorrente de A2A.

## Princípios

1. O Core é a única autoridade para estado, policy, lease e audit.
2. O worker recebe um snapshot imutável; não lê o Brain diretamente.
3. O modelo recebe uma renderização e schema de payload mínimos, nunca o envelope inteiro por padrão.
4. No envelope canônico, campos não observáveis ou não aplicáveis são omitidos; na projeção estrita, optionals declarados usam `null`, nunca valor inventado.
5. Budget e grant sempre declaram o grau real de enforcement.
6. Todo resultado relevante é correlacionável a projeto, tarefa, execução, contexto e policy.
7. `actor.authority` registra a origem `HUMAN | CORE | PROVIDER`; não transfere autoridade de estado ao emissor.
8. Policy snapshots são imutáveis. Somente o Core emite `WORK_ORDER` e aplica transições.

## Envelope canônico

Obrigatórios:

- `schema_version = 1`;
- `message_id`, `message_type`, `project_id`, `task_id`;
- `actor` com role, agent instance e `authority = HUMAN | CORE | PROVIDER`;
- `created_at` RFC 3339 UTC;
- `policy_snapshot_id`;
- `context.pack_hash` e referências internas;
- `payload` tipado conforme `message_type`.

Condicionais:

- `run_id` é obrigatório para `RESULT`, `BLOCKER` e `CANCEL_REQUEST`;
- `causation_id` aponta ao registro que causou a mensagem;
- `idempotency_key` é obrigatório quando a operação pode repetir efeito externo;
- `budget` é obrigatório no `WORK_ORDER`, só contém limites relevantes e deve indicar `HARD`, `SOFT` ou `UNAVAILABLE`.

O Core MUST rejeitar versão desconhecida, campos extras, ID fora do padrão, timestamp inválido e payload incompatível antes de iniciar efeito.

## Tipos V1

| Tipo | Uso | Resposta esperada |
|---|---|---|
| `WORK_ORDER` | atribui objetivo, contexto, aceitação, escopo, grants e budget | `RESULT` ou `BLOCKER` |
| `RESULT` | resultado terminal normalizado | transição/gate pelo Core |
| `BLOCKER` | input, scope, capability, budget, security, dependency ou conflito arquitetural | nova decisão, aprovação ou cancelamento |
| `APPROVAL_REQUEST` | elevação limitada com impacto, reversibilidade e expiração | `APPROVAL_RESULT` |
| `APPROVAL_RESULT` | aprovado, negado, expirado ou revogado | policy snapshot novo se aprovado |
| `CANCEL_REQUEST` | solicita cancelamento e política para descendentes | evento terminal ou `RESULT` interrompido |

`PROGRESS`, falhas de processo, budget warnings, retries e transições são eventos do journal, não mensagens de modelo. Review é outro `WORK_ORDER` com role independente. Pesquisa e decisão são tasks/knowledge items, não novos transportes.

## Work Order

Um `WORK_ORDER` MUST conter:

- `actor.authority = CORE`;
- um objetivo verificável;
- pelo menos um critério de aceitação;
- `allowed_paths` e `protected_paths` explícitos;
- grants com `DENY | ASK | ALLOW` e nível de enforcement;
- perfil/provider solicitado por capability, não por suposição;
- tentativas limitadas a 1 por padrão, máximo 3 em V1;
- hash do Context Pack;
- schema de resposta quando o provider suportar structured output.

Paths de repo são relativos, usam `/` e rejeitam caminho absoluto, drive, backslash, `..` e o glob nu `**`. `protected_paths` MUST incluir `.git/**`, `.apf/**` e `.tools/**`. Ausência de path permitido significa nenhum write. Um path protegido sempre vence um permitido. Expansão produz `BLOCKER(kind=SCOPE)`; o worker MUST NOT improvisar.

## Result

O payload terminal canônico inclui:

- `outcome`;
- resumo externo, sem thinking privado;
- manifesto de mudanças;
- checks e evidências;
- artifacts;
- novos riscos, premissas e blockers;
- uso/custo capturado pelo adapter/runtime, com estado, `cost_basis`, fonte e confiança;
- próxima ação recomendada.

O modelo não relata sua própria telemetria. O adapter extrai usage/custo do envelope/evento nativo e o Core injeta o campo canônico. `ACTUAL` aceita somente `METERED | NONE`; `cost_basis = UNKNOWN` não pode carregar amount; `source` e `confidence` são obrigatórios. O Core também não confia no manifesto do provider: ele recalcula diff/hashes e executa gates. `SUCCEEDED` do provider não equivale a `COMPLETED` da tarefa até os checks independentes passarem.

O schema normativo hoje rejeita controles C0/C1 e bidi em `WORK_ORDER.objective`, `RESULT.summary` e `RESULT.next_action`. Os demais textos ainda MUST passar pelo sanitizador do Core antes de persistência em log ou exibição; esta obrigação não deve ser apresentada como cobertura completa do JSON Schema.

## Estados de tarefa

```text
PROPOSED → READY → LEASED → EXECUTING → REVIEW → COMPLETED
                     │          │          │
                     │          ├→ INPUT_REQUIRED
                     │          ├→ BLOCKED
                     │          ├→ FAILED
                     │          └→ CANCELLED / INTERRUPTED
                     └────────────→ READY (lease expirado, sem efeito desconhecido)

REVIEW → CHANGES_REQUESTED → READY
```

Regras:

- transições ilegais falham explicitamente e geram audit event;
- `COMPLETED` exige aceitação, checks e review configurados;
- recovery transforma execução sem processo vivo em `INTERRUPTED` antes de qualquer decisão de retry;
- retry não ocorre se efeitos externos forem desconhecidos;
- `CANCEL_REQUEST` cancela descendentes por padrão; detach exige policy explícita.

## Lease

V1 mantém `lease_owner` e `lease_expires_at` na tarefa. Aquisição ocorre na mesma transação SQLite que muda `READY → LEASED`, condicionada a state atual e dependências concluídas.

Renovação é feita por evento de processo útil, não por mensagem gerada pelo modelo. Ao iniciar:

1. o Core identifica leases expirados;
2. verifica se ainda existe processo supervisionado;
3. marca `INTERRUPTED` e registra causa;
4. requer revisão humana quando os efeitos não puderem ser determinados.

## Idempotência e retries

- Leitura, análise e geração sem efeito externo podem ser reexecutadas com attempt novo.
- Deploy, mensagem, compra, infra e qualquer external action MUST ter idempotency key e receipt, ou ser negados.
- A chave é derivada de operação semântica + projeto + target, não do prompt bruto.
- Failure class: `TRANSIENT_INFRA`, `PROVIDER`, `TOOL`, `INVALID_ASSUMPTION`, `LOGIC`, `PERMISSION`, `BUDGET`, `UNKNOWN_EFFECT`.
- Apenas classes explicitamente retryable recebem retry automático; backoff é limitado e cada tentativa vira run distinta com lineage.

## Budgets

O Core pode impor de modo duro somente o que controla: duração local, attempts, concorrência, número de ações brokered, output bytes e subagents que ele cria.

Token/custo/tool-call de um provider opaco pode ser `SOFT` ou `UNAVAILABLE`. Ultrapassar um limite não observado não pode ser descrito como prevenção. Child budget MUST ser menor ou igual ao saldo do parent/task.

## Grants e autonomia

Autonomia decide **quem pode autorizar**. Grant decide **o que o processo pode fazer**. São eixos independentes.

Cada grant registra:

- capability;
- `DENY`, `ASK` ou `ALLOW`;
- paths/domains/environment/amount/expiry/tools;
- `OS_ENFORCED`, `PROVIDER_ENFORCED`, `APF_VERIFIED` ou `ADVISORY`.

Em V1, `production`, `financial_spending`, `external_communication`, `secrets` e `cloud` são sempre `DENY`; `destructive_action` aceita no máximo `ASK`. `ALLOW` exige expiração e nunca pode usar `ADVISORY`. `filesystem` e `network` em `ASK | ALLOW` exigem paths e domains, respectivamente.

Child grants MUST ser subconjunto dos grants delegáveis do parent. Aprovação é vinculada a capability, scope, run e expiração; não é consentimento permanente. O enforcement declarado por um grant não aceita `UNKNOWN`; já o enforcement observado de uma execução MUST poder registrar `UNKNOWN` no Brain e bloquear elevação.

## Context Pack

O pack canônico contém objective, requirements, decisions, architecture refs, file map, constraints, acceptance e history relevante. Ele é serializado de forma determinística e identificado por SHA-256.

O modelo recebe somente:

- brief renderizado;
- conteúdo necessário;
- IDs para recuperação autorizada;
- classificação de conteúdo não confiável.

O Core registra `pack_hash`; não duplica o repositório ou histórico inteiro em cada run.

## Capability descriptor do adapter

`apf doctor` deve materializar por versão:

```yaml
provider: codex_cli
binary_version: ...
supports:
  non_interactive: true
  structured_output: true
  streaming: true
  cancellation: UNKNOWN
  usage_reporting: true
  cost_reporting: false
  provider_sandbox: UNKNOWN
  mcp_revision: UNKNOWN
enforcement:
  filesystem: UNKNOWN
  network: UNKNOWN
checked_at: ...
```

Mudança de binário invalida o descriptor até novo probe.

## Boundaries

- MCP tools/resources/prompts são descobertos por adapter versionado. MCP não recebe ownership de task, budget ou audit.
- A2A Task é mapeada no edge quando existir agente remoto real. `external_task_id`, versão, tenant e deduplication são preservados.
- Provider-native skills/plugins permanecem nativos; metadados nunca elevam grant APF.

## Versionamento

- Adições compatíveis usam campos opcionais dentro de V1 somente após atualização do schema.
- Mudança semântica ou remoção incrementa major de APF-CP.
- O Core MUST conservar o envelope original e a versão do adapter que o interpretou.
- Não há obrigação de compatibilidade eterna com protótipos anteriores à primeira release, mas toda quebra é explícita e migrada.

Exemplos: [work order](../../spec/apf-cp/v1/examples/work-order.json), [payload do provider](../../spec/apf-cp/v1/examples/provider-result.json) e [result canônico](../../spec/apf-cp/v1/examples/result.json).

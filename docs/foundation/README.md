# Fundação APF

Este diretório continua como fonte narrativa durante a Slice 1. O runtime inicial do Project Brain já existe, mas ainda não substitui estes documentos como memória primária nem gera suas projeções humanas.

## Resultado executivo

O founding prompt foi aceito como visão e rejeitado como backlog literal. A V1 valida somente:

```text
intenção
→ tarefa limitada
→ execução por um provider
→ verificação
→ registro durável
→ explicação com referências internas
```

O control plane será código determinístico. Modelos planejam, classificam, implementam e revisam em pontos delimitados; não possuem transições, leases, budgets, permissões ou auditoria.

## Estado das fases

| Fase | Estado | Saída |
|---|---|---|
| 0 — ambiente | concluída | [environment.md](environment.md) |
| 1 — pesquisa atual | concluída em 2026-08-28 | [research.md](research.md) |
| 2–3 — produto, premissas e riscos | concluídas para V1 | [product-and-risk.md](product-and-risk.md) |
| 4–5 — opções e conselho | decisão com dissenso | [architecture.md](architecture.md) |
| 6 — APF-CP | especificação V1 | [apf-cp-v1.md](apf-cp-v1.md) |
| 7 — Project Brain | contrato V1; schema SQLite atual `user_version=2` | [project-brain-v1.md](project-brain-v1.md) |
| 8 — segurança | threat model e gates | [security.md](security.md) |
| 9–11 — UX, MVP e backlog | definidos progressivamente | [ux-mvp-backlog.md](ux-mvp-backlog.md) |
| 12 — organização | conselho temporário concluído | Central Codex, três revisores independentes e Claude Opus 5 externo |
| 13 — implementação | em andamento, Slice 1 parcial | `T1.1–T1.4` verificados; `T1.5–T1.6` pendentes |
| 14–15 | não iniciadas | dogfood operacional e publicação dependem da aceitação da Slice 1 |

Probe local de providers: [provider-capability-probe.md](provider-capability-probe.md).

## Decisões vigentes

- `DEC-001`: separar control plane determinístico de judgment calls por modelo.
- `DEC-002`: Rust Core e CLI primeiro; Tauri/React entra somente depois da prova central.
- `DEC-003`: SQLite/WAL/FTS5 e artifacts fora do workspace do agente.
- `DEC-004`: APF-CP V1 é contrato persistido, não protocolo distribuído.
- `DEC-005`: controles exibem o nível real de enforcement; `CONTROLLED` não significa sandbox.
- `DEC-006`: Codex é o primeiro executor; Claude prova a abstração depois da suíte do primeiro.

## Atenção humana

| ID | Classe | Questão | Bloqueia agora? |
|---|---|---|---|
| `ATTN-001` | `ACTION_REQUIRED` | Ratificar MIT ou autorizar Apache-2.0 antes de contribuições externas. | Não para spikes; sim para abertura pública a contribuições. |
| `ATTN-002` | `ACTION_REQUIRED` | Definir orçamento de AI compute e infraestrutura recorrente. | Não para trabalho local já autorizado; sim antes de novos gastos recorrentes. |

Todo o restante é `ON_DEMAND` ou `OPERATIONAL`; nenhuma decisão adicional do usuário é necessária nesta fase.

## Como validar

Execute `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate-foundation.ps1`. O bypass vale apenas para esse processo; o script usa SQLite, Node.js e AJV instalados em `.tools/`, cria estado descartável em `.tmp/` e não altera configuração global. Downloads oficiais são verificados por digest; dependências npm são reproduzidas pelo lock versionado e com install scripts desativados.

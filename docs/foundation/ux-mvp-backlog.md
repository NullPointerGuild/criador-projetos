# UX, MVP e backlog progressivo

## Princípios de experiência

- simplicidade por padrão, profundidade sob demanda;
- uma pergunta humana somente quando a decisão muda produto, risco, capital ou autoridade;
- mostrar destino de dados e enforcement antes da execução;
- nenhuma notificação por atividade normal de agente;
- “saudável” sempre decomponível em scope, quality, security, cost e validation;
- Studio é control plane, não IDE.

## Organização mínima

V1 usa roles, não departamentos permanentes:

| Role | Ativação | Responsabilidade |
|---|---|---|
| Central Orchestrator | sempre | síntese, prioridades e decisão técnica |
| Executor | quando há Work Order aprovado | implementar/analisar dentro de scope |
| Independent Reviewer | impacto médio+ ou gate configurado | revisar em contexto separado |
| Security Reviewer | capability nova ou risco alto/crítico | veto e threat review |
| Research Engineer | claim volátil/externo relevante | evidence pack; não decide arquitetura |

Uma tabela estática seleciona roles. Organization Builder por modelo só será criado quando o template falhar repetidamente.

## Jornadas prototipadas

### 1. Instalar e diagnosticar

```text
Abrir APF
→ escolher diretório de dados
→ Doctor detecta Git/providers/toolchains
→ cada capability mostra Available / Missing / Broken / Unknown
→ remediação local, nunca mutação silenciosa de config global
```

### 2. Criar projeto

Wizard conversacional de no máximo oito perguntas iniciais: nome, o que, por quê, para quem, sucesso, recursos, restrições e autonomia. `AUTO`, `UNKNOWN` e `RECOMMEND` são válidos. Antes de salvar, o usuário revê um resumo curto e o destino de dados.

### 3. Configurar provider

Selecionar provider → detectar versão/auth/modelos/capabilities → executar probe seguro → mostrar privacy/destination → salvar somente referência de credencial. Modelo fixo e “melhor disponível” são políticas diferentes.

### 4. Bootstrap

APF cria identidade, Brain protegido e opcional `PROJECT.md`; pesquisa/premissas aparecem como resumo. A organização inicial tem apenas roles necessárias e custo estimado/unknown explícito.

### 5. Revisar organização

Usuário vê role, provider/model, finalidade, grants e custo com `state`, `cost_basis`, fonte e confiança — não organograma ornamental. Roles suspensas não consomem compute.

### 6. Acompanhar trabalho

Estado vem de processo/journal, não de chatter do modelo. Timeline mostra task, run, gates, diff, blocker e custo como `ESTIMATED / LIST`, `ACTUAL / METERED` ou `UNKNOWN`, sem confundir estimativa com cobrança. Logs brutos ficam on demand.

### 7. Attention

Somente `ACTION_REQUIRED` interrompe. Approval mostra impacto, reversibilidade, scope, expiração e enforcement. Approval só existe para capabilities elegíveis; produção, gasto financeiro, comunicação externa, secrets e cloud permanecem `DENY` na V1. Deny não exige justificativa. Override humano pode aceitar uma recomendação advisory, mas não elevar um hard veto nem reclassificar enforcement.

### 8. Ask Project

Pergunta → resposta curta → refs clicáveis → evidência/decisão/run → raw record on demand. Falta de suporte produz `UNKNOWN`, nunca preenchimento plausível.

### 9. Abrir externamente

Open Folder / Terminal / VS Code / JetBrains usa associações configuráveis. O Studio não renderiza editor de código.

## Studio mínimo, após a prova CLI

```text
┌ Project / phase / data destination ───────────────┐
│ Attention: 1 action required                     │
├ Work ─────────────────────────────────────────────┤
│ TASK-42  REVIEW   scope ✓ tests ✓ security ?      │
│ latest event, elapsed time, estimated/list cost   │
├ Explain ──────────────────────────────────────────┤
│ Ask this project…                                 │
└ Open folder · Open IDE · View raw history ────────┘
```

Três superfícies bastam: criar/abrir, acompanhar/autorizar e perguntar. Cockpit extenso, analytics e organization map ficam condicionados a uso real.

## Roadmap por gates e fatias

### Gate F — Fundação (concluído nesta missão)

Pesquisa, produto, riscos, conselho, APF-CP, Brain, security, UX e backlog; schema/backup executáveis.

### Gate 0 — Provider control

Provar o contrato real antes de permitir writes. Saída: capability matrix + decisão Security.

### Slice 1 — APF lembra

`init`, `doctor` e `status`; Brain persiste projeto/task/event e restaura após restart.

### Slice 2 — APF executa

Work Order → approval → worktree → Codex → checks/diff → Result → recovery.

### Slice 3 — APF governa

Capability request/approval com scope/expiração; deny, revoke e audit testados.

### Slice 4 — APF explica

SQL/FTS + Judge + verificador de refs responde cinco perguntas canônicas.

### Slice 5 — APF é visual

Tauri Studio cobre as três superfícies sem terminal e sem shell genérico no renderer.

### Slice 6 — Abstração real

Claude executa a mesma conformance suite; diferenças ficam em capability descriptor, sem false lowest common denominator.

## Backlog executável

Dependências apontam IDs; `—` significa nenhuma além da fundação.

| ID | Tipo | Entrega | Depende | Aceitação |
|---|---|---|---|---|
| `E0` | epic | Gate 0: provider control | — | decisão Security por provider/OS |
| `T0.1` | spike | Capturar `--help`, versão e capability descriptor Codex | — | evidence versionada e sem secrets |
| `T0.2` | spike | JSONL + JSON Schema + exit/error Codex | `T0.1` | payload normalizado e uso capturado |
| `T0.3` | spike | Probe Claude restricted/schema/cost | `T0.1` | mesmo contrato ou gap explícito |
| `T0.4` | spike | Cancel/timeout/process-tree no Windows | `T0.2` | nenhum neto permanece |
| `T0.5` | spike | Env, Git credentials e output flood | `T0.2` | fixture não lê secret e cap atua |
| `T0.6` | spike | Path escape/junction/TOCTOU | `T0.2` | matriz prevention/detection |
| `T0.7` | spike | Network egress e destination disclosure | `T0.2` | loopback/public egress/DNS separados; enforcement real identificado |
| `T0.9` | spike | Autoload de instructions/config por versão e hash | `T0.1` | cada superfície testada ou `UNKNOWN`; execpolicy não é confundida com `AGENTS.md` |
| `T0.10` | spike | Crash/recovery e unknown effects | `T0.4` | crash forçado resulta em `INTERRUPTED`, sem retry ou conclusão silenciosa |
| `T0.11` | spike | Normalização de usage/cost | `T0.2,T0.3` | `state`, `cost_basis`, fonte e confiança consistentes; custo real não é inferido |
| `T0.8` | decision | Fechar Gate 0 para o executor | `T0.3–T0.7,T0.9–T0.11` | decisão por provider/binário/OS; `UNKNOWN` produz `DENY` |
| `T0.8a` | decision | Permitir Slice 1 sem writes de provider | `T0.4,T0.5,T0.9,T0.11` | `APPROVED_WITH_ADVISORY_LIMITS` somente para core determinístico e judgment read-only |
| `T0.8b` | decision | Permitir writes do provider em repo do owner | `T0.6,T0.7,T0.9,T0.10,T0.11` | positive control writable e containment de escopo medidos; enquanto incompleto, `DENY` |
| `T0.8c` | decision | Tratar repo/conteúdo hostil | `T0.6,T0.7` | `REQUIRES_CONTAINER`; container/VM também deve ser medido |
| `E1` | epic | Slice 1: durable core | `T0.8a` | init/doctor/status após restart |
| `T1.1` | task | Bootstrap Rust local + toolchain pin | `T0.8a` | build/check reprodutível sem PATH global |
| `T1.2` | task | Crate domain com IDs/states/invariants | `T1.1` | transition tests sem provider |
| `T1.3` | task | Brain repositories + bootstrap `user_version=2` | `T1.2` | schema/seed/backup tests passam e migration lineage é explícita |
| `T1.4` | task | `apf init` e intent digest | `T1.3` | divergence detectada |
| `T1.5` | task | `apf doctor` capability evidence | `T1.3,T0.8a` | binary/config/OS change invalida probe; enforcement observado persiste |
| `T1.6` | task | startup recovery e leases | `T1.3` | stale run vira interrupted |
| `E2` | epic | Slice 2: governed execution | `E1` | task real completa e auditável |
| `T2.1` | task | APF-CP parser/validator/render | `T1.2` | schemas/examples + invalid fixtures |
| `T2.2` | task | Git worktree + scope verifier | `T1.2` | 3/3 violações detectadas |
| `T2.3` | task | Execution Broker Windows | `T0.8b,T2.1` | argv/env/limits/cancel auditados |
| `T2.4` | task | Codex adapter | `T2.3` | conformance e normalized Result |
| `T2.5` | task | Gates e independent review | `T2.2,T2.4` | provider success não burla gate |
| `T2.6` | task | end-to-end APF dogfood task | `T2.5` | refs/run/diff/usage, `cost_basis`, fonte e confiança sobrevivem restart |
| `E3` | epic | Slice 3: approval | `E2` | scoped elevation expira/revoga |
| `T3.1` | task | Repository/evaluator de policy snapshots imutáveis | `E2` | deterministic policy tests sobre a tabela existente |
| `T3.2` | task | approval lifecycle | `T3.1` | deny/approve/expire/revoke auditados |
| `T3.3` | task | Attention query | `T3.2` | somente ação valiosa aparece |
| `E4` | epic | Slice 4: Ask Project | `E2` | cinco perguntas com refs válidas |
| `T4.1` | task | deterministic query planner | `T1.3` | corpus esperado recuperado |
| `T4.2` | task | FTS indexing/rebuild | `T4.1` | rebuild determinístico |
| `T4.3` | task | Judge adapter sem side effects | `T2.4` | nenhuma tool mutável disponível |
| `T4.4` | eval | citation verifier + 20 questions | `T4.2,T4.3` | ≥90%, caso contrário UNKNOWN |
| `E5` | epic | Slice 5: thin Studio | `E3,E4` | jornadas sem terminal |
| `T5.1` | spike | Tauri/WebView/PTY/accessibility/packaging | `E4` | go/no-go; Electron fallback |
| `T5.2` | task | narrow Tauri command API | `T5.1` | renderer sem fs/shell genérico |
| `T5.3` | task | create/work/attention/ask UI | `T5.2` | teste das três superfícies |
| `E6` | epic | Slice 6: second provider | `E2` | abstração provada |
| `T6.1` | task | Claude adapter por caminho/version probe | `E2,T0.3` | mesma suite, gaps declarados |
| `T6.2` | eval | compare providers and bare CLI | `T6.1,T2.6` | custo/qualidade/tempo publicados |

### Estado de implementação verificado em 2026-08-31

| Item | Estado | Evidência curta |
|---|---|---|
| `T1.1` | concluído | Rust 1.98.0 + LLVM-MinGW repo-local; árvore/binários usados têm digest fixado, ambiente é restaurado e Cargo usa resolução locked/frozen após fetch |
| `T1.2` | concluído | IDs tipados e transições de task/run testam lease, completion e unknown effects |
| `T1.3` | concluído | runtime SQLite 3.53.4 aplica `user_version=2`, migration digest, FTS5, append-only e publicação/backup por staging validado |
| `T1.4` | concluído | `init` publica Brain completo; `status` sobrevive restart e rejeita divergence de intent ou identidade/workspace cruzados |
| `T1.5` | parcial | `doctor` informa o escopo `T0.8a`; fingerprint binário/config/SO ainda não é persistido/invalidado |
| `T1.6` | não iniciado | recovery de run/lease ainda precisa de repository transaction e teste de restart |
| `E1` | não aceita | depende da conclusão de `T1.5` e `T1.6` |

## Backlog condicionado, não comprometido

- worktrees paralelos: quando conflitos/espera sequencial forem medidos;
- semantic index: quando eval FTS falhar;
- plugin system: depois de três extensões concretas independentes;
- Organization Builder: depois de três falhas observadas do template;
- MCP adapter: quando uma tool externa necessária não puder ser integrada de modo mais simples;
- A2A: quando houver peer remoto real;
- daemon: quando execução precisar sobreviver ao fechamento do cliente;
- cloud/team: somente após valor local comprovado.
